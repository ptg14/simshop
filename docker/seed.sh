#!/usr/bin/env bash
# docker/seed.sh — Idempotent placeholder seeder cho simshop Postgres.
#
# Mục đích: khi volume Postgres rỗng (lần đầu deploy hoặc sau reset),
# insert một bộ data placeholder đủ để FE render không còn skeleton
# trống. KHÔNG phải fixtures chính thức — dự án cố tình không seed
# fixtures (xem backend/cmd/seed/main.go:1-3) vì data thật do admin tạo
# qua UI. File này chỉ tạo data dạng placeholder để verify deployment
# hoạt động đầu cuối (FE render, BE serialize, DB lưu).
#
# Idempotent: check từng bảng riêng — nếu rỗng mới insert, nếu có
# data thì skip bảng đó. Cho phép partial-seed: admin tạo 1 phần data
# qua UI thì ta chỉ fill phần còn lại. store_info là singleton
# (id=1), luôn có sẵn 1 row từ 01-schema.sql → không seed lại, chỉ
# UPDATE các field nếu cần.
#
# Usage:
#   ./docker/seed.sh                    # dùng container đang chạy
#   POSTGRES_DB=other ./docker/seed.sh  # custom db
#
# Env defaults (override nếu cần):
#   PGUSER=simshop  PGDATABASE=simshop
#   POSTGRES_PASSWORD (bắt buộc — lấy từ docker/.env nếu thiếu)
#   POSTGRES_CONTAINER (default: simshop-postgres)

set -euo pipefail

# ---------- Resolve config ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${POSTGRES_PASSWORD:-}" && -f "$SCRIPT_DIR/.env" ]]; then
  POSTGRES_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' "$SCRIPT_DIR/.env" | cut -d= -f2-)
  export POSTGRES_PASSWORD
fi
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required (set via env or docker/.env)}"

CONTAINER="${POSTGRES_CONTAINER:-simshop-postgres}"
PGUSER="${PGUSER:-simshop}"
PGDATABASE="${PGDATABASE:-simshop}"

# ---------- Helpers ----------
# run_psql: chạy 1 câu SQL, trả về scalar (text mode).
run_psql() {
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER" \
    psql -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -t -A -c "$1"
}

# run_sql: chạy nhiều câu SQL (heredoc body), bỏ output.
# Cần `-i` (keep stdin) + heredoc pipe vì `<<<` here-string không
# attach stdin của docker exec. `-c` chỉ chạy được 1 statement.
run_sql() {
  docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER" \
    psql -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -q \
    <<<"$1" >/dev/null
}

# ---------- Per-table insert (idempotent) ----------
# Mỗi hàm check count bảng trước; nếu > 0 → skip, ngược lại insert.
# ON CONFLICT DO NOTHING bảo vệ nếu idempotency check miss edge case
# (race với admin UI đang tạo row cùng lúc).

insert_large_categories() {
  local n
  n=$(run_psql "SELECT count(*) FROM large_categories;")
  if [[ "$n" -gt 0 ]]; then
    echo "  large_categories: skip ($n rows)"
    return
  fi
  echo "  large_categories: insert"
  run_sql "$(cat <<'EOSQL'
INSERT INTO large_categories (id, name) VALUES
  (1, 'Thời trang'),
  (2, 'Điện tử')
ON CONFLICT (id) DO NOTHING;
-- Sync sequence với MAX(id) để INSERT sau (không chỉ định id) không
-- bị conflict với giá trị seed.
SELECT setval(pg_get_serial_sequence('large_categories','id'),
              (SELECT MAX(id) FROM large_categories));
EOSQL
)"
}

insert_categories() {
  local n
  n=$(run_psql "SELECT count(*) FROM categories;")
  if [[ "$n" -gt 0 ]]; then
    echo "  categories: skip ($n rows)"
    return
  fi
  echo "  categories: insert"
  run_sql "$(cat <<'EOSQL'
INSERT INTO categories (name, large_category_id) VALUES
  ('Áo thun',     1),
  ('Áo',          1),
  ('Quần áo',     1),
  ('Tai nghe',    2),
  ('Phụ kiện',    2)
ON CONFLICT (name) DO NOTHING;
EOSQL
)"
}

insert_articles() {
  local n
  n=$(run_psql "SELECT count(*) FROM articles;")
  if [[ "$n" -gt 0 ]]; then
    echo "  articles: skip ($n rows)"
    return
  fi
  echo "  articles: insert"
  run_sql "$(cat <<'EOSQL'
INSERT INTO articles (id, title, body_markdown, cover_image_url,
                      product_ids, created_at) VALUES
  ('smoke-art', 'Bộ sưu tập mới', 'Placeholder article body.',
   '', '[]'::jsonb, 1782282707)
ON CONFLICT (id) DO NOTHING;
EOSQL
)"
}

