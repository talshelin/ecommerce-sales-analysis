# Data Checks and Decisions

This document records how far the data can be trusted and every rule used in the analysis. It has three parts:

1. **[Data checks](#part-1-data-checks):** what was checked, what was found and why it matters. Queries: [`sql/02_data_checks.sql`](../sql/02_data_checks.sql)
2. **[Cleaning rules](#part-2-cleaning-rules):** the rules built into the views. Queries: [`sql/03_clean_views.sql`](../sql/03_clean_views.sql)
3. **[Analysis decisions](#part-3-analysis-decisions):** choices made while answering the business questions

> [!IMPORTANT]
> **Verdict: the data is reliable.** Problems are small and appear in specific places. No raw data is deleted. Problem records are left out only of the measures they would distort.

---

## Part 1. Data checks

| Check | Result | Action |
|---|---|---|
| [1. Keys](#1-keys) | 99,441 customer IDs belong to 96,096 people | Count people with `customer_unique_id` |
| [2. Links between tables](#2-links-between-tables) | 775 orders have no items: canceled or unavailable | None needed |
| [3. Missing values](#3-missing-values) | Missing dates follow the order journey | Leave out of the affected measure only |
| [4. Invalid values](#4-invalid-values) | Unhappy customers give 1 star, not 2 or 3 | Report the 1-star share next to the average |
| [5. Period covered](#5-period-covered) | The first and last months are almost empty | Trends use Jan 2017 to Aug 2018 |
| [6. Outliers](#6-outliers) | Extreme prices are real purchases | Keep them; report the median |
| [7. Consistency](#7-consistency) | Payments and items agree in 99.75% of orders | Revenue = sum of item prices |

### 1. Keys

**Checked:** how many customer IDs and how many real people there are.

```sql
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS customers
FROM dbo.customers;
```

**Found:** 99,441 customer IDs, but **96,096 people**. Olist creates a new `customer_id` for every order.

**Why it matters:** counted by `customer_id`, every customer would look like a one-time buyer and the repeat-purchase rate would be 0%.

> [!IMPORTANT]
> **Decision:** customers are counted with `customer_unique_id`.

---

### 2. Links between tables

**Checked:** orders that have no items.

```sql
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM dbo.orders AS o
LEFT JOIN dbo.order_items AS oi ON oi.order_id = o.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status;
```

**Found:** 775 orders, almost all **unavailable** (603) or **canceled** (164).

**Why it matters:** these are orders that never happened. They have no sales value, so they do not affect revenue.

---

### 3. Missing values

**Checked:** how many orders are missing each date.

```sql
SELECT COUNT(*) - COUNT(order_approved_at)             AS no_approval_date,
       COUNT(*) - COUNT(order_delivered_carrier_date)  AS no_carrier_date,
       COUNT(*) - COUNT(order_delivered_customer_date) AS no_delivery_date
FROM dbo.orders;
```

**Found:** 160 → 1,783 → 2,965. The gaps grow along the order journey.

**Why it matters:** a missing value is not always an error. A canceled order is never handed to the carrier, and an order on its way has no delivery date yet. Only **8 delivered orders** have no delivery date; they are left out of delivery time but still count as sales.

---

### 4. Invalid values

**Checked:** how review scores are spread.

```sql
SELECT review_score,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM dbo.reviews), 2) AS pct_reviews
FROM dbo.reviews
GROUP BY review_score
ORDER BY review_score;
```

**Found:** 58% give 5 stars, but **11.5% give 1 star**, more than 2 and 3 stars together.

**Why it matters:** unhappy customers do not give a middle score, they give 1. An average score would hide them, so the share of 1-star reviews is reported next to it.

---

### 5. Period covered

**Checked:** orders per month, including months with no orders.

```sql
SELECT DATETRUNC(month, order_purchase_timestamp) AS order_month,
       COUNT(*) AS orders
FROM dbo.orders
GROUP BY DATETRUNC(month, order_purchase_timestamp)
ORDER BY order_month;
```

**Found:** data runs from September 2016 to October 2018, but the edges are almost empty. November 2016 has **no orders**; September and October 2018 have only 20, mostly canceled.

**Why it matters:** going from 1 order to 800 would show as +79,900% growth, which is not real.

> [!IMPORTANT]
> **Decision:** trends use **January 2017 to August 2018** (20 months). The other 349 orders (0.35%) stay in the data but are left out of trends.

> [!NOTE]
> The peak in November 2017 (7,544 orders) is Black Friday, a real event, not an error.

---

### 6. Outliers

**Checked:** typical value vs extremes for price, freight and payment.

```sql
SELECT DISTINCT
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) OVER () AS median_price,
       AVG(price) OVER () AS avg_price,
       MAX(price) OVER () AS max_price
FROM dbo.order_items;
```

| BRL | Median | Average | Highest |
|---|---:|---:|---:|
| Item price | 75 | 121 | 6,735 |
| Freight | 16 | 20 | 410 |
| Payment | 100 | 154 | 13,664 |

**Found:** the average is well above the median. The most expensive items are computers, appliances and consoles, all delivered.

**Why it matters:** a few large values pull the average up, so the average alone overstates a typical purchase.

> [!IMPORTANT]
> **Decision:** extreme values are kept because they are real purchases. Typical values are reported with the **median**.

---

### 7. Consistency

**Checked:** whether item totals (price + freight) match payments for each order.

```sql
-- each table is first summarised to one row per order, then joined,
-- so orders with several items and several payments are not counted twice
WITH items_per_order    AS (SELECT order_id, SUM(price + freight_value) AS items_total
                            FROM dbo.order_items GROUP BY order_id),
     payments_per_order AS (SELECT order_id, SUM(payment_value) AS payments_total
                            FROM dbo.payments GROUP BY order_id)
SELECT ...
```

**Found:** **99.75%** of orders match within 1 BRL. Dates are also checked: no order is delivered before it was placed, but 1,359 orders were handed to the carrier before approval.

**Why it matters:** the tables confirm each other, so revenue can be measured as the sum of item prices. Total delivery time is safe to use.

> [!IMPORTANT]
> **Decision:** orders with dates out of order are kept and left out only of step-by-step durations.

---

## Part 2. Cleaning rules

The rules below are applied in the views, not in the raw tables. Records are never deleted: each one carries flags, so every measure uses only the orders that are valid for it.

| View | One row = | Rows |
|---|---|---:|
| `vw_orders` | one order | 99,441 |
| `vw_order_items` | one order item | 112,650 |
| `vw_customers` | one person | 96,096 |

| Flag | 1 when | Used for |
|---|---|---|
| `is_sale` | the order is not canceled or unavailable | revenue, orders, customers |
| `in_window` | the order is between January 2017 and August 2018 | trends |
| `has_valid_delivery` | the order is delivered and has a delivery date | delivery time, late deliveries |

### 8. Revenue = sum of item prices

```sql
SUM(price)
```

**Why:** `payment_value` includes freight and instalment interest, and it is recorded per order, so it cannot be split by product, category or seller. Vouchers appear in the data as a payment method, not as a discount, so they are not deducted.

### 9. A sale is any order that was not canceled or unavailable

```sql
is_sale = CASE WHEN order_status NOT IN ('canceled', 'unavailable') THEN 1 ELSE 0 END
```

**Why:** in these two statuses the customer never receives the product. Counting only delivered orders would make the last months look weaker, because orders still on their way are real sales.

### 10. Delivery measures use delivered orders with a delivery date

```sql
has_valid_delivery = CASE WHEN order_status = 'delivered'
                           AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END
```

**Why:** without the date condition, the 8 delivered orders with no delivery date would be counted as "on time".

> [!WARNING]
> The estimated delivery date has no time (00:00). An order delivered at 15:00 on the estimated day is on time, so the delivery date is compared as a date. Comparing with the time would mark **1,292** on-time orders as late (8.1% late instead of the correct **6.8%**).

### 11. One review score per order: the newest review

**Why:** 547 orders have more than one review, and in 202 of them the score changed. An average would create scores nobody gave (1 and 5 → 3) and hide the 1-star reviews. The newest review is a real score and the customer's last opinion. It affects 0.2% of orders.

### 12. Customers: latest address, first purchase from the full history

- **City and state** come from the person's latest order, because people can move (39 people changed state).
- **First purchase** is found over the whole history before the analysis window is applied, so a customer who first bought in 2016 is not counted as new in 2017.

### 13. Category names

Categories are shown in English. The 2 categories without a translation are translated in the view, and the 610 products without a category are labelled `unknown`.

---

## Part 3. Analysis decisions

### 14. Same-day repeat orders are not a return

29% of repeat orders (930 of 3,217) were placed on the same day as the customer's previous order: one shopping session split into two orders. They are left out of the time to the second order and of the return measure. With them, the median time to return would be 29 days instead of **69**.

### 15. When an order cannot be split, the unclear orders are left out

Reviews and late deliveries belong to an order, while categories and sellers belong to items.

| Measure | Orders used | Share |
|---|---|---:|
| Review score by category | Orders with one category | 99.2% of reviewed orders |
| Late deliveries by seller | Orders with one seller | 98.7% of delivered orders |

Guessing how to split an order between categories or sellers would add errors; leaving out the few unclear orders does not.

### 16. Minimum group size

In a small group one order moves the rate a lot: one more late order in a state with 40 deliveries adds 2.5 points. Groups below a minimum are left out of comparisons. The threshold is chosen from the group sizes:

| Comparison | Minimum | Left out |
|---|---:|---|
| States | 100 deliveries | 3 states, 0.2% of deliveries |
| Sellers | 30 deliveries | small sellers; the rest handle 83% of deliveries |

### 17. Churn threshold: 280 days

There is no subscription, so a lost customer has to be defined. 90% of returning customers placed their next order within 280 days. A customer with no order for **280 days** is treated as lost.

> [!NOTE]
> The data covers about two years, so very long gaps cannot be seen yet. The real threshold may be somewhat longer.

### 18. First experience: first orders before March 2018

To compare whether customers return after a late or on-time first order, only first orders before March 2018 are used, so everyone had at least six months to come back. Without this, late first orders (frequent in February and March 2018) would have had less time to return and would look worse than they are.

### 19. RFM: reference date and scoring

- **Reference date:** the day after the last order in the data (30 August 2018), not today. The data ends in 2018; using today would make every customer look years inactive.
- **Recency and monetary** are scored 1 to 5 with `NTILE(5)`: five equal groups, so the limits come from the data (for example, monetary score 4 starts at 110 BRL).
- **Frequency is not scored with NTILE:** 97% of customers have one order, and NTILE would give identical customers different scores. Frequency is used as 1 order or 2+ orders.
- **Segments** combine frequency, the recency and monetary scores and the 280-day churn threshold.
