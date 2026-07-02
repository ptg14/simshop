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
	productRepo := db.NewProductRepo(database, dialect)
	storeRepo := db.NewStoreRepo(database, dialect)
	articleRepo := db.NewArticleRepo(database, dialect)
	eventRepo := db.NewEventRepo(database, dialect)
	uploadCfg := uploadConfigForTest(uploadsDir)

	r := router.New(productRepo, storeRepo, articleRepo, eventRepo, uploadCfg, handler.NewSessionStore(), "", "*")
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
