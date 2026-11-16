/* 05_operations.sql
   Are we delivering what we promised?
   Uses vw_orders from 03_clean_views.sql, analysis window Jan 2017 - Aug 2018.
*/

USE Olist;
GO


/* ===== B1. Order funnel: where are orders lost? ===== */

-- One row for the whole window. A step's date is filled only if the order reached it,
-- so COUNT(column) counts the orders that reached each step.
-- is_sale is NOT used here: canceled and unavailable orders are exactly the losses we want to see.
SELECT COUNT(*)                             AS orders_placed,
       COUNT(order_approved_at)             AS orders_approved,
       COUNT(order_delivered_carrier_date)  AS orders_shipped,
       COUNT(order_delivered_customer_date) AS orders_delivered
FROM dbo.vw_orders
WHERE in_window = 1;
-- 99,092 -> 98,957 -> 97,376 -> 96,204   (97.1% of orders reach the customer)
-- Placed -> approved:   135 lost
-- Approved -> shipped:  1,581 lost, the largest step. This is the seller's step:
--                       602 unavailable + 394 canceled, plus 595 still "processing" or "invoiced".
-- Shipped -> delivered: 1,172 lost; 1,097 of them are still "shipped" (in transit when the data ends, or lost).


/* ===== B2. Delivery time and late deliveries ===== */

-- Only delivered orders with a delivery date: a canceled order has no delivery time.
-- Median and P90 need PERCENTILE_CONT, a window function, so the other measures use OVER () too
-- and DISTINCT keeps one row. "* 1.0" avoids integer averages (0.068 would become 0).
SELECT DISTINCT
       COUNT(*)                 OVER ()                                    AS deliveries,
       AVG(delivery_days * 1.0) OVER ()                                    AS avg_days,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) OVER () AS median_days,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days) OVER () AS p90_days,
       100.0 * AVG(is_late * 1.0) OVER ()                                  AS pct_late
FROM dbo.vw_orders
WHERE has_valid_delivery = 1
  AND in_window          = 1;
-- 96,203 deliveries | average 12.5 days | median 10 | P90 23 | 6.8% late
-- A typical order arrives in 10 days; 1 in 10 customers waits more than 23 days.
-- The average is above the median: a few very slow deliveries pull it up.
-- About 1 in 15 orders arrives after the estimated date.

-- Late deliveries by month: is the problem growing?
SELECT order_month,
       COUNT(*)                             AS deliveries,
       ROUND(100.0 * AVG(is_late * 1.0), 1) AS pct_late
FROM dbo.vw_orders
WHERE has_valid_delivery = 1
  AND in_window          = 1
GROUP BY order_month
ORDER BY order_month;
-- In most months 3-5% of orders are late. The 6.8% average hides three peaks:
-- Nov 2017 (12.4%, Black Friday: deliveries +63% on October), Feb 2018 (14.1%) and Mar 2018 (19.0%).
-- Lateness is not rising steadily; it jumps in specific months, once right after a volume surge.
-- The last months may look better than they are: orders still on their way are not counted yet.

-- Delivery time distribution (data for a histogram)
-- CASE WHEN takes the first true condition, so only the upper limit is needed.
-- Labels are text ('8-14' would sort after '31+'), so buckets are sorted by their smallest delivery_days.
WITH delivery_buckets AS (
    SELECT delivery_days,
           CASE
               WHEN delivery_days <= 7  THEN '0-7'
               WHEN delivery_days <= 14 THEN '8-14'
               WHEN delivery_days <= 21 THEN '15-21'
               WHEN delivery_days <= 30 THEN '22-30'
               ELSE                          '31+'
           END AS delivery_bucket
    FROM dbo.vw_orders
    WHERE has_valid_delivery = 1
      AND in_window          = 1
)
SELECT delivery_bucket,
       COUNT(*)                                           AS deliveries,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_deliveries
FROM delivery_buckets
GROUP BY delivery_bucket
ORDER BY MIN(delivery_days);
-- 0-7: 31.9% | 8-14: 39.4% | 15-21: 16.7% | 22-30: 7.6% | 31+: 4.4%
-- 71% of orders arrive within two weeks; 12% take more than three weeks.


/* ===== B3. Do late deliveries get lower review scores? ===== */

-- One row = one group (on time / late). Orders without a review are left out.
-- AVG(CASE WHEN ... THEN 1.0 ELSE 0 END) = share of orders that meet the condition.
SELECT is_late,
       COUNT(*)                                                              AS orders,
       ROUND(AVG(review_score * 1.0), 2)                                     AS avg_score,
       ROUND(100.0 * AVG(CASE WHEN review_score = 1 THEN 1.0 ELSE 0 END), 1) AS pct_one_star
FROM dbo.vw_orders
WHERE has_valid_delivery = 1
  AND in_window          = 1
  AND review_score IS NOT NULL
GROUP BY is_late;
-- On time: 89,182 orders | average 4.29 | 6.6% one star
-- Late:     6,378 orders | average 2.27 | 53.8% one star
-- More than half of late orders get 1 star, about 8 times the on-time rate.
-- This is a correlation, not proof of cause: late orders may cluster in certain states,
-- categories or sellers that also get lower scores.
