package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	_ "github.com/mattn/go-sqlite3"
	"github.com/ptg14/simshop/backend/internal/config"
)

// DB wraps a *sql.DB and provides helper methods. The dialect is
// stored alongside the connection so callers that take a *DB can
// also learn which driver is in use (e.g. to pass into repos that
// need it for placeholder rewriting).
type DB struct {
	*sql.DB
	Dialect Dialect
}

// New creates a new DB instance based on the provided configuration.
// Driver selection is driven by the DATABASE_URL scheme:
//   - "postgres://" / "postgresql://" → PostgreSQL via pgx
//   - "sqlite://"   / "sqlite3://"   → SQLite via mattn/go-sqlite3
//   - bare path     (e.g. "./simshop.db") → SQLite (backward compat)
//
// The detected dialect is what the schema and the repos branch on, so
// every SQL fragment is dialect-aware.
func New(cfg *config.Config) (*DB, error) {
	dialect := DetectDialect(cfg.DatabaseURL)
	dsn := ResolveDSN(cfg.DatabaseURL)

	db, err := sql.Open(dialect.DriverName(), dsn)
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

	// Enable foreign key constraints for SQLite. Postgres enforces
	// FKs by default so EnableFKPragma() returns "" for it.
	if pragma := dialect.EnableFKPragma(); pragma != "" {
		if _, err := db.Exec(pragma); err != nil {
			return nil, fmt.Errorf("enable foreign keys: %w", err)
		}
	}

	// Run schema migrations via the shared DDL registry.
	if err := runMigrations(db, dialect); err != nil {
		return nil, err
	}

	return &DB{DB: db, Dialect: dialect}, nil
}

// runMigrations executes the DDL produced by [SchemaFor]. Each
// statement is idempotent on a fresh database; ALTER TABLE failures
// on SQLite (where IF NOT EXISTS isn't supported) are swallowed so
// pre-existing columns don't break the boot path.
func runMigrations(db *sql.DB, dialect Dialect) error {
	for _, stmt := range SchemaFor(dialect) {
		if stmt == "" {
			// Skipped fragment (e.g. Postgres-only GIN index on SQLite).
			continue
		}
		if _, err := db.Exec(stmt); err != nil {
			// SQLite ALTER TABLE ADD COLUMN errors when the column
			// already exists; we treat that as success. All other
			// errors propagate.
			if dialect == DialectSQLite && isBenignAlterError(err) {
				continue
			}
			return fmt.Errorf("migration failed: %w", err)
		}
	}
	return nil
}

// isBenignAlterError returns true for SQLite errors that mean "this
// ALTER TABLE is a no-op because the column already exists". All
// other errors should propagate. Centralized here so the migration
// loop stays readable.
func isBenignAlterError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	// SQLite returns "duplicate column name: <col>" when ALTER TABLE
	// ADD COLUMN is run on a column that already exists.
	return contains(msg, "duplicate column name")
}

// contains is a tiny substring helper to avoid pulling in strings
// just for one call site. Keeps imports minimal.
func contains(haystack, needle string) bool {
	if len(needle) == 0 {
		return true
	}
	if len(needle) > len(haystack) {
		return false
	}
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

// Close safely closes the underlying DB.
func (d *DB) Close() error {
	if d.DB == nil {
		return nil
	}
	return d.DB.Close()
}