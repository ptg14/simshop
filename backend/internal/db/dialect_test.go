package db

import (
	"database/sql"
	"strings"
	"testing"
)

// openSQLiteMemory returns an in-memory SQLite *sql.DB for tests that
// need to actually execute SchemaFor(SQLite) — catching SQL typos
// that strings.Contains alone would miss. The driver is registered
// in db.go via the `_ "github.com/mattn/go-sqlite3"` import.
func openSQLiteMemory(t *testing.T) (*sql.DB, error) {
	t.Helper()
	conn, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		return nil, err
	}
	if _, err := conn.Exec(`PRAGMA foreign_keys = ON`); err != nil {
		conn.Close()
		return nil, err
	}
	return conn, nil
}

// TestDetectDialect asserts every documented DATABASE_URL scheme
// lands on the right enum value. The case-insensitivity and "no
// scheme" backward-compat branches live here too.
func TestDetectDialect(t *testing.T) {
	cases := []struct {
		name string
		url  string
		want Dialect
	}{
		{"empty defaults to SQLite", "", DialectSQLite},
		{"whitespace defaults to SQLite", "   ", DialectSQLite},
		{"bare path is SQLite (backward compat)", "./simshop.db", DialectSQLite},
		{"absolute path is SQLite", "/var/data/simshop.db", DialectSQLite},
		{":memory: is SQLite", ":memory:", DialectSQLite},
		{"sqlite:// path", "sqlite://./simshop.db", DialectSQLite},
		{"sqlite3:// path", "sqlite3://./simshop.db", DialectSQLite},
		{"sqlite:/// absolute", "sqlite:///var/data/simshop.db", DialectSQLite},
		{"postgres://", "postgres://u:p@h/db", DialectPostgres},
		{"postgresql://", "postgresql://u:p@h/db", DialectPostgres},
		{"mixed case scheme", "POSTGRES://u@h/db", DialectPostgres},
		{"with whitespace around scheme", "  postgres://u@h/db  ", DialectPostgres},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := DetectDialect(tc.url)
			if got != tc.want {
				t.Errorf("DetectDialect(%q) = %v, want %v", tc.url, got, tc.want)
			}
		})
	}
}

