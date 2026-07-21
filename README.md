# simshop — Flutter E-Commerce Storefront

A small but production-shaped e-commerce stack:

- **Frontend** — Flutter (web + iOS + Android) using MVVM + Provider. Ships
  as a customer-facing storefront and a hidden admin panel gated by an
  Ed25519 challenge-response flow.
- **Backend** — Go HTTP API. Single static binary, no ORM, two
  persistence modes (SQLite for dev, Postgres for prod).
- **Production stack** — Postgres + Go backend + Flutter web (release) +
  Nginx + Cloudflare Tunnel, all wired together by `docker compose`.

The whole thing is designed to be readable in one sitting: one repo,
~25 backend Go files, ~40 Flutter files, four Docker services.

```
simshop/
├── lib/           # Flutter app (MVVM)
├── backend/       # Go HTTP API + cmd tools (keygen / admincurl / seed)
├── docker/        # Production stack (compose, Dockerfiles, nginx, tunnel)
├── assets/        # Bundled images, icons, fonts (Roboto family)
├── tool/          # Local dev helpers (build_web.sh)
└── android/ ios/ linux/ macos/ windows/ web/   # platform shells
```

---

## Table of contents

1. [Features](#features)
2. [Architecture](#architecture)
3. [Repository layout](#repository-layout)
4. [Quick start (local dev)](#quick-start-local-dev)
5. [Flutter app structure (`lib/`)](#flutter-app-structure-lib)
6. [Backend structure (`backend/`)](#backend-structure-backend)
7. [Production stack (`docker/`)](#production-stack-docker)
8. [Admin authentication](#admin-authentication)
9. [Environment configuration](#environment-configuration)
10. [Build & run](#build--run)
11. [Testing](#testing)
12. [Data seeding](#data-seeding)
13. [Troubleshooting](#troubleshooting)
14. [Cross-platform notes](#cross-platform-notes)
15. [License](#license)

---

## Features

### 🛍️ Storefront (customer-facing)

- **Home feed** — hero banner carousel, large-category chip row, product
  grid, in-progress article strip, store-info footer.
- **Product catalog** — browse PC gaming components / accessories with
  ratings, original-vs-discount price badges, stock indicators, and
  category hierarchy.
- **Search & filter** — name search, category filter, smooth scrolling
  selector.
- **Product detail** — image carousel, specs table, Markdown description,
  options/variants, "current event" discount badge, related-article
  strip.
- **Article screen** — Markdown rendering with embedded product chips;
  supports draft / published visibility.
- **Shopping cart** — add / remove / adjust quantity, subtotal + tax +
  shipping calculation, persisted via Provider (in-memory).
- **Responsive design** — phone-first, tablet-aware, web with browser
  title management and SPA routing.

### 🎨 UI / theme

- Material Design 3, custom `AppTheme` (light-only).
- Reusable widgets: `ProductCard`, `PromoBanner`, `CategorySelector`,
  `HomeSkeleton`, `ShimmerPlaceholder`, `NetworkImage` (with bearer
  forwarding), `ImageCarousel`, `MarkdownSplitEditor`, etc.
- Vietnamese-friendly currency formatting (`intl`).
- Skeleton + shimmer placeholders for every network-bound view.

### 🔐 Admin (hidden panel)

- **Hidden trigger** — 7 taps within 3 seconds on the footer banner
  opens the admin auth gate. (Same pattern as Android's "tap Build
  Number 7 times to unlock Developer Options" — three copies of the
  trigger live on the home page so the entry-point is reachable from
  every state: real banner, skeleton banner placeholder, and empty-state
  banner placeholder.)
- **Key upload** — admin picks `admin.key` (binary Ed25519 secret key
  generated via `backend/cmd/keygen`). No password, no email, no
  server-side user table — possession of the key file IS the credential.
- **Ed25519 challenge / response** — Flutter signs the server nonce;
  server verifies with `ADMIN_PUBLIC_KEY`; on success a 24h bearer
  token is returned.
- **Admin CRUD** — products, categories (sub + large), banners,
  articles, events (time-boxed discounts), store info, image upload.
- **401 recovery** — every admin write ViewModel pops the admin shell
  back to the gate on `AdminSessionExpiredException`, so a dead token
  after server restart / TTL never strands the operator.

### 🏗️ Architecture (high-level)

- **MVVM pattern** — Views never call services directly; ViewModels
  own state and call services.
- **Provider state management** — `MultiProvider` at the root wires
  ViewModels as `lazy: true` singletons; the dependency chain
  (`AdminViewModel → IProductService → IAdminAuthService`) carries
  the bearer token automatically once admin opens.
- **Service layer** — `IProductService`, `IArticleService`,
  `IEventService`, `IStoreService`, `IAdminAuthService`. Backend
  swap-out would mean re-implementing the interfaces.
- **Immutable models** — every model has `==` / `hashCode` / `copyWith`
  / `fromJson` / `toJson`; no `mutable` fields.
- **Feature folders** — `lib/views/admin/` mirrors the backend
  resource layout (`admin_products`, `admin_articles`,
  `admin_categories`, `admin_events`, `admin_settings`).

---

## Repository layout

```
simshop/
├── README.md                  # This file
├── pubspec.yaml               # Flutter package config (deps, assets, fonts)
├── analysis_options.yaml      # flutter_lints + custom rules
├── lib/                       # Flutter app (see Flutter section)
├── backend/                   # Go HTTP API (see Backend section)
├── docker/                    # Production stack (see Docker section)
├── assets/                    # Bundled images, icons, fonts
│   ├── images/
│   └── icons/
├── android/  ios/  linux/  macos/  windows/   # platform shells
├── web/                       # Flutter web template (index.html etc.)
├── tool/                      # Dev helpers
│   └── build_web.sh           # Quick Flutter web release build
└── data/                      # Local backups (gitignored)
```

---

## Quick start (local dev)

This is the **fastest** path: SQLite + Flutter web, all on `localhost`.

### Prerequisites

- Flutter ≥ 3.16 (Dart ≥ 3.0). Verify: `flutter --version`.
- Go ≥ 1.25. Verify: `go version`.
- (Optional) Docker Desktop — only needed for the production stack.

### One-time setup

```bash
# 1. Clone & enter
git clone <repo> simshop && cd simshop

# 2. Backend: install deps + scaffold .env + create admin keypair
cd backend
go mod download
cp .env.example .env
go run ./cmd/keygen
# → in public-key hex → paste vào ADMIN_PUBLIC_KEY trong backend/.env
# → file admin.key  (private, gitignored) và admin.key.pub (public)

# 3. Frontend: fetch deps
cd ..
flutter pub get
cp .env.example .env   # nếu có (xem lib/config/api_config.dart)
```

### Run both processes

```bash
# Terminal 1 — backend
cd backend
go run .
# → listen :8080, log "admin auth enabled (public key loaded)"

# Terminal 2 — Flutter web
cd ..
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
# → mở Chrome, http gốc là FE, gọi BE qua localhost:8080
```

### Verify end-to-end

```bash
# Backend health
curl http://localhost:8080/health
# → {"status":"ok"}

# Admin auth verification (optional but recommended)
cd backend
go run ./cmd/admincurl
# → walks challenge / verify / product create against running BE
```

The admin panel is hidden inside the running app — tap the footer
banner **seven times within three seconds** to surface the auth gate,
then upload `admin.key`. (Implementation: `AdminBannerTrigger` in
`lib/widgets/admin_banner_trigger.dart`.)

---

## Flutter app structure (`lib/`)

```
lib/
├── main.dart                          # App entry, zone-safe bootstrap,
│                                      # MultiProvider wiring
│
├── config/                            # Cross-cutting configuration
│   └── api_config.dart                #   - API_BASE_URL resolver
│                                      #     (compile-time → dotenv → default)
│
├── theme/                             # Visual constants
│   └── app_theme.dart                 #   - ColorScheme, Typography, Spacing
│
├── utils/                             # Stateless helpers
│   ├── browser_title_manager.dart     #   - Web document.title sync
│   ├── currency_formatter.dart        #   - Vietnamese ₫ formatting
│   ├── page_transitions.dart          #   - Custom route transitions
│   ├── responsive.dart                #   - Breakpoints, sizing helpers
│   ├── document_title*.dart           #   - Web-only title stubs
│   └── animated_press.dart            #   - Reusable press feedback
│
├── models/                            # Immutable DTOs
│   ├── product.dart                   #   - Product + ProductSpec
│   ├── article.dart                   #   - Article + visibility helpers
│   ├── banner.dart                    #   - Banner
│   ├── category.dart                  #   - Category + LargeCategory + parent
│   ├── event.dart                     #   - Event + DiscountType enum
│   ├── store_info.dart                #   - StoreInfo singleton
│   └── product_list_response.dart     #   - Paginated wrapper
│
├── services/                          # HTTP + business boundaries
│   ├── i_product_service.dart         #   - Product service interface
│   ├── product_service.dart           #   - Product service impl
│   ├── article_service.dart           #   - Article service (draft-aware)
│   ├── event_service.dart             #   - Event service
│   ├── store_service.dart             #   - Store info service
│   ├── admin_auth_service.dart        #   - Ed25519 sign + session keepalive
│   └── _http_with_admin_token.dart    #   - http.Client shim that
│                                      #     forwards Bearer to every call
│
├── viewmodels/                        # MVVM state holders
│   ├── home_viewmodel.dart            #   - Home feed composition
│   ├── admin_viewmodel.dart           #   - Product CRUD
│   ├── articles_viewmodel.dart        #   - Article CRUD
│   ├── events_viewmodel.dart          #   - Event CRUD
│   ├── site_config_viewmodel.dart     #   - Store info edit
│   └── admin_auth_viewmodel.dart      #   - Auth gate state
│
├── views/                             # Screens
│   ├── home_screen.dart               #   - Customer home
│   ├── product_detail_screen.dart     #   - Product detail
│   ├── article_screen.dart            #   - Article reader
│   └── admin/                         #   - Hidden admin panel
│       ├── admin_banner_trigger.dart  #     - Long-press detector
│       ├── admin_product/             #     - Admin product CRUD
│       ├── admin_articles/            #     - Admin article CRUD
│       ├── admin_categories/          #     - Admin categories CRUD
│       ├── admin_events/              #     - Admin events CRUD
│       └── admin_settings/            #     - Admin store-info edit
│
└── widgets/                           # Reusable UI components
    ├── product_card.dart              #   - Storefront tile
    ├── product_card_pills.dart        #   - Discount + stock pills
    ├── category_selector.dart         #   - Horizontal chip row
    ├── promo_banner.dart              #   - Single banner
    ├── image_carousel.dart            #   - Swipeable + dots + zoom
    ├── home_skeleton.dart             #   - Loading state for home
    ├── shimmer_placeholder.dart       #   - Generic shimmer box
    ├── network_image.dart             #   - Image w/ Bearer forward
    ├── site_info_footer.dart          #   - Footer w/ hidden 7-tap admin entry
    ├── markdown_split_editor.dart     #   - Markdown editor for admin
    ├── animated_press.dart            #   - Press feedback wrapper
    └── carousel/                      #   - Promo banner carousel
```

### `lib/config/api_config.dart` — base URL resolution

`API_BASE_URL` is resolved in this priority order:

1. **Compile-time** via `--dart-define=API_BASE_URL=...` — what
   `docker/Dockerfile.web` passes from `docker/.env`.
2. **Runtime `.env` asset** via `flutter_dotenv` — present only in
   dev builds (the file is removed from `pubspec.yaml` `assets:`
   for release).
3. **Empty string** — services fail-fast on first network call so a
   misconfigured release can never silently hit a `localhost`.

`main.dart` skips `dotenv.load()` entirely in release mode to avoid
the 404 `rootBundle.loadString('.env')` request the engine logs.

### State management — `provider`

The root `MultiProvider` wires ViewModels as `lazy: true` singletons:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AdminAuthViewModel()),
    ChangeNotifierProxyProvider<AdminAuthViewModel, AdminViewModel>(
      create: (_) => AdminViewModel(),
      update: (_, auth, prev) => prev ?? AdminViewModel(dep: auth),
    ),
    // ...articles, events, site config
  ],
  child: const GuardedApp(),
);
```

`AdminViewModel` depends on `AdminAuthViewModel`; once the user
authenticates, every subsequent admin write picks up the bearer token
via the `IAdminAuthService` chain.

---

## Backend structure (`backend/`)

```
backend/
├── main.go                            # Entrypoint — signal handling,
│                                      # delegates to server.Start
├── schema.sql                         # Canonical schema (SQLite + Postgres)
├── go.mod, go.sum
├── .env.example                       # Env template (no secrets)
├── admin.key                          # Private key — gitignored
├── admin.key.pub                      # Public key bytes
│
├── cmd/                               # One-shot CLI tools
│   ├── keygen/                        #   - Generate Ed25519 keypair
│   ├── admincurl/                     #   - Walk challenge/verify for docs
│   └── seed/                          #   - Idempotent placeholder seeder
│
└── internal/                          # Application code (not importable)
    ├── config/                        #   - env parsing, .env loader
    ├── db/                            #   - sql.DB setup, retry ping,
    │                                  #     dialect-agnostic repos
    ├── handler/                       #   - HTTP handlers + repos + auth
    ├── middleware/                    #   - CORS, rate limit, admin session
    ├── router/                        #   - gorilla/mux route registration
    ├── server/                        #   - http.Server, graceful shutdown
    └── uploadfs/                      #   - Upload directory helpers
```

The backend has **two persistence modes** selected at startup:

| Mode | Driver | Trigger |
| ---- | ------ | ------- |
| Dev  | SQLite (mattn/go-sqlite3) | `DATABASE_URL` unset or starts with `./` |
| Prod | Postgres (pgx) | `DATABASE_URL` starts with `postgres://` |

Schema is in `schema.sql` — identical across both backends (only the
intersection of features: no SQLite-only functions, no Postgres-only
types). At boot, `db.New` retries the ping with `DB_RETRY_ATTEMPTS ×
DB_RETRY_INTERVAL_MS` (~10s default) so `docker compose up` doesn't
race Postgres readiness.

For the full backend documentation (every endpoint, env var, rate
limit, the admin auth protocol, build/test, etc.) see
[backend/README.md](backend/README.md).

---

## Production stack (`docker/`)

Four-service stack, all `restart: unless-stopped`:

| Service | Role |
| ------- | ---- |
| `postgres` | PostgreSQL 16, data in named volume (`simshop_postgres_data`) |
| `backend` | Go API, multi-stage Dockerfile (strip + non-root), healthcheck |
| `web` | Flutter web + Nginx, multi-stage Dockerfile (`--release`), SPA fallback, security headers |
| `cloudflared` | Cloudflare Tunnel, single `CF_TUNNEL_TOKEN`, 2 ingress from dashboard |

```
Internet → Cloudflare Tunnel (1 tunnel, 2 ingress)
              ├── api.<yourdomain>  →  backend:8080  (Go API)
              └──     <yourdomain>  →  web:80       (Flutter)
                                            │
                          postgres:5432  ◄──┘
                          (named volume, cross-OS)
```

The frontend calls the backend **via Cloudflare's URL**, never via the
internal Nginx — so there is no `/api/*` proxying to maintain.

For the full Docker documentation (Cloudflare setup, cache rules,
data persistence, backup/restore, rolling update, rollback, troubleshooting)
see [docker/README.md](docker/README.md).

---

## Admin authentication

Public reads are open. All writes require a valid admin session token
in `Authorization: Bearer <token>`. The token is obtained through an
Ed25519 challenge / response:

```
POST /api/admin/auth/challenge   →  { nonce }
POST /api/admin/auth/verify
  body: { nonce, signature }      →  { token, expires_at }
POST /api/admin/auth/logout      →  { ok }
```

Where `signature = Ed25519.Sign(admin.key, nonce)` (raw 64 bytes, hex
encoded). The server verifies with `ADMIN_PUBLIC_KEY`. Nonces are
single-use with a 60s TTL; tokens are opaque random strings in an
in-memory `SessionStore` with a 24h TTL.

Frontend trigger: **7 taps within 3 seconds on the footer banner**
(the banner is always mounted, even when its URL is empty — that's
how the admin entry stays reachable on a fresh DB). The gesture
opens the admin auth gate → user picks `admin.key` → Flutter calls
`/challenge`, signs the nonce with `cryptography`'s Ed25519, calls
`/verify`, stores the token in `SharedPreferences`. Every subsequent
admin write auto-attaches `Authorization: Bearer <token>` via the
`IAdminAuthService` chain.

### Generation flow

```bash
cd backend
go run ./cmd/keygen
# → secret key (binary 64 bytes) → admin.key  (mode 0600)
# → public  key (binary 32 bytes) → admin.key.pub (mode 0600)
# → cả 2 cũng được in hex để verify
```

Paste the public hex into `backend/.env` (`ADMIN_PUBLIC_KEY`) for dev,
or `docker/.env` for prod. Never commit `admin.key` — it is the credential.

### Why Ed25519 + a hidden trigger

- **No user table** — possession of the key file IS the credential.
- **No password to leak** — there is no password.
- **No phishing surface** — the only way to discover the trigger is to
  read the source.
- **Token expiry + nonce single-use** — replay window is at most 60s.

---

## Environment configuration

There are **three** `.env` files in this project, each scoped:

| File | Scope | Committed? |
| ---- | ----- | ---------- |
| `backend/.env` | Backend dev (SQLite, optional admin key, optional CORS origin) | ❌ gitignored |
| `.env` (repo root) | Flutter dev (only used in dev builds via `flutter_dotenv`) | ❌ gitignored |
| `docker/.env` | Production compose stack (Postgres password, tunnel token, admin key, Cloudflare URLs) | ❌ gitignored |

Templates:

- `backend/.env.example` — dev keys & comments
- `docker/.env.example` — production required-env checklist

Resolution order on the Flutter side:

1. `--dart-define=API_BASE_URL=...` (compile-time, what prod uses).
2. `.env` asset in `pubspec.yaml` (dev only — removed from release).
3. Empty (services fail-fast on first call).

Resolution order on the backend side:

1. Process env (always wins).
2. `backend/.env` (only if `Load()` finds one walking up from `cwd`).
3. Hard-coded defaults (port `8080`, SQLite `./simshop.db`, etc.).

> **Never commit any `.env` or `*.key` / `*.pub` files.** All are
> covered by `.gitignore`.

---

## Build & run

### Flutter web

```bash
# Dev
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080

# Release (used by Dockerfile.web)
flutter build web --release --no-tree-shake-icons \
    --dart-define=API_BASE_URL=https://api.example.com
# → build/web/  (static files, ready for Nginx)

# Helper: tool/build_web.sh
./tool/build_web.sh http://localhost:8080
```

### Flutter mobile (Android / iOS)

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android AAB
flutter build ios --release          # iOS (requires macOS + Xcode)
```

### Backend

```bash
# Dev
cd backend
go run .

# Production binary (stripped)
go build -ldflags="-s -w" -o server .
./server

# Run all tests
go test ./...
go test -race ./...        # data-race detector (slower)
go test -cover ./...       # coverage
```

### Docker stack (production)

```bash
cp docker/.env.example docker/.env
$EDITOR docker/.env        # fill POSTGRES_PASSWORD, ADMIN_PUBLIC_KEY, ...

docker compose -f docker/compose.yaml --env-file docker/.env up -d --build
docker compose -f docker/compose.yaml ps
docker compose -f docker/compose.yaml logs -f
```

See [docker/README.md](docker/README.md) for the production rollout
checklist, rolling-update, and rollback procedures.

---

## Testing

### Flutter

```bash
flutter test                    # all unit + widget tests
flutter test --coverage         # coverage report
```

### Backend

```bash
cd backend
go test ./...
```

Tests live next to the code they exercise (`handler/*_test.go`,
`db/*_test.go`, etc.). They spin up real `http.ServeMux` +
`httptest.ResponseRecorder` — no external mocks needed.

### End-to-end verification

The `backend/cmd/admincurl` binary walks the full admin flow
(challenge → sign → verify → create product → upload image) and
prints each step as both a verbatim curl transcript and a JSON
summary. Use it to prove a backend deploy accepts your key.

```bash
cd backend
go run ./cmd/admincurl
```

---

## Data seeding

The repo deliberately ships **no fixtures** — real data is created via
the admin panel. For the very first deployment verification (so the
frontend doesn't render an empty skeleton), the Docker stack includes
a placeholder seeder:

```bash
./docker/seed.sh
# → inserts a small placeholder set per table (idempotent: checks each
#   table is empty before inserting; partial seed is allowed)
```

It's not a fixture — it's a "render isn't blank" smoke test. Once an
admin logs in and creates real content, subsequent `seed.sh` runs are
no-ops.

For backup / restore of real data:

```bash
./docker/backup.sh backup                          # → ./data/simshop-YYYYMMDD-HHMMSS.sql
./docker/backup.sh backup ./my-backup.sql          # custom path
./docker/backup.sh restore ./my-backup.sql         # restore from file
```

---

## Troubleshooting

### Flutter can't reach the backend

1. Check `API_BASE_URL` resolution — `main.dart` prints it on boot.
2. In dev, set it explicitly: `--dart-define=API_BASE_URL=http://localhost:8080`.
3. CORS: `flutter run -d chrome` picks a random ephemeral port each
   run. Add it to `ALLOWED_ORIGIN` in `backend/.env` as a
   comma-separated allowlist.

### Admin gate keeps popping back

The token in `SharedPreferences` is dead (server restart clears the
in-memory `SessionStore`, or 24h TTL expired). `AdminSessionExpiredException`
on any admin write forces the shell back to the gate. Re-upload
`admin.key` — the gate handles re-auth transparently.

### Backend "db not ready" loop at boot

Postgres hasn't finished initializing yet. The backend retries
`DB_RETRY_ATTEMPTS × DB_RETRY_INTERVAL_MS` (~10s default). If Postgres
itself is crashing, check `docker compose logs postgres`.

### Cloudflare "Unable to reach origin: connection refused"

The ingress rule on the dashboard is pointing at the wrong service
URL. It must be `http://backend:8080` and `http://web:80` (Docker
service names — `localhost` would point at the cloudflared container,
which doesn't have a webserver).

### Frontend still loads old JS after rebuild

Cloudflare CDN caches `main.dart.js` for one year (Flutter's
`max-age=1y`). Either:

- **Quick**: Purge the URL via Cloudflare dashboard → Caching →
  **Purge Cache** → Custom Purge → `main.dart.js`.
- **Permanent**: Create a Cloudflare Cache Rule that **Bypass** for
  `main.dart.js`, `main.dart.wasm`, `flutter_bootstrap.js`.

See [docker/README.md](docker/README.md#nếu-fe-vẫn-gọi-localhost8080-sau-khi-rebuild)
for the full procedure.

---

## Cross-platform notes

### Windows (with WSL2)

- All paths use forward slashes; Docker Desktop maps to Windows paths
  internally.
- `docker compose` (v2, not `docker-compose`) is the only supported
  variant — comes bundled with Docker Desktop.
- Run all commands from a WSL2 shell, not PowerShell.

### macOS

- Docker Desktop with the new `docker buildx` is supported out of the
  box.
- `sudo` is **never** required; the user is added to the `docker`
  group by the installer.

### Linux

- Add your user to the `docker` group to avoid `sudo docker`:
  ```bash
  sudo usermod -aG docker $USER
  # log out + back in (or `newgrp docker`)
  ```
- For rootless Docker, named volumes live under
  `~/.local/share/docker/volumes/` instead of `/var/lib/docker/volumes/`.

---

## License

MIT — see `LICENSE` for the full text.

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/<thing>`).
3. Run `flutter analyze`, `flutter test`, `cd backend && go test ./...`.
4. Commit your changes.
5. Open a Pull Request describing **what** changed and **why**.

## See also

- [backend/README.md](backend/README.md) — Go API in detail.
- [docker/README.md](docker/README.md) — Production stack in detail.
