-- PostgreSQL schema for simshop backend
CREATE TABLE IF NOT EXISTS products (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    description   TEXT NOT NULL,
    price         NUMERIC NOT NULL,
    original_price NUMERIC,
    image_url     TEXT NOT NULL,
    category      TEXT NOT NULL,
    store_id      TEXT,
    rating        NUMERIC NOT NULL,
    reviews       INTEGER,
    stock         INTEGER,
    specs         JSONB NOT NULL DEFAULT '[]'::jsonb
);
