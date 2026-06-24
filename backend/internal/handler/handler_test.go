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
	uploadCfg := uploadConfigForTest(uploadsDir)

	r := router.New(productRepo, storeRepo, uploadCfg, "*")
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
