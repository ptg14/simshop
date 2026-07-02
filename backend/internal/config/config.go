package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Config holds runtime configuration for the backend server.
type Config struct {
	// Port on which the HTTP server listens.
	Port string
	// DatabaseURL is passed straight through to db.New, which detects
	// the dialect from the scheme:
	//   - "postgres://" / "postgresql://" → PostgreSQL via pgx
	//   - "sqlite://"   / "sqlite3://"   → SQLite via mattn/go-sqlite3
	//   - bare path     (e.g. "./simshop.db") → SQLite (backward compat)
	DatabaseURL string
	// MaxOpenConns limits the number of open connections to SQLite.
	MaxOpenConns int
	// ConnMaxLifetime sets the maximum amount of time a connection may be reused.
	ConnMaxLifetime time.Duration
	// UploadDir is the directory where uploaded images are stored.
	UploadDir string
	// MaxUploadSize is the maximum allowed size (in bytes) for uploaded files.
	MaxUploadSize int64
	// AllowedOrigin for CORS. Use "*" to allow any origin.
	AllowedOrigin string
	// BaseURL is the public base URL used to construct absolute URLs (e.g., for uploaded images).
	// When set, it overrides the Host/X-Forwarded-Host headers to prevent host header spoofing.
	// Example: "https://example.com"
	BaseURL string
	// AdminPublicKey is the Ed25519 public key (hex-encoded 32 bytes)
	// used to verify admin key uploads on `/api/admin/auth/verify`.
	// When empty the auth middleware is disabled and admin write
	// endpoints behave exactly like before — public — so a developer
	// who hasn't set up keys yet isn't locked out. Logged at startup.
	AdminPublicKey string
}

// Load reads configuration from environment variables, providing sensible defaults.
func Load() *Config {
	loadDotEnv()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Database URL – default to a location under the repository that works from any
	// working directory. If the server is started from the repository root, the
	// DB file will be at ./backend/simshop.db. If started from the backend
	// subdirectory, we use ./simshop.db (relative to that directory) to avoid
	// creating a nested backend/backend path.
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		if wd, err := os.Getwd(); err == nil && filepath.Base(wd) == "backend" {
			dsn = "./simshop.db"
		} else {
			dsn = "./backend/simshop.db"
		}
	}

	maxConns := 10
	if v := os.Getenv("DB_MAX_OPEN_CONNS"); v != "" {
		if i, err := strconv.Atoi(v); err == nil && i > 0 {
			maxConns = i
		}
	}

	// Default to 1 hour, can be overridden via DB_CONN_MAX_LIFETIME (seconds).
	connLifetime := time.Hour
	if v := os.Getenv("DB_CONN_MAX_LIFETIME"); v != "" {
		if secs, err := strconv.Atoi(v); err == nil && secs > 0 {
			connLifetime = time.Duration(secs) * time.Second
		}
	}

	uploadDir := os.Getenv("UPLOAD_DIR")
	if uploadDir == "" {
		uploadDir = "./uploads"
	}

	maxUploadSize := int64(10 << 20) // 10 MB
	if v := os.Getenv("MAX_UPLOAD_SIZE"); v != "" {
		if i, err := strconv.ParseInt(v, 10, 64); err == nil && i > 0 {
			maxUploadSize = i
		}
	}

	allowedOrigin := "*"
	if v := os.Getenv("ALLOWED_ORIGIN"); v != "" {
		allowedOrigin = v
	}

	baseURL := os.Getenv("BASE_URL")

	adminPublicKey := os.Getenv("ADMIN_PUBLIC_KEY")

	return &Config{
		Port:            port,
		DatabaseURL:     dsn,
		MaxOpenConns:    maxConns,
		ConnMaxLifetime: connLifetime,
		UploadDir:       uploadDir,
		MaxUploadSize:   maxUploadSize,
		AllowedOrigin:   allowedOrigin,
		BaseURL:         baseURL,
		AdminPublicKey:  adminPublicKey,
	}
}

// loadDotEnv walks up from the current working directory looking for
// a `.env` file and loads any `KEY=value` pairs it finds into the
// process environment. Lines beginning with `#` are treated as
// comments; blank lines are skipped; values may optionally be wrapped
// in single or double quotes (which are stripped). Existing env vars
// take precedence — if the operator has already exported `FOO=bar`
// from their shell, we don't overwrite it.
//
// This deliberately avoids `github.com/joho/godotenv` to keep the
// dependency surface small: the format is dead-simple and we only
// need a couple of knobs. If the format ever grows (`export`, `\.`,
// variable interpolation), swap this for the library.
func loadDotEnv() {
	path, err := findDotEnv()
	if err != nil {
		return // no .env in cwd or any parent — that's fine
	}
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		// Strip surrounding quotes if present.
		if len(val) >= 2 {
			first, last := val[0], val[len(val)-1]
			if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
				val = val[1 : len(val)-1]
			}
		}
		// Operator-set env wins over file.
		if _, already := os.LookupEnv(key); !already {
			_ = os.Setenv(key, val)
		}
	}
}

// findDotEnv starts at the cwd and walks up at most 5 parent dirs
// looking for a `.env` file. Returns the first match. Bounds the
// walk so we never spin forever in weirdly-mounted filesystems.
func findDotEnv() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	dir := wd
	for i := 0; i < 5; i++ {
		candidate := filepath.Join(dir, ".env")
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break // hit filesystem root
		}
		dir = parent
	}
	return "", os.ErrNotExist
}
