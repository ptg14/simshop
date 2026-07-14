# simshop Docker Stack (Production)

Postgres + Go backend + Flutter web (release) + Cloudflare Tunnel — chạy
trên cả **Windows** lẫn **Linux** mà không cần chỉnh sửa. Stack này
là **production build**: binary Go đã strip debug + non-root, Flutter
build `--release`, Nginx có security headers.

## Luồng kết nối

```
Internet → Cloudflare Tunnel (1 tunnel, 2 ingress)
              ├── api.simshop.example.com  →  backend:8080  (Go API)
              └──     simshop.example.com  →  web:80       (Flutter)
                                                  │
                            postgres:5432  ◄──────┘
                            (named volume, cross-OS)
```

- **FE gọi BE qua URL Cloudflare của BE** — không qua Nginx nội bộ.
- **BE chỉ kết nối Postgres nội bộ Docker** — không cần tunnel.
- **Schema init 1 lần** khi volume Postgres còn trống; restart không
  re-init → boot nhanh.
- **Tất cả service có `restart: unless-stopped`** → Docker tự khởi
  động lại cùng server.

## Yêu cầu

- **Docker** ≥ 20.10 với Compose v2 (`docker compose version`)
- **PostgreSQL client** (chỉ cần cho debug: `docker compose exec postgres psql`)

### Quyền truy cập Docker socket

Nếu gặp `permission denied while trying to connect to the docker
API at unix:///var/run/docker.sock`, có 2 cách fix:

**Cách 1 (khuyến nghị)**: thêm user vào group `docker` — không cần
`sudo` cho mỗi lệnh:

```bash
sudo usermod -aG docker $USER
# Đăng xuất rồi đăng nhập lại (hoặc `newgrp docker`) để áp dụng
```

**Cách 2**: chạy với `sudo` khi cần:

```bash
sudo docker compose -f docker/compose.yaml --env-file docker/.env up -d --build
```

Trên Windows + WSL2, group `docker` đã được Docker Desktop tự cấu hình;
nếu vẫn lỗi thì khởi động lại Docker Desktop.

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

## Cấu trúc file

```
docker/
├── compose.yaml              # 4 services (prod build, resource limits)
├── Dockerfile.backend        # Go multi-stage + strip + non-root (prod)
├── Dockerfile.web            # Flutter --release + Nginx (prod)
├── nginx.conf                # SPA fallback + security headers (prod)
├── cloudflared-config.yml    # 1 tunnel, 2 ingress
├── initdb/
│   └── 01-schema.sql         # Schema Postgres (chạy 1 lần)
├── backup.sh                 # pg_dump/pg_restore
├── .env.example              # Template environment (required-env checklist)
└── README.md                 # File này
```

## Các service

| Service       | Port nội bộ | Vai trò                           |
| ------------- | ----------- | --------------------------------- |
| `postgres`    | 5432        | PostgreSQL 16                     |
| `backend`     | 8080        | Go HTTP API                       |
| `web`         | 80          | Nginx serve Flutter static        |
| `cloudflared` | -           | Cloudflare Tunnel                 |

## Data persistence

Cả 2 loại data đều dùng **named Docker volume** (không bind-mount) →
cross-OS, Docker tự chọn path, không cần chmod:

```bash
# Xem path thực của volume trên host
docker volume inspect simshop_postgres_data
docker volume inspect simshop_backend_uploads
```

**Backup data ra file SQL** (hữu ích trước khi reset volume hoặc
chuyển máy):

```bash
./docker/backup.sh backup                       # → ./data/simshop-YYYYMMDD-HHMMSS.sql
./docker/backup.sh backup ./my-backup.sql       # custom path
```

**Restore**:

```bash
./docker/backup.sh restore ./my-backup.sql
```

**Reset toàn bộ data** (XÓA HẾT, dùng cẩn thận):

```bash
docker compose -f docker/compose.yaml down       # dừng containers
docker volume rm simshop_postgres_data           # xóa data Postgres
docker volume rm simshop_backend_uploads         # xóa data uploads
docker compose -f docker/compose.yaml up -d      # khởi động lại (schema tự re-init)
```

## Cloudflare setup (1 lần)

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
sudo docker inspect simshop-web -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
sudo docker inspect simshop-backend -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

Sửa trên dashboard:
- Vào tunnel → tab **Configured** → click hostname → đổi **Service**
  thành `http://backend:8080` (BE) hoặc `http://web:80` (FE).

Cloudflare tunnel auto-reload config, không cần restart container.

### Nếu FE vẫn gọi `localhost:8080` sau khi rebuild

