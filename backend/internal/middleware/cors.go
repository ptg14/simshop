package middleware

import (
	"net/http"
	"strings"
)

// CORSMiddleware adds CORS headers based on configuration.
//
// [allowedOrigin] is either:
//   - a single origin (e.g. `https://simshop.example.com`),
//   - a comma-separated allowlist (e.g.
//     `http://localhost:8080,http://localhost:9090`) — useful when
//     developers run the Flutter web build on different ports than
//     the standardized 9090 (e.g. `flutter run -d chrome` picks a
//     random ephemeral port),
//   - or `*` to allow any origin. Note: with credentialed requests
//     (admin endpoints carry `Authorization: Bearer ...`) the spec
//     forbids `*` as the response value. Operators wanting
//     credentials + cross-origin should use the allowlist form
//     instead — the multi-origin path then echoes back the matching
//     origin, which IS allowed for credentialed requests.
//
// On every request the middleware writes
// `Access-Control-Allow-Origin: <origin>` where <origin> is the
// request's Origin header if it matches an entry in the configured
// list, otherwise the *first* configured entry. Browsers reject
// responses whose Allow-Origin doesn't match the request's Origin,
// so an unknown origin gets a response that fails CORS — but the
// server never echoes an unconfigured origin (would let any site
// issue admin mutations).
//
// Preflight (OPTIONS) requests short-circuit with 200 after writing
// the headers — same shape as the original middleware.
//
// Why a list instead of `*`: credentialed cross-origin requests
// require a specific origin in the Allow-Origin response, not `*`.
// The single-origin shape didn't accommodate local dev where
// `flutter run -d chrome` picks an ephemeral port.
func CORSMiddleware(allowedOrigin string) func(http.Handler) http.Handler {
	allowed := splitAndTrim(allowedOrigin, ",")
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			echo := pickAllowedOrigin(origin, allowed)

			w.Header().Set("Access-Control-Allow-Origin", echo)
			// PATCH was added when the admin quick-adjust stock
			// stepper landed (`PATCH /api/products/{id}/stock`).
			// Without it the browser's preflight fails with
			// "method not allowed by Access-Control-Allow-Methods"
			// and the +/- button silently no-ops in dev. Keep this
			// in sync with the verbs registered in router.go.
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
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

// pickAllowedOrigin returns [origin] verbatim if it's in [allowed],
// otherwise the first entry of [allowed]. The fallback is
// intentional — every response must carry some Allow-Origin value
// (otherwise browsers refuse to render anything), and the configured
// entries are the only safe values to echo. The browser will reject
// the response because the value doesn't match the request's Origin,
// which is exactly what we want for an unknown origin.
func pickAllowedOrigin(origin string, allowed []string) string {
	if len(allowed) == 0 {
		return ""
	}
	for _, a := range allowed {
		if a == origin {
			return origin
		}
	}
	return allowed[0]
}

// splitAndTrim splits [s] on [sep] and trims surrounding whitespace
// from each piece. Empty pieces are dropped so a trailing comma
// (`"http://x,"`) doesn't accidentally allow the empty-string
// origin.
func splitAndTrim(s, sep string) []string {
	if s == "" {
		return nil
	}
	raw := strings.Split(s, sep)
	out := make([]string, 0, len(raw))
	for _, p := range raw {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}