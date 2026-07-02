// Command seed ensures the schema exists against the configured
// DATABASE_URL (SQLite or Postgres) and exits. It deliberately does
// NOT insert sample/fixture data — populate the catalog via the admin
// UI or the product handler endpoints.
package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strings"

	_ "github.com/jackc/pgx/v5/stdlib"
	_ "github.com/mattn/go-sqlite3"

	"github.com/ptg14/simshop/backend/internal/db"
)

// openDB opens the right driver for the scheme on DATABASE_URL and
// returns the connection plus the detected dialect so callers can
// rewrite queries for the matching driver.
func openDB(dsn string) (*sql.DB, db.Dialect, error) {
	dialect := db.DetectDialect(dsn)
	resolved := db.ResolveDSN(dsn)
	conn, err := sql.Open(dialect.DriverName(), resolved)
	if err != nil {
		return nil, dialect, err
	}
	if pragma := dialect.EnableFKPragma(); pragma != "" {
		if _, err := conn.Exec(pragma); err != nil {
			conn.Close()
			return nil, dialect, err
		}
	}
	return conn, dialect, nil
}

// applySchema runs the production schema registry for the given
// dialect. Idempotent on a fresh database and benign against an
// already-migrated one (ALTER TABLE errors on pre-existing SQLite
// columns are swallowed).
func applySchema(database *sql.DB, dialect db.Dialect) error {
	for _, stmt := range db.SchemaFor(dialect) {
		if stmt == "" {
			continue
		}
		if _, err := database.Exec(stmt); err != nil {
			if dialect == db.DialectSQLite && strings.Contains(err.Error(), "duplicate column name") {
				continue
			}
			return err
		}
	}
	return nil
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "test.db"
	}

	database, dialect, err := openDB(dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer database.Close()

	if err := applySchema(database, dialect); err != nil {
		log.Fatalf("apply schema: %v", err)
	}
	fmt.Printf("schema ready (%s): %s\n", dialect, dsn)
}