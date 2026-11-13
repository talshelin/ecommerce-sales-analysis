/* 02_data_checks.sql
   Data checks before the analysis: keys, links between tables, missing values,
   invalid values, period covered, outliers and consistency.
*/

USE Olist;
GO


/* ===== Keys ===== */

-- Which columns identify a row in the tables without a primary key?
SELECT 'order_items' AS table_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) AS unique_keys
FROM dbo.order_items
UNION ALL
SELECT 'payments', COUNT(*), COUNT(DISTINCT CONCAT(order_id, '-', payment_sequential))
FROM dbo.payments
UNION ALL
SELECT 'reviews', COUNT(*), COUNT(DISTINCT CONCAT(review_id, '-', order_id))
FROM dbo.reviews;
-- All three match: order_id + order_item_id, order_id + payment_sequential
-- and review_id + order_id are the keys.

-- How many real customers are there?
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS customers
FROM dbo.customers;
-- 99,441 customer_ids but 96,096 people: a new customer_id is created for every order,
-- so customers are counted with customer_unique_id.


/* ===== Links between tables ===== */

-- Orders without any item, by status
SELECT o.order_status,
       COUNT(*) AS orders_without_items
FROM dbo.orders AS o
LEFT JOIN dbo.order_items AS oi
       ON oi.order_id = o.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;
-- 775 orders, almost all unavailable (603) or canceled (164): orders that never happened.

-- Orders without a payment or a review
SELECT (SELECT COUNT(*) FROM dbo.orders AS o
        WHERE NOT EXISTS (SELECT 1 FROM dbo.payments AS p WHERE p.order_id = o.order_id)) AS orders_without_payment,
       (SELECT COUNT(*) FROM dbo.orders AS o
        WHERE NOT EXISTS (SELECT 1 FROM dbo.reviews AS r WHERE r.order_id = o.order_id))  AS orders_without_review;
-- 1 order has no payment. 768 orders have no review, which is normal: reviews are optional.

-- Product categories without an English name
SELECT p.product_category_name,
       COUNT(*) AS products
FROM dbo.products AS p
LEFT JOIN dbo.category_translation AS ct
       ON ct.product_category_name = p.product_category_name
WHERE ct.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY products DESC;
-- 610 products have no category at all; 2 small categories (13 products) have no translation.
-- Every product, seller and customer in the other tables exists in its own table.


/* ===== Missing values ===== */

-- Missing order dates, in the order of the order journey
SELECT COUNT(*) - COUNT(order_purchase_timestamp)      AS no_purchase_date,
       COUNT(*) - COUNT(order_approved_at)             AS no_approval_date,
       COUNT(*) - COUNT(order_delivered_carrier_date)  AS no_carrier_date,
       COUNT(*) - COUNT(order_delivered_customer_date) AS no_delivery_date,
       COUNT(*) - COUNT(order_estimated_delivery_date) AS no_estimated_date
FROM dbo.orders;
-- 0 | 160 | 1,783 | 2,965 | 0
-- The gaps grow along the journey: canceled orders and orders still on the way
-- never get the later dates, so most gaps are expected.

-- Reviews without a text message
SELECT ROUND(100.0 * (COUNT(*) - COUNT(review_comment_message)) / COUNT(*), 1) AS pct_reviews_without_text
FROM dbo.reviews;
-- 58.7%: most customers leave only a score, so satisfaction is measured with review_score.


/* ===== Invalid values ===== */

-- Order status
SELECT order_status,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.orders), 2) AS pct_orders
FROM dbo.orders
GROUP BY order_status
ORDER BY orders DESC;
-- 97% of orders are delivered; the rest are shipped, canceled, unavailable or still in process.

-- Payment type
SELECT payment_type,
       COUNT(*)           AS payments,
       SUM(payment_value) AS total_value
FROM dbo.payments
GROUP BY payment_type
ORDER BY payments DESC;
-- Credit card is 74% of payments. "not_defined" is not a real method: 3 payments of 0.

-- Review score
SELECT review_score,
       COUNT(*) AS reviews,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.reviews), 2) AS pct_reviews
FROM dbo.reviews
GROUP BY review_score
ORDER BY review_score;
-- All scores are 1-5. 58% give 5, but 11.5% give 1: more than 2 and 3 together,
-- so an average score would hide the unhappy customers.


/* ===== Period covered ===== */

-- Orders per month, including months without any order
-- (a recursive CTE builds the full list of months, then the counts are joined to it)
WITH months AS (
    SELECT DATETRUNC(month, MIN(order_purchase_timestamp)) AS month_start,
           DATETRUNC(month, MAX(order_purchase_timestamp)) AS last_month
    FROM dbo.orders
    UNION ALL
    SELECT DATEADD(month, 1, month_start), last_month
    FROM months
    WHERE month_start < last_month
),
monthly_orders AS (
    SELECT DATETRUNC(month, order_purchase_timestamp) AS order_month,
           COUNT(*) AS orders
    FROM dbo.orders
    GROUP BY DATETRUNC(month, order_purchase_timestamp)
)
SELECT m.month_start AS order_month,
       COALESCE(mo.orders, 0) AS orders
