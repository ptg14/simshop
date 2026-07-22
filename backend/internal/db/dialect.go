package db

import (
	"net/url"
	"regexp"
	"strings"
)

// Dialect identifies which SQL dialect the application is talking to.
// The dialect controls DDL syntax, placeholder format, and any
// driver-specific SQL fragments needed (e.g. JSONB containment on
// Postgres vs LIKE on SQLite).
//
// The zero value is DialectSQLite because the existing deployment
// path doesn't set DATABASE_URL — we default to SQLite and treat
// the URL as a file path. Callers should always populate it via
// [DetectDialect] rather than relying on the zero value.
type Dialect int

const (
	// DialectSQLite — file-backed SQLite via mattn/go-sqlite3.
	DialectSQLite Dialect = iota
	// DialectPostgres — PostgreSQL via jackc/pgx/v5/stdlib.
	DialectPostgres
)

// String returns a stable name for logging / config. Don't use this
// for SQL generation — call the typed helpers instead.
func (d Dialect) String() string {
	switch d {
	case DialectPostgres:
		return "postgres"
	default:
		return "sqlite"
	}
}

// DriverName is the name registered with database/sql.
func (d Dialect) DriverName() string {
	switch d {
	case DialectPostgres:
		return "pgx"
	default:
		return "sqlite3"
	}
}

// IsPostgres reports whether [d] is the Postgres dialect.
func (d Dialect) IsPostgres() bool { return d == DialectPostgres }

// placeholderPattern matches a `?` that is NOT inside a string literal
// (single-quoted) or a line comment (--). Postgres rewrites these to
// $N; SQLite keeps them as-is.
//
// We use a non-greedy regex: scan through the query and toggle in/out
// of literals. This is simpler and correct enough for our hand-written
// queries (none of which contain `?` inside a string literal).
var placeholderPattern = regexp.MustCompile(`\?`)

// Rebind rewrites `?` placeholders to the dialect-specific form.
// On SQLite it returns the query unchanged. On Postgres it converts
// each `?` to `$1`, `$2`, etc., in left-to-right order.
//
// We do NOT attempt to skip `?` inside string literals — none of our
// queries embed literal `?` characters. If a future query does, switch
// to a proper SQL tokenizer.
func (d Dialect) Rebind(query string) string {
	if d == DialectSQLite {
		return query
	}
	n := 0
	return placeholderPattern.ReplaceAllStringFunc(query, func(_ string) string {
		n++
		return "$" + itoa(n)
	})
}

// itoa is a tiny non-allocating integer-to-string helper, so Rebind
// doesn't drag in fmt.Sprintf for every placeholder.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

// UpsertIgnore returns the trailing SQL fragment for "insert this
// row but skip the conflict". Postgres: ON CONFLICT (...) DO NOTHING.
// SQLite: OR IGNORE goes between INSERT and INTO, so callers must
// splice it in themselves — see [UpsertSQL] for a complete query.
//
// We return the trailing fragment because Postgres ON CONFLICT requires
// a column target, which only the caller knows. The caller passes the
// unique column when building the full query.
func (d Dialect) UpsertIgnoreSuffix(uniqueCol string) string {
	if d == DialectPostgres {
		return " ON CONFLICT (" + uniqueCol + ") DO NOTHING"
	}
	// SQLite uses INSERT OR IGNORE — caller splices it in.
	return ""
}

// UpsertSQL builds a full INSERT statement with the dialect's
// conflict-handling clause. uniqueCols is the list of columns the
// dialect should consider for the conflict (often just the primary
// key or a UNIQUE column).
//
// Callers can keep their existing string concatenation style:
//
//	UpsertSQL("INSERT INTO x (a, b) VALUES (?, ?)", []string{"a"})
func (d Dialect) UpsertSQL(insertPrefix, uniqueColsCSV string) string {
	if d == DialectPostgres {
		return insertPrefix + " ON CONFLICT (" + uniqueColsCSV + ") DO NOTHING"
	}
	// SQLite: insertPrefix looks like "INSERT INTO x (...) VALUES (...)".
	// Transform to "INSERT OR IGNORE INTO x (...) VALUES (...)".
	return strings.Replace(insertPrefix, "INSERT INTO", "INSERT OR IGNORE INTO", 1)
}

