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
	"github.com/ptg14/simshop/backend/models"
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
// and a temp uploads dir. Returns a configured *httptest.Server, the
// raw *sql.DB (for tests that need to seed rows bypassing handler
// validation), and a cleanup func the caller must defer.
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
	database.SetMaxOpenConns(2)
	// Enable FK enforcement so ON DELETE SET NULL actually fires.
	if _, err := database.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		t.Fatalf("enable FK: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := database.PingContext(ctx); err != nil {
		t.Fatalf("ping db: %v", err)
	}

	// Apply schema by reusing the production migrations. The
	// test harness goes through the same SchemaFor registry so
	// the SQLite test schema can never drift from what production
	// sees against a real SQLite file.
	if err := applyMigrations(database); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	dialect := db.DialectSQLite
	uploadCfg := uploadConfigForTest(uploadsDir)
	productRepo := db.NewProductRepo(database, dialect, uploadCfg)
	storeRepo := db.NewStoreRepo(database, dialect, uploadCfg)
	articleRepo := db.NewArticleRepo(database, dialect, uploadCfg)
	eventRepo := db.NewEventRepo(database, dialect)

	r := router.New(productRepo, storeRepo, articleRepo, eventRepo, uploadCfg, handler.NewSessionStore(), "", "*", nil)
	srv := httptest.NewServer(r)

	cleanup := func() {
		srv.Close()
		_ = database.Close()
	}
	return srv, database, cleanup
}

