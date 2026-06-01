CREATE TABLE IF NOT EXISTS product (
    id          BIGSERIAL,
    name        VARCHAR(255) NOT NULL,
    picture_url VARCHAR(1024)
);

CREATE TABLE IF NOT EXISTS product_info (
    product_id BIGINT,
    price      DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS orders (
    id     BIGSERIAL,
    status VARCHAR(64) NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS orders_date (
    order_id   BIGINT,
    status     VARCHAR(64),
    changed_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_product (
    order_id   BIGINT,
    product_id BIGINT,
    quantity   INTEGER NOT NULL DEFAULT 1
);
