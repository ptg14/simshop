-- 01-schema.sql — Postgres schema cho simshop
--
-- File này được mount vào /docker-entrypoint-initdb.d/ của Postgres container.
-- Postgres chỉ chạy các file ở thư mục này MỘT LẦN DUY NHẤT khi volume
-- /var/lib/postgresql/data còn trống. Restart server sau đó KHÔNG re-run →
-- boot cực nhanh (vài giây).
--
-- LƯU Ý QUAN TRỌNG: Khi sửa schema phải sync với
-- backend/internal/db/schema.go::SchemaFor() vì Go runtime dùng
-- nguồn đó để áp các ALTER (nếu cần). Hiện tại SchemaFor() đã
-- idempotent nên cả 2 nguồn chạy cùng nhau an toàn, nhưng khuyến
-- nghị giữ cho khớp.
--
-- Tất cả CREATE TABLE dùng IF NOT EXISTS để an toàn nếu init chạy
-- lại trên volume đã có schema (trường hợp cạnh tranh khi 2 container
-- Postgres cùng khởi động).

-- ===== products =====
CREATE TABLE IF NOT EXISTS products (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    price           DOUBLE PRECISION NOT NULL,
    original_price  DOUBLE PRECISION,
    image_url       TEXT,
    category        TEXT NOT NULL,
    store_id        TEXT,
    rating          DOUBLE PRECISION NOT NULL,
    reviews         INTEGER,
    stock           INTEGER,
    specs           JSONB NOT NULL DEFAULT '[]'::jsonb,
    categories      JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- ===== product_images =====
CREATE TABLE IF NOT EXISTS product_images (
    id          SERIAL PRIMARY KEY,
    product_id  TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    image_url   TEXT NOT NULL,
    ord         INTEGER NOT NULL DEFAULT 0
);

-- ===== product_options =====
CREATE TABLE IF NOT EXISTS product_options (
    id          TEXT PRIMARY KEY,
    product_id  TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    image_urls  JSONB NOT NULL DEFAULT '[]'::jsonb,
    ord         INTEGER NOT NULL DEFAULT 0
);

-- ===== large_categories (parent) =====
CREATE TABLE IF NOT EXISTS large_categories (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- ===== categories (sub) =====
CREATE TABLE IF NOT EXISTS categories (
    id                 SERIAL PRIMARY KEY,
    name               TEXT NOT NULL UNIQUE,
    large_category_id  INTEGER REFERENCES large_categories(id) ON DELETE SET NULL
);

-- ===== store_info (singleton, id=1) =====
CREATE TABLE IF NOT EXISTS store_info (
    id                INTEGER PRIMARY KEY,
    name              TEXT NOT NULL DEFAULT 'simshop',
    description       TEXT NOT NULL DEFAULT '',
    banner_url        TEXT NOT NULL DEFAULT '',
    phone             TEXT NOT NULL DEFAULT '',
    email             TEXT NOT NULL DEFAULT '',
    address           TEXT NOT NULL DEFAULT '',
    google_maps_url   TEXT NOT NULL DEFAULT ''
);

-- Seed singleton row ngay khi init để API GET không 404
INSERT INTO store_info (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ===== articles (editorial) =====
CREATE TABLE IF NOT EXISTS articles (
    id               TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    body_markdown    TEXT NOT NULL DEFAULT '',
    cover_image_url  TEXT NOT NULL DEFAULT '',
    product_ids      JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at       BIGINT NOT NULL
);

-- ===== banner_slides =====
CREATE TABLE IF NOT EXISTS banner_slides (
    id          TEXT PRIMARY KEY,
    image_url   TEXT NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    subtitle    TEXT NOT NULL DEFAULT '',
    ord         INTEGER NOT NULL DEFAULT 0,
    article_id  TEXT REFERENCES articles(id) ON DELETE SET NULL
);

-- ===== events (time-boxed promotions) =====
CREATE TABLE IF NOT EXISTS events (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL DEFAULT '',
    end_time        BIGINT,
    discount_type   TEXT NOT NULL,           -- 'percent' | 'fixed'
    discount_value  DOUBLE PRECISION NOT NULL,
    product_ids     JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at      BIGINT NOT NULL
);

-- ===== indexes =====
CREATE INDEX IF NOT EXISTS idx_events_end_time ON events(end_time);

-- GIN index cho JSONB containment (@>) — backend dùng
-- dialect.ProductIDsContains() với pgx; chỉ áp dụng cho Postgres.
CREATE INDEX IF NOT EXISTS idx_events_product_ids_gin ON events USING GIN (product_ids);
