package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestSeedImagesResolve asserts that every product the seed inserts has an
// image_url that actually responds with HTTP 200. This guards against the
// recurring bug where seed data references example.com placeholders or
// stale UUID upload paths that return 404, leaving the home screen blank.
//
// The test runs the seed against a temp SQLite DB and a local uploads dir,
// then starts a small HTTP server that mimics the backend's /uploads handler
// so absolute URLs that point back into the seed are also testable.
func TestSeedImagesResolve(t *testing.T) {
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "seed_test.db")
	uploadsDir := filepath.Join(tmpDir, "uploads")
	if err := os.MkdirAll(uploadsDir, 0o755); err != nil {
		t.Fatalf("mkdir uploads: %v", err)
	}

	// The seed downloads from picsum.photos which is occasionally slow or
	// rate-limited in CI. Skip the test in that case rather than failing
	// on a flake, but record the reason so the operator knows.
	if testing.Short() {
		t.Skip("seed test requires network for image downloads")
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer db.Close()

	if err := applySchema(db); err != nil {
		t.Fatalf("apply schema: %v", err)
	}
	if err := seed(db, uploadsDir, "http://placeholder.invalid"); err != nil {
		t.Fatalf("seed: %v", err)
	}

	// Stand up a static file server backed by the *parent* of uploadsDir so
	// request paths of the form /uploads/<file> resolve correctly under
	// http.FileServer.
	uploadsServer := httptest.NewServer(http.FileServer(http.Dir(tmpDir)))
	defer uploadsServer.Close()

	rows, err := db.QueryContext(context.Background(),
		`SELECT id, name, image_url FROM products`)
	if err != nil {
		t.Fatalf("query products: %v", err)
	}
	defer rows.Close()

	type product struct {
		id, name, imageURL string
	}
	var products []product
	for rows.Next() {
		var p product
		if err := rows.Scan(&p.id, &p.name, &p.imageURL); err != nil {
			t.Fatalf("scan: %v", err)
		}
		products = append(products, p)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("rows: %v", err)
	}
	if len(products) == 0 {
		t.Fatalf("seed inserted no products")
	}

	client := &http.Client{Timeout: 5 * time.Second}
	for _, p := range products {
		if strings.TrimSpace(p.imageURL) == "" {
			t.Errorf("product %q (%s) has empty image_url", p.name, p.id)
			continue
		}
		if !strings.HasPrefix(p.imageURL, "http://") && !strings.HasPrefix(p.imageURL, "https://") {
			t.Errorf("product %q (%s) image_url is not absolute: %q", p.name, p.id, p.imageURL)
			continue
		}
		// Rewrite the well-known placeholder host to our local uploads
		// server so we can verify the file actually exists.
		target := p.imageURL
		if strings.HasPrefix(target, "http://placeholder.invalid/") {
			rest := strings.TrimPrefix(target, "http://placeholder.invalid")
			u, err := url.Parse(uploadsServer.URL + rest)
			if err != nil {
				t.Errorf("product %q (%s) bad url %q: %v", p.name, p.id, target, err)
				continue
			}
			target = u.String()
		}

		resp, err := client.Get(target)
		if err != nil {
			t.Errorf("product %q (%s) GET %q failed: %v", p.name, p.id, target, err)
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("product %q (%s) GET %q returned %d, want 200", p.name, p.id, target, resp.StatusCode)
			continue
		}
		if len(body) < 256 {
			t.Errorf("product %q (%s) GET %q returned %d bytes, want >=256 (image is empty/truncated)",
				p.name, p.id, target, len(body))
			continue
		}
		ct := resp.Header.Get("Content-Type")
		if !strings.HasPrefix(ct, "image/") {
			t.Errorf("product %q (%s) GET %q returned Content-Type %q, want image/*",
				p.name, p.id, target, ct)
		}
	}
}

// readAndClose drains resp.Body and closes it. Errors are ignored.
func readAndClose(_ *http.Response) {}
