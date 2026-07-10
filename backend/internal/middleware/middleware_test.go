package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ptg14/simshop/backend/internal/middleware"
)

// noopHandler is the inner handler the rate-limit middleware wraps.
// It just writes 200 so a test can tell "request reached the handler"
// apart from "middleware rejected it".
func noopHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

// TestRateLimit_RejectsSpoofedXFF is the regression test for
// NEW-HIGH-003: the original middleware trusted X-Forwarded-For
// unconditionally, letting any client spoof a different IP. The fix
// keys the bucket on r.RemoteAddr unless the immediate peer is in
// the trusted CIDR set.
//
// Layout: RateLimit(1, 1, nil) = bucket of 1 token, no trusted
// proxies. Two requests from 127.0.0.1 exhaust the bucket; a request
// from 6.6.6.6 (different host) succeeds — proving the bucket is
// keyed by RemoteAddr, not XFF.
func TestRateLimit_RejectsSpoofedXFF(t *testing.T) {
	rl := middleware.RateLimit(1, 1, nil)
	h := rl(noopHandler())

	// First request from 127.0.0.1 with a spoofed XFF → 200 (uses the
	// one token).
	rec1 := doReq(h, "127.0.0.1:11111", "6.6.6.6")
	if rec1.Code != http.StatusOK {
		t.Errorf("first request: status = %d, want 200", rec1.Code)
	}
	// Second request from the SAME RemoteAddr → 429 (bucket empty).
	rec2 := doReq(h, "127.0.0.1:11112", "7.7.7.7")
	if rec2.Code != http.StatusTooManyRequests {
		t.Errorf("second request from same RemoteAddr: status = %d, want 429", rec2.Code)
	}
	// Third request from a DIFFERENT RemoteAddr (no XFF) → 200 — the
	// spoofed XFF didn't unlock a new bucket.
	rec3 := doReq(h, "6.6.6.6:5000", "")
	if rec3.Code != http.StatusOK {
		t.Errorf("third request from different RemoteAddr: status = %d, want 200 (XFF must not spoof)", rec3.Code)
	}
}

// TestRateLimit_HonorsXFFWhenProxied is the inverse case: with the
// proxy allow-list populated, requests from a trusted peer ARE keyed
// by the leftmost XFF entry. So a single token bucket of 1 lets
// 127.0.0.1+6.6.6.6 burn the bucket; a fresh 127.0.0.1+6.6.6.6 then
// 429s; a 127.0.0.1+9.9.9.9 is a NEW client and succeeds.
func TestRateLimit_HonorsXFFWhenProxied(t *testing.T) {
	rl := middleware.RateLimit(1, 1, []string{"127.0.0.0/8"})
	h := rl(noopHandler())

	rec1 := doReq(h, "127.0.0.1:11111", "6.6.6.6")
	if rec1.Code != http.StatusOK {
		t.Errorf("first proxied request: status = %d, want 200", rec1.Code)
	}
	// Same effective client (6.6.6.6) → 429.
	rec2 := doReq(h, "127.0.0.1:22222", "6.6.6.6, 10.0.0.1")
	if rec2.Code != http.StatusTooManyRequests {
		t.Errorf("replay from same XFF client: status = %d, want 429", rec2.Code)
	}
	// Different effective client (9.9.9.9) → 200.
	rec3 := doReq(h, "127.0.0.1:33333", "9.9.9.9")
	if rec3.Code != http.StatusOK {
		t.Errorf("different XFF client: status = %d, want 200", rec3.Code)
	}
}

// TestRateLimit_NonTrustedPeer_IgnoresXFF confirms that when the
// immediate peer isn't in any trusted CIDR, even with a syntactically
// valid XFF, the bucket stays keyed on RemoteAddr. This is the
// important backstop for production deployments that forget to
// configure TRUSTED_PROXIES — the limiter still does the right
// thing.
func TestRateLimit_NonTrustedPeer_IgnoresXFF(t *testing.T) {
	rl := middleware.RateLimit(1, 1, []string{"10.0.0.0/8"})
	h := rl(noopHandler())

	// Peer is 192.168.1.1 — NOT in 10.0.0.0/8. XFF must be ignored.
	rec1 := doReq(h, "192.168.1.1:5555", "6.6.6.6")
	if rec1.Code != http.StatusOK {
		t.Errorf("first: status = %d, want 200", rec1.Code)
	}
	// Different XFF, same RemoteAddr → 429 (still keyed on 192.168.1.1).
	rec2 := doReq(h, "192.168.1.1:6666", "7.7.7.7")
	if rec2.Code != http.StatusTooManyRequests {
		t.Errorf("replay from same RemoteAddr (different XFF): status = %d, want 429", rec2.Code)
	}
}

func doReq(h http.Handler, remoteAddr, xff string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = remoteAddr
	if xff != "" {
		req.Header.Set("X-Forwarded-For", xff)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}