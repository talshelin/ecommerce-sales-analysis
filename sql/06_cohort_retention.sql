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


/* ===== C2. Cohort retention ===== */

-- A cohort = the people who made their first purchase in the same month.
-- Retention in month N = people from the cohort who bought again N months after their first month
--                        / all people in the cohort.
-- The first purchase comes from vw_customers, over the whole history; the window only limits
-- which cohorts and months are reported. DISTINCT counts a person once per month,
-- even with several orders that month.
-- Output is long (one row per cohort and month) so Power BI can turn it into a heatmap.
WITH cohorts AS (
    SELECT customer_unique_id,
           cohort_month
    FROM dbo.vw_customers
    WHERE cohort_month >= '2017-01-01'
      AND cohort_month <  '2018-09-01'
),
activity AS (
    SELECT DISTINCT
           c.cohort_month,
           c.customer_unique_id,
           DATEDIFF(month, c.cohort_month, o.order_month) AS month_index
    FROM dbo.vw_orders AS o
    JOIN cohorts       AS c ON c.customer_unique_id = o.customer_unique_id
    WHERE o.is_sale   = 1
      AND o.in_window = 1
),
cohort_size AS (
    SELECT cohort_month,
           COUNT(*) AS cohort_customers
    FROM cohorts
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       a.month_index,
       COUNT(*)                                        AS active_customers,
       s.cohort_customers,
       ROUND(100.0 * COUNT(*) / s.cohort_customers, 2) AS retention_pct
FROM activity    AS a
JOIN cohort_size AS s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, a.month_index, s.cohort_customers
ORDER BY a.cohort_month, a.month_index;
-- 207 rows, 20 cohorts. Month 0 is 100% for every cohort (by definition).
-- Cohorts grew from 752 people (Jan 2017) to 6,000-7,000 a month in 2018, but retention did not improve:
-- month 1 is 0.2-0.7% for every cohort (0.48% on average), then 0.2-0.3% in later months.
-- About 5 in 1,000 new customers buy again the next month.
-- More returning customers over time come from bigger cohorts, not from higher loyalty.
-- Newer cohorts have fewer months (right censoring: the data ends in August 2018).
