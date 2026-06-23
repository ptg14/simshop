package middleware

import (
	"net/http"
)

// CORSMiddleware adds basic CORS headers to allow cross‑origin requests.
// It permits any origin and common HTTP methods. For production you may
// want to restrict the allowed origins.
// CORSMiddleware adds CORS headers based on configuration.
// The allowed origin can be set via the Config.AllowedOrigin field (environment variable ALLOWED_ORIGIN).
// If not set, it defaults to "*" (allow any origin).
func CORSMiddleware(allowedOrigin string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")

			// Handle preflight requests.
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusOK)
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
