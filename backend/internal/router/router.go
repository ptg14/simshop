package router

import (
	"net/http"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/middleware"
)

// New returns a mux.Router with all routes and middleware registered.
func New(productRepo *handler.ProductRepo) *mux.Router {
	r := mux.NewRouter()
	// Global middleware
	r.Use(middleware.CORSMiddleware)

	// Health
	r.HandleFunc("/health", handler.HealthHandler).Methods(http.MethodGet)

	// Product routes – the handler package expects a repository.
	r.HandleFunc("/api/products", handler.GetProductsHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products/{id}", handler.GetProductHandler(productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products", handler.CreateProductHandler(productRepo)).Methods(http.MethodPost)
	r.HandleFunc("/api/products/{id}", handler.UpdateProductHandler(productRepo)).Methods(http.MethodPut)
	r.HandleFunc("/api/products/{id}", handler.DeleteProductHandler(productRepo)).Methods(http.MethodDelete)

	return r
}
