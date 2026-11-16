/* 07_rfm.sql
   Which customers should we focus on?
   RFM: Recency (days since last order), Frequency (number of orders), Monetary (revenue).
   Sales in the analysis window only (is_sale = 1, in_window = 1).
*/

USE Olist;
GO


/* ===== D. RFM segments ===== */

-- Reference date = the day after the last order in the data, not today:
-- the data ends in August 2018, and using today would make every customer look years inactive.
-- CROSS JOIN with the one-row reference CTE puts the reference date on every row.
-- R and M are scored 1-5 with NTILE (R: fewer days = 5). F is not scored with NTILE:
-- 97% of customers have one order, and NTILE would give identical customers different scores.
-- Segments use frequency, the R and M scores and the churn threshold from 06 (280 days).
-- CASE WHEN takes the first true condition, so repeat customers are separated first.
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
),
segments AS (
    SELECT *,
           CASE
               WHEN frequency >= 2 AND recency_days <= 280 THEN 'Champions'
               WHEN frequency >= 2                         THEN 'Lost repeat customers'
               WHEN recency_days > 280 AND m_score >= 4    THEN 'Lost big spenders'
               WHEN recency_days > 280                     THEN 'Lost customers'
               WHEN r_score >= 4 AND m_score >= 4          THEN 'Recent big spenders'
               WHEN r_score >= 4                           THEN 'Recent customers'
               ELSE                                             'Cooling down'
           END AS segment
    FROM rfm_scores
)
SELECT segment,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_customers,
       SUM(monetary)                                                AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(SUM(monetary) / COUNT(*), 0)                           AS revenue_per_customer
FROM segments
GROUP BY segment
ORDER BY revenue DESC;
-- 94,707 customers in 7 segments:
-- Recent big spenders   15.6% of customers | 29.3% of revenue | 267 BRL per customer
-- Lost big spenders     13.0%              | 25.7%            | 281 BRL
-- Cooling down          24.0%              | 22.0%            | 130 BRL
-- Recent customers      23.1%              |  9.0%            |  55 BRL
-- Lost customers        21.3%              |  8.4%            |  56 BRL
-- Champions              2.1%              |  3.9%            | 265 BRL
-- Lost repeat customers  0.9%              |  1.7%            | 249 BRL
-- Big spenders bring 55% of revenue, and almost half of that group is already lost.
-- Recent big spenders (about 14,750 people) are the group to protect first:
-- they spent the most and have not left yet.