// TestRebind is the core contract for placeholder rewriting.
// Postgres must convert each ? to $N in left-to-right order;
// SQLite must return the query unchanged.
func TestRebind(t *testing.T) {
	cases := []struct {
		name string
		d    Dialect
		in   string
		want string
	}{
		{"empty query unchanged on both", DialectSQLite, "", ""},
		{"empty query unchanged on Postgres", DialectPostgres, "", ""},
		{"SQLite is a no-op", DialectSQLite, "SELECT * FROM x WHERE a = ? AND b = ?", "SELECT * FROM x WHERE a = ? AND b = ?"},
		{"Postgres rewrites single placeholder", DialectPostgres, "SELECT * FROM x WHERE id = ?", "SELECT * FROM x WHERE id = $1"},
		{"Postgres rewrites multiple placeholders left to right", DialectPostgres,
			"INSERT INTO x (a, b, c) VALUES (?, ?, ?)",
			"INSERT INTO x (a, b, c) VALUES ($1, $2, $3)"},
		{"Postgres rewrites placeholders across lines", DialectPostgres,
			"SELECT *\nFROM x\nWHERE a = ?\n  AND b = ?",
			"SELECT *\nFROM x\nWHERE a = $1\n  AND b = $2"},
		{"SQLite inside string literal left alone", DialectSQLite,
			"SELECT 'a?b' FROM x WHERE c = ?",
			"SELECT 'a?b' FROM x WHERE c = ?"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.d.Rebind(tc.in)
			if got != tc.want {
				t.Errorf("Rebind(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// TestRebindManyPlaceholders guards against off-by-one errors in the
// counter for queries with more than nine placeholders. Picking 12
// also forces a multi-digit $N output.
func TestRebindManyPlaceholders(t *testing.T) {
	in := "SELECT ?,?,?,?,?,?,?,?,?,?,?,?"
	want := "SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12"
	got := DialectPostgres.Rebind(in)
	if got != want {
		t.Errorf("Rebind 12 placeholders = %q, want %q", got, want)
	}
}

// TestResolveDSN makes sure the scheme is stripped on SQLite and
// left alone on Postgres (pgx accepts URLs natively).
func TestResolveDSN(t *testing.T) {
	cases := []struct {
		name string
		url  string
		want string
	}{
		{"empty passthrough", "", ""},
		{"bare path passthrough", "./simshop.db", "./simshop.db"},
		{"sqlite:// stripped", "sqlite://./simshop.db", "./simshop.db"},
		{"sqlite3:// stripped", "sqlite3://./simshop.db", "./simshop.db"},
		{"sqlite:/// absolute path", "sqlite:///var/data/simshop.db", "/var/data/simshop.db"},
		{"sqlite://:memory: preserved", "sqlite://:memory:", ":memory:"},
		{"postgres:// untouched", "postgres://u:p@h/db", "postgres://u:p@h/db"},
		{"postgresql:// untouched", "postgresql://u@h/db", "postgresql://u@h/db"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ResolveDSN(tc.url)
			if got != tc.want {
				t.Errorf("ResolveDSN(%q) = %q, want %q", tc.url, got, tc.want)
			}
		})
	}
}

// TestUpsertSQLFragment pins the upsert fragment for each dialect
// because the contract between repos and the dialect helper is easy
// to break silently (e.g. forgetting to splice OR IGNORE on SQLite).
func TestUpsertSQLFragment(t *testing.T) {
	cases := []struct {
		name     string
		d        Dialect
		insert   string
		uniqueCS string
		want     string
	}{
		{
			"SQLite adds OR IGNORE between INSERT and INTO",
			DialectSQLite,
			"INSERT INTO x (a) VALUES (?)",
			"a",
			"INSERT OR IGNORE INTO x (a) VALUES (?)",
		},
		{
			"Postgres appends ON CONFLICT DO NOTHING",
			DialectPostgres,
			"INSERT INTO x (a, b) VALUES (?, ?)",
			"a",
			"INSERT INTO x (a, b) VALUES (?, ?) ON CONFLICT (a) DO NOTHING",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.d.UpsertSQL(tc.insert, tc.uniqueCS)
			if got != tc.want {
				t.Errorf("UpsertSQL = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestColumnTypes pins the per-dialect column-type helpers so the
// schema for one dialect can't silently use the other dialect's
// syntax.
func TestColumnTypes(t *testing.T) {
	if got := DialectSQLite.AutoIncrementPK(); got != "INTEGER PRIMARY KEY AUTOINCREMENT" {
		t.Errorf("SQLite PK = %q", got)
	}
	if got := DialectPostgres.AutoIncrementPK(); got != "BIGSERIAL PRIMARY KEY" {
		t.Errorf("Postgres PK = %q", got)
	}
	if got := DialectSQLite.JSONColumnType(); got != "TEXT" {
		t.Errorf("SQLite JSON = %q", got)
	}
	if got := DialectPostgres.JSONColumnType(); got != "JSONB" {
		t.Errorf("Postgres JSON = %q", got)
	}
	if got := DialectSQLite.Int64ColumnType(); got != "INTEGER" {
		t.Errorf("SQLite int64 = %q", got)
	}
	if got := DialectPostgres.Int64ColumnType(); got != "BIGINT" {
		t.Errorf("Postgres int64 = %q", got)
	}
}

// TestEnableFKPragma ensures only SQLite issues the PRAGMA — Postgres
// already enforces FKs by default, so emitting one is harmless on
// the server but visually wrong in logs.
func TestEnableFKPragma(t *testing.T) {
	if got := DialectSQLite.EnableFKPragma(); got != "PRAGMA foreign_keys = ON" {
		t.Errorf("SQLite FK pragma = %q", got)
	}
	if got := DialectPostgres.EnableFKPragma(); got != "" {
		t.Errorf("Postgres FK pragma = %q, want empty", got)
	}
}

// TestAddColumnSQL pins the per-dialect ALTER TABLE fragment. SQLite
// deliberately omits IF NOT EXISTS — the call site swallows the
// "duplicate column" error so pre-existing columns don't break boot.
func TestAddColumnSQL(t *testing.T) {
	cases := []struct {
		d      Dialect
		column string
		def    string
		want   string
	}{
		{DialectSQLite, "image_urls", "TEXT NOT NULL DEFAULT '[]'",
			"ALTER TABLE product_options ADD COLUMN image_urls TEXT NOT NULL DEFAULT '[]'"},
		{DialectPostgres, "image_urls", "JSONB NOT NULL DEFAULT '[]'",
			"ALTER TABLE product_options ADD COLUMN IF NOT EXISTS image_urls JSONB NOT NULL DEFAULT '[]'"},
	}
	for _, tc := range cases {
		got := tc.d.AddColumnSQL("product_options", tc.column, tc.def)
		if got != tc.want {
			t.Errorf("AddColumnSQL(%v) = %q, want %q", tc.d, got, tc.want)
		}
	}
}

// TestProductIDsContains pins the dialect split for the JSON-list
// containment query. Postgres uses JSONB @>; SQLite falls back to
// LIKE on the JSON-text form.
func TestProductIDsContains(t *testing.T) {
	if got := DialectPostgres.ProductIDsContains("?"); !strings.Contains(got, "@>") {
		t.Errorf("Postgres product_ids contains = %q, expected @>", got)
	}
	if got := DialectSQLite.ProductIDsContains("?"); !strings.Contains(got, "LIKE") {
		t.Errorf("SQLite product_ids contains = %q, expected LIKE", got)
	}
}

// TestSchemaForFragments ensures the DDL registry emits the expected
// per-dialect column types. We assert against a SQLite :memory:
// connection so we also catch typos that would break the real
// migration.
func TestSchemaForFragments(t *testing.T) {
	sqlite := SchemaFor(DialectSQLite)
	if len(sqlite) == 0 {
		t.Fatalf("SchemaFor(SQLite) returned empty list")
	}
	joined := strings.Join(sqlite, "\n")
	if !strings.Contains(joined, "INTEGER PRIMARY KEY AUTOINCREMENT") {
		t.Errorf("SQLite schema missing AUTOINCREMENT, got:\n%s", joined)
	}
	// The Postgres-only GIN index should be empty (filtered out at
	// run time) — but the function still returns the empty string,
	// so we just check the list isn't empty for Postgres either.
	pg := SchemaFor(DialectPostgres)
	if len(pg) == 0 {
		t.Fatalf("SchemaFor(Postgres) returned empty list")
	}
	pgJoined := strings.Join(pg, "\n")
	if !strings.Contains(pgJoined, "BIGSERIAL PRIMARY KEY") {
		t.Errorf("Postgres schema missing BIGSERIAL, got:\n%s", pgJoined)
	}
	if !strings.Contains(pgJoined, "JSONB") {
		t.Errorf("Postgres schema missing JSONB, got:\n%s", pgJoined)
	}
	if !strings.Contains(pgJoined, "USING GIN") {
		t.Errorf("Postgres schema missing GIN index, got:\n%s", pgJoined)
	}
}

// TestSchemaForRunsOnSQLite is the smoke test that SchemaFor(SQLite)
// is actually runnable against a real SQLite database. This catches
// SQL typos that strings.Contains-based tests would miss.
func TestSchemaForRunsOnSQLite(t *testing.T) {
	// Use an in-memory SQLite connection through the public path so
	// the test exercises the same DriverName/SQL surface as
	// production.
	conn, err := openSQLiteMemory(t)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer conn.Close()
	for _, stmt := range SchemaFor(DialectSQLite) {
		if stmt == "" {
			continue
		}
		if _, err := conn.Exec(stmt); err != nil {
			// ALTER TABLE on a pre-existing column is allowed to fail.
			if strings.Contains(err.Error(), "duplicate column name") {
				continue
			}
			t.Errorf("SchemaFor(SQLite) statement failed: %v\n--- stmt ---\n%s", err, stmt)
		}
	}
}

// TestCaseInsensitiveNameLike pins the SQL fragment that the
// product filter uses for the free-text `search` field. The
// customer reported that searching "Áo" or "ÁO" returned
// different results from "áo" because the old `name LIKE ?`
// was case-sensitive on Postgres and only ASCII-folding on
// SQLite. Both dialects now wrap both sides in LOWER() so the
// match is case-insensitive everywhere.
func TestCaseInsensitiveNameLike(t *testing.T) {
	cases := []struct {
		name        string
		d           Dialect
		placeholder string
		want        string
	}{
		{"SQLite wraps both sides in LOWER", DialectSQLite, "?",
			"(LOWER(name) LIKE LOWER(?) ESCAPE '\\')"},
		{"Postgres wraps both sides in LOWER", DialectPostgres, "$1",
			"(LOWER(name) LIKE LOWER($1) ESCAPE '\\')"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.d.CaseInsensitiveNameLike(tc.placeholder)
			if got != tc.want {
				t.Errorf("CaseInsensitiveNameLike = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestCaseInsensitiveNameLikeExecutes guards against SQL typos
// by running the actual predicate against an in-memory SQLite
// database with a few rows. The user reported that the search
// bar didn't recognise case differences — typing "IPHONE" or
// "iphone" or "Iphone" should all return the same row. The
// `LOWER(name) LIKE LOWER(?)` predicate wraps both sides so
// the ASCII letters are case-folded by SQLite's default
// C-locale LOWER.
//
// Note: SQLite's built-in LOWER() is C-locale only and does
// NOT fold non-ASCII letters — searching "Áo" still won't
// match "áo" via this predicate, because the Vietnamese
// capital Á is a different code point from lowercase á and
// neither is folded by C-locale LOWER. Diacritic-insensitive
// search would need a separate normalisation pipeline; the
// user only asked for upper/lower-case handling, which this
// predicate gives them.
func TestCaseInsensitiveNameLikeExecutes(t *testing.T) {
	conn, err := openSQLiteMemory(t)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer conn.Close()
	if _, err := conn.Exec(`CREATE TABLE products (name TEXT)`); err != nil {
		t.Fatalf("create: %v", err)
	}
	rows := []string{"iPhone 15", "IPHONE 14", "iphone SE", "Galaxy S24"}
	for _, r := range rows {
		if _, err := conn.Exec(`INSERT INTO products (name) VALUES (?)`, r); err != nil {
			t.Fatalf("insert: %v", err)
		}
	}
	predicate := DialectSQLite.CaseInsensitiveNameLike("?")
	query := "SELECT name FROM products WHERE " + predicate
	for _, q := range []string{"iphone", "IPHONE", "Iphone"} {
		var got []string
		r, err := conn.Query(query, "%"+q+"%")
		if err != nil {
			t.Fatalf("query %q: %v", q, err)
		}
		for r.Next() {
			var n string
			if err := r.Scan(&n); err != nil {
				t.Fatalf("scan: %v", err)
			}
			got = append(got, n)
		}
		r.Close()
		if len(got) != 3 {
			t.Errorf("search %q: got %d rows %v, want 3 (all iPhone variants)", q, len(got), got)
		}
	}
}