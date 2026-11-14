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
