-- PostgreSQL schema for simshop backend
CREATE TABLE IF NOT EXISTS products (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    description   TEXT NOT NULL,
    price         NUMERIC NOT NULL,
    original_price NUMERIC,
    image_url     TEXT,
    category      TEXT NOT NULL,
    store_id      TEXT,
    rating        NUMERIC NOT NULL,
    reviews       INTEGER,
    stock         INTEGER,
    specs         JSONB NOT NULL DEFAULT '[]'::jsonb
);

CREATE TABLE IF NOT EXISTS product_images (
    id SERIAL PRIMARY KEY,
    product_id TEXT NOT NULL,
    image_url TEXT NOT NULL,
    ord INTEGER NOT NULL DEFAULT 0
);

-- Product options/variants table. Each option may reference one image_url (optional).
CREATE TABLE IF NOT EXISTS product_options (
    id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL,
    name TEXT NOT NULL,
    image_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
    ord INTEGER NOT NULL DEFAULT 0
);

-- Large categories (parent categories)
CREATE TABLE IF NOT EXISTS large_categories (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- Subcategories (existing categories) now reference a large category.
CREATE TABLE IF NOT EXISTS categories (
    id               SERIAL PRIMARY KEY,
    name             TEXT NOT NULL UNIQUE,
    large_category_id INTEGER,
    FOREIGN KEY (large_category_id) REFERENCES large_categories(id) ON DELETE SET NULL
);

-- Events: time-boxed promotions. product_ids is a JSON array of product
-- IDs the discount applies to (no separate join table — same pattern as
-- articles.product_ids). end_time is nullable; a NULL means the event
-- never expires (the admin UI always sets one).
CREATE TABLE IF NOT EXISTS events (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL DEFAULT '',
    end_time      INTEGER,
    discount_type TEXT NOT NULL,             -- 'percent' | 'fixed'
    discount_value REAL NOT NULL,
    product_ids   TEXT NOT NULL DEFAULT '[]',
    created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_end_time ON events(end_time);
