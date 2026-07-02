package router

import (
	"crypto/ed25519"
	"encoding/hex"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/handler"
	"github.com/ptg14/simshop/backend/internal/middleware"
)

// New returns a mux.Router with all routes and middleware registered.
//
// [stores] holds admin auth state (challenges + session tokens). When
// nil, admin auth is fully bypassed (no challenge/verify endpoints
// registered, every write subrouter is unprotected). That matches the
// behavior before admin auth was introduced so older deployments
// don't crash if they haven't been configured.
//
// [adminPublicKeyHex] is the hex-encoded Ed25519 public key. When
// empty the middleware is a no-op (same back-compat reasoning).
func New(productRepo *handler.ProductRepo, storeRepo *handler.StoreRepo, articleRepo *handler.ArticleRepo, eventRepo *handler.EventRepo, uploadCfg *handler.UploadConfig, stores *handler.SessionStore, adminPublicKeyHex string, allowedOrigin string) *mux.Router {
	r := mux.NewRouter()
	// Global middleware – use configurable allowed origin.
	r.Use(middleware.CORSMiddleware(allowedOrigin))

	// Rate limit mutating endpoints: 10 req/s with burst of 20.
	rateLimit := middleware.RateLimit(10, 20)

	// Decode the admin public key once. Empty / malformed → disabled.
	var adminPub ed25519.PublicKey
	if adminPublicKeyHex != "" {
		raw, err := hex.DecodeString(adminPublicKeyHex)
		if err != nil || len(raw) != ed25519.PublicKeySize {
			// Bad config — leave adminPub nil so the middleware
			// no-ops. Server startup logs the warning.
			adminPub = nil
		} else {
			adminPub = ed25519.PublicKey(raw)
		}
	}
	adminAuth := middleware.RequireAdminSession(stores, len(adminPub))

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

	// Admin auth (challenge + verify + logout) — public. Wrapping
	// these in rateLimit (and later RequireAdminSession) would
	// deadlock the very endpoint needed to GET a session token.
	if stores != nil && len(adminPub) > 0 {
		authWrite := r.PathPrefix("/api/admin/auth").Subrouter()
		// No rate limit on verify: legitimate admins signing in would
		// hit it once per browser tab. We rely on the secret-key
		// verification being computationally cheap (~µs) and the
		// nonce TTL of 60s to bound abuse.
		authWrite.HandleFunc("/challenge", handler.ChallengeHandler(stores)).Methods(http.MethodPost)
		authWrite.HandleFunc("/verify", handler.VerifyHandler(stores, adminPub)).Methods(http.MethodPost)
		authWrite.HandleFunc("/logout", handler.LogoutHandler(stores)).Methods(http.MethodPost)
	}

	// Product routes – the handler package expects a repository.
	// eventRepo decorates each read with effective_price + current_event.
	r.HandleFunc("/api/products", handler.GetProductsHandler(productRepo, eventRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/products/{id}", handler.GetProductHandler(productRepo, eventRepo)).Methods(http.MethodGet)

	// Mutating product routes with rate limiting + admin auth.
	// Middleware order: RateLimit first (cheap, applies to every
	// write to throttle brute-force), then RequireAdminSession (more
	// expensive because of the map lookup).
	productsWrite := r.PathPrefix("/api/products").Subrouter()
	productsWrite.Use(rateLimit)
	productsWrite.Use(adminAuth)
	productsWrite.HandleFunc("", handler.CreateProductHandler(productRepo)).Methods(http.MethodPost)
	productsWrite.HandleFunc("/{id}", handler.UpdateProductHandler(productRepo)).Methods(http.MethodPut)
	productsWrite.HandleFunc("/{id}", handler.DeleteProductHandler(productRepo)).Methods(http.MethodDelete)

	// Structured categories with their large-category parent (for frontend hierarchy).
	r.HandleFunc("/api/categories/with-parent", handler.GetCategoriesWithParentHandler(productRepo)).Methods(http.MethodGet)
	categoriesWrite := r.PathPrefix("/api/categories").Subrouter()
	categoriesWrite.Use(rateLimit)
	categoriesWrite.Use(adminAuth)
	categoriesWrite.HandleFunc("", handler.CreateCategoryHandler(productRepo)).Methods(http.MethodPost)
	categoriesWrite.HandleFunc("/{name}", handler.DeleteCategoryHandler(productRepo)).Methods(http.MethodDelete)

	// Large categories (parent categories)
	r.HandleFunc("/api/large-categories", handler.GetLargeCategoriesHandler(productRepo)).Methods(http.MethodGet)
	largeCategoriesWrite := r.PathPrefix("/api/large-categories").Subrouter()
	largeCategoriesWrite.Use(rateLimit)
	largeCategoriesWrite.Use(adminAuth)
	largeCategoriesWrite.HandleFunc("", handler.CreateLargeCategoryHandler(productRepo)).Methods(http.MethodPost)
	largeCategoriesWrite.HandleFunc("/{name}", handler.DeleteLargeCategoryHandler(productRepo)).Methods(http.MethodDelete)

	// Site info (singleton). GET is public (used by home + product detail),
	// PUT is admin-only.
	r.HandleFunc("/api/store-info", handler.GetStoreInfoHandler(storeRepo)).Methods(http.MethodGet)
	storeInfoWrite := r.PathPrefix("/api/store-info").Subrouter()
	storeInfoWrite.Use(rateLimit)
	storeInfoWrite.Use(adminAuth)
	storeInfoWrite.HandleFunc("", handler.UpdateStoreInfoHandler(storeRepo)).Methods(http.MethodPut)

	// Banners (carousel). GET is public; mutating routes require admin auth.
	r.HandleFunc("/api/banners", handler.ListBannersHandler(articleRepo)).Methods(http.MethodGet)
	bannersWrite := r.PathPrefix("/api/banners").Subrouter()
	bannersWrite.Use(rateLimit)
	bannersWrite.Use(adminAuth)
	bannersWrite.HandleFunc("", handler.CreateBannerHandler(articleRepo)).Methods(http.MethodPost)
	bannersWrite.HandleFunc("/{id}", handler.UpdateBannerHandler(articleRepo)).Methods(http.MethodPut)
	bannersWrite.HandleFunc("/{id}", handler.DeleteBannerHandler(articleRepo)).Methods(http.MethodDelete)

	// Events (time-boxed promotions). GET is public — the home
	// and product-detail flows read them indirectly via the
	// `current_event` field that GetProductsHandler/GetProductHandler
	// attach to each product. The dedicated list endpoint is for the
	// admin dashboard.
	r.HandleFunc("/api/events", handler.ListEventsHandler(eventRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/events/{id}", handler.GetEventHandler(eventRepo)).Methods(http.MethodGet)
	eventsWrite := r.PathPrefix("/api/events").Subrouter()
	eventsWrite.Use(rateLimit)
	eventsWrite.Use(adminAuth)
	eventsWrite.HandleFunc("", handler.CreateEventHandler(eventRepo)).Methods(http.MethodPost)
	eventsWrite.HandleFunc("/{id}", handler.UpdateEventHandler(eventRepo)).Methods(http.MethodPut)
	eventsWrite.HandleFunc("/{id}", handler.DeleteEventHandler(eventRepo)).Methods(http.MethodDelete)

	// Articles. The GET on /:id joins the products the article
	// mentions (used by the home carousel tap → article screen flow).
	r.HandleFunc("/api/articles/{id}", handler.GetArticleWithProductsHandler(articleRepo, productRepo)).Methods(http.MethodGet)
	r.HandleFunc("/api/articles", handler.ListArticlesHandler(articleRepo)).Methods(http.MethodGet)
	articlesWrite := r.PathPrefix("/api/articles").Subrouter()
	articlesWrite.Use(rateLimit)
	articlesWrite.Use(adminAuth)
	articlesWrite.HandleFunc("", handler.CreateArticleHandler(articleRepo)).Methods(http.MethodPost)
	articlesWrite.HandleFunc("/{id}", handler.UpdateArticleHandler(articleRepo)).Methods(http.MethodPut)
	articlesWrite.HandleFunc("/{id}", handler.DeleteArticleHandler(articleRepo)).Methods(http.MethodDelete)

	// Upload route with rate limiting + admin auth.
	uploadWrite := r.PathPrefix("/api/upload").Subrouter()
	uploadWrite.Use(rateLimit)
	uploadWrite.Use(adminAuth)
	uploadWrite.HandleFunc("", handler.UploadImageHandler(uploadCfg)).Methods(http.MethodPost)

	// Serve uploaded files as static content.
	uploadDir := http.Dir(uploadCfg.UploadDir)
	fileServer := http.FileServer(uploadDir)
	r.PathPrefix("/uploads/").Handler(http.StripPrefix("/uploads/", fileServer))

	return r
}