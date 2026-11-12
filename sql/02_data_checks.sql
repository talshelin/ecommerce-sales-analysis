/* 02_data_checks.sql
   Checks what one row means in each table and which columns identify a row.
*/

USE Olist;
GO

/* ---------- Grain: what does one row represent? ---------- */

-- One row = one order
SELECT TOP 10 * FROM dbo.orders;

-- One row = one item line in an order (no quantity column: 3 units = 3 rows)
SELECT TOP 10 * FROM dbo.order_items;

-- Example: an order with 3 or more item lines
SELECT order_id, order_item_id, product_id, price
FROM dbo.order_items
WHERE order_id = (SELECT TOP 1 order_id FROM dbo.order_items WHERE order_item_id = 3)
ORDER BY order_item_id;

-- One row = the customer record of one order.
-- A new customer_id is created for every order; the person is customer_unique_id.
SELECT TOP 10 * FROM dbo.customers;

-- Example: one person with 3 or more customer_ids
SELECT customer_unique_id, customer_id, customer_city
FROM dbo.customers
WHERE customer_unique_id = (SELECT TOP 1 customer_unique_id
                            FROM dbo.customers
                            GROUP BY customer_unique_id
                            HAVING COUNT(*) >= 3);

-- One row = one payment of an order (e.g. credit card + voucher)
SELECT TOP 10 * FROM dbo.payments;

-- Example: an order paid in 2 or more parts
SELECT order_id, payment_sequential, payment_type, payment_value
FROM dbo.payments
WHERE order_id = (SELECT TOP 1 order_id FROM dbo.payments WHERE payment_sequential = 2)
ORDER BY payment_sequential;

-- One row = one review linked to an order
SELECT TOP 10 * FROM dbo.reviews;

-- Example: an order with more than one review
SELECT order_id, review_id, review_score, review_creation_date
FROM dbo.reviews
WHERE order_id = (SELECT TOP 1 order_id
                  FROM dbo.reviews
                  GROUP BY order_id
                  HAVING COUNT(*) > 1);

-- One row = one product / one seller / one category
SELECT TOP 10 * FROM dbo.products;
SELECT TOP 10 * FROM dbo.sellers;
SELECT TOP 10 * FROM dbo.category_translation;


/* ---------- Keys: which columns identify a row? ----------
   A column is a key when COUNT(*) = COUNT(DISTINCT column).
   For two columns: COUNT(DISTINCT CONCAT(a, '-', b)).
*/

-- orders: order_id
SELECT COUNT(*)                 AS rows_total,
       COUNT(DISTINCT order_id) AS unique_orders
FROM dbo.orders;
-- 99,441 = 99,441 -> key

-- order_items: order_id + order_item_id
SELECT COUNT(*)                                             AS rows_total,
       COUNT(DISTINCT order_id)                             AS unique_orders,
       COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) AS unique_pairs
FROM dbo.order_items;
-- 112,650 rows = 112,650 pairs -> key
-- 98,666 orders vs 99,441 in orders -> 775 orders have no items

-- customers: customer_id vs customer_unique_id
SELECT COUNT(*)                           AS rows_total,
       COUNT(DISTINCT customer_id)        AS unique_customer_ids,
       COUNT(DISTINCT customer_unique_id) AS unique_persons
FROM dbo.customers;
-- 99,441 customer_ids, 96,096 persons -> customers are counted by customer_unique_id

-- payments: order_id + payment_sequential
SELECT COUNT(*)                                                  AS rows_total,
       COUNT(DISTINCT order_id)                                  AS unique_orders,
       COUNT(DISTINCT CONCAT(order_id, '-', payment_sequential)) AS unique_pairs
FROM dbo.payments;
-- 103,886 rows = 103,886 pairs -> key
-- 99,440 orders vs 99,441 in orders -> 1 order has no payment