// applyMigrations runs the production schema registry against a raw
// *sql.DB. Tests stay SQLite-only; we hardcode the dialect so the
// path matches what production sees on a SQLite file.
func applyMigrations(database *sql.DB) error {
	for _, stmt := range db.SchemaFor(db.DialectSQLite) {
		if stmt == "" {
			continue
		}
		if _, err := database.Exec(stmt); err != nil {
			// SQLite ALTER TABLE on a pre-existing column errors with
			// "duplicate column name" — treat as no-op.
			if strings.Contains(err.Error(), "duplicate column name") {
				continue
			}
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
        "banner_url": "http://localhost:8080/uploads/seed-shirt.jpg",
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

// TestStoreInfoGoogleMapsUrlPersists asserts the new google_maps_url
// field round-trips through PUT/GET. Old clients that don't send the
// field must get an empty string back (default), so we send the
// body without the key and verify the GET response also has it.
func TestStoreInfoGoogleMapsUrlPersists(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	// PUT with the new key set.
	body := strings.NewReader(`{
        "name": "Cửa hàng ABC",
        "google_maps_url": "https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue"
    }`)
	req, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/store-info", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		respBody, _ := readAll(resp)
		t.Fatalf("PUT status = %d, body=%s", resp.StatusCode, string(respBody))
	}
	var put map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&put); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if put["google_maps_url"] != "https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue" {
		t.Errorf("PUT response google_maps_url = %v, want the value just set", put["google_maps_url"])
	}

	// GET should reflect the stored value.
	resp2, err := http.Get(srv.URL + "/api/store-info")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp2.Body.Close()
	var got map[string]any
	if err := json.NewDecoder(resp2.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["google_maps_url"] != "https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue" {
		t.Errorf("GET google_maps_url = %v, want the stored URL", got["google_maps_url"])
	}

	// Clearing the field via PUT round-trips back to "".
	body2 := strings.NewReader(`{
        "name": "Cửa hàng ABC",
        "google_maps_url": ""
    }`)
	req2, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/store-info", body2)
	req2.Header.Set("Content-Type", "application/json")
	resp3, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("clear PUT: %v", err)
	}
	resp3.Body.Close()
	if resp3.StatusCode != http.StatusOK {
		t.Fatalf("clear PUT status = %d, want 200", resp3.StatusCode)
	}
	resp4, err := http.Get(srv.URL + "/api/store-info")
	if err != nil {
		t.Fatalf("GET after clear: %v", err)
	}
	defer resp4.Body.Close()
	var got2 map[string]any
	if err := json.NewDecoder(resp4.Body).Decode(&got2); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got2["google_maps_url"] != "" && got2["google_maps_url"] != nil {
		t.Errorf("GET after clear google_maps_url = %v, want empty", got2["google_maps_url"])
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

// ---------- Product update option ID edge cases ----------
//
// These tests cover the contract [ProductRepo.Update] now guarantees for
// Option.ID values: empty and duplicate IDs are silently reassigned to
// fresh UUIDs rather than aborting the transaction with a 500. Without
// this tolerance, an admin copy/pasting a new option (or a buggy client
// submitting id="") would break every save for the whole product.

// TestProductUpdateEmptyOptionID asserts the "client sent id=\"\""
// case: a single new option without an ID should be persisted with a
// freshly-minted UUID.
func TestProductUpdateEmptyOptionID(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	createBody := strings.NewReader(`{
		"id": "p-upd",
		"name": "Áo thun",
		"description": "",
		"price": 100000,
		"image_url": "http://localhost:8080/uploads/p.jpg",
		"category": "Áo",
		"rating": 0,
		"specs": []
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/products", createBody)
	req.Header.Set("Content-Type", "application/json")
	if resp, err := http.DefaultClient.Do(req); err != nil {
		t.Fatalf("create: %v", err)
	} else if resp.StatusCode != http.StatusCreated {
		body, _ := readAll(resp)
		t.Fatalf("create status = %d, body=%s", resp.StatusCode, string(body))
	}

	// PUT with a single option whose id is "".
	putBody := strings.NewReader(`{
		"id": "p-upd",
		"name": "Áo thun",
		"description": "",
		"price": 100000,
		"image_url": "http://localhost:8080/uploads/p.jpg",
		"category": "Áo",
		"rating": 0,
		"specs": [],
		"images": ["http://localhost:8080/uploads/p.jpg"],
		"options": [{"id": "", "name": "Size M", "image_urls": []}]
	}`)
	req2, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/products/p-upd", putBody)
	req2.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("PUT status = %d, body=%s", resp.StatusCode, string(body))
	}

	var storedID string
	if err := database.QueryRow(
		`SELECT id FROM product_options WHERE product_id=? AND name=?`,
		"p-upd", "Size M",
	).Scan(&storedID); err != nil {
		t.Fatalf("read back option id: %v", err)
	}
	if storedID == "" {
		t.Errorf("option id persisted as empty string; want a UUID")
	}
}

// TestProductUpdateDuplicateOptionIDs is the regression test for the
// PRIMARY KEY collision that previously 500'd the whole transaction
// when two options in the same payload carried the same id. The
// server must tolerate this by minting a fresh UUID for the second
// occurrence and persisting both.
func TestProductUpdateDuplicateOptionIDs(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	// Seed product.
	createBody := strings.NewReader(`{
		"id": "p-dup",
		"name": "Áo thun",
		"description": "",
		"price": 100000,
		"image_url": "http://localhost:8080/uploads/p.jpg",
		"category": "Áo",
		"rating": 0,
		"specs": []
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/products", createBody)
	req.Header.Set("Content-Type", "application/json")
	if resp, err := http.DefaultClient.Do(req); err != nil {
		t.Fatalf("create: %v", err)
	} else if resp.StatusCode != http.StatusCreated {
		body, _ := readAll(resp)
		t.Fatalf("create status = %d, body=%s", resp.StatusCode, string(body))
	}

	// PUT with two options both carrying the SAME non-empty id. This is
	// the exact case the dedupe logic exists for: the client supplied
	// a colliding id (e.g. copy/paste, or a bug that re-uses id=""),
	// and without the fix the second INSERT fails the whole transaction
	// with a 500. With the fix the second occurrence is reassigned and
	// the PUT succeeds with both rows persisted.
	const collidingID = "dup-test-id-12345"
	putBody := strings.NewReader(`{
		"id": "p-dup",
		"name": "Áo thun",
		"description": "",
		"price": 100000,
		"image_url": "http://localhost:8080/uploads/p.jpg",
		"category": "Áo",
		"rating": 0,
		"specs": [],
		"images": ["http://localhost:8080/uploads/p.jpg"],
		"options": [
			{"id": "` + collidingID + `", "name": "Size M", "image_urls": []},
			{"id": "` + collidingID + `", "name": "Size L", "image_urls": []}
		]
	}`)
	req2, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/products/p-dup", putBody)
	req2.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("PUT: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("PUT status = %d, body=%s (expected 200 — duplicate id must not 500)", resp.StatusCode, string(body))
	}

	rows, err := database.Query(
		`SELECT id, name FROM product_options WHERE product_id=? ORDER BY ord ASC`,
		"p-dup",
	)
	if err != nil {
		t.Fatalf("query options: %v", err)
	}
	defer rows.Close()
	type row struct {
		id   string
		name string
	}
	var got []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.name); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got = append(got, r)
	}
	if len(got) != 2 {
		t.Fatalf("persisted options = %d, want 2", len(got))
	}
	if got[0].id == got[1].id {
		t.Errorf("both options got the same id %q — duplicate not reassigned", got[0].id)
	}
	// The first option preserves the client-supplied id; the second
	// is what the server minted. Lock the names to their rows so we
	// know the reassignment didn't also scramble order.
	if got[0].name != "Size M" {
		t.Errorf("first option name = %q, want Size M", got[0].name)
	}
	if got[1].name != "Size L" {
		t.Errorf("second option name = %q, want Size L", got[1].name)
	}
}

// TestProductCreateAcceptsNoImage asserts the regression: a product with
// no image_url and no images list (admin leaves the gallery empty)
// must still be accepted by POST /api/products. The old
// `validateProduct` enforced "at least one image is required" which
// locked admins out of creating text-only products and produced a
// confusing 400 when the admin UI submitted a draft.
//
// Other fields stay required by design (name + price > 0); only the
// image requirement was removed per the user request "image không bắt
// buộc".
func TestProductCreateAcceptsNoImage(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{
		"id": "p-noimg",
		"name": "Áo thun draft",
		"description": "",
		"price": 100000,
		"image_url": "",
		"images": [],
		"category": "",
		"categories": [],
		"rating": 0,
		"specs": []
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/products", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		respBody, _ := readAll(resp)
		t.Fatalf("status = %d, want 201 (body=%s)", resp.StatusCode, string(respBody))
	}
}

// TestProductCreateStillRequiresNameAndPrice locks the *other* half of
// the contract so a future refactor can't accidentally widen the
// relaxation to all fields. name + price > 0 stay required; only the
// image requirement was removed.
func TestProductCreateStillRequiresNameAndPrice(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	cases := []struct {
		name string
		body string
		want string
	}{
		{
			name: "missing name",
			body: `{"price": 100000, "image_url": ""}`,
			want: "name is required",
		},
		{
			name: "zero price",
			body: `{"name": "x", "price": 0, "image_url": ""}`,
			want: "price must be greater than 0",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/products", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("create: %v", err)
			}
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusBadRequest {
				respBody, _ := readAll(resp)
				t.Fatalf("status = %d, want 400 (body=%s)", resp.StatusCode, string(respBody))
			}
			respBody, _ := readAll(resp)
			if !bytes.Contains(respBody, []byte(tc.want)) {
				t.Errorf("body = %s, want it to contain %q", string(respBody), tc.want)
			}
		})
	}
}

// ---------- Pentest remediation tests ----------

// TestCreateCategory_PersistsName is the regression test for the
// CRITICAL-001 bug: AddCategory/AddLargeCategory used to bind the
// literal string "name" rather than the supplied variable, so every
// category POST silently stored NULL. After the fix the row's name
// column must equal the value the client sent.
func TestCreateCategory_PersistsName(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"name": "Phụ kiện"}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/categories", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		respBody, _ := readAll(resp)
		t.Fatalf("POST status = %d, body=%s", resp.StatusCode, string(respBody))
	}

	// Verify the row's name column actually equals "Phụ kiện" — the
	// old bug stored NULL despite the 201.
	var name sql.NullString
	if err := database.QueryRow(`SELECT name FROM categories WHERE name = ?`, "Phụ kiện").Scan(&name); err != nil {
		t.Fatalf("re-read stored name: %v", err)
	}
	if !name.Valid {
		t.Fatal("stored name is NULL — CRITICAL-001 regression")
	}
	if name.String != "Phụ kiện" {
		t.Errorf("stored name = %q, want %q", name.String, "Phụ kiện")
	}
}

