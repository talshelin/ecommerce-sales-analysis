/* 03_clean_views.sql
   Analysis-ready views. The raw tables are never changed:
   cleaning rules live in the views, and problem records are flagged, not deleted.
*/

USE Olist;
GO


/* ===== vw_orders: one row = one order ===== */

-- Order items, payments and reviews can have several rows per order.
-- Each is first summarised to one row per order, then joined, so totals are not counted twice.
CREATE OR ALTER VIEW dbo.vw_orders AS
WITH items_per_order AS (
    SELECT order_id,
           COUNT(*)           AS item_count,
           SUM(price)         AS items_revenue,
           SUM(freight_value) AS freight_total
    FROM dbo.order_items
    GROUP BY order_id
),
payments_per_order AS (
    SELECT order_id,
           SUM(payment_value)        AS payment_total,
           MAX(payment_installments) AS max_installments
    FROM dbo.payments
    GROUP BY order_id
),
ranked_reviews AS (
    -- An order can have more than one review: the newest one is kept.
    -- review_creation_date has no time, so review_answer_timestamp breaks ties.
    SELECT order_id,
           review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_creation_date DESC,
                                       review_answer_timestamp DESC) AS review_rank
    FROM dbo.reviews
),
latest_review AS (
    SELECT order_id, review_score
    FROM ranked_reviews
    WHERE review_rank = 1
)
SELECT
    -- identity
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    -- dates
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATETRUNC(month, o.order_purchase_timestamp) AS order_month,
    -- items (revenue = item prices, without freight)
    i.item_count,
    i.items_revenue,
    i.freight_total,
    -- payments
    p.payment_total,
    p.max_installments,
    -- review
    r.review_score,
    -- delivery: only for delivered orders with a delivery date, otherwise NULL
    CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
         THEN DATEDIFF(day, o.order_purchase_timestamp, o.order_delivered_customer_date)
    END AS delivery_days,
    -- the estimated date has no time, so the delivery date is compared as a date
    CASE WHEN o.order_status <> 'delivered' OR o.order_delivered_customer_date IS NULL THEN NULL
         WHEN CAST(o.order_delivered_customer_date AS date) > o.order_estimated_delivery_date THEN 1
         ELSE 0
    END AS is_late,
    -- flags
    CASE WHEN o.order_status NOT IN ('canceled', 'unavailable') THEN 1 ELSE 0 END AS is_sale,
    CASE WHEN o.order_purchase_timestamp >= '2017-01-01'
          AND o.order_purchase_timestamp <  '2018-09-01' THEN 1 ELSE 0 END AS in_window,
    CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
         THEN 1 ELSE 0 END AS has_valid_delivery
FROM dbo.orders AS o
JOIN      dbo.customers      AS c ON c.customer_id = o.customer_id
LEFT JOIN items_per_order    AS i ON i.order_id    = o.order_id
LEFT JOIN payments_per_order AS p ON p.order_id    = o.order_id
LEFT JOIN latest_review      AS r ON r.order_id    = o.order_id;
GO

-- Check: one row per order, and the flags match the earlier checks
SELECT COUNT(*)                             AS total_rows,
       COUNT(DISTINCT order_id)             AS unique_orders,
       SUM(1 - in_window)                   AS outside_window,
       SUM(has_valid_delivery)              AS valid_deliveries,
       ROUND(100.0 * AVG(is_late * 1.0), 1) AS pct_late
FROM dbo.vw_orders;
-- 99,441 | 99,441 | 349 | 96,470 | 6.8
-- One row per order (no fan-out). 6.8% of valid deliveries arrived after the estimated date.


/* ===== vw_order_items: one row = one order item ===== */

-- Every joined table is on the "one" side (one product, one seller, one order per item),
-- so the row count stays the same as order_items.
-- Order details and flags come from vw_orders, so each rule is written only once.
CREATE OR ALTER VIEW dbo.vw_order_items AS
SELECT
    -- item
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.price,
    oi.freight_value,
    -- product and seller
    -- English name; 2 categories without a translation are named here; products without a category are 'unknown'
    COALESCE(ct.product_category_name_english,
             CASE p.product_category_name
                  WHEN 'pc_gamer' THEN 'pc_gamer'
                  WHEN 'portateis_cozinha_e_preparadores_de_alimentos' THEN 'portable_kitchen_food_preparers'
             END,
             'unknown') AS category,
    s.seller_state,
    -- from the order
    vo.customer_unique_id,
    vo.customer_state,
    vo.order_month,
    vo.review_score,
    vo.is_late,
    -- flags
    vo.is_sale,
    vo.in_window,
    vo.has_valid_delivery
FROM dbo.order_items AS oi
JOIN      dbo.products             AS p  ON p.product_id             = oi.product_id
LEFT JOIN dbo.category_translation AS ct ON ct.product_category_name = p.product_category_name
JOIN      dbo.sellers              AS s  ON s.seller_id              = oi.seller_id
JOIN      dbo.vw_orders            AS vo ON vo.order_id              = oi.order_id;
GO

-- Check: same rows and same revenue as the raw table
SELECT COUNT(*)   AS item_rows,
       SUM(price) AS total_revenue,
       SUM(CASE WHEN category = 'unknown' THEN 1 ELSE 0 END) AS unknown_category_items
FROM dbo.vw_order_items;
-- 112,650 | 13,591,643.70 | 1,603
-- No item lost or duplicated; revenue matches SUM(price) in order_items.


/* ===== vw_customers: one row = one person ===== */

-- City and state come from the person's latest order (people can move).
-- The first sale is found over the whole history, before any analysis-window filter,
-- so a 2016 customer does not look new in 2017.
CREATE OR ALTER VIEW dbo.vw_customers AS
WITH ranked_orders AS (
    SELECT c.customer_unique_id,
           c.customer_city,
           c.customer_state,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp DESC) AS order_rank
    FROM dbo.orders    AS o
    JOIN dbo.customers AS c ON c.customer_id = o.customer_id
),
sales_per_customer AS (
    SELECT customer_unique_id,
           MIN(CASE WHEN is_sale = 1 THEN order_purchase_timestamp END) AS first_sale_date,
           SUM(is_sale) AS sale_count
    FROM dbo.vw_orders
    GROUP BY customer_unique_id
)
SELECT r.customer_unique_id,
       r.customer_city,
       r.customer_state,
       s.first_sale_date,
       DATETRUNC(month, s.first_sale_date) AS cohort_month,
       s.sale_count
FROM ranked_orders AS r
JOIN sales_per_customer AS s ON s.customer_unique_id = r.customer_unique_id
WHERE r.order_rank = 1;
GO

-- Check: one row per person
SELECT COUNT(*)                                         AS customers,
       COUNT(DISTINCT customer_unique_id)               AS unique_customers,
       SUM(CASE WHEN sale_count = 0  THEN 1 ELSE 0 END) AS no_sale_customers,
       SUM(CASE WHEN sale_count >= 2 THEN 1 ELSE 0 END) AS repeat_customers
FROM dbo.vw_customers;
-- 96,096 | 96,096 | 1,106 | 2,888
-- One row per person. 1,106 people only have canceled or unavailable orders;
-- 2,888 people bought at least twice.