FROM months AS m
LEFT JOIN monthly_orders AS mo
       ON mo.order_month = m.month_start
ORDER BY m.month_start;
-- Data runs from Sep 2016 to Oct 2018. 2016 has very few orders (none in Nov 2016),
-- and Sep-Oct 2018 have only 20, almost all canceled.
-- Months used for trends: Jan 2017 to Aug 2018. Nov 2017 peaks because of Black Friday.


/* ===== Outliers ===== */

-- Price, freight and payment value: typical value vs extremes
SELECT DISTINCT 'price' AS measure,
       MIN(price) OVER () AS min_value,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) OVER () AS median_value,
       AVG(price) OVER () AS avg_value,
       MAX(price) OVER () AS max_value
FROM dbo.order_items
UNION ALL
SELECT DISTINCT 'freight',
       MIN(freight_value) OVER (),
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY freight_value) OVER (),
       AVG(freight_value) OVER (),
       MAX(freight_value) OVER ()
FROM dbo.order_items
UNION ALL
SELECT DISTINCT 'payment',
       MIN(payment_value) OVER (),
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY payment_value) OVER (),
       AVG(payment_value) OVER (),
       MAX(payment_value) OVER ()
FROM dbo.payments;
-- Price: median 75, average 121, max 6,735. Freight: median 16, average 20.
-- Payment: median 100, average 154. All three are pulled up by a few large values,
-- so the median is used as the typical value.

-- The 10 most expensive items
SELECT TOP 10
       COALESCE(ct.product_category_name_english, p.product_category_name) AS category,
       o.order_status,
       oi.price
FROM dbo.order_items AS oi
JOIN dbo.products AS p ON p.product_id = oi.product_id
JOIN dbo.orders   AS o ON o.order_id   = oi.order_id
LEFT JOIN dbo.category_translation AS ct
       ON ct.product_category_name = p.product_category_name
ORDER BY oi.price DESC;
-- Computers, appliances, art, instruments, consoles; all delivered.
-- These are real purchases, so they stay in the analysis.


/* ===== Consistency ===== */

-- Do items (price + freight) match payments for each order?
-- Each table is first summarised to one row per order, then joined,
-- so that orders with several items and several payments are not counted twice.
WITH items_per_order AS (
    SELECT order_id, SUM(price + freight_value) AS items_total
    FROM dbo.order_items
    GROUP BY order_id
),
payments_per_order AS (
    SELECT order_id, SUM(payment_value) AS payments_total
    FROM dbo.payments
    GROUP BY order_id
)
SELECT CASE
           WHEN p.payments_total IS NULL                    THEN 'no payment'
           WHEN ABS(p.payments_total - i.items_total) <= 1  THEN 'match'
           WHEN p.payments_total > i.items_total            THEN 'paid more'
           ELSE                                                  'paid less'
       END AS result,
       COUNT(*) AS orders
FROM items_per_order AS i
LEFT JOIN payments_per_order AS p
       ON p.order_id = i.order_id
GROUP BY CASE
           WHEN p.payments_total IS NULL                    THEN 'no payment'
           WHEN ABS(p.payments_total - i.items_total) <= 1  THEN 'match'
           WHEN p.payments_total > i.items_total            THEN 'paid more'
           ELSE                                                  'paid less'
       END
ORDER BY orders DESC;
-- 99.75% of orders match within 1 BRL. The two tables agree.

-- Are the order dates in a logical order?
SELECT SUM(CASE WHEN order_approved_at             < order_purchase_timestamp     THEN 1 ELSE 0 END) AS approved_before_purchase,
       SUM(CASE WHEN order_delivered_carrier_date  < order_approved_at            THEN 1 ELSE 0 END) AS carrier_before_approved,
       SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END) AS delivered_before_carrier,
       SUM(CASE WHEN order_delivered_customer_date < order_purchase_timestamp     THEN 1 ELSE 0 END) AS delivered_before_purchase
FROM dbo.orders;
-- 0 | 1,359 | 23 | 0
-- No order is delivered before it was placed, so delivery time is never negative.

-- Does the status agree with the dates?
SELECT SUM(CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL     THEN 1 ELSE 0 END) AS delivered_without_delivery_date,
       SUM(CASE WHEN order_status = 'delivered' AND order_approved_at IS NULL                 THEN 1 ELSE 0 END) AS delivered_without_approval_date,
       SUM(CASE WHEN order_status = 'delivered' AND order_delivered_carrier_date IS NULL      THEN 1 ELSE 0 END) AS delivered_without_carrier_date,
       SUM(CASE WHEN order_status = 'canceled'  AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS canceled_with_delivery_date
FROM dbo.orders;
-- 8 | 14 | 2 | 6: 30 orders in total. They stay in the data and are left out
-- only of the measures they would distort (e.g. delivery time).
