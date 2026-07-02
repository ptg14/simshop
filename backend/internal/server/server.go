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

	productRepo := db.NewProductRepo(database.DB, database.Dialect)
	storeRepo := db.NewStoreRepo(database.DB, database.Dialect)
	articleRepo := db.NewArticleRepo(database.DB, database.Dialect)
	eventRepo := db.NewEventRepo(database.DB, database.Dialect)

	uploadCfg := &handler.UploadConfig{
		UploadDir:     cfg.UploadDir,
		MaxUploadSize: cfg.MaxUploadSize,
		BaseURL:       cfg.BaseURL,
	}

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
		log.Printf("WARNING: ADMIN_PUBLIC_KEY is empty — admin auth disabled, all write endpoints are public")
	} else {
		log.Printf("admin auth enabled (public key loaded)")
	}

	r := router.New(productRepo, storeRepo, articleRepo, eventRepo, uploadCfg, stores, cfg.AdminPublicKey, cfg.AllowedOrigin)

	addr := fmt.Sprintf(":%s", cfg.Port)
	srv := &http.Server{
		Addr:    addr,
		Handler: r,
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
