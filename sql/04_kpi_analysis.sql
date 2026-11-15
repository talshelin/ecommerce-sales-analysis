/* 04_kpi_analysis.sql
   Are we growing, and where does growth come from?
   All queries use the views in 03_clean_views.sql:
   sales only (is_sale = 1) and the analysis window Jan 2017 - Aug 2018 (in_window = 1).
*/

USE Olist;
GO


/* ===== A1. Monthly revenue, orders, average order value, MoM and YoY growth ===== */

-- One row = one month.
-- Revenue = orders x average order value (AOV), so the three are shown side by side.
-- LAG(x)     = the previous month's value          -> month-over-month (MoM) change
-- LAG(x, 12) = the same month of the previous year -> year-over-year (YoY) change
WITH monthly AS (
    SELECT order_month,
           SUM(items_revenue)                 AS revenue,
           COUNT(*)                           AS orders,
           COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM dbo.vw_orders
    WHERE is_sale   = 1
      AND in_window = 1
    GROUP BY order_month
)
SELECT order_month,
       revenue,
       orders,
       active_customers,
       ROUND(revenue / orders, 2)               AS aov,
       LAG(revenue) OVER (ORDER BY order_month) AS prev_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
             / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0), 1)         AS revenue_mom_pct,
       ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY order_month))
             / NULLIF(LAG(revenue, 12) OVER (ORDER BY order_month), 0), 1)     AS revenue_yoy_pct
FROM monthly
ORDER BY order_month;
-- Revenue grew about 7x, from 120K BRL (Jan 2017) to 849K BRL (Aug 2018).
-- Orders grew about 8x (787 -> 6,421), while AOV stayed between 125 and 153 BRL:
-- growth came from more orders, not bigger baskets.
-- In 2018 monthly revenue stayed flat at 840K-990K BRL. YoY growth is still positive
-- but fell from +687% (Jan) to +49% (Aug): growth continues but is slowing.
-- Nov 2017 (1.0M BRL, +52% MoM) is Black Friday. The -26% MoM in Dec 2017 is not a drop:
-- December is still above October; it only looks low next to the November peak.


/* ===== A2. Where does growth come from: more orders or bigger baskets? ===== */

-- One row = one year. January to August only, so both years cover the same months
-- (2018 data ends in August, and 2017 alone would include Black Friday).
SELECT YEAR(order_month)                       AS order_year,
       SUM(items_revenue)                      AS revenue,
       COUNT(*)                                AS orders,
       ROUND(SUM(items_revenue) / COUNT(*), 2) AS aov
FROM dbo.vw_orders
WHERE is_sale   = 1
  AND in_window = 1
  AND MONTH(order_month) <= 8
GROUP BY YEAR(order_month)
ORDER BY order_year;
-- 2017: 3.08M BRL | 22,562 orders | AOV 136.55
-- 2018: 7.34M BRL | 53,531 orders | AOV 137.14
-- Revenue +138%, orders +137%, AOV +0.4%.
-- Almost all growth comes from more orders; customers did not spend more per order.


/* ===== A3. Which categories bring the revenue? Share and Pareto ===== */

-- One row = one category. vw_order_items is used because category is an item-level detail;
-- orders are counted with DISTINCT, since one order can hold several items of the same category.
-- SUM(...) OVER ()                     = total revenue on every row -> share of total
-- SUM(...) OVER (ORDER BY ... ROWS ...) = running total             -> cumulative share
-- ROWS adds one row at a time; the default RANGE would add categories with equal revenue together.
WITH category_revenue AS (
    SELECT category,
           SUM(price)               AS revenue,
           COUNT(DISTINCT order_id) AS orders
    FROM dbo.vw_order_items
    WHERE is_sale   = 1
      AND in_window = 1
    GROUP BY category
)
SELECT category,
       revenue,
       orders,
       ROUND(revenue / orders, 2)                    AS aov,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS revenue_share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(revenue) OVER (), 2)              AS cumulative_share_pct
FROM category_revenue
ORDER BY revenue DESC;
-- 74 categories, 13.45M BRL in total.
-- The largest category, health_beauty, is only 9.3% of revenue: no category dominates.
-- The top 7 categories bring half of revenue; the top 18 (24% of categories) bring 80%.
-- Categories earn in different ways: watches_gifts sells fewer, pricier orders (AOV 213 BRL),
-- bed_bath_table sells many cheaper ones (AOV 110 BRL), with similar revenue.
