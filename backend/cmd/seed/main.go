package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

// Product mirrors the definition used by the backend server.
type Product struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Description   string   `json:"description"`
	Price         float64  `json:"price"`
	OriginalPrice *float64 `json:"original_price,omitempty"`
	ImageURL      string   `json:"image_url"`
	Category      string   `json:"category"`
	StoreID       *string  `json:"store_id,omitempty"`
	Rating        float64  `json:"rating"`
	Reviews       *int32   `json:"reviews,omitempty"`
	Stock         *int32   `json:"stock,omitempty"`
	Specs         []string `json:"specs"`
}

func intPtr(v int32) *int32       { return &v }
func floatPtr(v float64) *float64 { return &v }

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "test.db"
	}
	db, err := sql.Open("sqlite3", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	// Ensure the schema exists (same as backend).
	schema := `
    CREATE TABLE IF NOT EXISTS products (
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
    );`
	if _, err := db.Exec(schema); err != nil {
		log.Fatalf("create schema: %v", err)
	}

	// product_images table for multiple images per product
	imagesSchema := `
    CREATE TABLE IF NOT EXISTS product_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL,
        image_url TEXT NOT NULL,
        ord INTEGER NOT NULL DEFAULT 0
    );`
	if _, err := db.Exec(imagesSchema); err != nil {
		log.Fatalf("create images schema: %v", err)
	}

	// Skip seeding if data already present.
	var count int
	if err := db.QueryRowContext(context.Background(), "SELECT COUNT(*) FROM products").Scan(&count); err != nil {
		log.Fatalf("count products: %v", err)
	}
	if count > 0 {
		fmt.Println("Database already contains data; skipping seeding.")
		return
	}

	samples := []Product{
		{
			ID:            "p1",
			Name:          "Sample Shirt",
			Description:   "A comfortable cotton shirt.",
			Price:         29.99,
			OriginalPrice: nil,
			ImageURL:      "https://example.com/shirt.png",
			Category:      "Clothing",
			StoreID:       nil,
			Rating:        4.5,
			Reviews:       intPtr(12),
			Stock:         intPtr(100),
			Specs:         []string{"Size: M", "Color: Blue"},
		},
		{
			ID:            "p2",
			Name:          "Wireless Headphones",
			Description:   "Noise‑cancelling over‑ear headphones.",
			Price:         199.99,
			OriginalPrice: floatPtr(249.99),
			ImageURL:      "https://example.com/headphones.png",
			Category:      "Electronics",
			StoreID:       nil,
			Rating:        4.8,
			Reviews:       intPtr(45),
			Stock:         intPtr(30),
			Specs:         []string{"Battery: 20h", "Bluetooth: 5.0"},
		},
	}

	tx, err := db.Begin()
	if err != nil {
		log.Fatalf("begin tx: %v", err)
	}
	stmt, err := tx.Prepare(`INSERT INTO products (id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		log.Fatalf("prepare stmt: %v", err)
	}
	defer stmt.Close()

	for _, p := range samples {
		specsJSON, _ := json.Marshal(p.Specs)
		_, err := stmt.Exec(p.ID, p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON))
		if err != nil {
			tx.Rollback()
			log.Fatalf("insert sample: %v", err)
		}
		// Insert into product_images as well for compatibility
		if p.ImageURL != "" {
			if _, err := tx.Exec(`INSERT INTO product_images (product_id, image_url, ord) VALUES (?,?,?)`, p.ID, p.ImageURL, 0); err != nil {
				tx.Rollback()
				log.Fatalf("insert image sample: %v", err)
			}
		}
	}
	if err := tx.Commit(); err != nil {
		log.Fatalf("commit: %v", err)
	}
	fmt.Println("Sample data inserted into", dsn)
}
