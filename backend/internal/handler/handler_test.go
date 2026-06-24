package handler_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/router"
)

// uploadConfigForTest builds an UploadConfig pointing at the test's temp
// uploads dir with the production defaults (10 MB cap).
func uploadConfigForTest(uploadsDir string) *handler.UploadConfig {
	return &handler.UploadConfig{
		UploadDir:     uploadsDir,
		MaxUploadSize: 10 << 20,
	}
}

// newTestServer stands up the full router against an isolated SQLite DB
// and a temp uploads dir. Returns a configured *httptest.Server and a
// cleanup func the caller must defer.
//
// The migration runs as part of db.New, so the store_info row exists
// with sensible defaults before any handler is hit.
func newTestServer(t *testing.T) (*httptest.Server, *sql.DB, func()) {
	t.Helper()
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "test.db")
	uploadsDir := filepath.Join(tmpDir, "uploads")
	if err := os.MkdirAll(uploadsDir, 0o755); err != nil {
		t.Fatalf("mkdir uploads: %v", err)
	}

	database, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	database.SetMaxOpenConns(1)
	// Enable FK enforcement so ON DELETE SET NULL actually fires.
	if _, err := database.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		t.Fatalf("enable FK: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := database.PingContext(ctx); err != nil {
		t.Fatalf("ping db: %v", err)
	}

	// Apply schema by reusing the production migrations.
	d := &db.DB{DB: database}
	if err := applyMigrations(d); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	productRepo := db.NewProductRepo(database)
	storeRepo := db.NewStoreRepo(database)
	articleRepo := db.NewArticleRepo(database)
	uploadCfg := uploadConfigForTest(uploadsDir)

	r := router.New(productRepo, storeRepo, articleRepo, uploadCfg, "*")
	srv := httptest.NewServer(r)

	cleanup := func() {
		srv.Close()
		_ = database.Close()
	}
	return srv, database, cleanup
}

// applyMigrations is a copy of db.runMigrations so the test doesn't reach
// into the package's private API. Kept in lock-step manually; if the
// production schema changes, mirror the change here.
func applyMigrations(d *db.DB) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            price REAL NOT NULL,
            original_price REAL,
            image_url TEXT,
            category TEXT NOT NULL,
            store_id TEXT,
            rating REAL NOT NULL,
            reviews INTEGER,
            stock INTEGER,
            specs TEXT NOT NULL DEFAULT '[]'
        )`,
		`CREATE TABLE IF NOT EXISTS product_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id TEXT NOT NULL,
            image_url TEXT NOT NULL,
            ord INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
        )`,
		`CREATE TABLE IF NOT EXISTS product_options (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            name TEXT NOT NULL,
            image_urls TEXT NOT NULL DEFAULT '[]',
            ord INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
        )`,
		`CREATE TABLE IF NOT EXISTS large_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        )`,
		`CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            large_category_id INTEGER,
            FOREIGN KEY(large_category_id) REFERENCES large_categories(id) ON DELETE SET NULL
        )`,
		`CREATE TABLE IF NOT EXISTS store_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            name TEXT NOT NULL DEFAULT 'simshop',
            description TEXT NOT NULL DEFAULT '',
            logo_url TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            email TEXT NOT NULL DEFAULT '',
            address TEXT NOT NULL DEFAULT ''
        )`,
		`INSERT OR IGNORE INTO store_info (id) VALUES (1)`,
		`ALTER TABLE products ADD COLUMN categories TEXT`,
		`CREATE TABLE IF NOT EXISTS articles (
			id TEXT PRIMARY KEY,
			title TEXT NOT NULL,
			body_markdown TEXT NOT NULL DEFAULT '',
			cover_image_url TEXT NOT NULL DEFAULT '',
			product_ids TEXT NOT NULL DEFAULT '[]',
			created_at INTEGER NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS banner_slides (
			id TEXT PRIMARY KEY,
			image_url TEXT NOT NULL,
			title TEXT NOT NULL DEFAULT '',
			subtitle TEXT NOT NULL DEFAULT '',
			ord INTEGER NOT NULL DEFAULT 0,
			article_id TEXT,
			FOREIGN KEY(article_id) REFERENCES articles(id) ON DELETE SET NULL
		)`,
	}
	for _, s := range stmts {
		if _, err := d.Exec(s); err != nil {
			return err
		}
	}
	return nil
}

// TestStoreInfoDefaultGet asserts that GET /api/store-info returns the
// migration-seeded defaults — never 404 — so first-run clients can render
// the home page without any conditional handling.
func TestStoreInfoDefaultGet(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	resp, err := http.Get(srv.URL + "/api/store-info")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["name"] != "simshop" {
		t.Errorf("default name = %v, want simshop", got["name"])
	}
	if got["id"].(float64) != 1 {
		t.Errorf("default id = %v, want 1", got["id"])
	}
}

// TestStoreInfoUpdatePersists asserts that PUT persists the new values and
// the very next GET reflects them.
func TestStoreInfoUpdatePersists(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{
        "name": "Cửa hàng ABC",
        "description": "Chuyên đồ gia dụng",
        "logo_url": "http://localhost:8080/uploads/seed-shirt.jpg",
        "phone": "0901234567",
        "email": "abc@example.com",
        "address": "12 Nguyễn Huệ, Q1"
    }`)
	req, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/store-info", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("PUT status = %d, body=%s", resp.StatusCode, string(body))
	}

	// Second GET should see the updated row.
	resp2, err := http.Get(srv.URL + "/api/store-info")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp2.Body.Close()
	var got map[string]any
	if err := json.NewDecoder(resp2.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["name"] != "Cửa hàng ABC" {
		t.Errorf("after PUT name = %v, want Cửa hàng ABC", got["name"])
	}
	if got["phone"] != "0901234567" {
		t.Errorf("after PUT phone = %v, want 0901234567", got["phone"])
	}
}