// EnableFKPragma returns the per-connection SQL needed to enforce
// foreign keys. SQLite needs PRAGMA foreign_keys = ON. Postgres
// enforces FKs by default, so this returns "" (no-op).
func (d Dialect) EnableFKPragma() string {
	if d == DialectPostgres {
		return ""
	}
	return "PRAGMA foreign_keys = ON"
}

// AutoIncrementPK returns the column type for a surrogate integer
// primary key. Postgres gets BIGSERIAL; SQLite gets the older
// AUTOINCREMENT form so the rowid stays stable across deletes.
func (d Dialect) AutoIncrementPK() string {
	if d == DialectPostgres {
		return "BIGSERIAL PRIMARY KEY"
	}
	return "INTEGER PRIMARY KEY AUTOINCREMENT"
}

// Int64ColumnType returns the column type for unix-second /
// unix-millis timestamps. Postgres `INTEGER` is 32-bit, which
// overflows on millisecond timestamps, so we use BIGINT to be safe.
func (d Dialect) Int64ColumnType() string {
	if d == DialectPostgres {
		return "BIGINT"
	}
	return "INTEGER"
}

// JSONColumnType returns the column type for JSON-text columns.
// Postgres gets JSONB (queryable via @>, indexed via GIN). SQLite
// has no native JSON type, so we store JSON-as-text.
func (d Dialect) JSONColumnType() string {
	if d == DialectPostgres {
		return "JSONB"
	}
	return "TEXT"
}

// AddColumnSQL returns the SQL statement to add a column to an
// existing table. Postgres supports `ADD COLUMN IF NOT EXISTS`
// natively. SQLite does not, so we return a plain ADD COLUMN and
// the caller must swallow the "duplicate column" error.
func (d Dialect) AddColumnSQL(table, column, definition string) string {
	if d == DialectPostgres {
		return "ALTER TABLE " + table + " ADD COLUMN IF NOT EXISTS " + column + " " + definition
	}
	return "ALTER TABLE " + table + " ADD COLUMN " + column + " " + definition
}

// ProductIDsContains returns a SQL predicate that matches rows where
// the `product_ids` column contains [productID]. Postgres uses the
// JSONB `@>` containment operator (efficient, indexed via GIN).
// SQLite uses LIKE on the JSON-encoded text representation.
//
// The returned fragment includes the leading AND/OR, so the caller
// can drop it into a WHERE clause directly.
func (d Dialect) ProductIDsContains(productIDPlaceholder string) string {
	if d == DialectPostgres {
		// product_ids is JSONB (a JSON array). Build a JSON array
		// containing a single text element, then check containment.
		// The placeholder is bound to a text parameter — we cast to
		// ::text inside the JSON literal so the driver serializes it
		// safely even if the client passes weird bytes.
		return "product_ids @> jsonb_build_array(" + productIDPlaceholder + "::text)"
	}
	// SQLite: LIKE match on the JSON-encoded form "id" surrounded by
	// quotes. We rely on the defense-in-depth check in
	// [EventRepo.ListActiveEventsForProduct] to confirm the id is
	// actually in the parsed slice.
	return `product_ids LIKE '%' || ` + productIDPlaceholder + ` || '%'`
}

// CaseInsensitiveNameLike returns a SQL predicate that matches a
// product whose `name` contains [valuePlaceholder] case
// insensitively. SQLite's default `LIKE` is ASCII-only
// case-insensitive (only when `case_sensitive_like = OFF`, and
// even then ignores UTF-8 diacritics), and Postgres' `LIKE` is
// always case-sensitive — so both dialects need an explicit
// `LOWER(...) LIKE LOWER(...)` to give the customer a
// search-by-substring behaviour that respects their input
// casing. The caller is expected to bind a lower-cased
// parameter, OR rely on the SQL wrapping to lowercase the
// value too. We lowercase the value here so the existing call
// sites (which bind the raw query string) keep working
// unchanged.
//
// The returned fragment includes the leading AND/OR, so the
// caller can drop it into a WHERE clause directly.
func (d Dialect) CaseInsensitiveNameLike(valuePlaceholder string) string {
	return "(LOWER(name) LIKE LOWER(" + valuePlaceholder + ") ESCAPE '\\')"
}

