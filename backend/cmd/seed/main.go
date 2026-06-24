package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// Product mirrors the definition used by the backend server.
type Product struct {
	ID            string    `json:"id"`
	Name          string    `json:"name"`
	Description   string    `json:"description"`
	Price         float64   `json:"price"`
	OriginalPrice *float64  `json:"original_price,omitempty"`
	ImageURL      string    `json:"image_url"`
	Category      string    `json:"category"`
	Categories    []string  `json:"categories"`
	StoreID       *string   `json:"store_id,omitempty"`
	Rating        float64   `json:"rating"`
	Reviews       *int32    `json:"reviews,omitempty"`
	Stock         *int32    `json:"stock,omitempty"`
	Specs         []string  `json:"specs"`
	Options       []Option  `json:"options,omitempty"`
	Images        []string  `json:"images,omitempty"`
}

type Option struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Price     *float64 `json:"price,omitempty"`
	Stock     *int32   `json:"stock,omitempty"`
	ImageURLs []string `json:"image_urls,omitempty"`
}

func intPtr(v int32) *int32       { return &v }
func floatPtr(v float64) *float64 { return &v }

// openDB opens a SQLite connection at dsn and returns it to the caller,
// who is responsible for closing it.
func openDB(dsn string) (*sql.DB, error) {
	return sql.Open("sqlite3", dsn)
}

