ALTER TABLE product ADD COLUMN price DOUBLE PRECISION DEFAULT 0.0;
ALTER TABLE orders  ADD COLUMN date_created DATE DEFAULT CURRENT_DATE;

ALTER TABLE product       ADD PRIMARY KEY (id);
ALTER TABLE orders        ADD PRIMARY KEY (id);
ALTER TABLE order_product ADD PRIMARY KEY (order_id, product_id);

ALTER TABLE order_product
    ADD CONSTRAINT fk_order_product_order   FOREIGN KEY (order_id)   REFERENCES orders(id),
    ADD CONSTRAINT fk_order_product_product FOREIGN KEY (product_id) REFERENCES product(id),
    ADD CONSTRAINT chk_quantity_positive    CHECK (quantity > 0);

DROP TABLE product_info;
DROP TABLE orders_date;
