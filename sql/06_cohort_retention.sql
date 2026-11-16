/* 06_cohort_retention.sql
   Do customers come back?
   A customer is a person (customer_unique_id). Sales only (is_sale = 1).
   C1 uses the full sales history, so it matches vw_customers.sale_count.
*/

USE Olist;
GO


/* ===== C1. How many customers buy again, and how much revenue do they bring? ===== */

-- People by number of sales. People whose orders were all canceled or unavailable are left out:
-- they never bought, and counting them would lower the repeat rate.
SELECT CASE
           WHEN sale_count = 1 THEN '1'
           WHEN sale_count = 2 THEN '2'
           ELSE                     '3+'
       END                                                AS order_group,
       COUNT(*)                                           AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers
FROM dbo.vw_customers
WHERE sale_count >= 1
GROUP BY CASE
             WHEN sale_count = 1 THEN '1'
             WHEN sale_count = 2 THEN '2'
             ELSE                     '3+'
         END
ORDER BY MIN(sale_count);
-- 1: 92,102 (96.96%) | 2: 2,652 (2.79%) | 3+: 236 (0.25%)
-- Only 3% of customers bought more than once: about 1 in 33.

-- The same groups with their revenue. Each person's orders and revenue come from vw_orders;
-- the customer counts match the query above (cross-check between two views).
-- SUM(COUNT(*)) OVER () and SUM(SUM(revenue)) OVER (): window functions run after GROUP BY,
-- so they add up the group results to get the total on every row.
WITH customer_sales AS (
    SELECT customer_unique_id,
           COUNT(*)           AS orders,
           SUM(items_revenue) AS revenue
    FROM dbo.vw_orders
    WHERE is_sale = 1
    GROUP BY customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN '1'
            WHEN orders = 2 THEN '2'
            ELSE                 '3+' END                         AS order_group,
       COUNT(*)                                                   AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS pct_customers,
       SUM(revenue)                                               AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2) AS pct_revenue,
       ROUND(SUM(revenue) / COUNT(*), 2)                          AS revenue_per_customer
FROM customer_sales
GROUP BY CASE WHEN orders = 1 THEN '1'
              WHEN orders = 2 THEN '2'
              ELSE                 '3+' END
ORDER BY MIN(orders);
-- 1:  96.96% of customers | 94.44% of revenue | 138 BRL per customer
-- 2:   2.79%              |  4.82%            | 245 BRL
-- 3+:  0.25%              |  0.74%            | 422 BRL
-- Repeat customers are 3% of customers and 5.6% of revenue. A 3+ customer brings 3 times
-- as much as a one-time customer, by buying more often rather than spending more per order.