// TestStoreInfoEmptyNameRejected asserts the only required-field check.
func TestStoreInfoEmptyNameRejected(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"name": "   "}`)
	req, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/store-info", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	respBody, _ := readAll(resp)
	if !bytes.Contains(respBody, []byte("name is required")) {
		t.Errorf("body = %s, want it to mention 'name is required'", string(respBody))
	}
}

// TestStoreInfoNameTooLong asserts the length cap.
func TestStoreInfoNameTooLong(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	longName := strings.Repeat("a", 81)
	body := strings.NewReader(`{"name": "` + longName + `"}`)
	req, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/store-info", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

// readAll drains the body. Avoids pulling in io.ReadAll for a one-liner.
func readAll(resp *http.Response) ([]byte, error) {
	var buf bytes.Buffer
	_, err := buf.ReadFrom(resp.Body)
	return buf.Bytes(), err
}

// ---------- Banner + article tests ----------

// TestBannerListEmpty asserts GET /api/banners returns an empty list
// (not 404) on a fresh database so the home carousel can render
// without special-casing.
func TestBannerListEmpty(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	resp, err := http.Get(srv.URL + "/api/banners")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	arr, ok := got["banners"].([]any)
	if !ok {
		t.Fatalf("banners field missing or not array: %v", got["banners"])
	}
	if len(arr) != 0 {
		t.Errorf("len(banners) = %d, want 0", len(arr))
	}
}

// TestArticleCreateAndGetWithProducts exercises the full article CRUD
// plus the joined /api/articles/:id endpoint. Creates a product,
// creates an article that mentions the product, GETs the joined
// payload, and asserts the product stub is returned with the chip
// fields populated.
func TestArticleCreateAndGetWithProducts(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	// Seed a product the article will reference.
	if _, err := database.Exec(`INSERT INTO products (id, name, description, price, image_url, category, rating, specs) VALUES (?, ?, ?, ?, ?, ?, ?, '[]')`,
		"p-1", "Áo thun", "Cotton 100%", 99000.0, "http://example.com/shirt.jpg", "Thời trang", 4.5); err != nil {
		t.Fatalf("seed product: %v", err)
	}

	// Create article.
	body := strings.NewReader(`{
		"id": "a-1",
		"title": "BST mùa hè",
		"body_markdown": "## Mới về\n\nBộ sưu tập mới.",
		"cover_image_url": "http://localhost:8080/uploads/cover.jpg",
		"product_ids": ["p-1"]
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/articles", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		body, _ := readAll(resp)
		t.Fatalf("POST status = %d, body=%s", resp.StatusCode, string(body))
	}

	// Debug: what did the server actually store?
	var storedProductIDs string
	if err := database.QueryRow(`SELECT product_ids FROM articles WHERE id = 'a-1'`).Scan(&storedProductIDs); err != nil {
		t.Fatalf("re-read stored product_ids: %v", err)
	}
	if storedProductIDs != `["p-1"]` {
		t.Errorf("stored product_ids = %q, want [\"p-1\"]", storedProductIDs)
	}

	// GET joined payload.
	resp2, err := http.Get(srv.URL + "/api/articles/a-1")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusOK {
		body, _ := readAll(resp2)
		t.Fatalf("GET status = %d, body=%s", resp2.StatusCode, string(body))
	}
	var got map[string]any
	if err := json.NewDecoder(resp2.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	article, ok := got["article"].(map[string]any)
	if !ok {
		t.Fatalf("article field missing: %v", got)
	}
	if article["title"] != "BST mùa hè" {
		t.Errorf("article.title = %v, want BST mùa hè", article["title"])
	}
	products, ok := got["products"].([]any)
	if !ok {
		t.Fatalf("products field missing: %v", got)
	}
	if len(products) != 1 {
		t.Fatalf("len(products) = %d, want 1", len(products))
	}
	p0 := products[0].(map[string]any)
	if p0["id"] != "p-1" {
		t.Errorf("product.id = %v, want p-1", p0["id"])
	}
	if p0["name"] != "Áo thun" {
		t.Errorf("product.name = %v, want Áo thun", p0["name"])
	}
}

