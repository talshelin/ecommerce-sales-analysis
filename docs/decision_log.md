# Data Checks and Decisions

Every check made on the data and every rule used in the analysis, with the reason behind it. No raw data is deleted: problem records are flagged and left out only of the measures they would distort.

## 1. Data checks

Queries: [`sql/02_data_checks.sql`](../sql/02_data_checks.sql)

| # | Check | Found | Decision |
|---|---|---|---|
| 1 | Keys | 99,441 customer IDs but 96,096 people: Olist creates a new `customer_id` for every order | Count people with `customer_unique_id`; otherwise the repeat rate would be 0% |
| 2 | Links between tables | 775 orders have no items; almost all are unavailable or canceled | None needed: they are not sales |
| 3 | Missing values | Missing dates grow along the order journey (160 → 1,783 → 2,965); canceled and in-transit orders have no later dates | Leave orders out only of the measure that needs the missing date |
| 4 | Review scores | 11.5% of reviews give 1 star, more than 2 and 3 stars together | Report the 1-star share next to the average score |
| 5 | Period | The first and last months are almost empty (no orders in November 2016) | Trends use January 2017 to August 2018; 349 orders (0.35%) fall outside |
| 6 | Outliers | Prices are skewed (median 75 BRL, average 121 BRL); the most expensive items are real purchases | Keep them; report typical values with the median |
| 7 | Consistency | Payments match items + freight in 99.75% of orders; 1,359 orders were handed to the carrier before approval | Revenue = sum of item prices; orders with dates out of order are left out only of step-by-step durations |

## 2. Cleaning rules

Built into the views in [`sql/03_clean_views.sql`](../sql/03_clean_views.sql): `vw_orders` (one row per order), `vw_order_items` (one row per item), `vw_customers` (one row per person).

| # | Rule | Why |
|---|---|---|
| 8 | Revenue = sum of item prices, without freight | Payments include freight and interest and cannot be split by product, category or seller |
| 9 | A sale is any order that is not canceled or unavailable | In these two statuses the customer never gets the product |
| 10 | Delivery measures use delivered orders with a delivery date; late = delivered after the estimated date, compared as dates | The estimate has no time. Comparing with the time would mark 1,292 on-time orders as late (8.1% instead of 6.8%) |
| 11 | One review score per order: the newest review | An average would create scores nobody gave (1 and 5 → 3) and hide 1-star reviews |
| 12 | Customer address = latest order; first purchase found over the full history | People move; a 2016 customer must not look new in 2017 |
| 13 | Categories in English; products without a category are `unknown` | The report is in English; 610 products have no category |

## 3. Analysis decisions

| # | Decision | Why |
|---|---|---|
| 14 | Same-day repeat orders are not a return | 29% of repeat orders are one shopping session split into two orders. With them, the median time to return would be 29 days instead of 69 |
| 15 | Review score by category and late rate by seller use only orders with one category or one seller | Splitting an order between categories or sellers would be a guess; these orders are 99.2% and 98.7% of the total |
| 16 | Minimum group size: 100 deliveries per state, 30 per seller | In small groups one order moves the rate a lot |
| 17 | Churn threshold: 280 days | 90% of returning customers come back within 280 days |
| 18 | First-experience analysis uses first orders before March 2018 | Everyone needs at least six months to come back |
| 19 | RFM reference date = the day after the last order; frequency is used as 1 order or 2+ orders | Using today would make everyone look inactive. 97% of customers have one order, so frequency cannot be split into five groups |

## 4. Dashboard decisions

| # | Decision | Why |
|---|---|---|
| 20 | Star schema: `DimDate` and `vw_customers` filter the two fact views, which are not linked to each other | A direct link would give filters two paths to the same table |
| 21 | The analysis window is a report-level filter | Every page uses the same 20 months as the SQL results |
| 22 | Orders are counted from items (97,905, not 97,910) | 5 sale orders have no items; revenue and orders come from the same table, so the average order value stays consistent |
| 23 | Growth cards compare January-August 2018 with January-August 2017 | 2018 ends in August; a full-year comparison would compare 12 months with 8 |
| 24 | Typical delivery time is the median (10 days) | The average (12.5 days) is pulled up by a few very late orders |
| 25 | Cohorts, repeat-order gaps, RFM segments and seller results are prepared in SQL ([`sql/08_powerbi_views.sql`](../sql/08_powerbi_views.sql)) | They need person-level history that measures cannot rebuild |
| 26 | Sellers are shown as a scatter, not a "worst 15" table | Sellers late 15%+ of the time cause only 8% of late deliveries; a ranking would suggest the opposite ([Delivery page](../reports/images/page_b_delivery.png)) |
| 27 | The repeat-customer chart shows only customers with 2+ orders; shares still use all customers | The one-order bar (97%) hid the others |
| 28 | Ranked bar charts show the top 8 with values on the bars | All bars fit without a scrollbar |
| 29 | A retention curve sits next to the cohort matrix | The curve shows the average shape at a glance: 0.48% in month 1, about 0.2% later ([Retention page](../reports/images/page_c_retention.png)) |
