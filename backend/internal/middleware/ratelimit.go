package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// RateLimiter implements a simple token-bucket rate limiter per client IP.
// It is safe for concurrent use.
type RateLimiter struct {
	mu       sync.Mutex
	visitors map[string]*visitor
	rate     float64 // tokens per second
	burst    int     // max burst size
}

type visitor struct {
	tokens    float64
	lastCheck time.Time
}

// NewRateLimiter creates a rate limiter with the given rate (requests/second) and burst.
func NewRateLimiter(rate float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     rate,
		burst:    burst,
	}
	// Periodically clean up stale visitors.
	go rl.cleanup(5 * time.Minute)
	return rl
}

// Allow checks whether a request from the given IP is allowed.
func (rl *RateLimiter) Allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.visitors[ip]
	now := time.Now()
	if !exists {
		rl.visitors[ip] = &visitor{tokens: float64(rl.burst) - 1, lastCheck: now}
		return true
	}

	elapsed := now.Sub(v.lastCheck).Seconds()
	v.tokens += elapsed * rl.rate
	if v.tokens > float64(rl.burst) {
		v.tokens = float64(rl.burst)
	}
	v.lastCheck = now

	if v.tokens < 1 {
		return false
	}
	v.tokens--
	return true
}

// cleanup removes visitors that haven't been seen for the given duration.
func (rl *RateLimiter) cleanup(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastCheck) > interval {
				delete(rl.visitors, ip)
			}
		}
		rl.mu.Unlock()
	}
}

// RateLimit returns middleware that limits requests per client IP. rate
// is requests/second, burst is the max bucket size.
//
// [trustedCIDRs] gates the use of the X-Forwarded-For header. When
// empty, the middleware always uses r.RemoteAddr — preventing clients
// from spoofing a different IP by injecting their own XFF header. When
// non-empty, only requests whose r.RemoteAddr host falls in one of
// the listed CIDRs may have their XFF honored (the leftmost IP in the
// header is taken as the client). Call this from behind a known
// reverse proxy with TRUSTED_PROXIES=10.0.0.0/8,127.0.0.1/32 etc.
//
// Use RateLimitStrict when the endpoint must never trust proxy headers
// (e.g. /api/admin/auth/challenge).
func RateLimit(rate, burst float64, trustedCIDRs []string) func(http.Handler) http.Handler {
	trusted := parseTrustedCIDRs(trustedCIDRs)
	limiter := NewRateLimiter(rate, int(burst))
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := resolveClientIP(r, trusted)
			if !limiter.Allow(ip) {
				w.Header().Set("Retry-After", "1")
				http.Error(w, `{"error":"rate limit exceeded"}`, http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RateLimitStrict is the "never trust proxy headers" variant of
// RateLimit. Use it on endpoints whose abuse model assumes the client
// is the immediate TCP peer (e.g. /api/admin/auth/challenge, where
// each request costs CPU).
func RateLimitStrict(rate, burst float64) func(http.Handler) http.Handler {
	return RateLimit(rate, burst, nil)
}

// resolveClientIP picks the IP to key the rate-limit bucket on. When
// [trusted] is empty (or the immediate peer isn't in any of the
// trusted CIDRs) we always return r.RemoteAddr's host component so
// clients can't bypass the limiter by injecting their own
// X-Forwarded-For header AND so ephemeral source-port changes don't
// fragment the bucket.
//
// [trusted] is the parsed list of CIDRs from RateLimit's caller.
func resolveClientIP(r *http.Request, trusted []*net.IPNet) string {
	host := hostFromRemoteAddr(r.RemoteAddr)
	if host == "" {
		return r.RemoteAddr
	}
	peerIP := net.ParseIP(host)
	if peerIP == nil {
		return r.RemoteAddr
	}
	// Only honor XFF when the immediate peer is itself trusted.
	trustedPeer := false
	for _, n := range trusted {
		if n.Contains(peerIP) {
			trustedPeer = true
			break
		}
	}
	if !trustedPeer {
		// Use the bare host (no port) so ephemeral source-port
		// changes from the same client don't fragment the bucket.
		return host
	}
	xff := r.Header.Get("X-Forwarded-For")
	if xff == "" {
		return host
	}
	// Take the leftmost (original client) IP — the format is
	// "client, proxy1, proxy2, ...".
	for i := 0; i < len(xff); i++ {
		if xff[i] == ',' {
			return strings.TrimSpace(xff[:i])
		}
	}
	return strings.TrimSpace(xff)
}

// hostFromRemoteAddr strips the :port suffix from a "host:port"
// RemoteAddr, returning the bare host. Returns the input unchanged
// when no port is present (e.g. a bare "::1" IPv6 literal).
func hostFromRemoteAddr(addr string) string {
	if addr == "" {
		return ""
	}
	// net.SplitHostPort handles IPv4 and bracketed IPv6 correctly.
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		// Likely a bare IPv6 without brackets; fall back to TrimSpace.
		return strings.TrimSpace(addr)
	}
	return host
}

// parseTrustedCIDRs turns the raw []string (env-derived) into parsed
// *net.IPNet values. Empty / unparseable entries are silently dropped
// — the caller falls back to "never trust XFF", which is the safer
// default.
func parseTrustedCIDRs(raw []string) []*net.IPNet {
	if len(raw) == 0 {
		return nil
	}
	var out []*net.IPNet
	for _, s := range raw {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		_, n, err := net.ParseCIDR(s)
		if err != nil {
			continue
		}
		out = append(out, n)
	}
	return out
}