// TestCreateLargeCategory_PersistsName mirrors the above for large
// categories (same root-cause bug).
func TestCreateLargeCategory_PersistsName(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"name": "Điện tử"}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/large-categories", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		respBody, _ := readAll(resp)
		t.Fatalf("POST status = %d, body=%s", resp.StatusCode, string(respBody))
	}

	var name sql.NullString
	if err := database.QueryRow(`SELECT name FROM large_categories WHERE name = ?`, "Điện tử").Scan(&name); err != nil {
		t.Fatalf("re-read: %v", err)
	}
	if !name.Valid {
		t.Fatal("stored name is NULL — CRITICAL-001 regression for large categories")
	}
}

// TestCreateCategory_RejectsInvalidName covers the MEDIUM-003 input
// validation. Three sub-cases: <script>-style payload, oversized
// name, and pure-whitespace.
func TestCreateCategory_RejectsInvalidName(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	cases := []struct {
		name     string
		body     string
		wantSubs string
	}{
		{
			name:     "script tag",
			body:     `{"name": "<script>alert(1)</script>"}`,
			wantSubs: "disallowed characters",
		},
		{
			name:     "oversized name",
			body:     `{"name": "` + strings.Repeat("a", 65) + `"}`,
			wantSubs: "64 characters",
		},
		{
			name:     "whitespace only",
			body:     `{"name": "   "}`,
			wantSubs: "name is required",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/categories", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatalf("POST: %v", err)
			}
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusBadRequest {
				respBody, _ := readAll(resp)
				t.Fatalf("status = %d, want 400 (body=%s)", resp.StatusCode, string(respBody))
			}
			respBody, _ := readAll(resp)
			if !bytes.Contains(respBody, []byte(tc.wantSubs)) {
				t.Errorf("body = %s, want it to contain %q", string(respBody), tc.wantSubs)
			}
		})
	}
}

