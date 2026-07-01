package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/ptg14/simshop/backend/internal/config"
)

// DB wraps a *sql.DB and provides helper methods.
type DB struct {
	*sql.DB
}

// New creates a new DB instance based on the provided configuration.
func New(cfg *config.Config) (*DB, error) {
	db, err := sql.Open("sqlite3", cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetConnMaxLifetime(cfg.ConnMaxLifetime)

	// Verify connection.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return nil, err
	}

	// Enable foreign key constraints for SQLite. This ensures ON DELETE/UPDATE actions are enforced.
	if _, err := db.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		return nil, fmt.Errorf("enable foreign keys: %w", err)
	}

	// Run schema migrations.
	if err := runMigrations(db); err != nil {
		return nil, err
	}

	return &DB{DB: db}, nil
}

// runMigrations executes the initial schema. In a real project this would use a
// migration tool, but for now we embed the SQL directly.
func runMigrations(db *sql.DB) error {
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
	_, err := db.Exec(schema)
	if err != nil {
		return err
	}

	// Table to store multiple images per product. 'ord' preserves ordering.
	images := `
	CREATE TABLE IF NOT EXISTS product_images (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		product_id TEXT NOT NULL,
		image_url TEXT NOT NULL,
		ord INTEGER NOT NULL DEFAULT 0,
		FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
	);`
	_, err = db.Exec(images)
	if err != nil {
		return err
	}

	// Product options/variants table. Each option may reference multiple image URLs stored as JSON text.
	options := `
	CREATE TABLE IF NOT EXISTS product_options (
		id TEXT PRIMARY KEY,
		product_id TEXT NOT NULL,
		name TEXT NOT NULL,
		image_urls TEXT NOT NULL DEFAULT '[]',
		ord INTEGER NOT NULL DEFAULT 0,
		FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
	);`
	_, err = db.Exec(options)
	if err != nil {
		return err
	}

	// Ensure the image_urls column exists (SQLite will error if column exists; ignore error).
	if _, err = db.Exec(`ALTER TABLE product_options ADD COLUMN image_urls TEXT NOT NULL DEFAULT '[]'`); err != nil {
		// ignore error, column may already exist
	}

	// Categories table to persist available product categories.
	// Large categories (parent categories)
	largeCats := `
	CREATE TABLE IF NOT EXISTS large_categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL UNIQUE
	);`
	_, err = db.Exec(largeCats)
	if err != nil {
		return err
	}

	// Ensure categories table exists (may already exist from previous migrations).
	// If it does not exist, create it with optional large_category_id column.
	if _, err = db.Exec(`CREATE TABLE IF NOT EXISTS categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL UNIQUE,
		large_category_id INTEGER,
		FOREIGN KEY(large_category_id) REFERENCES large_categories(id) ON DELETE SET NULL
	);`); err != nil {
		return err
	}

	// Add large_category_id column if missing (SQLite will error if column exists; ignore).
	if _, err = db.Exec(`ALTER TABLE categories ADD COLUMN large_category_id INTEGER`); err != nil {
		// ignore error, column may already exist
	}

	// Seed categories from existing products to preserve historical data.
	if _, err := db.Exec(`INSERT OR IGNORE INTO categories (name) SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category <> ''`); err != nil {
		return err
	}

	// Ensure products table has a 'categories' TEXT column to store JSON array of categories.
	// SQLite ALTER TABLE ADD COLUMN will error if column exists; ignore error.
	if _, err := db.Exec(`ALTER TABLE products ADD COLUMN categories TEXT`); err != nil {
		// ignore error; column may already exist
	}

	// Singleton site identity / branding row. The table holds at most one
	// row (id = 1) so the API never 404s on a missing site config.
	// Default values match the existing hardcoded values in the admin
	// settings UI so first-run behavior is unchanged.
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS store_info (
		id INTEGER PRIMARY KEY CHECK (id = 1),
		name TEXT NOT NULL DEFAULT 'simshop',
		description TEXT NOT NULL DEFAULT '',
		logo_url TEXT NOT NULL DEFAULT '',
		phone TEXT NOT NULL DEFAULT '',
		email TEXT NOT NULL DEFAULT '',
		address TEXT NOT NULL DEFAULT '',
		google_maps_url TEXT NOT NULL DEFAULT ''
	)`); err != nil {
		return err
	}
	// Upgrade path for installs that pre-date the google_maps_url column.
	// SQLite has no ADD COLUMN IF NOT EXISTS, so we ignore the duplicate-
	// column error the same way the categories/products migrations do.
	if _, err := db.Exec(`ALTER TABLE store_info ADD COLUMN google_maps_url TEXT NOT NULL DEFAULT ''`); err != nil {
		// ignore error; column may already exist
	}
	// Ensure the single row exists even if the table was created empty.
	if _, err := db.Exec(`INSERT OR IGNORE INTO store_info (id) VALUES (1)`); err != nil {
		return err
	}

	// Articles: editorial content referenced by banner_slides. Body is
	// Markdown; product_ids is a JSON array of product IDs the article
	// mentions (rendered as chips in the article screen).
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS articles (
		id TEXT PRIMARY KEY,
		title TEXT NOT NULL,
		body_markdown TEXT NOT NULL DEFAULT '',
		cover_image_url TEXT NOT NULL DEFAULT '',
		product_ids TEXT NOT NULL DEFAULT '[]',
		created_at INTEGER NOT NULL
	)`); err != nil {
		return err
	}

	// Banner slides shown on the home carousel. Carries a 1-1
	// article_id; ON DELETE SET NULL so deleting an article leaves a
	// banner that goes nowhere rather than 500-ing the home carousel.
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS banner_slides (
		id TEXT PRIMARY KEY,
		image_url TEXT NOT NULL,
		title TEXT NOT NULL DEFAULT '',
		subtitle TEXT NOT NULL DEFAULT '',
		ord INTEGER NOT NULL DEFAULT 0,
		article_id TEXT,
		FOREIGN KEY(article_id) REFERENCES articles(id) ON DELETE SET NULL
	)`); err != nil {
		return err
	}

	// Analytics: anonymous pageview tracking. The Flutter client
	// fires one row per home load and per product-detail view.
	// product_id is NULLABLE so 'home_view' (and any future event
	// types without a product association) fits the same row shape.
	// The (event_type, created_at) index speeds up the top-N query
	// for the admin overview's "Sản phẩm xem nhiều nhất" table.
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS pageview_events (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		event_type TEXT NOT NULL,
		product_id TEXT,
		created_at INTEGER NOT NULL
	)`); err != nil {
		return err
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_pageview_events_type_created ON pageview_events(event_type, created_at)`); err != nil {
		return err
	}

	// Events: time-boxed promotions applied to a JSON-array list of
	// product IDs (mirrors articles.product_ids — same pattern, no
	// separate join table). end_time is NULLABLE: a NULL means the
	// event never expires, but the admin UI always sets a value so
	// promotions don't accidentally run forever. product_ids is
	// stored as JSON so ListActiveEventsForProduct can LIKE-match
	// cheaply without a join; an index on end_time keeps the active
	// filter fast even with thousands of past events.
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS events (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL DEFAULT '',
		end_time INTEGER,
		discount_type TEXT NOT NULL,
		discount_value REAL NOT NULL,
		product_ids TEXT NOT NULL DEFAULT '[]',
		created_at INTEGER NOT NULL
	)`); err != nil {
		return err
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_events_end_time ON events(end_time)`); err != nil {
		return err
	}

	return nil
}

// Close safely closes the underlying DB.
func (d *DB) Close() error {
	if d.DB == nil {
		return nil
	}
	return d.DB.Close()
}
