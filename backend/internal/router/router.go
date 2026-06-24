package router

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/middleware"
)

// New returns a mux.Router with all routes and middleware registered.
func New(productRepo *handler.ProductRepo, uploadCfg *handler.UploadConfig, allowedOrigin string) *mux.Router {
	r := mux.NewRouter()
	// Global middleware – use configurable allowed origin.
	r.Use(middleware.CORSMiddleware(allowedOrigin))

	// Rate limit mutating endpoints: 10 req/s with burst of 20.
	rateLimit := middleware.RateLimit(10, 20)

	// Ensure preflight requests for API paths always return CORS headers.
	// Some clients issue OPTIONS preflight to endpoints that are method-restricted;
	// registering an explicit OPTIONS handler for the /api/ prefix guarantees
	// we respond with the proper CORS headers.
	// Preflight handler respects the configured allowed origin.
	r.PathPrefix("/api/").Methods(http.MethodOptions).HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
		w.WriteHeader(http.StatusOK)
	})

	// Health
	r.HandleFunc("/health", handler.HealthHandler).Methods(http.MethodGet)

	// Product routes – the handler package expects a repository.
	r.HandleFunc("/api/products", handler.GetProductsHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products/{id}", handler.GetProductHandler(productRepo)).Methods(http.MethodGet)

	// Mutating product routes with rate limiting.
	productsWrite := r.PathPrefix("/api/products").Subrouter()
	productsWrite.Use(rateLimit)
	productsWrite.HandleFunc("", handler.CreateProductHandler(productRepo)).Methods(http.MethodPost)
	productsWrite.HandleFunc("/{id}", handler.UpdateProductHandler(productRepo)).Methods(http.MethodPut)
	productsWrite.HandleFunc("/{id}", handler.DeleteProductHandler(productRepo)).Methods(http.MethodDelete)

	// Categories
	r.HandleFunc("/api/categories", handler.GetCategoriesHandler(productRepo)).Methods(http.MethodGet)
	// Structured categories with their large-category parent (for frontend hierarchy).
	r.HandleFunc("/api/categories/with-parent", handler.GetCategoriesWithParentHandler(productRepo)).Methods(http.MethodGet)
	categoriesWrite := r.PathPrefix("/api/categories").Subrouter()
	categoriesWrite.Use(rateLimit)
	categoriesWrite.HandleFunc("", handler.CreateCategoryHandler(productRepo)).Methods(http.MethodPost)
	categoriesWrite.HandleFunc("/{name}", handler.DeleteCategoryHandler(productRepo)).Methods(http.MethodDelete)

	// Large categories (parent categories)
	r.HandleFunc("/api/large-categories", handler.GetLargeCategoriesHandler(productRepo)).Methods(http.MethodGet)
	largeCategoriesWrite := r.PathPrefix("/api/large-categories").Subrouter()
	largeCategoriesWrite.Use(rateLimit)
	largeCategoriesWrite.HandleFunc("", handler.CreateLargeCategoryHandler(productRepo)).Methods(http.MethodPost)
	largeCategoriesWrite.HandleFunc("/{name}", handler.DeleteLargeCategoryHandler(productRepo)).Methods(http.MethodDelete)

	// Upload route with rate limiting.
	uploadWrite := r.PathPrefix("/api/upload").Subrouter()
	uploadWrite.Use(rateLimit)
	uploadWrite.HandleFunc("", handler.UploadImageHandler(uploadCfg)).Methods(http.MethodPost)

	// Serve uploaded files as static content.
	uploadDir := http.Dir(uploadCfg.UploadDir)
	fileServer := http.FileServer(uploadDir)
	r.PathPrefix("/uploads/").Handler(http.StripPrefix("/uploads/", fileServer))

	return r
}