// TestCreateCategory_WithNewLargeCategory covers the
// {name, large_category} POST path where large_category does NOT
// exist yet — AddCategoryWithParent is expected to upsert the
// large category first and then insert the category row with the
// resolved FK. Regression for the 500 the admin UI hits when
// creating a sub-category whose parent Large is brand-new.
func TestCreateCategory_WithNewLargeCategory(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"name":"Ao","large_category":"ThoiTrang"}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/categories", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	respBody, _ := readAll(resp)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("POST status = %d, body=%s", resp.StatusCode, string(respBody))
	}

	// Verify both rows landed. The Large should exist with the
	// supplied name, and the sub-category should reference it
	// through large_category_id (joined to its name).
	var (
		largeName  string
		subName    string
		joinedName string
	)
	if err := database.QueryRow(
		`SELECT name FROM large_categories WHERE name = ?`, "ThoiTrang",
	).Scan(&largeName); err != nil {
		t.Fatalf("large_categories row missing: %v", err)
	}
	if largeName != "ThoiTrang" {
		t.Errorf("large name = %q, want %q", largeName, "ThoiTrang")
	}
	if err := database.QueryRow(
		`SELECT c.name, lc.name
		   FROM categories c
		   LEFT JOIN large_categories lc ON lc.id = c.large_category_id
		  WHERE c.name = ?`, "Ao",
	).Scan(&subName, &joinedName); err != nil {
		t.Fatalf("categories row missing: %v", err)
	}
	if subName != "Ao" {
		t.Errorf("category name = %q, want %q", subName, "Ao")
	}
	if joinedName != "ThoiTrang" {
		t.Errorf("category.large_category_id → %q, want %q",
			joinedName, "ThoiTrang")
	}
}

// TestCreateCategory_WithExistingLargeCategory mirrors the above
// but the Large already exists, so AddCategoryWithParent must reuse
// its id rather than insert a duplicate row.
func TestCreateCategory_WithExistingLargeCategory(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	// Seed the Large first via the public endpoint.
	seed := strings.NewReader(`{"name":"ThoiTrang"}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/large-categories", seed)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("seed large: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("seed large status = %d", resp.StatusCode)
	}

	// Then create a sub-category under it.
	body := strings.NewReader(`{"name":"Ao","large_category":"ThoiTrang"}`)
	req, _ = http.NewRequest(http.MethodPost, srv.URL+"/api/categories", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	defer resp.Body.Close()
	respBody, _ := readAll(resp)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("POST status = %d, body=%s", resp.StatusCode, string(respBody))
	}

	// Exactly one Large row, exactly one sub-category, joined.
	var (
		largeCount int
		subCount   int
		joinedName string
	)
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM large_categories WHERE name = ?`, "ThoiTrang",
	).Scan(&largeCount); err != nil {
		t.Fatalf("count large: %v", err)
	}
	if largeCount != 1 {
		t.Errorf("large count = %d, want 1", largeCount)
	}
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM categories WHERE name = ?`, "Ao",
	).Scan(&subCount); err != nil {
		t.Fatalf("count sub: %v", err)
	}
	if subCount != 1 {
		t.Errorf("sub count = %d, want 1", subCount)
	}
	if err := database.QueryRow(
		`SELECT lc.name
		   FROM categories c
		   JOIN large_categories lc ON lc.id = c.large_category_id
		  WHERE c.name = ?`, "Ao",
	).Scan(&joinedName); err != nil {
		t.Fatalf("join: %v", err)
	}
	if joinedName != "ThoiTrang" {
		t.Errorf("joined large = %q, want %q", joinedName, "ThoiTrang")
	}
}

// TestDeleteProduct_Returns404OnMissing is the regression test for
// HIGH-001: the handler used to return 204 unconditionally, hiding
// from admins whether their delete attempt hit a row.
func TestDeleteProduct_Returns404OnMissing(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/products/does-not-exist-uuid", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("DELETE: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

// TestDeleteProduct_WithOptions pins the contract that DELETE
// /api/products/{id} succeeds when the product has option rows on
// the modern schema (FK ON DELETE CASCADE). The repo's Delete()
// emits explicit DELETE FROM product_options / product_images
// statements before the parent row goes; on the CASCADE schema
// those are no-ops, but the test still proves the handler doesn't
// 500 on the join tables.
func TestDeleteProduct_WithOptions(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	if _, err := database.Exec(
		`INSERT INTO products (id, name, description, price, image_url, category, rating, specs)
		 VALUES (?, 'Áo thun', 'Cotton', 99000.0, '', 'Thời trang', 4.5, '[]')`,
		"p-1",
	); err != nil {
		t.Fatalf("seed product: %v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO product_options (id, product_id, name, image_urls)
		 VALUES (?, ?, 'Đỏ', '["http://localhost:8080/uploads/red.png"]')`,
		"o-1", "p-1",
	); err != nil {
		t.Fatalf("seed option: %v", err)
	}

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/products/p-1", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("DELETE: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("DELETE status=%d body=%s", resp.StatusCode, string(body))
	}

	var optionCount int
	if err := database.QueryRow(`SELECT COUNT(*) FROM product_options WHERE product_id='p-1'`).Scan(&optionCount); err != nil {
		t.Fatalf("count options: %v", err)
	}
	if optionCount != 0 {
		t.Fatalf("product_options rows left over after delete: %d", optionCount)
	}
}