insert_products() {
  local n
  n=$(run_psql "SELECT count(*) FROM products;")
  if [[ "$n" -gt 0 ]]; then
    echo "  products: skip ($n rows)"
    return
  fi
  echo "  products: insert"
  run_sql "$(cat <<'EOSQL'
-- image_url rỗng — admin upload ảnh thật qua dashboard sau.
-- specs/categories là JSONB (Postgres), array literal cần cast ::jsonb.
INSERT INTO products (id, name, description, price, original_price,
                      image_url, category, store_id, rating, reviews,
                      stock, specs, categories) VALUES
  ('3d34cfad-a63e-454b-a69a-e102e27754dd',
   'Tai nghe M1', 'Tai nghe bluetooth giá rẻ, pin 8 giờ.',
   123000, NULL, '', 'Tai nghe', 'store1', 0, 0, 40,
   '[]'::jsonb, '["Tai nghe"]'::jsonb),
  ('8074b786-7088-4136-bd6c-aa012f5b1054',
   'Áo phông', 'Áo phông cotton 100%, form rộng.',
   340000, NULL, '', 'Áo thun', 'store1', 0, 0, 20,
   '["Chất liệu: Cotton"]'::jsonb,
   '["Áo thun","Áo","Quần áo"]'::jsonb),
  ('1a043529-7608-4e2c-9de8-e6d15a09195c',
   'Tai nghe chống ồn', 'Tai nghe chống ồn chủ động ANC, pin 35 giờ.',
   256000, NULL, '', 'Tai nghe', 'store1', 0, 0, 0,
   '["Chống ồn: ANC","Pin: 35 giờ"]'::jsonb,
   '["Tai nghe"]'::jsonb)
ON CONFLICT (id) DO NOTHING;
EOSQL
)"
}

insert_banner_slides() {
  local n
  n=$(run_psql "SELECT count(*) FROM banner_slides;")
  if [[ "$n" -gt 0 ]]; then
    echo "  banner_slides: skip insert ($n rows); backfilling image_url for rows that are empty"
    # Backfill image_url rỗng → picsum placeholder để carousel render.
    # UPDATE thay vì INSERT vì rows đã tồn tại. Nếu admin đã set URL
    # thật → giữ nguyên (WHERE image_url = '' OR image_url IS NULL).
    run_sql "$(cat <<'EOSQL'
UPDATE banner_slides
   SET image_url = CASE id
     WHEN 'smoke-1'           THEN 'https://picsum.photos/seed/simshop-slide-1/1200/400'
     WHEN '1782894127659000'  THEN 'https://picsum.photos/seed/simshop-slide-2/1200/400'
     ELSE image_url
   END
 WHERE image_url = '' OR image_url IS NULL;
EOSQL
)"
    return
  fi
  echo "  banner_slides: insert"
  run_sql "$(cat <<'EOSQL'
-- image_url picsum.photos (deterministic seed) để carousel có ảnh
-- render thật thay vì trống. Admin upload ảnh thật sau.
INSERT INTO banner_slides (id, image_url, title, subtitle, ord,
                           article_id) VALUES
  ('smoke-1', 'https://picsum.photos/seed/simshop-slide-1/1200/400', 'Placeholder banner 1', 'Demo slide', 0, NULL),
  ('1782894127659000', 'https://picsum.photos/seed/simshop-slide-2/1200/400', '', '', 1, NULL)
ON CONFLICT (id) DO NOTHING;
EOSQL
)"
}

# store_info là singleton (id=1), luôn có sẵn 1 row từ 01-schema.sql.
# UPDATE các field placeholder để API GET trả về content thay vì rỗng.
# QUAN TRỌNG: banner_url KHÔNG được để rỗng — SiteInfoFooter
# (lib/widgets/site_info_footer.dart) chỉ render card khi
# bannerUrl.isNotEmpty, và toàn bộ hit-zone 7-tap admin entry
# nằm trên banner đó. Nếu banner rỗng → footer không hiển thị →
# không có cách nào vào admin dashboard (trừ khi admin tự upload
# banner trước, nhưng đó là vấn đề gà-quả-trứng).
# Dùng picsum.photos URL placeholder (1500×500, deterministic seed
# để luôn ra cùng ảnh) — chỉ để có hit zone, admin sẽ upload
# ảnh thật sau.
update_store_info() {
  echo "  store_info: update (singleton)"
  run_sql "$(cat <<'EOSQL'
UPDATE store_info SET
  name = 'simshop',
  description = 'Cửa hàng trực tuyến — sản phẩm thời trang & điện tử',
  banner_url = 'https://picsum.photos/seed/simshop-banner/1500/500',
  phone = '+84 000 000 000',
  email = 'contact@simshop.example',
  address = 'Việt Nam',
  google_maps_url = ''
WHERE id = 1;
EOSQL
)"
}

# ---------- Main ----------
echo "seed: per-table check + insert (idempotent)..."
insert_large_categories
insert_categories
insert_articles
insert_products
insert_banner_slides
update_store_info

echo "seed: done. Final state:"
run_psql "SELECT 'products' AS t, count(*) FROM products
UNION ALL SELECT 'banner_slides', count(*) FROM banner_slides
UNION ALL SELECT 'large_categories', count(*) FROM large_categories
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'articles', count(*) FROM articles
UNION ALL SELECT 'store_info', count(*) FROM store_info;" | \
  awk -F'|' '{printf "  %-20s %s\n", $1, $2}'
