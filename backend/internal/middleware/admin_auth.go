package middleware

import (
	"net/http"

	"github.com/ptg14/simshop/backend/internal/handler"
)

// RequireAdminSession guards admin write endpoints.
//
// When [pubKeyLen] is 0 the middleware is a no-op so a developer who
// hasn't configured `ADMIN_PUBLIC_KEY` yet is not locked out of their
// own server. A warning is logged once at startup by [server.Start];
// we don't repeat it here to avoid log spam per request.
//
// The token lookup uses constant-ish time on the map path. We don't
// bother with a constant-time comparison because the token is already
// a 32-byte random secret — guessing it is infeasible regardless of
// timing.
func RequireAdminSession(stores *handler.SessionStore, pubKeyLen int) func(http.Handler) http.Handler {
	authDisabled := pubKeyLen == 0
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if authDisabled {
				next.ServeHTTP(w, r)
				return
			}
			token := extractBearerToken(r.Header.Get("Authorization"))
			if token == "" || !stores.ValidSession(token) {
				w.Header().Set("Content-Type", "application/json")
				w.Header().Set("WWW-Authenticate", `Bearer realm="admin"`)
				w.WriteHeader(http.StatusUnauthorized)
				_, _ = w.Write([]byte(`{"error":"admin session required"}`))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// extractBearerToken mirrors [handler.extractBearer]. We duplicate
// rather than export to keep the middleware package dependency-light
// (middleware → handler.SessionStore is one direction; this is fine).
func extractBearerToken(h string) string {
	const prefix = "Bearer "
	if len(h) <= len(prefix) {
		return ""
	}
	if h[:len(prefix)] != prefix {
		return ""
	}
	// Trim is sufficient — no need for constant-time on a randomly
	// generated secret.
	t := h[len(prefix):]
	// Strip trailing whitespace in a single pass.
	for len(t) > 0 && (t[len(t)-1] == ' ' || t[len(t)-1] == '\t') {
		t = t[:len(t)-1]
	}
	return t
}