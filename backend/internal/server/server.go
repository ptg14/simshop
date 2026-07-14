package server

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/ptg14/simshop/backend/internal/config"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/middleware"
	"github.com/ptg14/simshop/backend/internal/router"
)

// Start starts the HTTP server and blocks until the provided context is
// cancelled. On cancellation it attempts a graceful shutdown and closes
// database connections. This allows callers (e.g. main) to control shutdown
// in response to signals such as SIGINT/SIGTERM.
func Start(ctx context.Context) error {
	cfg := config.Load()

	database, err := db.New(cfg)
	if err != nil {
		return fmt.Errorf("database init: %w", err)
	}

	// Build uploadCfg first so we can pass it into the repos —
	// productRepo/storeRepo/articleRepo need it to best-effort
	// delete physical image files after DB writes commit.
	uploadCfg := &handler.UploadConfig{
		UploadDir:     cfg.UploadDir,
		MaxUploadSize: cfg.MaxUploadSize,
		BaseURL:       cfg.BaseURL,
	}

	productRepo := db.NewProductRepo(database.DB, database.Dialect, uploadCfg)
	storeRepo := db.NewStoreRepo(database.DB, database.Dialect, uploadCfg)
	articleRepo := db.NewArticleRepo(database.DB, database.Dialect, uploadCfg)
	eventRepo := db.NewEventRepo(database.DB, database.Dialect)

	// Ensure upload directory exists.
	if err := os.MkdirAll(cfg.UploadDir, 0755); err != nil {
		database.Close()
		return fmt.Errorf("create upload dir: %w", err)
	}

	// Admin auth state. In-memory only — sessions are lost on restart,
	// which forces the admin to re-prove possession of the secret key
	// after a deploy. The session/challenge cleanup goroutine runs for
	// the lifetime of the process; no shutdown hook needed (it dies
	// with main()).
	stores := handler.NewSessionStore()
	go stores.Cleanup()
	if cfg.AdminPublicKey == "" {
		// In production, refuse to start when admin auth would be
		// silent — the operator likely forgot to set the key, and
		// running with public write endpoints is much worse than
		// refusing the deploy. In development, warn and continue so
		// local iteration isn't painful.
		if cfg.Env == "production" {
			log.Fatalf("ADMIN_PUBLIC_KEY is empty in production (ENV=production); refusing to start with admin auth disabled. Set ADMIN_PUBLIC_KEY or unset ENV.")
		}
		log.Printf("WARNING: ADMIN_PUBLIC_KEY is empty — admin auth disabled, all write endpoints are public")
	} else {
		log.Printf("admin auth enabled (public key loaded)")
	}
	log.Printf("starting server (env=%q, adminAuth=%v, trustedProxies=%d)", cfg.Env, cfg.AdminPublicKey != "", len(cfg.TrustedProxies))

	r := router.New(productRepo, storeRepo, articleRepo, eventRepo, uploadCfg, stores, cfg.AdminPublicKey, cfg.AllowedOrigin, cfg.TrustedProxies)

	addr := fmt.Sprintf(":%s", cfg.Port)

	// Wrap the mux router in CORS middleware at the http.Server level
	// instead of registering it via [mux.Router.Use]. gorilla/mux's
	// `Use` only fires middleware for requests that match a route —
	// OPTIONS preflight for paths the client doesn't know about
	// (e.g. /api/upload, /api/store-info) hit a 404/405 *before*
	// the CORS middleware runs, so the browser sees a preflight
	// failure with no Allow-Origin header and refuses to send the
	// real request. Wrapping at the Server level guarantees every
	// request (including OPTIONS for unknown paths) passes through
	// the middleware first.
	//
	// The router-internal `r.Use(CORSMiddleware(...))` call is
	// preserved as a safety net — if a future refactor drops this
	// outer wrapper, single-method routes still get the right
	// Allow-Origin value on plain (non-preflight) requests.
	handler := middleware.CORSMiddleware(cfg.AllowedOrigin)(r)

	srv := &http.Server{
		Addr:    addr,
		Handler: handler,
	}

	// Run server in background.
	errCh := make(chan error, 1)
	go func() {
		log.Printf("starting server on %s", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
		close(errCh)
	}()

	// Wait for context cancellation or server error.
	select {
	case <-ctx.Done():
		// Attempt graceful shutdown with timeout.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Printf("error during shutdown: %v", err)
		}
		// Close DB after server has shut down.
		if cerr := database.Close(); cerr != nil {
			log.Printf("error closing database: %v", cerr)
		}
		return nil
	case err := <-errCh:
		// Server encountered an unexpected error.
		database.Close()
		if err != nil {
			return fmt.Errorf("server error: %w", err)
		}
		return nil
	}
}
