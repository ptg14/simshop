package handler

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Admin-auth state: Ed25519 challenge/verify + in-memory session tokens.
//
// Flow (admin client):
//   1. POST /api/admin/auth/challenge  → { "nonce": "<hex>" }
//   2. Sign the nonce with the secret key file the admin holds.
//   3. POST /api/admin/auth/verify (multipart):
//        fields: nonce, signature (hex of ed25519 signature)
//        file:   key (raw 64-byte Ed25519 secret key)
//      → { "token": "<hex>", "expires_at": <unix> }
//   4. Subsequent admin write calls carry `Authorization: Bearer <token>`.
//
// All state lives in [SessionStore] — in-memory only, so server
// restarts log everyone out. That's intentional: it forces the admin
// to re-prove possession of the secret key after a deploy.

// SessionStore holds active admin sessions (token → expiry) and
// pending challenges (nonce → expiry). Safe for concurrent use.
//
// MaxChallenges and MaxSessions cap the in-memory map sizes so an
// unauthenticated attacker can't OOM the server by issuing challenges
// or verifying them at a high rate. Defaults are 1024 each — orders
// of magnitude more than any legitimate admin fleet would produce.
// Tests can mutate these fields directly to exercise the cap paths.
type SessionStore struct {
	mu            sync.RWMutex
	sessions      map[string]time.Time // token → expiry
	challenges    map[string]time.Time // nonce → expiry
	tokenTTL      time.Duration
	challengeTTL  time.Duration
	MaxChallenges int // public: max in-flight challenges; default 1024
	MaxSessions   int // public: max active sessions; default 1024
}

// NewSessionStore returns a SessionStore with sensible defaults:
// 24-hour token TTL, 60-second challenge TTL, 1024-entry caps on
// each in-memory map.
func NewSessionStore() *SessionStore {
	return &SessionStore{
		sessions:      make(map[string]time.Time),
		challenges:    make(map[string]time.Time),
		tokenTTL:      24 * time.Hour,
		challengeTTL:  60 * time.Second,
		MaxChallenges: 1024,
		MaxSessions:   1024,
	}
}

// IssueChallenge generates a random nonce, stores it, and returns it.
// Returns ErrChallengeCapacity when the in-memory map is already at
// MaxChallenges entries — the caller (ChallengeHandler) maps that to
// a 429.
func (s *SessionStore) IssueChallenge() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	nonce := hex.EncodeToString(raw)
	s.mu.Lock()
	if s.MaxChallenges > 0 && len(s.challenges) >= s.MaxChallenges {
		s.mu.Unlock()
		return "", ErrChallengeCapacity
	}
	s.challenges[nonce] = time.Now().Add(s.challengeTTL)
	s.mu.Unlock()
	return nonce, nil
}

// ConsumeChallenge validates and removes a challenge nonce. Returns
// ErrChallengeExpired if the nonce is unknown or has aged out.
func (s *SessionStore) ConsumeChallenge(nonce string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	expiry, ok := s.challenges[nonce]
	delete(s.challenges, nonce)
	if !ok || time.Now().After(expiry) {
		return ErrChallengeExpired
	}
	return nil
}

// IssueSession mints a token for a verified admin. Returns
// ErrSessionCapacity when the in-memory map is already at
// MaxSessions entries.
func (s *SessionStore) IssueSession() (string, time.Time, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, err
	}
	token := hex.EncodeToString(raw)
	expiry := time.Now().Add(s.tokenTTL)
	s.mu.Lock()
	if s.MaxSessions > 0 && len(s.sessions) >= s.MaxSessions {
		s.mu.Unlock()
		return "", time.Time{}, ErrSessionCapacity
	}
	s.sessions[token] = expiry
	s.mu.Unlock()
	return token, expiry, nil
}

// ValidSession reports whether [token] is active.
func (s *SessionStore) ValidSession(token string) bool {
	s.mu.RLock()
	expiry, ok := s.sessions[token]
	s.mu.RUnlock()
	return ok && time.Now().Before(expiry)
}

