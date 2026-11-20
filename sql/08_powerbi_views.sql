/* 08_powerbi_views.sql
   Result views for Power BI. Each one saves an analysis from 05-07 that is too complex
   to rebuild with Power BI measures. The logic and the reasons are explained in those files.
*/

USE Olist;
GO


/* ===== Cohort retention (from 06, C2): one row = one cohort and month ===== */

CREATE OR ALTER VIEW dbo.vw_cohort_retention AS
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
GROUP BY a.cohort_month, a.month_index, s.cohort_customers;
GO


/* ===== RFM (from 07, D): one row = one person ===== */

CREATE OR ALTER VIEW dbo.vw_rfm_customers AS
WITH reference AS (
    SELECT DATEADD(day, 1, CAST(MAX(order_purchase_timestamp) AS date)) AS ref_date
    FROM dbo.vw_orders
    WHERE is_sale = 1 AND in_window = 1
),
customer_rfm AS (
    SELECT o.customer_unique_id,
           DATEDIFF(day, CAST(MAX(o.order_purchase_timestamp) AS date), r.ref_date) AS recency_days,
           COUNT(*)                                                               AS frequency,
           SUM(o.items_revenue)                                                   AS monetary
    FROM dbo.vw_orders AS o
    CROSS JOIN reference AS r
    WHERE o.is_sale = 1 AND o.in_window = 1
    GROUP BY o.customer_unique_id, r.ref_date
),
rfm_scores AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM customer_rfm
)
SELECT customer_unique_id,
       recency_days,
       frequency,
       monetary,
       r_score,
       m_score,
       CASE
           WHEN frequency >= 2 AND recency_days <= 280 THEN 'Champions'
           WHEN frequency >= 2                         THEN 'Lost repeat customers'
           WHEN recency_days > 280 AND m_score >= 4    THEN 'Lost big spenders'
           WHEN recency_days > 280                     THEN 'Lost customers'
           WHEN r_score >= 4 AND m_score >= 4          THEN 'Recent big spenders'
           WHEN r_score >= 4                           THEN 'Recent customers'
           ELSE                                             'Cooling down'
       END AS segment
FROM rfm_scores;
GO


/* ===== Late deliveries by seller (from 05, B5): one row = one seller ===== */

-- Single-seller orders only. All sellers are kept; the 30-delivery minimum is applied in the report.
CREATE OR ALTER VIEW dbo.vw_seller_delivery AS
WITH sellers_per_order AS (
    SELECT order_id,
           COUNT(DISTINCT seller_id) AS seller_count,
           MIN(seller_id)            AS seller_id
    FROM dbo.vw_order_items
    GROUP BY order_id
),
single_seller_deliveries AS (
    SELECT s.seller_id,
           o.is_late
    FROM dbo.vw_orders AS o
    JOIN sellers_per_order AS s ON s.order_id = o.order_id
    WHERE s.seller_count       = 1
      AND o.has_valid_delivery = 1
      AND o.in_window          = 1
)
SELECT d.seller_id,
       se.seller_state,
       COUNT(*)                                  AS deliveries,
       SUM(d.is_late)                            AS late_deliveries,
       ROUND(100.0 * SUM(d.is_late) / COUNT(*), 1) AS pct_late
FROM single_seller_deliveries AS d
JOIN dbo.sellers              AS se ON se.seller_id = d.seller_id
GROUP BY d.seller_id, se.seller_state;
GO


-- Check
SELECT 'vw_cohort_retention' AS view_name, COUNT(*) AS row_count FROM dbo.vw_cohort_retention
UNION ALL SELECT 'vw_rfm_customers',   COUNT(*) FROM dbo.vw_rfm_customers
UNION ALL SELECT 'vw_seller_delivery', COUNT(*) FROM dbo.vw_seller_delivery;
-- 207 | 94,707 | 2,925
