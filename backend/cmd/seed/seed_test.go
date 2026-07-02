package main

import (
	"context"
	"path/filepath"
	"testing"
)

// TestApplySchemaEmpty asserts that running applySchema against a
// fresh SQLite file produces a working schema with zero products
// (the seed command deliberately does not insert fixtures — sample
// data is created through the admin UI / product handlers).
func TestApplySchemaEmpty(t *testing.T) {
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "seed_test.db")

	database, dialect, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	defer database.Close()

	if err := applySchema(database, dialect); err != nil {
		t.Fatalf("apply schema: %v", err)
	}

	var count int
	if err := database.QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM products`).Scan(&count); err != nil {
		t.Fatalf("count products: %v", err)
	}
	if count != 0 {
		t.Errorf("expected 0 products after fresh schema, got %d", count)
	}

	// All required tables should exist after applySchema.
	for _, table := range []string{
		"products", "product_images", "product_options",
		"large_categories", "categories",
		"store_info", "articles", "banner_slides",
		"events",
	} {
		var name string
		err := database.QueryRowContext(context.Background(),
			`SELECT name FROM sqlite_master WHERE type='table' AND name=?`, table,
		).Scan(&name)
		if err != nil {
			t.Errorf("table %s missing after applySchema: %v", table, err)
		}
	}
}