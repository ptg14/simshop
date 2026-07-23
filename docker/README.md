# Docker stack (production)

Postgres + Go backend + Flutter web (release) + Cloudflare Tunnel —
chạy trên cả **Windows** lẫn **Linux** mà không cần chỉnh sửa. Stack
này là **production build**: binary Go đã strip debug + non-root,
Flutter build `--release`, Nginx có security headers.

For the overall system design see
[README.md](../README.md).
For the backend API surface see
[backend/README.md](../backend/README.md).

---

## Table of contents

1. [Connection flow](#connection-flow)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [File structure](#file-structure)
5. [Services](#services)
6. [Environment variables](#environment-variables)
7. [Data persistence](#data-persistence)
8. [Cloudflare setup](#cloudflare-setup-one-time)
9. [Common test scenarios](#common-test-scenarios)
10. [Cross-OS notes](#cross-os-notes)
11. [When to rebuild](#when-to-rebuild)
12. [Troubleshooting](#troubleshooting)
13. [Production rollout checklist](#production-rollout-checklist)
14. [Rolling update & rollback](#rolling-update--rollback)
15. [Backup & restore](#backup--restore)

---

## Connection flow

```
Internet → Cloudflare Tunnel (1 tunnel, 2 ingress)
              ├── api.<yourdomain>  →  backend:8080  (Go API)
              └──     <yourdomain>  →  web:80       (Flutter)
                                            │
                          postgres:5432  ◄──┘
                          (named volume, cross-OS)
```

Key invariants:

- **FE gọi BE qua URL Cloudflare của BE** — không qua Nginx nội bộ.
  Nginx chỉ serve static Flutter assets.
- **BE chỉ kết nối Postgres nội bộ Docker** — không cần tunnel.
- **Schema init 1 lần** khi volume Postgres còn trống; restart không
  re-init → boot nhanh.
- **Tất cả service có `restart: unless-stopped`** → Docker tự khởi
  động lại cùng server (reboot host → containers trở lại).
- **No host port publishing** — Cloudflare Tunnel là entrypoint duy
  nhất. Postgres / backend / web chỉ mở trong Docker network
  `simshop-net`.

---

## Requirements

- **Docker** ≥ 20.10 với Compose v2 (`docker compose version`)
- **PostgreSQL client** (chỉ cần cho debug: `docker compose exec postgres psql`)
- **Cloudflare account** with a domain added (so you can create a tunnel)

### Docker socket permissions

If you hit `permission denied while trying to connect to the docker
API at unix:///var/run/docker.sock`:

**Option 1 (recommended)** — add your user to the `docker` group:

```bash
sudo usermod -aG docker $USER
# Log out and back in (or `newgrp docker`)
```

**Option 2** — prefix every command with `sudo`:

```bash
sudo docker compose -f docker/compose.yaml --env-file docker/.env up -d --build
```

On Windows + WSL2, Docker Desktop configures the `docker` group
automatically; if you still see errors, restart Docker Desktop.

---

## Quick start

```bash
# 1. Tạo .env từ template
cp docker/.env.example docker/.env

# 2. Điền các giá trị BẮT BUỘC (compose fail-fast nếu thiếu)
#    - POSTGRES_PASSWORD : đổi từ "changeme"
#    - ADMIN_PUBLIC_KEY  : hex 64 chars — lấy bằng `cd backend && go run ./cmd/keygen`
#    - ALLOWED_ORIGIN    : URL Cloudflare của frontend (vd https://testweb.dvthang.qzz.io)
#    - CF_TUNNEL_TOKEN   : từ Cloudflare dashboard (xem "Cloudflare setup")
#    - BE_PUBLIC_URL     : URL Cloudflare của backend (vd https://api.dvthang.qzz.io)
#    - IMAGE_TAG         : git SHA hoặc build number (để trace image đang chạy)
$EDITOR docker/.env

# 3. Khởi động stack (lần đầu: ~5-10 phút build image Flutter)
docker compose -f docker/compose.yaml --env-file docker/.env up -d --build

# 4. Xem log
docker compose -f docker/compose.yaml logs -f

# 5. Kiểm tra
docker compose -f docker/compose.yaml ps
# → tất cả services Up (healthy)
```

Verify end-to-end:

```bash
# Postgres
docker compose -f docker/compose.yaml exec postgres \
  pg_isready -U simshop -d simshop
# → "accepting connections"

# Backend (nội bộ Docker network)
docker compose -f docker/compose.yaml exec backend \
  wget -qO- http://localhost:8080/health
# → {"status":"ok"}

# Web (nội bộ Docker network)
docker compose -f docker/compose.yaml exec web \
  wget -qO- http://localhost/healthz
# → ok

# Cloudflare Tunnel
docker compose -f docker/compose.yaml logs cloudflared | tail
# → "Registered tunnel connection" + 2 hostname
```

External test (từ trình duyệt hoặc curl):

```bash
curl https://api.<yourdomain>/health
# → {"status":"ok"}

open https://<yourdomain>
# → Flutter web load
```

---

## File structure

```
docker/
├── compose.yaml              # 4 services (prod build, resource limits)
├── Dockerfile.backend        # Go multi-stage + strip + non-root (prod)
├── Dockerfile.web            # Flutter --release + Nginx (prod)
├── nginx.conf                # SPA fallback + security headers (prod)
├── cloudflared-config.yml    # Reference only — Cloudflare fetches
│                             # ingress from dashboard, not this file
├── initdb/
│   └── 01-schema.sql         # Schema Postgres (chạy 1 lần khi volume trống)
├── backup.sh                 # pg_dump / pg_restore helpers
├── seed.sh                   # Idempotent placeholder seeder
├── .env.example              # Template environment (required-env checklist)
└── README.md                 # This file
```

### `initdb/01-schema.sql`

Mounted at `/docker-entrypoint-initdb.d` in the Postgres container.
Postgres runs every `*.sql` file there exactly once, **the first time
the data directory is empty**. After that, restart never re-runs the
script. This is what makes the stack boot fast on restarts.

### `cloudflared-config.yml`

Reference only. Cloudflare's `cloudflared` reads its ingress rules
from the Cloudflare Zero Trust dashboard, not from this file. We
mount it for operators to see the expected Service URLs at a glance.

### `nginx.conf`

Production config — SPA fallback, security headers (`X-Frame-Options`,
`X-Content-Type-Options`, `Referrer-Policy`, `Strict-Transport-Security`),
gzip on, and a tuned cache policy:

| Path | Cache-Control | Why |
| ---- | ------------- | --- |
| `*.woff2 / *.ttf / *.otf / *.svg / *.png / *.jpg / *.webp / *.ico` | `public, immutable` (1y) | Asset filenames are content-hashed by Flutter |
| `/main.dart.js` `/main.dart.wasm` `/flutter_bootstrap.js` | `no-cache, must-revalidate` | No hash in filename → CDN would otherwise cache stale code forever |
| Other `*.js / *.css` | `no-cache, must-revalidate` | Same reasoning (asset bundles re-shuffle per build) |
| `/index.html` | `no-cache, no-store, must-revalidate` | Rollout must take effect immediately |
| `/healthz` | n/a (returns 200 `ok`) | For Docker healthcheck + Cloudflare monitor |
| everything else | SPA fallback to `/index.html` | Flutter `go_router` handles routing |

---

## Services

| Service | Port nội bộ | Resource limits | Image | Role |
| ------- | ----------- | --------------- | ----- | ---- |
| `postgres` | 5432 | mem 512M / 128M res | `postgres:16-alpine` | PostgreSQL 16, named volume, initdb hook |
| `backend` | 8080 | mem 256M / 64M res, 0.5 CPU | `simshop/backend:${IMAGE_TAG}` | Go HTTP API (static, non-root) |
| `web` | 80 | mem 128M / 32M res, 0.25 CPU | `simshop/web:${IMAGE_TAG}` | Nginx serve Flutter static |
| `cloudflared` | — | none | `cloudflare/cloudflared:latest` | Tunnel → 2 ingress from dashboard |

All services have `restart: unless-stopped` so they survive Docker
daemon / host reboots.

### `depends_on` chain

```
postgres (healthy)
   └── backend (healthy)
            ├── web (healthy)
            └── cloudflared
```

Cloudflared starts after both backend + web are healthy so the tunnel
doesn't connect to a half-up stack.

### Healthchecks

Each service defines one. Compose marks the service `healthy` only
after the check passes, which gates `depends_on: condition:
service_healthy`:

| Service | Check |
| ------- | ----- |
| postgres | `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` every 10s, 10 retries, 10s start period |
| backend | `wget -qO- http://localhost:8080/health` every 30s, 3 retries, 15s start period |
| web | `wget -qO- http://localhost/healthz` every 30s, 3 retries, 5s start period |
| cloudflared | (no healthcheck — cloudflared exits if the token is wrong; watch logs) |

---

## Environment variables

`docker/.env.example` is the canonical template. Required (compose
fails fast if missing):

| Variable | Why required | How to fill |
| -------- | ------------ | ----------- |
| `POSTGRES_PASSWORD` | Postgres user creation | `openssl rand -hex 24` or password manager |
| `ADMIN_PUBLIC_KEY` | Backend admin auth | `cd backend && go run ./cmd/keygen` (paste public hex) |
| `ALLOWED_ORIGIN` | CORS allowlist | `https://<your-fe-domain>` |
| `CF_TUNNEL_TOKEN` | Tunnel auth | Cloudflare Zero Trust → Tunnels → your tunnel → "Install cloudflared" |

Recommended (production):

| Variable | Why | Example |
| -------- | --- | ------- |
| `IMAGE_TAG` | Image traceability, enables rollback | `<git-sha>` or `<build-number>` |
| `BE_PUBLIC_URL` | Absolute upload URLs, embedded into Flutter build | `https://api.<your-domain>` |
| `API_BASE_URL` | Explicit Flutter API base (defaults to `BE_PUBLIC_URL`) | same as `BE_PUBLIC_URL` |
| `POSTGRES_DB` | DB name (defaults `simshop`) | `simshop` |
| `POSTGRES_USER` | DB user (defaults `simshop`) | `simshop` |

Optional (defaults work fine):

| Variable | Default | Notes |
| -------- | ------- | ----- |
| `DB_RETRY_ATTEMPTS` | `10` | Backend ping retries on boot |
| `DB_RETRY_INTERVAL_MS` | `1000` | Delay between retries (10s total window) |

### What gets baked into each image

| Image | Build arg | Effect |
| ----- | --------- | ------ |
| `simshop/web` | `API_BASE_URL` | Compiled into Flutter JS bundle via `--dart-define`; also injected into `web/index.html` for `<link rel="preconnect">` |
| `simshop/backend` | _(none)_ | All config via env at runtime; the image is config-agnostic |

So changing `BE_PUBLIC_URL` requires rebuilding the `web` image (the
value is baked at build time). Changing `ADMIN_PUBLIC_KEY` only needs
a backend container restart.

---

## Data persistence

Cả 2 loại data đều dùng **named Docker volume** (không bind-mount) →
cross-OS, Docker tự chọn path, không cần chmod:

```bash
# Xem path thực của volume trên host
docker volume inspect simshop_postgres_data
docker volume inspect simshop_backend_uploads
```

| Volume | Mount point in container | Contents |
| ------ | ------------------------ | -------- |
| `simshop_postgres_data` | `/var/lib/postgresql/data` | Postgres data dir |
| `simshop_backend_uploads` | `/data/uploads` | Multipart uploads |

### Schema init lifecycle

- **First boot** (volume trống): Postgres runs `/docker-entrypoint-initdb.d/*.sql`
  once, then boots.
- **Every subsequent boot** (volume có data): Postgres skips init,
  boots in ~1 second.
- **If you change `initdb/01-schema.sql` after the first boot**:
  schema is **NOT** re-applied. To force re-init:

  ```bash
  docker compose -f docker/compose.yaml down
  docker volume rm simshop_postgres_data
  docker compose -f docker/compose.yaml up -d
  # → schema re-init from scratch
  ```

### Backup & restore

```bash
# Backup (writes to ./data/simshop-YYYYMMDD-HHMMSS.sql)
./docker/backup.sh backup

# Backup to custom path
./docker/backup.sh backup ./my-backup.sql

# Restore (uses --clean --if-exists, drops + recreates)
./docker/backup.sh restore ./my-backup.sql

# Uploads volume — manual
docker run --rm -v simshop_backend_uploads:/data -v $(pwd):/backup \
    alpine tar czf /backup/uploads-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

### Reset toàn bộ data (XÓA HẾT, dùng cẩn thận)

```bash
docker compose -f docker/compose.yaml down
docker volume rm simshop_postgres_data
docker volume rm simshop_backend_uploads
docker compose -f docker/compose.yaml up -d
# → schema tự re-init, uploads empty
```

---

## Cloudflare setup (one-time)

Trước khi chạy `docker compose up`, cần chuẩn bị tunnel trên
Cloudflare:

1. Vào [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/)
   → **Networks** → **Tunnels** → **Create a tunnel**
2. Chọn **Cloudflared** → đặt tên (vd: `simshop`) → **Save**
3. Copy **token** ở màn hình tiếp theo → paste vào
   `docker/.env` biến `CF_TUNNEL_TOKEN`
4. Trên dashboard, tab **Public Hostname** → **Add a public hostname**,
   khai **2 hostname** với service URL trỏ vào Docker service name
   (không phải `localhost`):

   | Subdomain | Domain | Service URL |
   | --- | --- | --- |
   | `api` (hoặc hostname đầy đủ) | `yourdomain.com` | `http://backend:8080` |
   | `app` (hoặc FE hostname) | `yourdomain.com` | `http://web:80` |

   **Quan trọng**: `backend` và `web` là Docker **service name** —
   Cloudflare tunnel chạy trong cùng Docker network (`simshop-net`)
   nên resolve được. Dùng `localhost` sẽ trỏ về chính container
   cloudflared (không có webserver ở port 80) → lỗi
   `connection refused to localhost:80`.

### Nếu gặp lỗi "Unable to reach origin: connection refused"

Lỗi này nghĩa là ingress rule trên dashboard trỏ về sai service URL.
Kiểm tra:

```bash
# Xem IP thực của web/backend trong Docker network
docker inspect simshop-web -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect simshop-backend -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Sửa trên dashboard:

- Vào tunnel → tab **Configured** → click hostname → đổi **Service**
  thành `http://backend:8080` (BE) hoặc `http://web:80` (FE).

Cloudflare tunnel auto-reload config, không cần restart container.

### Nếu FE vẫn load code cũ sau khi rebuild

Đây là vấn đề **Cloudflare cache file cũ**. Container `web` đã serve
file mới nhưng Cloudflare CDN cache theo `max-age=1y` của Flutter
asset, ignore `Cache-Control: no-cache` từ nginx.

**Cách fix nhanh** (mỗi lần update FE):

1. Vào Cloudflare dashboard → Caching → **Purge Cache** →
   "Custom Purge" → nhập URL `https://<your-fe-domain>/main.dart.js`
   → Purge.

**Cách fix vĩnh viễn** (khuyến nghị cho production):

1. Vào Cloudflare dashboard → Caching → **Configuration** →
   **Cache Rules** → Create rule:
   - Name: `Bypass Flutter entrypoints`
   - Match: `URI Path` → contains → `main.dart.js`
   - Action: **Bypass cache**

   Tạo thêm rule tương tự cho `flutter_bootstrap.js`,
   `main.dart.wasm`.

Sau khi rule active, mọi `docker compose build web` mới sẽ được user
nhận ngay (không cần purge thủ công).

---

## Common test scenarios

### Health check toàn stack

```bash
# Postgres
docker compose -f docker/compose.yaml exec postgres \
  pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
# → "accepting connections"

# Backend
docker compose -f docker/compose.yaml exec backend \
  wget -qO- http://localhost:8080/health
# → {"status":"ok"}

# Web
docker compose -f docker/compose.yaml exec web \
  wget -qO- http://localhost/healthz
# → ok

# Cloudflared
docker compose -f docker/compose.yaml logs cloudflared | tail
# → "Registered tunnel connection" + 2 hostname
```

### Test retry logic (mô phỏng Postgres chưa ready)

```bash
# 1. Tắt postgres
docker compose -f docker/compose.yaml stop postgres

# 2. Restart backend — sẽ retry
docker compose -f docker/compose.yaml up -d backend
docker compose -f docker/compose.yaml logs -f backend
# → "db not ready (attempt 1/10): ..." → "attempt 2/10..." → ...

# 3. Khởi động lại postgres
docker compose -f docker/compose.yaml start postgres

# 4. Sau vài giây, backend log "database init: connected"
```

### Test restart server (giữ data)

```bash
# Restart toàn bộ containers (giữ volumes)
docker compose -f docker/compose.yaml restart

# Verify data còn
docker compose -f docker/compose.yaml exec postgres \
  psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT count(*) FROM products;"
```

### Test admin auth end-to-end (qua Cloudflare URL)

```bash
cd backend
# Update admincurl's baseURL temporarily, or run from a machine that
# can resolve the Cloudflare hostname. Then:
go run ./cmd/admincurl
# → walks challenge / verify / create product qua https://api.<domain>
```

### Rebuild sau khi sửa code

```bash
# Backend (Go) — build nhanh (~30s)
docker compose -f docker/compose.yaml build backend
docker compose -f docker/compose.yaml up -d backend

# Web (Flutter) — image build lâu (~5 phút cold cache)
docker compose -f docker/compose.yaml build web
docker compose -f docker/compose.yaml up -d web
```

---

## Cross-OS notes

### Windows (with WSL2)

- Đường dẫn file dùng `/` (forward slash) cho Linux-side mount
  (`./initdb`, `./cloudflared-config.yml`) — Docker Desktop tự map
  sang Windows path.
- `docker compose` (không phải `docker-compose`) cần WSL2 backend,
  xem [Docker Desktop WSL2](https://docs.docker.com/desktop/wsl/).
- Line endings trong `.env` không quan trọng — Docker tự parse.
- Run all commands from a WSL2 shell, not PowerShell or CMD.

### Linux

- If running Docker with `rootless` mode, volume paths live under
  `~/.local/share/docker/volumes/` instead of `/var/lib/docker/volumes/`.
- Không cần `chmod` UID 999 vì dùng **named volume** (không bind-mount
  vào host filesystem).
- SELinux: if you see `permission denied` on volume mounts, run
  `:z` or `:Z` on the volume mount. We don't bind-mount, so this
  doesn't apply.

### macOS

- Docker Desktop with the new `docker buildx` works out of the box.
- No `sudo` required (Docker Desktop adds the user to the `docker`
  group during install).

---

## Debug container

Tất cả lệnh dưới đây dùng `--env-file docker/.env` để compose resolve
cùng config với lúc `up`. Nếu bạn dùng compose từ ngoài `docker/`,
nhớ thêm `-f docker/compose.yaml`.

### Đọc log

```bash
# Tất cả services, follow mode
docker compose -f docker/compose.yaml logs -f

# Chỉ một service
docker compose -f docker/compose.yaml logs -f backend

# 100 dòng cuối + timestamps
docker compose -f docker/compose.yaml logs --tail=100 -t backend

# Lọc log theo mức độ (compose ≥ 2.20)
docker compose -f docker/compose.yaml logs -f --level error
```

Log backend có format `YYYY-MM-DD HH:MM:SS msg` (default `log` package).
Tìm các marker:

| Pattern | Ý nghĩa |
| ------- | -------- |
| `admin auth enabled (public key loaded)` | Backend đọc được `ADMIN_PUBLIC_KEY` |
| `WARNING: ADMIN_PUBLIC_KEY is empty` | Dev mode + key rỗng → admin auth TẮT (mọi write public) |
| `db not ready (attempt N/M): ...` | Postgres chưa ready, đang retry (xem [Backend crash](#backend-crash-liên-tục-db-not-ready)) |
| `database init: connected` | Postgres ready, migrations xong |
| `starting server on :8080` | Backend listen thành công |
| `signal received, shutting down...` | Nhận SIGTERM, đang shutdown graceful |
| panic stack trace | Bug — xem [Debug Go panic](#debug-go-panic) |

### Exec shell vào container

Mỗi container đều có shell để inspect runtime:

```bash
# Backend (Alpine)
docker compose -f docker/compose.yaml exec backend sh

# Web (Nginx Alpine)
docker compose -f docker/compose.yaml exec web sh

# Postgres
docker compose -f docker/compose.yaml exec postgres sh

# Cloudflared (debug thường không cần — chỉ tail log là đủ)
docker compose -f docker/compose.yaml logs cloudflared --tail=200
```

Trong shell của backend:

```bash
# Xem file binary, env, working dir
ls -la /app/
env | grep -E '^(DATABASE_URL|ADMIN_PUBLIC_KEY|ALLOWED_ORIGIN)='
ps auxf

# Xem HTTP server còn listen không
wget -qO- http://localhost:8080/health
# → {"status":"ok"}

# Test connectivity tới Postgres (không cần psql client)
wget -qO- --timeout=2 http://postgres:5432/ || echo "expected: connection refused on HTTP"
nc -zv postgres 5432
# → postgres (172.18.0.x:5432) open
```

### Inspect Postgres query

`docker/initdb/01-schema.sql` đã seed sẵn 1 row trong `store_info`.
Container Postgres có sẵn `psql` client:

```bash
# Mở psql
docker compose -f docker/compose.yaml exec postgres psql \
    -U simshop -d simshop

# Một số query hữu ích
\dt                                       # liệt kê tables
\dt+ products                             # chi tiết 1 table
\d products                               # columns + indexes

SELECT count(*) FROM products;
SELECT id, name, price, stock FROM products ORDER BY id LIMIT 10;

-- Xem draft articles (admin-only field)
SELECT id, title, is_draft FROM articles;

-- Xem events còn hiệu lực (Unix timestamp)
SELECT id, name, end_time, discount_type, discount_value
  FROM events
 WHERE end_time IS NULL OR end_time > extract(epoch from now());

-- Xem ảnh upload gần đây
SELECT id, product_id, image_url
  FROM product_images
 ORDER BY id DESC LIMIT 10;

-- Thoát
\q
```

Chạy 1 query mà không cần vào REPL:

```bash
docker compose -f docker/compose.yaml exec -T postgres \
    psql -U simshop -d simshop -c "SELECT count(*) FROM products;"
```

### Debug Go panic

Panic trong backend in full stack trace ra stdout — bạn sẽ thấy trong
`docker logs`. Ví dụ:

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation ...]

goroutine 42 [running]:
github.com/ptg14/simshop/backend/internal/handler.GetProductHandler.func1
        /src/internal/handler/handler.go:142 +0x1a3
github.com/ptg14/simshop/backend/internal/router.New.func11
        /src/internal/router/router.go:87 +0x88
...
```

Lưu ý:

- **Stack trace đã bị strip** (build với `-ldflags="-s -w"`). Bạn sẽ
  thấy file + line number (`handler.go:142`) nhưng không có tên
  biến cục bộ. Đủ để tìm bug.
- **Path là `/src/...`** chứ không phải path repo. Đó là `WORKDIR`
  trong stage build của `Dockerfile.backend` — line number vẫn khớp
  với code trong repo local.
- **Restart tự động**: container có `restart: unless-stopped`, nên
  panic sẽ khiến container restart. Nếu panic liên tục, container
  vào crash loop → xem log dài hơn:

  ```bash
  docker compose -f docker/compose.yaml logs --tail=500 backend
  ```

- **Reproduce local**: với stack trace bạn tìm được `file:line`, đọc
  code local rồi viết test trong `backend/internal/handler/*_test.go`.
  Chạy test ngoài Docker:

  ```bash
  cd backend
  go test -run TestFailingCase ./internal/handler/...
  ```

### Xem Docker network + DNS

Service discovery trong compose dùng Docker DNS. Kiểm tra nhanh:

```bash
# Liệt kê networks
docker network ls | grep simshop

# Xem services trong network
docker network inspect simshop-net --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
# → simshop-postgres 172.18.0.2/16
# → simshop-backend  172.18.0.3/16
# → simshop-web      172.18.0.4/16
# → simshop-cloudflared 172.18.0.5/16

# Resolve DNS từ trong 1 container
docker compose -f docker/compose.yaml exec backend nslookup postgres
docker compose -f docker/compose.yaml exec backend nslookup web

# Xem port map / mount của container
docker inspect simshop-backend \
    --format '{{json .Mounts}}' | python3 -m json.tool
```

### Resource usage

Container có `deploy.resources.limits` trong `compose.yaml`. Kiểm
tra xem có sắp bị OOM không:

```bash
# Real-time stats
docker stats simshop-backend simshop-web simshop-postgres simshop-cloudflared

# Lịch sử (cần cgroup v2 + systemd)
systemctl status docker   # xem journal
journalctl -u docker --since "1 hour ago" | grep -i 'oom\|killed'
```

Nếu backend bị kill vì OOM, tăng `mem.limit` trong `compose.yaml`:

```yaml
backend:
  deploy:
    resources:
      limits:
        memory: 512M   # ↑ từ 256M
```

### Reset mà KHÔNG mất data

```bash
# Restart 1 service (giữ volume)
docker compose -f docker/compose.yaml restart backend

# Force re-create (giữ volume, rebuild image)
docker compose -f docker/compose.yaml up -d --force-recreate backend

# Tail logs của 1 service để xem nó có boot OK không
docker compose -f docker/compose.yaml logs -f --tail=50 backend
```

### Reset mà MẤT data

```bash
# Dừng + xóa containers + volumes
docker compose -f docker/compose.yaml down -v
# (-v = xóa cả named volumes)

# Khởi động lại (volume tạo mới, schema re-init)
docker compose -f docker/compose.yaml --env-file docker/.env up -d --build

# Chạy seeder để có placeholder data
./docker/seed.sh
```

### Xem Cloudflare tunnel state

`cloudflared` chạy ở foreground, log ra stdout. Một số pattern hữu ích:

```bash
# Tail log cloudflared
docker compose -f docker/compose.yaml logs -f --tail=100 cloudflared

# Đếm số connection tới Cloudflare edge (càng nhiều càng ổn)
docker compose -f docker/compose.yaml logs cloudflared 2>&1 \
    | grep -c "Registered tunnel connection"

# Verify ingress rules trên dashboard đang active
docker compose -f docker/compose.yaml logs cloudflared 2>&1 \
    | grep -E "(https://|http://)" | tail -20
# → "https://api.<your-domain>" → http://backend:8080
# → "https://<your-domain>"     → http://web:80
```

Nếu thấy `Unable to reach origin: connection refused`: ingress rule
trên dashboard đang trỏ sai service URL. Xem
[Nếu gặp lỗi "Unable to reach origin: connection refused"](#nếu-gặp-lỗi-unable-to-reach-origin-connection-refused).

### Verify cache-bypass hoạt động

Sau khi tạo Cache Rule Bypass cho `main.dart.js`:

```bash
# 1. Lấy URL từ Cloudflare (qua DNS thật)
curl -I https://<your-domain>/main.dart.js

# Response phải có:
#   cf-cache-status: DYNAMIC         ← không phải HIT
#   cache-control: no-cache, must-revalidate   ← từ nginx
```

Nếu thấy `cf-cache-status: HIT`, rule chưa active hoặc path không
match (xem lại match pattern trong dashboard).

---

## When to rebuild

| Thay đổi | Cần rebuild? |
| -------- | ------------ |
| Sửa Go code trong `backend/` | `build backend` + `up -d backend` |
| Sửa Flutter code trong `lib/` | `build web` + `up -d web` |
| Đổi `BE_PUBLIC_URL` / `API_BASE_URL` | `build web` (Flutter build-time only) |
| Đổi `nginx.conf` | `build web` |
| Đổi `Dockerfile.backend` / `Dockerfile.web` | `build backend` / `build web` |
| Đổi `compose.yaml` (resource limits, depends_on) | `up -d` (compose re-creates affected services) |
| Đổi `initdb/01-schema.sql` | **Cẩn thận** — chỉ chạy 1 lần volume trống. Reset volume để re-init. |
| Đổi `POSTGRES_PASSWORD` | Không — chỉ restart `postgres` |
| Đổi `ADMIN_PUBLIC_KEY` | Không — chỉ restart `backend` |
| Đổi `ALLOWED_ORIGIN` | Không — chỉ restart `backend` |
| Đổi `CF_TUNNEL_TOKEN` | Không — chỉ restart `cloudflared` |
| Đổi `IMAGE_TAG` | `build` + `up -d` để image mới replace |

---

## Troubleshooting

### Backend crash liên tục "db not ready"

Postgres chưa ready hoặc sai `DATABASE_URL`. Kiểm tra:

```bash
docker compose -f docker/compose.yaml logs postgres | tail
docker compose -f docker/compose.yaml exec backend env | grep DATABASE_URL
```

Sửa bằng cách tăng `DB_RETRY_ATTEMPTS` và `DB_RETRY_INTERVAL_MS`
trong `docker/.env` rồi `up -d backend`.

### Backend log "ADMIN_PUBLIC_KEY is empty in production"

Compose đã truyền `ADMIN_PUBLIC_KEY` qua env, nhưng giá trị rỗng.
Kiểm tra `docker/.env` đã điền biến này chưa (`docker compose config`
in ra config resolved).

### Cloudflare tunnel "no such host"

`cloudflared-config.yml` chưa thay `<TUNNEL_ID>`, hoặc `CF_TUNNEL_TOKEN`
không khớp tunnel ID trên dashboard. Lấy lại từ dashboard.

### Cloudflare "Unable to reach origin: connection refused"

Ingress rule trên dashboard trỏ sai service URL. Xem
[Cloudflare setup](#nếu-gặp-lỗi-unable-to-reach-origin-connection-refused).

### Schema init không chạy

File SQL đã có trên volume Postgres rồi. Init chỉ chạy 1 lần với
volume trống. Reset:

```bash
docker compose -f docker/compose.yaml down
docker volume rm simshop_postgres_data
docker compose -f docker/compose.yaml up -d
```

### Frontend load 404 hoặc blank

- Kiểm tra log: `docker compose -f docker/compose.yaml logs web`
- Nginx đòi SPA fallback. File `index.html` phải tồn tại trong
  `build/web/`. Build lại: `docker compose -f docker/compose.yaml
  build web --no-cache`.
- `BE_PUBLIC_URL` rỗng → Flutter dùng `http://localhost:8080` →
  browser không gọi được khi truy cập qua Cloudflare. **Luôn đặt
  `BE_PUBLIC_URL` thành URL Cloudflare của BE.**
- Cloudflare CDN caching stale JS — xem
  [nếu FE vẫn load code cũ](#nếu-fe-vẫn-load-code-cũ-sau-khi-rebuild).

### Container restart loop

```bash
# Xem exit code + last log
docker compose -f docker/compose.yaml ps
docker compose -f docker/compose.yaml logs --tail=50 <service>
```

Common culprits: missing required env var (compose should have caught
this — verify with `docker compose config`), bad volume permissions
(rare — we use named volumes), port conflict on host (we don't
publish ports, so this shouldn't happen).

### Out of disk space

Docker build cache + image layers add up. Clean up:

```bash
docker system df                              # see what's using space
docker image prune -a                         # remove unused images
docker builder prune                          # remove build cache
docker volume prune                           # remove unused volumes (CAREFUL)
```

Old images with explicit `IMAGE_TAG` are **kept** until `docker image
prune` — that's intentional, to enable rollback.

---

## Production rollout checklist

Trước khi deploy:

- [ ] `POSTGRES_PASSWORD` đã đổi từ placeholder (khác rỗng, mạnh).
- [ ] `ADMIN_PUBLIC_KEY` đã set (hex 64 chars, lấy từ `go run ./cmd/keygen`).
- [ ] `ALLOWED_ORIGIN` đã trỏ về URL Cloudflare của FE (không có trailing slash).
- [ ] `BE_PUBLIC_URL` đã trỏ về URL Cloudflare của BE.
- [ ] `CF_TUNNEL_TOKEN` đã paste từ Cloudflare dashboard.
- [ ] `IMAGE_TAG` đã set thành git SHA (hoặc build number) — tránh
      `latest` cho rollout để có thể rollback.
- [ ] Cloudflare dashboard đã khai 2 ingress với service URL
      `http://backend:8080` và `http://web:80` (xem phần Cloudflare setup).
- [ ] Cloudflare Cache Rules đã tạo cho `main.dart.js`,
      `flutter_bootstrap.js`, `main.dart.wasm` (Bypass cache) — tránh
      phải purge thủ công mỗi deploy.
- [ ] File `docker/.env` KHÔNG commit (đã có trong `.gitignore`).
- [ ] `admin.key` được backup offline (USB, password manager) —
      nếu mất, không có cách nào khôi phục admin access.

---

## Rolling update & rollback

### Rolling update (BE / FE)

Không cần `down` — compose replace container, volume Postgres + uploads
giữ nguyên.

```bash
# Cập nhật IMAGE_TAG trong docker/.env trước
$EDITOR docker/.env
# IMAGE_TAG=v1.2.3

# Build lại image với tag mới + replace container đang chạy
docker compose -f docker/compose.yaml --env-file docker/.env \
    build backend         # hoặc: web
docker compose -f docker/compose.yaml --env-file docker/.env \
    up -d backend         # zero-downtime: rolling replace
```

### Rollback

Vì image có tag (vd `simshop/backend:v1.2.3`), rollback chỉ cần đổi
tag về bản cũ trong `.env` rồi `up -d`:

```bash
$EDITOR docker/.env
# IMAGE_TAG=v1.2.2
docker compose -f docker/compose.yaml --env-file docker/.env \
    pull backend
docker compose -f docker/compose.yaml --env-file docker/.env \
    up -d backend
```

Image cũ KHÔNG bị xóa cho đến khi `docker image prune` thủ công →
giữ nguyên trên host để rollback nhanh.

### Rollback nếu schema mới đã apply

Nếu migration đã chạy trong `initdb/01-schema.sql` (hoặc qua admin
panel) rồi mới rollback BE image, **dữ liệu có thể không tương
thích** với code cũ. Hai lựa chọn:

1. Restore DB từ backup trước deploy:
   ```bash
   docker compose -f docker/compose.yaml down
   ./docker/backup.sh restore ./data/simshop-<pre-deploy>.sql
   docker compose -f docker/compose.yaml up -d
   ```
2. Forward-fix (viết migration tương thích ngược rồi deploy lại).

---

## License

Cùng license với phần còn lại của dự án (MIT).