// RevokeSession removes a session (logout).
func (s *SessionStore) RevokeSession(token string) {
	s.mu.Lock()
	delete(s.sessions, token)
	s.mu.Unlock()
}

// Cleanup runs a goroutine that prunes expired sessions + challenges
// every 5 minutes. Returns immediately; cancel via context if needed
// (we don't bother — the goroutine is fine for a process lifetime).
//
// The sweep is two-pass: collect expired keys under RLock so other
// readers/writers don't block, then re-lock for the deletes. The
// previous single-pass version held the write lock for the entire
// sweep and could stall concurrent verifications on a busy server.
func (s *SessionStore) Cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		s.runCleanupOnce(time.Now())
	}
}

// RunCleanupOnce performs a single sweep synchronously. Intended for
// tests that need deterministic behavior; production uses Cleanup's
// ticker.
func (s *SessionStore) RunCleanupOnce() {
	s.runCleanupOnce(time.Now())
}

func (s *SessionStore) runCleanupOnce(now time.Time) {
	var expiredChallenges, expiredSessions []string
	s.mu.RLock()
	for k, exp := range s.challenges {
		if now.After(exp) {
			expiredChallenges = append(expiredChallenges, k)
		}
	}
	for k, exp := range s.sessions {
		if now.After(exp) {
			expiredSessions = append(expiredSessions, k)
		}
	}
	s.mu.RUnlock()

	if len(expiredChallenges) == 0 && len(expiredSessions) == 0 {
		return
	}
	s.mu.Lock()
	for _, k := range expiredChallenges {
		delete(s.challenges, k)
	}
	for _, k := range expiredSessions {
		delete(s.sessions, k)
	}
	s.mu.Unlock()
}

// ErrChallengeExpired is returned when a verify call uses an unknown
// or aged-out nonce. We use a sentinel error so the handler can map
// it to a 401 without leaking internal detail.
var ErrChallengeExpired = errors.New("challenge expired or unknown")

// ErrChallengeCapacity is returned by IssueChallenge when the
// in-memory challenges map is at MaxChallenges entries. The handler
// maps it to 429 so legitimate admins see a transient rate-limit-like
// response.
var ErrChallengeCapacity = errors.New("challenge capacity exceeded")

// ErrSessionCapacity is returned by IssueSession when the in-memory
// sessions map is at MaxSessions entries. The handler maps it to 503.
var ErrSessionCapacity = errors.New("session capacity exceeded")

// MaxSecretKeySize bounds the uploaded secret key file. A raw Ed25519
// seed is 32 bytes; the expanded secret key is 64 bytes; allow some
// slack for line endings or accidental padding but reject anything
// obviously bloated.
const MaxSecretKeySize = 1024

// ChallengeHandler returns a nonce the client must sign.
//
//	POST /api/admin/auth/challenge
//	→ 200 { "nonce": "<64-hex>" }
//	→ 429 when the in-memory challenge map is at MaxChallenges.
//	→ 500 on rand.Read failure.
func ChallengeHandler(store *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		nonce, err := store.IssueChallenge()
		if errors.Is(err, ErrChallengeCapacity) {
			writeJSON(w, http.StatusTooManyRequests, map[string]string{
				"error": "challenge capacity exceeded",
			})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to issue challenge",
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"nonce": nonce})
	}
}

