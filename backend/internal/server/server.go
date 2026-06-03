package server

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/ptg14/simshop/backend/internal/config"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/router"
)

// Start loads configuration, initialises the database, sets up routes, and
// starts the HTTP server.
func Start() error {
	cfg := config.Load()

	database, err := db.New(cfg)
	if err != nil {
		return fmt.Errorf("database init: %w", err)
	}
	defer database.Close()

	productRepo := db.NewProductRepo(database.DB)

	uploadCfg := &handler.UploadConfig{
		UploadDir:     cfg.UploadDir,
		MaxUploadSize: cfg.MaxUploadSize,
	}

	// Ensure upload directory exists.
	if err := os.MkdirAll(cfg.UploadDir, 0755); err != nil {
		return fmt.Errorf("create upload dir: %w", err)
	}

	r := router.New(productRepo, uploadCfg)

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("starting server on %s", addr)
	return http.ListenAndServe(addr, r)
}