// TestDeleteProduct_LegacyPostgresNoCascade pins the contract that
// the explicit DELETE FROM product_options / product_images statements
// in repo.Delete() work even when the schema lacks ON DELETE CASCADE.
// We build a hand-rolled schema (no FK) and seed the same shape; the
// test would have returned 500 before the fix because the implicit
// cleanup failed.
func TestDeleteProduct_LegacyPostgresNoCascade(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	// Override the default product_options table to drop the FK so
	// we exercise the "no CASCADE" path. SchemaFor already created
	// the table with a FK; drop and recreate without it.
	if _, err := database.Exec(`DROP TABLE product_options`); err != nil {
		t.Fatalf("drop product_options: %v", err)
	}
	if _, err := database.Exec(`CREATE TABLE product_options (
		id TEXT PRIMARY KEY,
		product_id TEXT NOT NULL,
		name TEXT NOT NULL,
		image_urls TEXT NOT NULL DEFAULT '[]'
	)`); err != nil {
		t.Fatalf("recreate product_options: %v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO products (id, name, description, price, image_url, category, rating, specs)
		 VALUES (?, 'Áo thun', 'Cotton', 99000.0, '', 'Thời trang', 4.5, '[]')`,
		"p-legacy",
	); err != nil {
		t.Fatalf("seed product: %v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO product_options (id, product_id, name, image_urls)
		 VALUES ('o-legacy', 'p-legacy', 'Đỏ', '[]')`,
	); err != nil {
		t.Fatalf("seed option: %v", err)
	}

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/products/p-legacy", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("DELETE: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("DELETE status=%d body=%s", resp.StatusCode, string(body))
	}

	var optionCount int
	if err := database.QueryRow(`SELECT COUNT(*) FROM product_options WHERE product_id='p-legacy'`).Scan(&optionCount); err != nil {
		t.Fatalf("count options: %v", err)
	}
	if optionCount != 0 {
		t.Fatalf("orphan product_options rows after delete: %d", optionCount)
	}
}

