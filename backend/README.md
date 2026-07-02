# simshop backend

Go HTTP backend for the simshop e-commerce app. Public read APIs
serve the storefront; admin write APIs (`POST/PUT/DELETE`) are gated
behind an Ed25519 challenge/response auth flow with a Bearer session
token.

## Quick start (dev)

```bash
# 1. Generate an admin keypair (see "Admin auth" below).
go run ./cmd/keygen

# 2. Drop the public key into backend/.env.
cp .env.example .env  # edit as needed
# paste the printed public key as ADMIN_PUBLIC_KEY=<64-hex-chars>

# 3. Run.
go run ./

# Server listens on http://localhost:8080 by default.
curl http://localhost:8080/health
```

## Admin auth

Admin write endpoints (`PUT /api/store-info`, `POST/PUT/DELETE
/api/products`, …) are protected by an Ed25519 challenge/response
handshake plus a Bearer session token.

### Generate a keypair

```bash
go run ./cmd/keygen
```

The tool writes two files in the current directory and prints their
hex to stdout:

```
admin.key      64 bytes, mode 0600  (Ed25519 expanded secret key)
admin.key.pub  32 bytes, mode 0600  (Ed25519 public key)
```

- **Secret key** (`admin.key`): 64 raw bytes — the Ed25519 expanded
  private key. The Flutter app reads this file via `file_picker`
  and signs the server-issued nonce with the first 32 bytes (the
  seed). Back it up OFFLINE — a USB stick, a password-manager
  attachment — and **never commit it**.
- **Public key** (`admin.key.pub`): 32 bytes. Copy its hex into
  `ADMIN_PUBLIC_KEY` in `backend/.env` (no `0x` prefix, 64 chars).
  The tool prints the hex for you in the "Next steps" block.

Flags:

```bash
go run ./cmd/keygen -out /path/to/admin.key     # custom secret path
go run ./cmd/keygen -pub /path/to/admin.key.pub # custom public path
go run ./cmd/keygen -stdout                     # hex-only, write nothing
```

### Handshake flow

```
1. Flutter                    Backend
   POST /api/admin/auth/challenge
                          ──► { "nonce": "<32 random hex>" }
   <── stores nonce for 60s

2. Flutter: signEd25519(secretKey, nonce) → 64-byte sig
   POST /api/admin/auth/verify (multipart)
        fields: nonce, signature (hex)
        file:   key (binary 64-byte secret key)
                          ──► verifies ed25519.Verify(pubKey, nonce, sig)
                          ──► returns { "token": "<32 random hex>" }
                                   session stored for 24h

3. Subsequent admin writes:
   PUT /api/store-info
        Authorization: Bearer <token>
                          ──► middleware checks session store
```

Token TTL: **24 hours**. Sessions are **in-memory** — server restart
forces re-auth. Nonces TTL: 60 seconds, single use (consumed on
verify).

### Disabling auth (dev only)

If `ADMIN_PUBLIC_KEY` is empty or unset, the startup logs:

```
WARNING: ADMIN_PUBLIC_KEY not set — admin write endpoints are PUBLIC.
Anyone with network access can mutate the store. Set ADMIN_PUBLIC_KEY
in .env to gate admin endpoints behind Ed25519 challenge/response.
```

…and `RequireAdminSession` is a no-op, so the backend behaves like
the pre-auth version. This is dev-only convenience; production must
have `ADMIN_PUBLIC_KEY` set.

## Security notes

- **HTTPS required in production.** The Bearer token can be sniffed
  over plain HTTP. Behind nginx/Caddy with TLS termination is the
  expected setup.
- **Secret key never leaves the admin's device.** The Flutter app
  reads it via `file_picker`, signs the nonce in memory, and never
  persists it.
- **Rate limit (10 req/s per IP)** still applies *outside* the auth
  middleware — brute-forcing an Ed25519 signature is infeasible but
  the rate limit guards against accidental key-spamming probes.
- **Session invalidation**: drop the in-memory map (server restart,
  or a future `POST /api/admin/auth/revoke-all`) to force re-auth.

## Config

All config is read from environment variables (with defaults):

| Var                  | Default          | Notes                                   |
| -------------------- | ---------------- | --------------------------------------- |
| `PORT`               | `8080`           |                                         |
| `DATABASE_PATH`      | `simshop.db`     | SQLite file path, auto-migrated on boot |
| `ADMIN_PUBLIC_KEY`   | *(empty)*        | 64-char hex; empty disables auth        |
| `UPLOAD_DIR`         | `uploads/`       | Where product/article images land       |
| `CORS_ORIGINS`       | `*`              | Comma-separated; `*` allows all         |
| `RATE_LIMIT_PER_SEC` | `10`             | Per-IP request rate for write endpoints |

## Layout

```
backend/
├── cmd/
│   ├── seed/         seed.go           populates dev fixtures
│   └── keygen/       keygen.go         admin keypair helper
├── internal/
│   ├── config/       config.go         env loader + defaults
│   ├── db/           *.go              SQLite repos
│   ├── handler/      *.go              HTTP handlers (+ admin_auth.go)
│   ├── middleware/   *.go              CORS, rate-limit, admin_auth.go
│   ├── router/       router.go         mounts every route + middleware
│   └── server/       server.go         wires DB + stores + router
└── simshop.db        local dev DB (gitignored)
```

## Tests

```bash
go test ./...
```

94 tests covering repos, handlers, and the admin auth flow (roundtrip,
bad signature, expired challenge, replay protection, middleware).
