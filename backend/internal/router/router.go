package router

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/middleware"
)

// New returns a mux.Router with all routes and middleware registered.
func New(productRepo *handler.ProductRepo, uploadCfg *handler.UploadConfig) *mux.Router {
	r := mux.NewRouter()
	// Global middleware
	r.Use(middleware.CORSMiddleware)

	// Ensure preflight requests for API paths always return CORS headers.
	// Some clients issue OPTIONS preflight to endpoints that are method-restricted;
	// registering an explicit OPTIONS handler for the /api/ prefix guarantees
	// we respond with the proper CORS headers.
	r.PathPrefix("/api/").Methods(http.MethodOptions).HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
		w.WriteHeader(http.StatusOK)
	})

	// Health
	r.HandleFunc("/health", handler.HealthHandler).Methods(http.MethodGet)

	// Product routes – the handler package expects a repository.
	r.HandleFunc("/api/products", handler.GetProductsHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products/{id}", handler.GetProductHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products", handler.CreateProductHandler(productRepo)).Methods(http.MethodPost)
	r.HandleFunc("/api/products/{id}", handler.UpdateProductHandler(productRepo)).Methods(http.MethodPut)
	r.HandleFunc("/api/products/{id}", handler.DeleteProductHandler(productRepo)).Methods(http.MethodDelete)

	// Categories
	r.HandleFunc("/api/categories", handler.GetCategoriesHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/categories", handler.CreateCategoryHandler(productRepo)).Methods(http.MethodPost)
	r.HandleFunc("/api/categories/{name}", handler.DeleteCategoryHandler(productRepo)).Methods(http.MethodDelete)

	// Upload route
	r.HandleFunc("/api/upload", handler.UploadImageHandler(uploadCfg)).Methods(http.MethodPost)

	// Serve uploaded files as static content.
	uploadDir := http.Dir(uploadCfg.UploadDir)
	fileServer := http.FileServer(uploadDir)
	r.PathPrefix("/uploads/").Handler(http.StripPrefix("/uploads/", fileServer))

	return r
}