// TestDeleteProduct_ScrubsArticleAndEventReferences pins the
// junction-by-JSON scrub: deleting a product must remove its id from
// articles.product_ids and events.product_ids even though those
// columns have no FK to products. The helper short-circuits rows
// whose JSON doesn't actually contain the deleted id, so untouched
// rows stay byte-identical.
func TestDeleteProduct_ScrubsArticleAndEventReferences(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	const liveProductID = "11111111-1111-1111-1111-111111111111"
	const deadProductID = "22222222-2222-2222-2222-222222222222"

	if _, err := database.Exec(
		`INSERT INTO products (id, name, description, price, image_url, category, rating, specs)
		 VALUES (?, 'Áo', '', 0, '', '', 0, '[]')`,
		liveProductID,
	); err != nil {
		t.Fatalf("seed live product: %v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO products (id, name, description, price, image_url, category, rating, specs)
		 VALUES (?, 'Quần', '', 0, '', '', 0, '[]')`,
		deadProductID,
	); err != nil {
		t.Fatalf("seed dead product: %v", err)
	}

	// Article that referenced both ids — only the dead one must go.
	if _, err := database.Exec(
		`INSERT INTO articles (id, title, body_markdown, product_ids, created_at, is_draft)
		 VALUES ('a-1', 'Bài viết', '', ?, 1, 0)`,
		`["`+liveProductID+`","`+deadProductID+`"]`,
	); err != nil {
		t.Fatalf("seed article: %v", err)
	}

	// Event that referenced the dead id twice plus live once — duplicates
	// of the dead id must collapse to a single removal; live stays.
	if _, err := database.Exec(
		`INSERT INTO events (id, name, discount_type, discount_value, product_ids, created_at)
		 VALUES ('e-1', 'Sự kiện', 'percent', 10, ?, 1)`,
		`["`+liveProductID+`","`+deadProductID+`","`+deadProductID+`"]`,
	); err != nil {
		t.Fatalf("seed event e-1: %v", err)
	}

	// Event that doesn't reference the dead id — must stay untouched.
	if _, err := database.Exec(
		`INSERT INTO events (id, name, discount_type, discount_value, product_ids, created_at)
		 VALUES ('e-2', 'Khác', 'percent', 5, ?, 1)`,
		`["`+liveProductID+`"]`,
	); err != nil {
		t.Fatalf("seed event e-2: %v", err)
	}

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/api/products/"+deadProductID, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("DELETE: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		body, _ := readAll(resp)
		t.Fatalf("DELETE status=%d body=%s", resp.StatusCode, string(body))
	}

	// Article row: dead id gone, live id preserved.
	var articleIDs string
	if err := database.QueryRow(`SELECT product_ids FROM articles WHERE id='a-1'`).Scan(&articleIDs); err != nil {
		t.Fatalf("re-read article: %v", err)
	}
	var parsedArticle []string
	if err := json.Unmarshal([]byte(articleIDs), &parsedArticle); err != nil {
		t.Fatalf("decode article product_ids = %q: %v", articleIDs, err)
	}
	if len(parsedArticle) != 1 || parsedArticle[0] != liveProductID {
		t.Fatalf("articles.product_ids = %v after delete, want [%q]", parsedArticle, liveProductID)
	}

	// Event row that referenced the dead id (twice) — both
	// occurrences must be gone, live id preserved, no duplicates.
	var eventIDs string
	if err := database.QueryRow(`SELECT product_ids FROM events WHERE id='e-1'`).Scan(&eventIDs); err != nil {
		t.Fatalf("re-read event e-1: %v", err)
	}
	var parsedEvent []string
	if err := json.Unmarshal([]byte(eventIDs), &parsedEvent); err != nil {
		t.Fatalf("decode event e-1 product_ids = %q: %v", eventIDs, err)
	}
	if len(parsedEvent) != 1 || parsedEvent[0] != liveProductID {
		t.Fatalf("events[id=e-1].product_ids = %v after delete, want [%q]", parsedEvent, liveProductID)
	}

	// Untouched event row — must NOT have been rewritten.
	var untouchedIDs string
	if err := database.QueryRow(`SELECT product_ids FROM events WHERE id='e-2'`).Scan(&untouchedIDs); err != nil {
		t.Fatalf("re-read event e-2: %v", err)
	}
	if untouchedIDs != `["`+liveProductID+`"]` {
		t.Fatalf("events[id=e-2].product_ids = %q after delete, want [\"%s\"] (row must stay untouched)", untouchedIDs, liveProductID)
	}
}

// TestGetCategoriesWithParent_HandlesNULL covers the MEDIUM-001 fix:
// the read path now scans c.name via sql.NullString instead of a bare
// string. The production schema declares c.name NOT NULL, so we can't
// inject a NULL row without disabling the constraint — we instead use
// a dedicated in-memory DB that mirrors SchemaFor minus the NOT NULL
// on categories.name, then exercise the read path through the live
// handler.
func TestGetCategoriesWithParent_HandlesNULL(t *testing.T) {
	// Stand up a parallel SQLite DB with categories.name as nullable.
	tmpDir := t.TempDir()
	dsn := filepath.Join(tmpDir, "null.db")
	d, err := sql.Open("sqlite3", dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer d.Close()
	if _, err := d.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		t.Fatalf("FK: %v", err)
	}
	if _, err := d.Exec(`
		CREATE TABLE large_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE);
		CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, large_category_id INTEGER);
		CREATE TABLE store_info (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT 'simshop', description TEXT NOT NULL DEFAULT '', banner_url TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', google_maps_url TEXT NOT NULL DEFAULT '');
		INSERT INTO store_info (id) VALUES (1);
	`); err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := d.Exec(`INSERT INTO categories (name) VALUES (NULL)`); err != nil {
		t.Fatalf("insert NULL: %v", err)
	}

	uploadCfg := uploadConfigForTest(t.TempDir())
	productRepo := db.NewProductRepo(d, db.DialectSQLite, uploadCfg)
	storeRepo := db.NewStoreRepo(d, db.DialectSQLite, uploadCfg)
	articleRepo := db.NewArticleRepo(d, db.DialectSQLite, uploadCfg)
	eventRepo := db.NewEventRepo(d, db.DialectSQLite)

	r := router.New(productRepo, storeRepo, articleRepo, eventRepo, uploadCfg, handler.NewSessionStore(), "", "*", nil)
	srv := httptest.NewServer(r)
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/api/categories/with-parent")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		respBody, _ := readAll(resp)
		t.Fatalf("status = %d, want 200 (body=%s)", resp.StatusCode, string(respBody))
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	cats, ok := got["categories"].([]any)
	if !ok {
		t.Fatalf("categories field missing or not array: %v", got)
	}
	if len(cats) == 0 {
		t.Errorf("expected at least one row (the NULL-name row), got 0")
	}
}

// TestArticleDraftHidesFromAnonymous pins the LOW-001 repo contract:
// GetArticlePublic returns sql.ErrNoRows for drafts, while the admin
// GetArticle still returns the row. The handler layer maps the
// sql.ErrNoRows into a 404 via the existing pattern; the contract
// tested here is what the handler relies on.
func TestArticleDraftHidesFromAnonymous(t *testing.T) {
	// Stand up a dedicated in-memory DB so we control the schema
	// exactly and don't depend on the test server's admin-bypass
	// behavior.
	tmpDir := t.TempDir()
	dsn := filepath.Join(tmpDir, "drafts.db")
	d, err := sql.Open("sqlite3", dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer d.Close()
	if _, err := d.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		t.Fatalf("FK: %v", err)
	}
	if err := applyMigrations(d); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	repo := db.NewArticleRepo(d, db.DialectSQLite, nil)
	draft := models.Article{
		ID:            "draft-1",
		Title:         "WIP",
		BodyMarkdown:  "secret body",
		CoverImageURL: "",
		ProductIDs:    []string{},
		CreatedAt:     time.Now().Unix(),
		IsDraft:       true,
	}
	if _, err := repo.CreateArticle(draft); err != nil {
		t.Fatalf("create draft: %v", err)
	}

	if _, err := repo.GetArticlePublic("draft-1"); err != sql.ErrNoRows {
		t.Errorf("GetArticlePublic(draft) = %v, want sql.ErrNoRows", err)
	}
	got, err := repo.GetArticle("draft-1")
	if err != nil {
		t.Fatalf("GetArticle(draft) admin path: %v", err)
	}
	if !got.IsDraft {
		t.Errorf("IsDraft = false, want true (admin view)")
	}
}

// -----------------------------------------------------------------------------
// PATCH /api/products/{id}/stock — admin quick-adjust endpoint
// -----------------------------------------------------------------------------
//
// These tests exercise the new stock-only endpoint added for the
// admin product list's +/- stepper. The full-stack seed (admin auth,
// DB, router) is reused from newTestServer; the harness's default
// `adminPublicKeyHex=""` disables adminAuth so we can hit the
// admin-only PATCH route from a plain http.Client without
// performing the Ed25519 challenge/verify dance.
//
// Each test seeds its own row by direct INSERT so the assertions
// stay focused on the handler contract (200/400/404 + payload) and
// not on CreateProduct's validation rules.

func insertTestProduct(t *testing.T, database *sql.DB, id string, stock *int) {
	t.Helper()
	// stock column is nullable; pass nil to mean "unknown" so the
	// handler's pointer-vs-nil dispatch is also exercised.
	var stockArg interface{}
	if stock != nil {
		stockArg = *stock
	}
	_, err := database.Exec(`
		INSERT INTO products
			(id, name, description, price, image_url, category, rating, stock, specs, categories)
		VALUES
			(?, ?, '', 100000, '', 'Áo thun', 0, ?, '[]', '[]')`,
		id, "Áo thun "+id, stockArg)
	if err != nil {
		t.Fatalf("seed product %s: %v", id, err)
	}
}

// TestUpdateProductStock_HappyPath asserts that a valid PATCH
// rewrites ONLY the stock column and returns the refreshed product.
// This is the regression guard for the bug that motivated the
// endpoint: the old path PUT'd the entire product back, which could
// clobber a concurrent edit from another admin tab.
func TestUpdateProductStock_HappyPath(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	insertTestProduct(t, database, "stock-1", intPtr(7))

	body := strings.NewReader(`{"stock": 12}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/stock-1/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		respBody, _ := readAll(resp)
		t.Fatalf("status = %d, want 200 (body=%s)", resp.StatusCode, string(respBody))
	}

	var got map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got["id"] != "stock-1" {
		t.Errorf("response id = %v, want stock-1", got["id"])
	}
	// JSON numbers decode as float64.
	if s, ok := got["stock"].(float64); !ok || s != 12 {
		t.Errorf("response stock = %v (%T), want 12", got["stock"], got["stock"])
	}

	// Re-read via the public GET so we know the value actually
	// landed on disk (not just in the response echo).
	req2, _ := http.NewRequest(http.MethodGet, srv.URL+"/api/products/stock-1", nil)
	resp2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusOK {
		t.Fatalf("GET status = %d, want 200", resp2.StatusCode)
	}
	var persisted map[string]interface{}
	if err := json.NewDecoder(resp2.Body).Decode(&persisted); err != nil {
		t.Fatalf("decode GET: %v", err)
	}
	if s, ok := persisted["stock"].(float64); !ok || s != 12 {
		t.Errorf("persisted stock = %v (%T), want 12", persisted["stock"], persisted["stock"])
	}
}

