package db

import (
	"context"
	"database/sql"
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
        image_url TEXT NOT NULL,
        category TEXT NOT NULL,
        store_id TEXT,
        rating REAL NOT NULL,
        reviews INTEGER,
        stock INTEGER,
        specs TEXT NOT NULL DEFAULT '[]'
    );`
	_, err := db.Exec(schema)
	return err
}

// Close safely closes the underlying DB.
func (d *DB) Close() error {
	if d.DB == nil {
		return nil
	}
	return d.DB.Close()
}