// TestArticleMissingProductSkippedInJoin asserts the join silently
// drops product IDs that no longer exist (e.g., the referenced
// product was deleted). The article itself is still returned.
func TestArticleMissingProductSkippedInJoin(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{
		"id": "a-2",
		"title": "Bài viết",
		"body_markdown": "x",
		"product_ids": ["nonexistent"]
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/articles", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	resp.Body.Close()

	resp2, err := http.Get(srv.URL + "/api/articles/a-2")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp2.Body.Close()
	var got map[string]any
	if err := json.NewDecoder(resp2.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	products := got["products"].([]any)
	if len(products) != 0 {
		t.Errorf("len(products) = %d, want 0", len(products))
	}
}

// TestArticleDeleteCascadesBannerFK asserts that deleting an article
// leaves existing banner_slides with article_id set to NULL — so the
// home carousel keeps rendering but a tap leads to a friendly empty
// state.
func TestArticleDeleteCascadesBannerFK(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	if _, err := database.Exec(`INSERT INTO articles (id, title, body_markdown, product_ids, created_at) VALUES (?, ?, ?, '[]', ?)`,
		"a-3", "Bài viết", "x", time.Now().Unix()); err != nil {
		t.Fatalf("seed article: %v", err)
	}
	if _, err := database.Exec(`INSERT INTO banner_slides (id, image_url, ord, article_id) VALUES (?, ?, ?, ?)`,
		"b-1", "http://example.com/img.jpg", 0, "a-3"); err != nil {
		t.Fatalf("seed banner: %v", err)
	}

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/articles/a-3", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("DELETE: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("DELETE status = %d, want 204", resp.StatusCode)
	}

	var articleID sql.NullString
	if err := database.QueryRow(`SELECT article_id FROM banner_slides WHERE id = 'b-1'`).Scan(&articleID); err != nil {
		t.Fatalf("re-read: %v", err)
	}
	if articleID.Valid {
		t.Errorf("article_id should be NULL after delete, got %q", articleID.String)
	}
}

// TestBannerCreateRequiresImageURL asserts the only required-field
// check on banners.
func TestBannerCreateRequiresImageURL(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"id": "b-2", "title": "no img"}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/banners", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	respBody, _ := readAll(resp)
	if !bytes.Contains(respBody, []byte("image_url is required")) {
		t.Errorf("body = %s, want it to mention 'image_url is required'", string(respBody))
	}
}
