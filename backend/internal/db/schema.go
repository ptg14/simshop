package db

// SchemaFor returns the ordered list of DDL statements that create
// (and upgrade) every table this app uses, for the given dialect.
//
// It is the single source of truth for DDL. Production code (db.New)
// and the test harness (handler_test.go's applyMigrations) and the
// seed command (cmd/seed/main.go) all consume this list.
//
// Statements are written so they are idempotent on a fresh database
// (CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS) AND on a
// pre-existing SQLite database that already has the old columns
// (ALTER TABLE errors are swallowed at call sites; see
// [Dialect.AddColumnSQL]).
//
// Order matters: tables that hold foreign keys come AFTER the
// referenced tables. The CREATE INDEX statements can run in any
// order, but we group them by table for readability.
//
// Adding a new table?
//  1. Add the CREATE TABLE here, parameterized via dialect helpers
//     for the bits that differ (BIGSERIAL vs AUTOINCREMENT, JSONB
//     vs TEXT, BIGINT vs INTEGER).
//  2. Append it to the end so existing tables stay unchanged and
//     existing rows aren't disturbed.
func SchemaFor(dialect Dialect) []string {
	// Per-dialect helpers cached as locals so the strings.Builder-style
	// concatenation below is concise. We don't pre-compute every
	// statement — only the parts that vary by dialect — so the DDL
	// stays readable.
	pk := dialect.AutoIncrementPK()
	ts := dialect.Int64ColumnType()
	jsonType := dialect.JSONColumnType()

	return []string{
		// ----- products -----
		`CREATE TABLE IF NOT EXISTS products (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT NOT NULL,
			price DOUBLE PRECISION NOT NULL,
			original_price DOUBLE PRECISION,
			image_url TEXT,
			category TEXT NOT NULL,
			store_id TEXT,
			rating DOUBLE PRECISION NOT NULL,
			reviews INTEGER,
			stock INTEGER,
			specs ` + jsonType + ` NOT NULL DEFAULT '[]',
			categories ` + jsonType + ` NOT NULL DEFAULT '[]'
		)`,

		// ----- product_images -----
		`CREATE TABLE IF NOT EXISTS product_images (
			id ` + pk + `,
			product_id TEXT NOT NULL,
			image_url TEXT NOT NULL,
			ord INTEGER NOT NULL DEFAULT 0,
			FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
		)`,

		// ----- product_options -----
		`CREATE TABLE IF NOT EXISTS product_options (
			id TEXT PRIMARY KEY,
			product_id TEXT NOT NULL,
			name TEXT NOT NULL,
			image_urls ` + jsonType + ` NOT NULL DEFAULT '[]',
			ord INTEGER NOT NULL DEFAULT 0,
			FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
		)`,
		// SQLite has no ADD COLUMN IF NOT EXISTS — the caller
		// (runMigrations) swallows the "duplicate column" error
		// when running on SQLite. On Postgres we use the IF NOT
		// EXISTS variant.
		dialect.AddColumnSQL("product_options", "image_urls", jsonType+" NOT NULL DEFAULT '[]'"),

		// ----- large_categories (parent) -----
		`CREATE TABLE IF NOT EXISTS large_categories (
			id ` + pk + `,
			name TEXT NOT NULL UNIQUE
		)`,

		// ----- categories (sub) -----
		`CREATE TABLE IF NOT EXISTS categories (
			id ` + pk + `,
			name TEXT NOT NULL UNIQUE,
			large_category_id INTEGER,
			FOREIGN KEY(large_category_id) REFERENCES large_categories(id) ON DELETE SET NULL
		)`,
		dialect.AddColumnSQL("categories", "large_category_id", "INTEGER"),

		// Backfill: copy distinct existing categories into the table.
		// Idempotent on both dialects thanks to ON CONFLICT DO
		// NOTHING (Postgres) / INSERT OR IGNORE (SQLite, applied
		// by runMigrations when iterating).
		`INSERT INTO categories (name) SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category <> '' AND NOT EXISTS (SELECT 1 FROM categories WHERE categories.name = products.category)`,

		// Add categories column to products (it may already exist on
		// legacy SQLite databases). See runMigrations for the error
		// handling.
		dialect.AddColumnSQL("products", "categories", jsonType),

		// ----- store_info singleton -----
		// id is constrained to a single value so the API never 404s
		// on a missing site config. Postgres needs the column to
		// NOT NULL + have a default so we can `INSERT ... ON
		// CONFLICT DO NOTHING`.
		`CREATE TABLE IF NOT EXISTS store_info (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL DEFAULT 'simshop',
			description TEXT NOT NULL DEFAULT '',
			banner_url TEXT NOT NULL DEFAULT '',
			phone TEXT NOT NULL DEFAULT '',
			email TEXT NOT NULL DEFAULT '',
			address TEXT NOT NULL DEFAULT '',
			google_maps_url TEXT NOT NULL DEFAULT ''
		)`,
		dialect.AddColumnSQL("store_info", "google_maps_url", "TEXT NOT NULL DEFAULT ''"),
		// banner_url was renamed from logo_url; for pre-existing
		// databases the legacy logo_url column sticks around empty —
		// SQLite (no IF NOT EXISTS) and Postgres both tolerate the
		// "duplicate column" / no-op on the freshly created path.
		dialect.AddColumnSQL("store_info", "banner_url", "TEXT NOT NULL DEFAULT ''"),
		// Seed the singleton row. Both dialects accept this; on
		// Postgres a PRIMARY KEY column without a DEFAULT would
		// require us to pass (1) here. Since id has no default on
		// SQLite, the INSERT is the same.
		`INSERT INTO store_info (id) VALUES (1) ON CONFLICT (id) DO NOTHING`,

		// ----- articles (editorial) -----
		`CREATE TABLE IF NOT EXISTS articles (
			id TEXT PRIMARY KEY,
			title TEXT NOT NULL,
			body_markdown TEXT NOT NULL DEFAULT '',
			cover_image_url TEXT NOT NULL DEFAULT '',
			product_ids ` + jsonType + ` NOT NULL DEFAULT '[]',
			created_at ` + ts + ` NOT NULL
		)`,
		// is_draft gates the public article endpoint: anonymous GETs see
		// only is_draft = 0 rows. Admins always see drafts. Idempotent —
		// SQLite's duplicate-column error is swallowed by runMigrations,
		// Postgres uses ADD COLUMN IF NOT EXISTS via dialect.AddColumnSQL.
		dialect.AddColumnSQL("articles", "is_draft", "INTEGER NOT NULL DEFAULT 0"),

		// Backfill: legacy rows from a buggy AddCategory stored NULL in
		// categories.name. Stamp them with a synthetic name so the
		// handler's Scan doesn't choke on a NULL and the row stays
		// addressable. SQLite uses rowid (a hidden pseudo-column) because
		// pre-existing databases created before `id INTEGER PRIMARY KEY`
		// was added don't have it; Postgres always has the named `id`
		// column (initdb/01-schema.sql declares it as SERIAL PRIMARY KEY).
		// Idempotent on both: WHERE name IS NULL is a no-op on clean DBs.
		backfillLegacyCategoryNames(dialect),

		// ----- banner_slides -----
		`CREATE TABLE IF NOT EXISTS banner_slides (
			id TEXT PRIMARY KEY,
			image_url TEXT NOT NULL,
			title TEXT NOT NULL DEFAULT '',
			subtitle TEXT NOT NULL DEFAULT '',
			ord INTEGER NOT NULL DEFAULT 0,
			article_id TEXT,
			FOREIGN KEY(article_id) REFERENCES articles(id) ON DELETE SET NULL
		)`,

		// ----- events (time-boxed promotions) -----
		// Same JSON-array pattern as articles.product_ids. On
		// Postgres the column is JSONB; ListActiveEventsForProduct
		// uses @> for efficient containment checks (and a GIN
		// index for scale). On SQLite it's TEXT and we LIKE-match.
		`CREATE TABLE IF NOT EXISTS events (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL DEFAULT '',
			end_time ` + ts + `,
			discount_type TEXT NOT NULL,
			discount_value DOUBLE PRECISION NOT NULL,
			product_ids ` + jsonType + ` NOT NULL DEFAULT '[]',
			created_at ` + ts + ` NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_events_end_time ON events(end_time)`,
		// Postgres-specific GIN index on the JSONB product_ids
		// column. SQLite ignores CREATE INDEX IF NOT EXISTS but
		// doesn't support GIN, so this statement is wrapped in a
		// dialect check below.
		eventProductIDsIndex(dialect),
	}
}