-- reviews: neither column alone is a key
SELECT COUNT(*)                                         AS rows_total,
       COUNT(DISTINCT review_id)                        AS unique_review_ids,
       COUNT(DISTINCT order_id)                         AS unique_orders,
       COUNT(DISTINCT CONCAT(review_id, '-', order_id)) AS unique_pairs
FROM dbo.reviews;
-- 99,224 rows = 99,224 pairs -> review_id + order_id is the key
-- the same review can belong to several orders, and an order can have several reviews

-- Example: one review linked to several orders
SELECT review_id, order_id, review_score
FROM dbo.reviews
WHERE review_id = (SELECT TOP 1 review_id
                   FROM dbo.reviews
                   GROUP BY review_id
                   HAVING COUNT(DISTINCT order_id) > 1);

-- products, sellers, category_translation
SELECT 'products' AS table_name, COUNT(*) AS rows_total, COUNT(DISTINCT product_id) AS unique_keys FROM dbo.products
UNION ALL SELECT 'sellers', COUNT(*), COUNT(DISTINCT seller_id) FROM dbo.sellers
UNION ALL SELECT 'category_translation', COUNT(*), COUNT(DISTINCT product_category_name) FROM dbo.category_translation;
-- all equal -> single-column keys


/* ---------- Integrity: do the tables match each other? ----------
   LEFT JOIN + IS NULL keeps the rows on the left that have no match on the right.
*/

-- Orders without any item line, by status
SELECT o.order_status,
       COUNT(*) AS orders_without_items
FROM dbo.orders AS o
LEFT JOIN dbo.order_items AS oi
       ON oi.order_id = o.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;
-- unavailable 603 | canceled 164 | created 5 | invoiced 2 | shipped 1 (total 775)
-- 767 are expected (never fulfilled); 3 invoiced/shipped orders without items are inconsistent

-- Orders without a payment
SELECT o.order_id, o.order_status, o.order_purchase_timestamp
FROM dbo.orders AS o
LEFT JOIN dbo.payments AS p
       ON p.order_id = o.order_id
WHERE p.order_id IS NULL;
-- 1 order: delivered, 2016-09-15 (the first weeks of the data)
-- inconsistent (a delivered order should be paid), but a single row

-- Orders without a review, by status
SELECT o.order_status,
       COUNT(*) AS orders_without_review
FROM dbo.orders AS o
LEFT JOIN dbo.reviews AS r
       ON r.order_id = o.order_id
WHERE r.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_review DESC;
-- delivered 646 | shipped 75 | canceled 20 | unavailable 14 | processing 6 | invoiced 5 | created 2
-- total 768 = 99,441 orders - 98,673 orders in reviews
-- reviews are optional, so this is expected; review scores describe only reviewed orders

-- Every product in order_items exists in products
SELECT COUNT(*) AS items_without_product
FROM dbo.order_items AS oi
LEFT JOIN dbo.products AS p
       ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;
-- 0

-- Every seller in order_items exists in sellers
SELECT COUNT(*) AS items_without_seller
FROM dbo.order_items AS oi
LEFT JOIN dbo.sellers AS s
       ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;
-- 0

-- Every order has a customer record
SELECT COUNT(*) AS orders_without_customer
FROM dbo.orders AS o
LEFT JOIN dbo.customers AS c
       ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;
-- 0

-- Product categories without an English name
SELECT p.product_category_name,
       COUNT(*) AS products
FROM dbo.products AS p
LEFT JOIN dbo.category_translation AS ct
       ON ct.product_category_name = p.product_category_name
WHERE ct.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY products DESC;
-- NULL 610 | portateis_cozinha_e_preparadores_de_alimentos 10 | pc_gamer 3
-- 610 products have no category at all; 2 real categories are missing from the translation table

/* Integrity summary
   - Every item has a known product and seller; every order has a customer record.
   - 775 orders have no items (767 unavailable or canceled), 1 delivered order has no payment,
     768 orders have no review.
   - 610 products have no category and 2 categories have no English name.
*/


