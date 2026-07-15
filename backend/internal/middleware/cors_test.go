package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ptg14/simshop/backend/internal/middleware"
)

// TestCORS_SingleOriginMatches verifies the original contract: a
// single string ALLOWED_ORIGIN is echoed back as
// Access-Control-Allow-Origin, exactly. Both preflight (OPTIONS) and
// real requests must carry the header; mismatch with the request's
// Origin is what triggers the browser's "allow-origin-mismatch"
// error, so the value MUST match.
func TestCORS_SingleOriginMatches(t *testing.T) {
	h := middleware.CORSMiddleware("http://localhost:9090")(noopHandler())

	req := httptest.NewRequest(http.MethodGet, "/api/products", nil)
	req.Header.Set("Origin", "http://localhost:9090")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9090" {
		t.Errorf("Access-Control-Allow-Origin = %q, want %q", got, "http://localhost:9090")
	}
}

// TestCORS_SingleOriginMismatches pins the production bug: when the
// request's Origin doesn't match the configured ALLOWED_ORIGIN, the
// server still echoes back the configured origin (it cannot lie
// about which origins it allows), so the browser's preflight check
// fails. This is the "allow-origin-mismatch" surface — the test
// simply documents that the middleware itself can't be tricked into
// echoing the request's Origin; the operator has to configure the
// right value(s).
func TestCORS_SingleOriginMismatches(t *testing.T) {
	h := middleware.CORSMiddleware("http://localhost:9090")(noopHandler())

	// Origin on the request is the Flutter web dev port (8080),
	// not 9090 — must NOT be echoed back.
	req := httptest.NewRequest(http.MethodGet, "/api/products", nil)
	req.Header.Set("Origin", "http://localhost:8080")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9090" {
		t.Errorf("mismatch path: Access-Control-Allow-Origin = %q, want %q (server must not echo untrusted origin)",
			got, "http://localhost:9090")
	}
}

// TestCORS_MultipleOriginsEchoesTheMatchingOne pins the fix: the
// ALLOWED_ORIGIN env var is now a comma-separated list. The middleware
// builds a lookup at construction time; on each request it echoes
// back the entry that matches the request's Origin. Origins not in
// the list still get the *first* configured entry (the browser will
// then reject because the value doesn't match its Origin — but the
// server's behaviour is consistent and easy to reason about).
//
// Why a list rather than `*`: when admin endpoints carry
// `Authorization: Bearer ...` the request is "credentialed" and the
// spec disallows `*` as the response value. Echoing a specific
// matching origin is the only correct way to allow credentialed
// cross-origin admin requests.
func TestCORS_MultipleOriginsEchoesTheMatchingOne(t *testing.T) {
	h := middleware.CORSMiddleware(
		"http://localhost:8080,http://localhost:9090,http://localhost:8081",
	)(noopHandler())

	for _, origin := range []string{
		"http://localhost:8080",
		"http://localhost:9090",
		"http://localhost:8081",
	} {
		req := httptest.NewRequest(http.MethodGet, "/api/products", nil)
		req.Header.Set("Origin", origin)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)

		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != origin {
			t.Errorf("origin %q: Access-Control-Allow-Origin = %q, want %q",
				origin, got, origin)
		}
	}
}

// TestCORS_MultipleOriginsRejectsUnknown verifies the security back-
// stop: a request with an Origin that's not in the configured list
// must NOT be echoed back. The browser will reject the response
// because the value doesn't match its Origin — that's the whole
// point of an allowlist.
func TestCORS_MultipleOriginsRejectsUnknown(t *testing.T) {
	h := middleware.CORSMiddleware(
		"http://localhost:8080,http://localhost:9090",
	)(noopHandler())

	req := httptest.NewRequest(http.MethodGet, "/api/products", nil)
	req.Header.Set("Origin", "http://evil.example.com")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got == "http://evil.example.com" {
		t.Errorf("server echoed an unconfigured origin %q — that would let any site issue admin mutations", got)
	}
}

// TestCORS_PreflightOptions confirms preflight (OPTIONS) requests
// still return 200 with the CORS headers attached, regardless of
// whether the configured origin list matches.
func TestCORS_PreflightOptions(t *testing.T) {
	h := middleware.CORSMiddleware("http://localhost:9090")(noopHandler())

	req := httptest.NewRequest(http.MethodOptions, "/api/products", nil)
	req.Header.Set("Origin", "http://localhost:9090")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("OPTIONS preflight: status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:9090" {
		t.Errorf("OPTIONS preflight: Allow-Origin = %q, want %q", got, "http://localhost:9090")
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "POST") {
		t.Errorf("OPTIONS preflight: Allow-Methods = %q, missing POST", got)
	}
}

// TestCORS_AllowMethodsIncludesPATCH pins the regression that bit the
// admin quick-adjust stock stepper: the Allow-Methods header omitted
// PATCH, so the browser preflight for `PATCH /api/products/{id}/stock`
// failed with "method not allowed by Access-Control-Allow-Methods"
// and the +/- buttons silently no-op'd in the dev browser (the Go
// server itself was fine — it was only the preflight that blocked).
//
// The header is shipped as a single comma-separated string. We assert
// on each verb individually so a future refactor that uses
// `strings.Split` instead of substring search keeps the test useful,
// and a missing verb (the regression we just fixed) fails loudly.
func TestCORS_AllowMethodsIncludesPATCH(t *testing.T) {
	h := middleware.CORSMiddleware("http://localhost:9090")(noopHandler())

	// A non-OPTIONS request so we hit the path that just sets
	// headers and calls next (no preflight short-circuit). That
	// also exercises the same code path that real (non-PATCH)
	// admin mutations hit, so the assertion is meaningful for the
	// preflight response too.
	req := httptest.NewRequest(http.MethodGet, "/api/products", nil)
	req.Header.Set("Origin", "http://localhost:9090")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	got := rec.Header().Get("Access-Control-Allow-Methods")
	wantVerbs := []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"}
	parts := strings.Split(got, ",")
	// Trim spaces (the spec allows optional whitespace after the
	// comma; the middleware ships none, but a future reader
	// shouldn't break on whitespace if they ever format it).
	for i, p := range parts {
		parts[i] = strings.TrimSpace(p)
	}
	for _, want := range wantVerbs {
		var found bool
		for _, p := range parts {
			if p == want {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Allow-Methods %q missing verb %q (browser preflight will reject requests using it)", got, want)
		}
	}
}