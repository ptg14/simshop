package db

import (
	"context"
	"database/sql"
	"fmt"
	"log"
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
//
// Ping retry: when cfg.DBRetryAttempts > 1 (default 10), the ping
// loop tolerates a slow-to-boot Postgres — useful in Docker Compose
// where backend and database containers start in parallel. Each
// attempt gets a 5s context, then waits cfg.DBRetryInterval before
// the next. Total wait is approximately Attempts × Interval.
func New(cfg *config.Config) (*DB, error) {
	dialect := DetectDialect(cfg.DatabaseURL)
	dsn := ResolveDSN(cfg.DatabaseURL)

	db, err := sql.Open(dialect.DriverName(), dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetConnMaxLifetime(cfg.ConnMaxLifetime)

	// Verify connection with retry. We ping before doing anything else
	// (FK pragma, migrations) so a transiently-unreachable database
	// fails fast at boot rather than producing confusing migration
	// errors.
	if err := pingWithRetry(db, cfg); err != nil {
		_ = db.Close()
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

// pinger is the minimum surface pingWithRetry needs from a database
// connection. *sql.DB satisfies it; tests substitute a stub.
type pinger interface {
	PingContext(ctx context.Context) error
}

// pingWithRetry calls p.PingContext up to cfg.DBRetryAttempts times,
// sleeping cfg.DBRetryInterval between attempts. Returns nil on the
// first success; the last error if all attempts fail.
//
// SQLite (file path) is expected to succeed on the first attempt
// because the file is local — retry is mostly a no-op there, but
// keeping the same code path avoids a special case.
func pingWithRetry(p pinger, cfg *config.Config) error {
	attempts := cfg.DBRetryAttempts
	if attempts < 1 {
		attempts = 1
	}
	interval := cfg.DBRetryInterval
	if interval <= 0 {
		interval = time.Second
	}

	var lastErr error
	for i := 1; i <= attempts; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err := p.PingContext(ctx)
		cancel()
		if err == nil {
			return nil
		}
		lastErr = err
		// Don't sleep after the final attempt — there's no point.
		if i < attempts {
			log.Printf("db not ready (attempt %d/%d): %v", i, attempts, err)
			time.Sleep(interval)
		}
	}
	return fmt.Errorf("db unreachable after %d attempts: %w", attempts, lastErr)
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