Đây là vấn đề **Cloudflare cache file cũ**. Container `web` đã serve
file mới nhưng Cloudflare CDN cache theo `max-age=1y` của Flutter
asset, ignore `Cache-Control: no-cache` từ nginx.

**Cách fix nhanh** (mỗi lần update FE):

1. Vào Cloudflare dashboard → Caching → **Purge Cache** →
   "Custom Purge" → nhập URL `https://testweb.dvthang.qzz.io/main.dart.js`
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

## Test thường gặp

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

### Rebuild sau khi sửa code

```bash
# Backend (Go)
docker compose -f docker/compose.yaml build backend
docker compose -f docker/compose.yaml up -d backend

# Web (Flutter) — image build lâu (~5 phút cold cache)
docker compose -f docker/compose.yaml build web
docker compose -f docker/compose.yaml up -d web
```

## Cross-OS notes

### Windows

- Đường dẫn file dùng `/` (forward slash) cho Linux-side mount
  (`./initdb`, `./cloudflared-config.yml`) — Docker Desktop tự map
  sang Windows path.
- `docker compose` (không phải `docker-compose`) cần WSL2 backend,
  xem [Docker Desktop WSL2](https://docs.docker.com/desktop/wsl/).
- Line endings trong `.env` không quan trọng — Docker tự parse.

### Linux

- Nếu chạy Docker với `rootless` mode, volume path sẽ nằm trong
  `~/.local/share/docker/volumes/` thay vì `/var/lib/docker/volumes/`.
- Không cần `chmod` UID 999 vì dùng **named volume** (không bind-mount
  vào host filesystem).

## Khi nào cần rebuild image

| Thay đổi                  | Cần rebuild?                              |
| ------------------------- | ----------------------------------------- |
| Sửa Go code trong `backend/` | `build backend` + `up -d backend`     |
| Sửa Flutter code trong `lib/` | `build web` + `up -d web`             |
| Đổi `BE_PUBLIC_URL` / `API_BASE_URL` | `build web` (Flutter build-time only) |
| Đổi `nginx.conf`          | `build web`                                |
| Đổi `POSTGRES_PASSWORD`   | Không — chỉ restart `postgres`            |
| Đổi `ADMIN_PUBLIC_KEY`    | Không — chỉ restart `backend`             |
| Đổi `CF_TUNNEL_TOKEN`     | Không — chỉ restart `cloudflared`         |
| Đổi `IMAGE_TAG`           | `build` + `up -d` để image mới replace     |
| Đổi `initdb/01-schema.sql` | Cẩn thận — chỉ chạy 1 lần volume trống  |

## Troubleshooting

### Backend crash liên tục "db not ready"

Postgres chưa ready hoặc sai `DATABASE_URL`. Kiểm tra:

```bash
docker compose -f docker/compose.yaml logs postgres | tail
docker compose -f docker/compose.yaml exec backend env | grep DATABASE_URL
```

### Cloudflare tunnel "no such host"

`cloudflared-config.yml` chưa thay `<TUNNEL_ID>`, hoặc `CF_TUNNEL_TOKEN`
không khớp tunnel ID trên dashboard. Lấy lại từ dashboard.

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

## License

Cùng license với phần còn lại của dự án.

## Production rollout

Stack đã build sẵn theo hướng production: BE strip debug + non-root,
FE `--release`, Nginx có security headers, mọi service `restart:
unless-stopped`. Phần này tổng hợp checklist + cách cập nhật an toàn.

### Checklist trước khi deploy

- [ ] `POSTGRES_PASSWORD` đã đổi từ placeholder (khác rỗng).
- [ ] `ADMIN_PUBLIC_KEY` đã set (hex 64 chars).
- [ ] `ALLOWED_ORIGIN` đã trỏ về URL Cloudflare của FE.
- [ ] `BE_PUBLIC_URL` đã trỏ về URL Cloudflare của BE.
- [ ] `CF_TUNNEL_TOKEN` đã paste từ Cloudflare dashboard.
- [ ] `IMAGE_TAG` đã set thành git SHA (hoặc build number) — tránh
  `latest` cho rollout để có thể rollback.
- [ ] Cloudflare dashboard đã khai 2 ingress với service URL
  `http://backend:8080` và `http://web:80` (xem phần Cloudflare setup).
- [ ] File `docker/.env` KHÔNG commit (đã có trong `.gitignore`).

### Rolling update (BE / FE)

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

Không cần `down` — compose replace container, volume Postgres + uploads
giữ nguyên.

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