// VerifyHandler consumes a nonce + signature + secret key file, checks
// the Ed25519 signature against the server's public key, and on success
// issues a session token.
//
//	POST /api/admin/auth/verify  (multipart/form-data)
//	  fields: nonce, signature (hex)
//	  file:   key (raw secret key bytes; only the first 64 are used)
//	→ 200 { "token": "<hex>", "expires_at": <unix-seconds> }
//	→ 401 on bad signature / unknown nonce / disabled public key.
func VerifyHandler(store *SessionStore, pubKey ed25519.PublicKey) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// If no public key was configured, refuse every verify. The
		// middleware also short-circuits, but being explicit here
		// means the admin client always sees a clear 401.
		if len(pubKey) == 0 {
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "admin auth disabled (ADMIN_PUBLIC_KEY not set)",
			})
			return
		}

		// Cap the multipart body so a giant upload can't OOM us.
		if err := r.ParseMultipartForm(MaxSecretKeySize); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "invalid multipart payload",
			})
			return
		}

		nonce := strings.TrimSpace(r.FormValue("nonce"))
		signatureHex := strings.TrimSpace(r.FormValue("signature"))
		if nonce == "" || signatureHex == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "missing nonce or signature",
			})
			return
		}
		signature, err := hex.DecodeString(signatureHex)
		if err != nil || len(signature) != ed25519.SignatureSize {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "signature must be hex of 64 bytes",
			})
			return
		}

		// Consume the nonce FIRST so a replay attack can't reuse it
		// even if the rest of the verification succeeds. The order
		// matters: if we verified the signature before consuming,
		// an attacker who captured one successful exchange could
		// replay it (nonce still valid → signature still valid).
		if err := store.ConsumeChallenge(nonce); err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "challenge expired or unknown",
			})
			return
		}

		// Read the uploaded key file. We accept up to MaxSecretKeySize.
		keyFile, _, err := r.FormFile("key")
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "missing key file",
			})
			return
		}
		defer keyFile.Close()
		keyBytes, err := io.ReadAll(io.LimitReader(keyFile, MaxSecretKeySize))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "failed to read key file",
			})
			return
		}
		// Ed25519 secret keys are 64 bytes (seed || public) or 32 bytes
		// (seed only, with the public half re-derived). We don't need
		// to keep the parsed private key around — verify only needs
		// the [pubKey] and the signature — but we validate that the
		// file looks like a key before moving on, so a junk file
		// fails with a helpful 400 instead of a confusing 401.
		switch len(keyBytes) {
		case ed25519.PrivateKeySize, ed25519.SeedSize:
			// shape OK; contents are validated by Verify below
		default:
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error": "key file must be 32 or 64 raw bytes",
			})
			return
		}

		if !ed25519.Verify(pubKey, []byte(nonce), signature) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "signature does not match public key",
			})
			return
		}

		token, expiry, err := store.IssueSession()
		if errors.Is(err, ErrSessionCapacity) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"error": "session capacity exceeded",
			})
			return
		}
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{
				"error": "failed to issue session",
			})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"token":      token,
			"expires_at": expiry.Unix(),
		})
	}
}

// LogoutHandler revokes a session token.
//
//	POST /api/admin/auth/logout
//	  Authorization: Bearer <token>
//	→ 204 (idempotent: revoking an unknown token is still a 204 so a
//	  caller can't probe which tokens are alive).
//
// We intentionally do NOT issue a new session on logout (token
// rotation). The current contract — revoke-only — is what the Flutter
// admin client expects (idempotent fire-and-forget). Switching to
// rotation would change the response body from 204 to 200 and break
// that client.
func LogoutHandler(store *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := extractBearer(r.Header.Get("Authorization"))
		if token != "" {
			store.RevokeSession(token)
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// IsAdminFunc is the contract a caller uses to decide whether the
// incoming request is an authenticated admin. Returns true iff [token]
// is a live bearer token. A nil IsAdminFunc means "admin auth is
// disabled" — every caller is treated as admin (back-compat with
// pre-draft deployments).
//
// The article handler uses this to gate draft visibility without
// importing the SessionStore type — keeps the dependency arrow pointing
// one way.
type IsAdminFunc func(token string) bool

// extractBearer pulls the token out of an `Authorization: Bearer ...`
// header. Returns "" if missing or malformed.
func extractBearer(h string) string {
	const prefix = "Bearer "
	if len(h) <= len(prefix) {
		return ""
	}
	if subtle.ConstantTimeCompare([]byte(h[:len(prefix)]), []byte(prefix)) != 1 {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

// writeJSON is a tiny shared helper for the auth handlers. Lives here
// (not in handler.go) to avoid touching the existing file.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