// applySchema creates the tables the server (and the seed) need. Idempotent.
func applySchema(db *sql.DB) error {
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
            specs TEXT NOT NULL DEFAULT '[]',
            categories TEXT NOT NULL DEFAULT '[]'
        );`,
		`CREATE TABLE IF NOT EXISTS product_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id TEXT NOT NULL,
            image_url TEXT NOT NULL,
            ord INTEGER NOT NULL DEFAULT 0
        );`,
		`CREATE TABLE IF NOT EXISTS large_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        );`,
		`CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            large_category_id INTEGER,
            FOREIGN KEY(large_category_id) REFERENCES large_categories(id) ON DELETE SET NULL
        );`,
	}
	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return fmt.Errorf("schema: %w", err)
		}
	}
	return nil
}

// seed inserts the sample data into db. If uploadsDir + publicBaseURL are
// provided, it downloads each product's primary image into uploadsDir and
// rewrites ImageURL/Images to point at publicBaseURL/uploads/<file> so the
// frontend always loads images from the same origin (no CORS, no 404s).
//
// Returns nil if data already exists (skipped), or after successful insert.
// An error is returned on any DB or download failure.
func seed(db *sql.DB, uploadsDir, publicBaseURL string) error {
	var count int
	if err := db.QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM products").Scan(&count); err != nil {
		return fmt.Errorf("count products: %w", err)
	}
	if count > 0 {
		return nil // already seeded
	}

	// Source images: picsum.photos serves real, random photos at fixed
	// dimensions and never returns 404. We pin the seed so a re-run gives
	// the same images.
	type src struct {
		filename string
		url      string
	}
	sources := []src{
		{"seed-shirt.jpg", "https://picsum.photos/seed/simshop-shirt/800/800"},
		{"seed-headphones.jpg", "https://picsum.photos/seed/simshop-headphones/800/800"},
	}

	if uploadsDir != "" {
		if err := os.MkdirAll(uploadsDir, 0o755); err != nil {
			return fmt.Errorf("mkdir uploads: %w", err)
		}
		client := &http.Client{Timeout: 15 * time.Second}
		for _, s := range sources {
			dst := filepath.Join(uploadsDir, s.filename)
			if _, err := os.Stat(dst); err == nil {
				continue // already downloaded
			}
			if err := download(client, s.url, dst); err != nil {
				return fmt.Errorf("download %s: %w", s.url, err)
			}
		}
	}

	// Build absolute URLs that the backend will serve. Strip trailing /
	// from publicBaseURL to avoid double slashes.
	base := strings.TrimRight(publicBaseURL, "/")
	shirtURL := base + "/uploads/" + sources[0].filename
	headphonesURL := base + "/uploads/" + sources[1].filename

	samples := []Product{
		{
			ID:            "p1",
			Name:          "Áo thun nam cotton",
			Description:   "Áo thun cotton 100%, thoáng mát, form regular fit.",
			Price:         299000,
			OriginalPrice: floatPtr(399000),
			ImageURL:      shirtURL,
			Images:        []string{shirtURL},
			Category:      "Áo thun",
			Categories:    []string{"Áo thun"},
			Rating:        4.5,
			Reviews:       intPtr(120),
			Stock:         intPtr(85),
			Specs:         []string{"Chất liệu: Cotton 100%", "Size: M / L / XL"},
			Options: []Option{
				{ID: "p1-s", Name: "Size S", Price: floatPtr(299000), Stock: intPtr(20), ImageURLs: []string{}},
				{ID: "p1-m", Name: "Size M", Price: floatPtr(299000), Stock: intPtr(35), ImageURLs: []string{}},
				{ID: "p1-l", Name: "Size L", Price: floatPtr(329000), Stock: intPtr(30), ImageURLs: []string{}},
			},
		},
		{
			ID:            "p2",
			Name:          "Tai nghe chống ồn không dây",
			Description:   "Tai nghe over-ear chống ồn chủ động, pin 30 giờ.",
			Price:         2490000,
			OriginalPrice: floatPtr(3190000),
			ImageURL:      headphonesURL,
			Images:        []string{headphonesURL},
			Category:      "Tai nghe",
			Categories:    []string{"Tai nghe"},
			Rating:        4.8,
			Reviews:       intPtr(45),
			Stock:         intPtr(30),
			Specs:         []string{"Pin: 30 giờ", "Bluetooth: 5.3"},
			Options: []Option{
				{ID: "p2-bk", Name: "Đen", Price: floatPtr(2490000), Stock: intPtr(15), ImageURLs: []string{}},
				{ID: "p2-wh", Name: "Trắng", Price: floatPtr(2590000), Stock: intPtr(15), ImageURLs: []string{}},
			},
		},
	}

	largeToSubs := map[string][]string{
		"Thời trang": {"Áo thun"},
		"Điện tử":    {"Tai nghe"},
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	// rollback is a no-op after commit; safe to call unconditionally.
	defer tx.Rollback()

	largeIDs := make(map[string]int64, len(largeToSubs))
	for large := range largeToSubs {
		if _, err := tx.Exec(`INSERT OR IGNORE INTO large_categories (name) VALUES (?)`, large); err != nil {
			return fmt.Errorf("insert large_category %q: %w", large, err)
		}
		var id int64
		if err := tx.QueryRow(`SELECT id FROM large_categories WHERE name = ?`, large).Scan(&id); err != nil {
			return fmt.Errorf("lookup large_category %q: %w", large, err)
		}
		largeIDs[large] = id
	}
	for large, subs := range largeToSubs {
		for _, sub := range subs {
			if _, err := tx.Exec(`INSERT OR IGNORE INTO categories (name, large_category_id) VALUES (?, ?)`, sub, largeIDs[large]); err != nil {
				return fmt.Errorf("insert sub-category %q: %w", sub, err)
			}
		}
	}

	stmt, err := tx.Prepare(`INSERT INTO products (id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs, categories) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return fmt.Errorf("prepare stmt: %w", err)
	}
	defer stmt.Close()

	for _, p := range samples {
		specsJSON, _ := json.Marshal(p.Specs)
		cats := p.Categories
		if len(cats) == 0 && p.Category != "" {
			cats = []string{p.Category}
		}
		categoriesJSON, _ := json.Marshal(cats)
		_, err := stmt.Exec(p.ID, p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON), string(categoriesJSON))
		if err != nil {
			return fmt.Errorf("insert sample %q: %w", p.Name, err)
		}
		if p.ImageURL != "" {
			if _, err := tx.Exec(`INSERT INTO product_images (product_id, image_url, ord) VALUES (?,?,?)`, p.ID, p.ImageURL, 0); err != nil {
				return fmt.Errorf("insert image sample: %w", err)
			}
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// download fetches url into path with a GET + small timeout. Creates any
// parent dirs as needed.
func download(client *http.Client, url, path string) error {
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "test.db"
	}
	uploadsDir := os.Getenv("UPLOAD_DIR")
	publicBase := os.Getenv("PUBLIC_BASE_URL")
	if publicBase == "" {
		publicBase = "http://localhost:8080"
	}

	db, err := openDB(dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	if err := applySchema(db); err != nil {
		log.Fatalf("apply schema: %v", err)
	}

	var count int
	if err := db.QueryRowContext(context.Background(),
		"SELECT COUNT(*) FROM products").Scan(&count); err != nil {
		log.Fatalf("count products: %v", err)
	}
	if count > 0 {
		fmt.Println("Database already contains data; skipping seeding.")
		return
	}

	if err := seed(db, uploadsDir, publicBase); err != nil {
		log.Fatalf("seed: %v", err)
	}
	fmt.Println("Sample data inserted into", dsn)
}
