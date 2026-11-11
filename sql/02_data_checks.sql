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
