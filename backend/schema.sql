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
