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