/* ---------- Completeness: where are values missing, and why? ----------
   COUNT(column) skips NULLs, so COUNT(*) - COUNT(column) = number of NULLs.
*/

-- orders: missing dates, in the order of the order journey
SELECT COUNT(*)                                        AS total_orders,
       COUNT(*) - COUNT(order_purchase_timestamp)      AS null_purchase,
       COUNT(*) - COUNT(order_approved_at)             AS null_approved,
       COUNT(*) - COUNT(order_delivered_carrier_date)  AS null_carrier,
       COUNT(*) - COUNT(order_delivered_customer_date) AS null_delivered,
       COUNT(*) - COUNT(order_estimated_delivery_date) AS null_estimated
FROM dbo.orders;
-- 99,441 | 0 | 160 | 1,783 | 2,965 | 0
-- purchase and estimated dates are always set (NOT NULL in the table)
-- the other gaps grow along the journey: orders that stop early (canceled, in transit)
-- never get the later dates

-- orders without a delivery date, by status
SELECT order_status,
       COUNT(*) AS orders_without_delivery_date
FROM dbo.orders
WHERE order_delivered_customer_date IS NULL
GROUP BY order_status
ORDER BY orders_without_delivery_date DESC;
-- shipped 1,107 | canceled 619 | unavailable 609 | invoiced 314 | processing 301
-- created 5 | delivered 8 | approved 2 (total 2,965)
-- 2,957 are expected (the order never reached the customer);
-- 8 delivered orders have no delivery date -> cannot be used for delivery time

-- reviews: share of reviews without a text message
-- 100.0 avoids integer division; the brackets make the subtraction happen first
SELECT COUNT(*)                                                      AS total_reviews,
       COUNT(*) - COUNT(review_comment_message)                      AS reviews_without_text,
       100.0 * (COUNT(*) - COUNT(review_comment_message)) / COUNT(*) AS pct_without_text
FROM dbo.reviews;
-- 99,224 | 58,256 | 58.7%
-- most reviews have only a score -> satisfaction is measured with review_score

-- products: missing category and size information
SELECT COUNT(*)                                 AS total_products,
       COUNT(*) - COUNT(product_category_name)  AS null_category,
       COUNT(*) - COUNT(product_photos_qty)     AS null_photos,
       COUNT(*) - COUNT(product_weight_g)       AS null_weight
FROM dbo.products;
-- 32,951 | 610 | 610 | 2
-- the same 610 products have no category, name length, description length or photo count

-- Columns used in the analysis: no missing values expected
SELECT COUNT(*) - COUNT(review_score)  AS null_review_score  FROM dbo.reviews;
SELECT COUNT(*) - COUNT(payment_type)  AS null_payment_type,
       COUNT(*) - COUNT(payment_value) AS null_payment_value FROM dbo.payments;
SELECT COUNT(*) - COUNT(customer_unique_id) AS null_person,
       COUNT(*) - COUNT(customer_state)     AS null_state    FROM dbo.customers;
SELECT COUNT(*) - COUNT(price)         AS null_price,
       COUNT(*) - COUNT(freight_value) AS null_freight,
       COUNT(*) - COUNT(product_id)    AS null_product,
       COUNT(*) - COUNT(seller_id)     AS null_seller    FROM dbo.order_items;
-- all 0


/* ---------- Validity: are the values possible? ----------
   Listing every value of a column shows values that should not be there.
*/

-- Order status distribution
SELECT order_status,
       COUNT(*)                                                    AS orders,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.orders), 2) AS pct_orders
FROM dbo.orders
GROUP BY order_status
ORDER BY orders DESC;
-- delivered 96,478 (97.02%) | shipped 1,107 | canceled 625 | unavailable 609
-- invoiced 314 | processing 301 | created 5 | approved 2
-- compared with the missing delivery dates by status:
-- 625 canceled orders but only 619 without a delivery date
-- -> 6 canceled orders have a delivery date (inconsistent)
