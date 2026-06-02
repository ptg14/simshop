package config

import (
	"os"
	"strconv"
	"time"
)

// Config holds runtime configuration for the backend server.
type Config struct {
	// Port on which the HTTP server listens.
	Port string
	// DSN for SQLite – either a file path or ":memory:".
	DatabaseURL string
	// MaxOpenConns limits the number of open connections to SQLite.
	MaxOpenConns int
	// ConnMaxLifetime sets the maximum amount of time a connection may be reused.
	ConnMaxLifetime time.Duration
}

// Load reads configuration from environment variables, providing sensible defaults.
func Load() *Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = ":memory:"
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

	return &Config{
		Port:            port,
		DatabaseURL:     dsn,
		MaxOpenConns:    maxConns,
		ConnMaxLifetime: connLifetime,
	}
}
