CREATE TABLE IF NOT EXISTS reviews (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    rating INTEGER NOT NULL,
    skin_type TEXT NOT NULL,
    duration TEXT NOT NULL,
    reaction TEXT NOT NULL,
    notes TEXT NOT NULL,
    created_at TEXT NOT NULL,
    hidden INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_reviews_user_created
    ON reviews(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    brand TEXT NOT NULL,
    price REAL,
    currency TEXT NOT NULL,
    image_url TEXT NOT NULL,
    product_url TEXT NOT NULL,
    skin_types TEXT NOT NULL,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_products_created
    ON products(created_at DESC);