// eventProductIDsIndex returns a GIN index on the JSONB product_ids
// column for Postgres, or "" for SQLite (which has no equivalent
// JSON index type — LIKE will scan, but events are a small admin
// table so this is acceptable). The empty string is filtered out
// by runMigrations so we don't issue a no-op Exec.
func eventProductIDsIndex(dialect Dialect) string {
	if dialect == DialectPostgres {
		return "CREATE INDEX IF NOT EXISTS idx_events_product_ids_gin ON events USING GIN (product_ids)"
	}
	return ""
}

// backfillLegacyCategoryNames stamps a synthetic name on any row
// where categories.name is NULL. This guards against an old buggy
// AddCategory that let NULLs through; the handler's Scan would
// choke on a NULL, so the row stays addressable with a name like
// `legacy-42`.
//
// Per-dialect: SQLite uses rowid (a hidden pseudo-column present
// even on databases created before `id INTEGER PRIMARY KEY` was
// added); Postgres has no rowid pseudo-column but always has the
// named `id` (initdb/01-schema.sql declares it as SERIAL PRIMARY
// KEY). Idempotent on a clean DB — WHERE name IS NULL matches
// nothing.
func backfillLegacyCategoryNames(dialect Dialect) string {
	if dialect == DialectPostgres {
		return `UPDATE categories SET name = 'legacy-' || id WHERE name IS NULL`
	}
	return `UPDATE categories SET name = 'legacy-' || rowid WHERE name IS NULL`
}
