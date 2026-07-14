#!/usr/bin/env bash
# docker/backup.sh — pg_dump / pg_restore cho simshop Postgres.
#
# Dùng để extract data từ named volume ra file SQL (backup),
# hoặc nạp lại data từ file SQL vào volume (restore).
# Hữu ích khi cần chuyển data giữa máy hoặc trước khi reset volume.
#
# Usage:
#   ./docker/backup.sh backup                       # → ./data/simshop-YYYYMMDD-HHMMSS.sql
#   ./docker/backup.sh backup ./my-backup.sql       # custom path
#   ./docker/backup.sh restore ./my-backup.sql      # restore từ file
#
# Yêu cầu: docker compose đang chạy (containers up). Đọc POSTGRES_USER
# và POSTGRES_DB từ docker/.env hoặc fallback về "simshop".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
ENV_FILE="$SCRIPT_DIR/.env"
ACTION="${1:-backup}"
OUT="${2:-}"

# Mặc định thư mục lưu backup ở repo root, ngoài docker/ để tránh
# volume mount conflict nếu user cấu hình thêm.
DEFAULT_BACKUP_DIR="$SCRIPT_DIR/../data"

# ----- Load .env nếu có -----
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-simshop}"
POSTGRES_DB="${POSTGRES_DB:-simshop}"
COMPOSE=(docker compose -f "$COMPOSE_FILE")

# ----- Helpers -----
log() { echo "[backup] $*"; }
err() { echo "[backup] ERROR: $*" >&2; exit 1; }

# ----- Main -----
case "$ACTION" in
  backup)
    [[ -z "$OUT" ]] && OUT="$DEFAULT_BACKUP_DIR/simshop-$(date +%Y%m%d-%H%M%S).sql"
    mkdir -p "$(dirname "$OUT")"

    log "Backing up database to $OUT"
    "${COMPOSE[@]}" exec -T postgres \
      pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        --no-owner --no-acl --clean --if-exists \
      > "$OUT"

    log "Done. Size: $(du -h "$OUT" | cut -f1)"
    ;;

  restore)
    [[ -z "$OUT" ]] && err "restore requires a file path: $0 restore <file.sql>"
    [[ -f "$OUT" ]] || err "file not found: $OUT"

    log "Restoring from $OUT into $POSTGRES_DB"
    # --clean --if-exists sẽ drop các object trước khi tạo lại.
    # Nếu muốn merge (không drop), dùng: psql ... < "$OUT"
    "${COMPOSE[@]}" exec -T postgres \
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
        -v ON_ERROR_STOP=1 \
      < "$OUT"

    log "Done."
    ;;

  *)
    err "unknown action: $ACTION. Usage: $0 {backup|restore} [path]"
    ;;
esac
