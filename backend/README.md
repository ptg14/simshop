# Backend (Go)

The simshop HTTP API. Single static binary, no ORM, two persistence
modes (SQLite for dev, Postgres for prod). All write endpoints are
gated by an Ed25519 challenge/response admin auth flow.

For the user-facing architecture overview see the repo root
[README.md](../README.md).
For the production Docker stack see
[docker/README.md](../docker/README.md).

---

## Table of contents

1. [Quick start](#quick-start)
2. [Layout](#layout)
3. [Persistence](#persistence)
4. [Environment variables](#environment-variables)
5. [Admin authentication](#admin-authentication)
6. [Generating a key](#generating-a-key)
7. [Build & run](#build--run)
8. [Testing](#testing)
9. [API surface](#api-surface)
10. [Rate limiting](#rate-limiting)
11. [CORS](#cors)
12. [Static files & uploads](#static-files--uploads)
13. [Logging](#logging)
14. [Graceful shutdown](#graceful-shutdown)
15. [See also](#see-also)

---

## Quick start

```bash
# From backend/ directory
cp .env.example .env
go run ./cmd/keygen          # → in public-key hex, write admin.key
# Paste the public-key hex into ADMIN_PUBLIC_KEY in .env

go run .                     # backend listens on :8080
curl http://localhost:8080/health
# → {"status":"ok"}
```

End-to-end admin auth verification (walks challenge → sign → verify →
create product, prints verbatim curl transcript + JSON summaries):

```bash
go run ./cmd/admincurl
```

---

## Layout

```
backend/
├── main.go                          # Entry — signal handling,
│                                      delegates to server.Start
├── schema.sql                       # Canonical schema (SQLite + Postgres)
├── go.mod, go.sum
├── .env.example                     # Env template (no secrets)
│
├── admin.key                        # Private key — gitignored, do not commit
├── admin.key.pub                    # Public key bytes (binary 32)
│
├── cmd/                             # One-shot CLI tools
│   ├── keygen/                      #   - Generate Ed25519 keypair
│   ├── admincurl/                   #   - Walk challenge/verify for docs
│   └── seed/                        #   - Idempotent placeholder seeder
│
└── internal/                        # Application code (not importable
    │                                #   by other modules)
        ├── config/                  #   - Env parsing, .env loader,
        │                            #     trusted-proxy CIDR parser
        ├── db/                      #   - sql.DB setup, retry ping,
        │                            #     dialect-agnostic repos
        ├── handler/                 #   - HTTP handlers + repos +
        │                            #     auth SessionStore
        ├── middleware/              #   - CORS, rate limit, admin session
        ├── router/                  #   - gorilla/mux route registration
        ├── server/                  #   - http.Server, graceful shutdown
        └── uploadfs/                #   - Upload directory helpers
```

The repo keeps the binary tools (`keygen`, `admincurl`) out of git —
they're built on demand via `go run ./cmd/<name>`. Source under
`cmd/<name>/main.go` is always present.

---

## Persistence

| Mode | Driver | Triggered by |
| ---- | ------ | ------------ |
| Dev  | SQLite (mattn/go-sqlite3) | `DATABASE_URL` unset, empty, or starting with `./` |
| Prod | Postgres (jackc/pgx) | `DATABASE_URL` starts with `postgres://` or `postgresql://` |

The dialect is detected from the URL scheme in `internal/db/db.go`.
Schema is in `schema.sql` and is identical across both — only the
intersection of features is used (no SQLite-only functions, no
Postgres-only types). `NUMERIC` / `JSONB` columns are written the same
way; the dialect layer handles differences in placeholder syntax and
return types.

### DB ping retry at startup

The backend pings the DB on startup with retries
(`DB_RETRY_ATTEMPTS × DB_RETRY_INTERVAL_MS`, default 10 × 1s = ~10s)
to tolerate slow `docker compose up` boots where Postgres is still
initializing. Without this, the backend would crash-loop every time
Postgres needed an extra second.

### Schema (current)

The canonical schema lives in two places that must stay in sync:

- `schema.sql` — single-file DDL for SQLite + Postgres.
- `internal/db/schema.go::SchemaFor()` — runtime DDL driven by the
  `Dialect` interface, used by `db.New` at startup and by the test
  harness. This is where idempotent `ALTER TABLE ADD COLUMN` upgrades
  live (e.g. `articles.is_draft`, `product_options.image_urls`).

Tables:

- `products` — id, name, description, price, original_price, image_url,
  category, store_id, rating, reviews, stock, specs (JSON array),
  categories (JSON array of subcategory names).
- `product_images` — additional images per product, ordered, ON DELETE
  CASCADE.
- `product_options` — variants per product (name + image_urls, ordered),
  ON DELETE CASCADE. `image_urls` was added after the table was
  introduced (handled by `Dialect.AddColumnSQL`).
- `large_categories` — parent categories (e.g. "PC Components").
- `categories` — subcategories (e.g. "GPUs"), references
  `large_categories(id) ON DELETE SET NULL`.
- `events` — time-boxed promotions (`percent` or `fixed`), with a JSON
  array of product IDs. `end_time` is unix seconds, nullable for
  never-expires (admin UI always sets one).
- `articles` — title, Markdown body (`body_markdown`), cover image,
  `product_ids` JSON array, `created_at`, `is_draft`. Anonymous reads
  filter on `is_draft = 0` (404 for drafts).
- `banner_slides` — home carousel slides (image_url, title, subtitle,
  ord, optional `article_id` FK for tap-through). Note: the table is
  `banner_slides` but the public API path is `/api/banners` — the
  naming inconsistency is intentional (the API has shipped as
  `/api/banners` since v0 and renaming would break deployed
  Flutter apps).
- `store_info` — singleton (id=1): name, description, banner_url,
  phone, email, address, google_maps_url. The banner URL is the
  hidden admin entry-point — `lib/widgets/site_info_footer.dart`
  always mounts the banner slot (real image, skeleton shimmer, or
  empty placeholder alike) so the 7-tap admin gesture stays reachable
  even on a fresh DB. `docker/seed.sh` seeds a `picsum.photos`
  placeholder URL so a first-deploy user can still reach the admin
  gate.

`docker/initdb/01-schema.sql` mirrors `schema.sql` for first-boot
Postgres init.

---

## Environment variables

All variables are read at startup. No defaults that silently mask
misconfiguration.

| Variable | Purpose | Default |
| -------- | ------- | ------- |
| `PORT` | HTTP listen port. | `8080` |
| `DATABASE_URL` | DSN. Scheme picks the driver (see [Persistence](#persistence)). | `./simshop.db` |
| `DATABASE_PATH` | Legacy SQLite path (only consulted if `DATABASE_URL` is unset AND ends with `.db`). | `./simshop.db` |
| `MAX_UPLOAD_SIZE` | Max bytes per multipart upload. | `10485760` (10 MB) |
| `DB_MAX_OPEN_CONNS` | SQLite connection cap (Postgres uses its own pool). | `10` |
| `DB_CONN_MAX_LIFETIME` | Reuse window in seconds. | `3600` (1 hour) |
| `DB_RETRY_ATTEMPTS` | Boot-time ping retries. | `10` |
| `DB_RETRY_INTERVAL_MS` | Delay between retries. | `1000` |
| `UPLOAD_DIR` | Where multipart uploads land. | `./uploads` |
| `MAX_UPLOAD_SIZE` | Max upload bytes. | `10485760` (10 MB) |
| `ALLOWED_ORIGIN` | CORS allowlist. Comma-separated for multi-origin. | `*` (dev only) |
| `ADMIN_PUBLIC_KEY` | Ed25519 public key, hex 64 chars. Empty = admin auth disabled (warn in dev, fail-fast in production). | _(empty)_ |
| `BASE_URL` | Public base URL for absolute upload URLs. Falls back to `Host` header when unset. | _(empty)_ |
| `ENV` | `production` triggers fail-fast on missing `ADMIN_PUBLIC_KEY`. | _(empty)_ |
| `RATE_LIMIT_PER_SEC` | Per-IP write rate (req/s). | `10` |
| `TRUSTED_PROXIES` | Comma-separated CIDR list whose `X-Forwarded-For` is honored. Empty = no proxy trust. | _(empty)_ |
| `GODEBUG` | (Docker sets this to `""` to silence std-lib debug logs.) | inherited |

See `backend/.env.example` for the canonical template (with a
required-env checklist for production).

> **Do not commit `backend/.env` or `backend/admin.key`.** Both are
> gitignored. The shipped `keygen` and `admincurl` binaries are also
> gitignored — only their source (`backend/cmd/...`) is tracked.

### `.env` resolution

`config.Load()` calls `loadDotEnv()` which walks up from the current
working directory (max 5 levels) looking for a `.env`. Format:

```
KEY=value                  # plain
KEY="quoted value"         # double-quoted (stripped)
KEY='quoted value'         # single-quoted (stripped)
# comments                 # skipped
```

The loader **never overwrites** an operator-set env var (`os.LookupEnv`
gates the `os.Setenv`). Process env always wins over the file. The
backend deliberately doesn't pull in `github.com/joho/godotenv` to keep
the dependency surface minimal — the format is dead-simple.

---

## Admin authentication

Public reads are open. All writes (`POST/PUT/PATCH/DELETE` on
`/api/products/*`, `/api/categories/*`, `/api/large-categories/*`,
`/api/store-info`, `/api/banners/*`, `/api/events/*`, `/api/articles/*`,
`/api/upload`) require a valid admin session token in the
`Authorization: Bearer <token>` header.

The token is obtained through an Ed25519 challenge / response:

```
POST /api/admin/auth/challenge   →  { nonce }
POST /api/admin/auth/verify
  body: { nonce, signature }      →  { token, expires_at }
POST /api/admin/auth/logout      →  { ok }
```

Where `signature = Ed25519.Sign(admin.key, nonce)` (raw 64 bytes, hex
encoded). The verifier uses the server-side `ADMIN_PUBLIC_KEY`.

### Lifecycle

| Item | TTL | Storage |
| ---- | --- | ------- |
| Nonce | 60s | In-memory map, single-use |
| Bearer token | 24h | In-memory `SessionStore`, opaque random |
| `admin.key` | forever | The admin's device (Flutter picks it via `file_picker`) |

### Server behavior when key is empty

- **Development** (`ENV` unset): log a warning, start anyway, every
  write is public. Matches the pre-auth behavior so newcomers aren't
  locked out.
- **Production** (`ENV=production`): `log.Fatalf` — the process refuses
  to start. Running with public write endpoints is much worse than
  refusing the deploy.

### Why Ed25519

- 32-byte public keys, 64-byte signatures, constant-time verify.
- No need for ASN.1 parsing / PEM framing — raw bytes, hex in env.
- No padding oracle, no algorithm agility foot-guns — one signature
  scheme, one verifier.

For the full protocol and threat model see the root
[README.md → Admin authentication](../README.md#admin-authentication).

---

## Generating a key

```bash
go run ./cmd/keygen
# → secret key → admin.key     (binary 64 bytes, mode 0600)
# → public  key → admin.key.pub (binary 32 bytes, mode 0600)
# → both also printed in hex (round-trip verification)
```

Optional flags:

```bash
go run ./cmd/keygen -stdout          # print hex only, write nothing
go run ./cmd/keygen -out key1 -pub key1.pub   # custom paths
```

Verify the full chain (challenge → sign → verify → create product):

```bash
go run ./cmd/admincurl
# → walks full admin auth flow against running backend
# → prints each request as a verbatim curl transcript + JSON summary
```

> **Back up `admin.key` somewhere offline** (USB, password manager
> attachment). Anyone with the file can authenticate as admin on a
> server whose `ADMIN_PUBLIC_KEY` matches. The backend never sees the
> secret key — only the public hex.

---

## Build & run

### Local dev

```bash
go run .                           # foreground, logs to stdout
go build -o simshop-api .          # local binary
./simshop-api                      # run it
```

### Production-style binary

```bash
# Static, stripped, no debug info, reproducible paths
CGO_ENABLED=0 go build \
    -trimpath \
    -buildvcs=false \
    -ldflags="-s -w" \
    -o server .
./server
```

In the Docker stack the binary is built with `docker/Dockerfile.backend`,
a multi-stage `golang:1.25-alpine → alpine:3.20` that:

- Pins Go toolchain
- Caches `go mod download` separately from source
- Strips with `-trimpath -buildvcs=false -ldflags="-s -w"`
- Adds `ca-certificates` for outbound HTTPS
- Runs as UID/GID 10001 (avoids alpine's `nobody` = 65534)
- Sets `HEALTHCHECK` to `wget http://localhost:8080/health`

### Local Docker

```bash
docker build -f ../docker/Dockerfile.backend -t simshop-backend:dev ..
docker run --rm -p 8080:8080 \
    -e ADMIN_PUBLIC_KEY=$(cat admin.key.pub | xxd -p -c 256) \
    -e ALLOWED_ORIGIN='http://localhost:8080,http://localhost:8081' \
    -v $(pwd)/uploads:/data/uploads \
    simshop-backend:dev
```

---

## Testing

```bash
go test ./...                  # all tests
go test -race ./...            # data-race detector (slower)
go test -cover ./...           # coverage
go test -run TestFoo ./...     # single test by name
```

Tests live next to the code they exercise (`handler/*_test.go`,
`db/*_test.go`, `middleware/*_test.go`). They spin up real
`http.ServeMux` + `httptest.ResponseRecorder` — no external mocks
needed. SQLite test databases are written to `backend/test.db` and
auto-pruned via `t.TempDir()` patterns where appropriate.

### What's covered

- `handler/handler_test.go` — happy path + auth for products.
- `handler/article_handler_test.go` — list / get with draft filtering.
- `handler/event_handler_test.go` — event CRUD + `current_event` join.
- `handler/upload_handler_test.go` — multipart + size limit + ext whitelist.
- `middleware/cors_test.go` — single + comma-separated origin echo,
  preflight, credentials-mode rules.
- `middleware/middleware_test.go` — rate limit (per-IP via RemoteAddr).
- `db/dialect_test.go` — SQLite vs Postgres SQL differences.
- `db/db_test.go` — retry ping behaviour.
- `handler/slugify_test.go` — URL slug helper.
- `uploadfs_test.go` — directory creation, file overwrite, cleanup.

---

## API surface

> Full request/response shapes are documented in
> `docs/api-reference.md` (if present) or by reading the handler
> sources. The table below lists every endpoint + auth requirement.

### Health

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/health` | public |

### Admin auth

| Method | Path | Auth |
| ------ | ---- | ---- |
| POST | `/api/admin/auth/challenge` | public (strict rate limit) |
| POST | `/api/admin/auth/verify` | public |
| POST | `/api/admin/auth/logout` | admin |

### Products

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/products` | public |
| GET | `/api/products/{id}` | public |
| POST | `/api/products` | admin |
| PUT | `/api/products/{id}` | admin |
| PATCH | `/api/products/{id}/stock` | admin |
| DELETE | `/api/products/{id}` | admin |

### Categories

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/categories/with-parent` | public |
| GET | `/api/large-categories` | public |
| POST | `/api/categories` | admin |
| DELETE | `/api/categories/{name}` | admin |
| POST | `/api/large-categories` | admin |
| DELETE | `/api/large-categories/{name}` | admin |

### Store info (singleton)

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/store-info` | public |
| PUT | `/api/store-info` | admin |

### Banner slides (carousel)

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/banners` | public |
| POST | `/api/banners` | admin |
| PUT | `/api/banners/{id}` | admin |
| DELETE | `/api/banners/{id}` | admin |

### Events (time-boxed promotions)

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/events` | public |
| GET | `/api/events/{id}` | public |
| POST | `/api/events` | admin |
| PUT | `/api/events/{id}` | admin |
| DELETE | `/api/events/{id}` | admin |

Product reads (`/api/products*`) decorate each row with `current_event`
+ effective `price` based on the most recent active event that lists
the product's id. Public event endpoints are for the admin dashboard.

### Articles

| Method | Path | Auth |
| ------ | ---- | ---- |
| GET | `/api/articles` | public (admins see drafts) |
| GET | `/api/articles/{id}` | public |
| POST | `/api/articles` | admin |
| PUT | `/api/articles/{id}` | admin |
| DELETE | `/api/articles/{id}` | admin |

The `/{id}` GET joins `product_ids` and returns the article + the
related products in one round-trip (used by the home carousel tap →
article screen flow).

### Upload

| Method | Path | Auth |
| ------ | ---- | ---- |
| POST | `/api/upload` | admin |
| GET | `/uploads/{filename}` | public static |

---

## Rate limiting

Token-bucket per IP via `golang.org/x/time/rate`.

| Endpoint | Limit | Notes |
| -------- | ----- | ----- |
| `/api/admin/auth/challenge` | 2 req/s, burst 5 | Strict — never trusts `XFF`. The endpoint costs server CPU (`rand.Read` + map insertion), so abusive clients must be cut off faster. |
| All other write endpoints | 10 req/s, burst 20 | Trusts `XFF` only from `TRUSTED_PROXIES`. |
| Public reads | none | |

When `TRUSTED_PROXIES` is empty (the default), the rate limiter keys on
`r.RemoteAddr`. Operators behind a reverse proxy must populate this
list or every client will look like the proxy IP and share one bucket.

### Why two rate limiters

- `RateLimit` trusts `X-Forwarded-For` only from the trusted CIDRs —
  outside of those it uses `r.RemoteAddr`.
- `RateLimitStrict` (used by `/challenge`) **never** trusts `XFF`,
  regardless of the trusted-proxy list. That keeps an unauthenticated
  endpoint from being abused through a spoofed header.

---

## CORS

`middleware/cors.go` reads `ALLOWED_ORIGIN` at startup. The string is
parsed as a comma-separated allowlist when it contains a comma,
otherwise it's treated as a single origin. Examples:

```
ALLOWED_ORIGIN=https://shop.example.com
ALLOWED_ORIGIN=https://shop.example.com,https://staging.shop.example.com
ALLOWED_ORIGIN=http://localhost:8080,http://localhost:8081,http://localhost:9090
```

### Why an allowlist

- Credentialed cross-origin requests (admin endpoints carry
  `Authorization: Bearer ...`) cannot use `*` as the `Allow-Origin`
  response value per the CORS spec.
- The allowlist form echoes the matching entry back verbatim, which
  IS valid for credentialed requests.
- Local dev tip: `flutter run -d chrome` picks a random ephemeral
  port each run. Pin a few obvious ports here to avoid CORS rejections
  every time the dev port rolls.

### Preflight

The CORS middleware is registered at the `http.Server` level, not via
`mux.Router.Use`. gorilla/mux's `Use` only fires middleware for
requests that match a route — OPTIONS preflight for paths the client
doesn't know about (e.g. `/api/upload`, `/api/store-info`) hit a 404
*before* the CORS middleware runs. Wrapping at the Server level
guarantees every request (including OPTIONS for unknown paths) passes
through the middleware first.

---

## Static files & uploads

`POST /api/upload` accepts a multipart file with field name `file`
and a path query `?path=<relative-path>` (e.g. `?path=products/x.jpg`).
The backend:

1. Validates extension (jpg / jpeg / png / webp / gif).
2. Checks size against `MAX_UPLOAD_SIZE`.
3. Writes to `<UPLOAD_DIR>/<path>`.
4. Returns an absolute URL — using `BASE_URL` if set, otherwise
   the request `Host` header (with a console warning that this is
   spoofable).

`GET /uploads/{filename}` is served from `UPLOAD_DIR` directly.

### Upload URL resolution

| `BASE_URL` set? | Result |
| --------------- | ------ |
| Yes | `BASE_URL + "/uploads/" + filename` |
| No, `TRUSTED_PROXIES` set | `<X-Forwarded-Proto><X-Forwarded-Host>/uploads/<file>` |
| Neither | Falls back to `r.Host` (spoofable — logged at WARN) |

In dev this is fine (`http://localhost:8080`). In production **always
set `BASE_URL`** (or `BE_PUBLIC_URL`, which `docker compose` passes
through).

### In Docker

`UPLOAD_DIR=/data/uploads` lives on the `simshop_backend_uploads`
named volume so uploads survive image rebuilds. The web container
serves the same files via its own mount (read-only) — see
[docker/README.md](../docker/README.md).

### Cleanup on entity delete

`productRepo`, `storeRepo`, and `articleRepo` receive an `UploadConfig`
so they can best-effort delete physical image files after a DB write
commits. Failures here are logged but don't roll back the DB
transaction — the file is orphaned but the row is correct.

---

## Logging

Plain `log.Printf` style to stdout in `YYYY-MM-DD HH:MM:SS` format
(the default `log` package format). The Docker stack pipes logs through
the Cloudflare tunnel container (no log shipping, no aggregation).

### What's logged

- Startup: `admin auth enabled (public key loaded)` /
  `WARNING: ADMIN_PUBLIC_KEY is empty — admin auth disabled`.
- DB retry: `db not ready (attempt N/M): ...`.
- HTTP errors at the handler level (5xx only).
- Upload cleanup failures.

### What's NOT logged

- Bearer tokens, nonces, signatures (would enable replay / forgery).
- Request bodies in production (could leak PII from product descriptions).

---

## Graceful shutdown

`main.go` installs a SIGINT/SIGTERM handler that cancels a root
`context.Context`. `server.Start` listens on this context:

1. On `ctx.Done()`: `srv.Shutdown(ctx)` with a 5s timeout.
2. After shutdown: `database.Close()` (closes the underlying `*sql.DB`).

The `SessionStore` cleanup goroutine (which evicts expired nonces and
tokens) just dies with `main()` — no shutdown hook needed.

### Why 5s

Long enough for in-flight HTTP handlers to finish writing responses,
short enough that `docker stop` (which sends SIGTERM and waits 10s by
default) doesn't escalate to SIGKILL.

---

## See also

- [README.md](../README.md) — repo-level overview.
- [docker/README.md](../docker/README.md) — production stack.
- `schema.sql` — canonical schema (SQLite + Postgres).
- `cmd/keygen/main.go` — keypair generator with security notes.
- `cmd/admincurl/main.go` — end-to-end admin auth verifier.
- `internal/middleware/cors.go` — CORS allowlist implementation.
- `internal/middleware/ratelimit.go` — per-IP token-bucket.
- `internal/handler/admin_auth.go` — challenge / verify / logout.