// TestUpdateProductStock_RejectsUnknownFields pins the contract
// that the body schema is strict — only {"stock": <int|null>} is
// accepted. An attacker (or a buggy client) cannot smuggle a
// rename/reprice through this endpoint by piggybacking extra keys;
// the handler must 400 before the write hits disk.
//
// This is the security-oriented counterpart to the happy path:
// readJSONBody uses DisallowUnknownFields so the rejection happens
// at parse time, before the repo is touched.
func TestUpdateProductStock_RejectsUnknownFields(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	insertTestProduct(t, database, "stock-2", intPtr(3))

	// Try to rewrite the name + price via the stock endpoint.
	// They MUST be rejected with 400, not silently dropped.
	body := strings.NewReader(`{"stock": 9, "name": "HACKED", "price": 1}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/stock-2/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 — extra body fields must not be accepted", resp.StatusCode)
	}

	// Confirm the row's other fields were NOT touched even by a
	// malicious request (defense-in-depth: even if the strict
	// parser were ever loosened, the repo only writes `stock`).
	var name string
	var price float64
	if err := database.QueryRow(
		`SELECT name, price FROM products WHERE id=?`, "stock-2",
	).Scan(&name, &price); err != nil {
		t.Fatalf("scan: %v", err)
	}
	if name == "HACKED" {
		t.Errorf("name was overwritten to HACKED despite 400 response")
	}
	if price != 100000 {
		t.Errorf("price = %v, want 100000 (untouched seed value)", price)
	}

	// And stock must also be untouched — the parse error must
	// happen BEFORE any DB write.
	var stock sql.NullFloat64
	if err := database.QueryRow(
		`SELECT stock FROM products WHERE id=?`, "stock-2",
	).Scan(&stock); err != nil {
		t.Fatalf("scan stock: %v", err)
	}
	if !stock.Valid || stock.Float64 != 3 {
		t.Errorf("stock on disk = %+v, want 3 (unchanged after 400)", stock)
	}
}

// TestUpdateProductStock_RejectsNegative guards the 400 path. The
// repo surfaces db.ErrInvalidStock which the handler maps to
// BadRequest rather than letting it bubble up as a 500.
func TestUpdateProductStock_RejectsNegative(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	insertTestProduct(t, database, "stock-3", intPtr(5))

	body := strings.NewReader(`{"stock": -1}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/stock-3/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	// Stock must NOT have been changed.
	var row struct {
		Stock sql.NullFloat64
	}
	if err := database.QueryRow(`SELECT stock FROM products WHERE id=?`, "stock-3").Scan(&row.Stock); err != nil {
		t.Fatalf("scan: %v", err)
	}
	if !row.Stock.Valid || row.Stock.Float64 != 5 {
		t.Errorf("stock on disk = %+v, want 5 (unchanged)", row.Stock)
	}
}

// TestUpdateProductStock_RejectsMalformedBody locks the
// "garbage in → 400 out" contract so future refactors can't
// silently fall back to "set stock to NULL" on a broken payload.
func TestUpdateProductStock_RejectsMalformedBody(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	insertTestProduct(t, database, "stock-4", intPtr(2))

	body := strings.NewReader(`not-json-at-all`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/stock-4/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

// TestUpdateProductStock_Returns404OnMissing — the quick-adjust
// stepper must surface "product gone" as a clean 404 so the VM
// can show the user a clear error rather than a stale-spinner
// silence.
func TestUpdateProductStock_Returns404OnMissing(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	body := strings.NewReader(`{"stock": 4}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/does-not-exist/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

// TestUpdateProductStock_NullClearsColumn — passing the JSON
// literal `null` for `stock` should store SQL NULL (= unknown),
// not 0. The frontend distinguishes the two: NULL renders as "?"
// (we don't know), 0 renders as "0" (out of stock).
func TestUpdateProductStock_NullClearsColumn(t *testing.T) {
	srv, database, cleanup := newTestServer(t)
	defer cleanup()

	insertTestProduct(t, database, "stock-5", intPtr(11))

	body := strings.NewReader(`{"stock": null}`)
	req, _ := http.NewRequest(http.MethodPatch, srv.URL+"/api/products/stock-5/stock", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("PATCH: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		respBody, _ := readAll(resp)
		t.Fatalf("status = %d, want 200 (body=%s)", resp.StatusCode, string(respBody))
	}
	var row struct {
		Stock sql.NullFloat64
	}
	if err := database.QueryRow(`SELECT stock FROM products WHERE id=?`, "stock-5").Scan(&row.Stock); err != nil {
		t.Fatalf("scan: %v", err)
	}
	if row.Stock.Valid {
		t.Errorf("stock on disk = %+v, want NULL after null-clearing PATCH", row.Stock)
	}
}

func intPtr(v int) *int { return &v }