// ProductIDsJSONArrayLiteral returns the value to bind for the
// Postgres JSONB containment predicate. On Postgres we pass the
// raw product id text; on SQLite (LIKE branch) we pass the
// JSON-quoted form so the substring matches between brackets.
//
// This keeps the in-Go code uniform: callers don't need to know
// whether the column is text or JSONB.
func (d Dialect) ProductIDsJSONArrayLiteral(productID string) string {
	if d == DialectPostgres {
		return productID
	}
	// SQLite JSON encoding of a string: "...". JSON-escape any
	// embedded quotes/backslashes; product IDs today are UUIDs and
	// short slugs so this is theoretical, but defense in depth.
	b := strings.Builder{}
	b.Grow(len(productID) + 2)
	b.WriteByte('"')
	for _, r := range productID {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// DetectDialect inspects [raw] for a URL scheme and returns the
// matching dialect. Schemes recognized:
//   - "postgres://" or "postgresql://" → DialectPostgres
//   - "sqlite://" or "sqlite3://"      → DialectSQLite
//
// A value without a scheme (e.g. "./simshop.db", ":memory:",
// "/tmp/test.db") is treated as a SQLite file path. This preserves
// backward compatibility with existing deployments that set
// DATABASE_URL to a raw file path.
//
// We accept both `sqlite:///abs/path` (three slashes — host empty)
// and `sqlite://relative/path` (treated as a relative path).
func DetectDialect(raw string) Dialect {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return DialectSQLite
	}
	// url.Parse fails on bare paths like "./simshop.db", but the
	// scheme prefix is what we care about — check the leading
	// substring first to short-circuit.
	lower := strings.ToLower(trimmed)
	if strings.HasPrefix(lower, "postgres://") || strings.HasPrefix(lower, "postgresql://") {
		return DialectPostgres
	}
	if strings.HasPrefix(lower, "sqlite://") || strings.HasPrefix(lower, "sqlite3://") {
		return DialectSQLite
	}
	// No scheme → assume SQLite file path (backward compatibility).
	return DialectSQLite
}

// ResolveDSN converts a possibly-scheme-prefixed DATABASE_URL into
// the form the registered driver expects:
//   - "sqlite://./simshop.db"  → "./simshop.db"
//   - "sqlite://:memory:"      → ":memory:"
//   - "postgres://u:p@h/db"    → unchanged (pgx accepts URL or KV)
//   - "./simshop.db"           → unchanged (no scheme → SQLite)
//
// This is the ONE place where scheme stripping happens, so the rest
// of the codebase can stay driver-agnostic.
//
// `net/url.Parse` is awkward for relative paths because it
// interprets `sqlite://simshop.db` as host="simshop.db" with empty
// path, and `sqlite://./simshop.db` as host="." path="/simshop.db"
// (the leading dot gets eaten as authority). We compensate for
// those cases below.
func ResolveDSN(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return trimmed
	}
	lower := strings.ToLower(trimmed)
	if !strings.HasPrefix(lower, "sqlite://") && !strings.HasPrefix(lower, "sqlite3://") {
		// Either no scheme (SQLite file path) or postgres://. Pass
		// through — pgx accepts URL form directly.
		return trimmed
	}
	// Strip the sqlite:// prefix and parse as URL so we can recover
	// the path component correctly for absolute paths.
	u, err := url.Parse(trimmed)
	if err != nil {
		// Malformed URL — fall back to a naive prefix strip.
		return strings.TrimPrefix(strings.TrimPrefix(trimmed, "sqlite://"), "sqlite3://")
	}
	// `sqlite://:memory:` parses with host=":memory:"; preserve the
	// well-known in-memory marker (some drivers reject anything else).
	if u.Host == ":memory:" || u.Opaque == ":memory:" {
		return ":memory:"
	}
	// `sqlite:///abs/path.db` parses with empty host and path set —
	// the happy path. Return it directly.
	if u.Path != "" {
		// `url.Parse` eats the leading "." of `sqlite://./foo` as
		// the authority, leaving path="/foo". Re-attach the dot so
		// SQLite resolves the file relative to the current dir.
		if u.Host == "." {
			return "./" + strings.TrimPrefix(u.Path, "/")
		}
		return u.Path
	}
	// `sqlite://relative` lands here (host set, path empty). The
	// "host" is actually the intended relative path. Fall back to
	// manual scheme stripping so we don't lose any characters the
	// URL parser would have normalized.
	return strings.TrimPrefix(strings.TrimPrefix(trimmed, "sqlite://"), "sqlite3://")
}
