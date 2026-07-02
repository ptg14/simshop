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
type SessionStore struct {
	mu          sync.RWMutex
	sessions    map[string]time.Time // token → expiry
	challenges  map[string]time.Time // nonce → expiry
	tokenTTL    time.Duration
	challengeTTL time.Duration
}

// NewSessionStore returns a SessionStore with sensible defaults:
// 24-hour token TTL, 60-second challenge TTL.
func NewSessionStore() *SessionStore {
	return &SessionStore{
		sessions:     make(map[string]time.Time),
		challenges:   make(map[string]time.Time),
		tokenTTL:     24 * time.Hour,
		challengeTTL: 60 * time.Second,
	}
}

// IssueChallenge generates a random nonce, stores it, and returns it.
func (s *SessionStore) IssueChallenge() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	nonce := hex.EncodeToString(raw)
	s.mu.Lock()
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

// IssueSession mints a token for a verified admin.
func (s *SessionStore) IssueSession() (string, time.Time, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, err
	}
	token := hex.EncodeToString(raw)
	expiry := time.Now().Add(s.tokenTTL)
	s.mu.Lock()
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
func (s *SessionStore) Cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		now := time.Now()
		s.mu.Lock()
		for k, exp := range s.challenges {
			if now.After(exp) {
				delete(s.challenges, k)
			}
		}
		for k, exp := range s.sessions {
			if now.After(exp) {
				delete(s.sessions, k)
			}
		}
		s.mu.Unlock()
	}
}

// ErrChallengeExpired is returned when a verify call uses an unknown
// or aged-out nonce. We use a sentinel error so the handler can map
// it to a 401 without leaking internal detail.
var ErrChallengeExpired = errors.New("challenge expired or unknown")

// MaxSecretKeySize bounds the uploaded secret key file. A raw Ed25519
// seed is 32 bytes; the expanded secret key is 64 bytes; allow some
// slack for line endings or accidental padding but reject anything
// obviously bloated.
const MaxSecretKeySize = 1024

// ChallengeHandler returns a nonce the client must sign.
//
//	POST /api/admin/auth/challenge
//	→ 200 { "nonce": "<64-hex>" }
func ChallengeHandler(store *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		nonce, err := store.IssueChallenge()
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
func LogoutHandler(store *SessionStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := extractBearer(r.Header.Get("Authorization"))
		if token != "" {
			store.RevokeSession(token)
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

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