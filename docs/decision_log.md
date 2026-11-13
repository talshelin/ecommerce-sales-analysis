# Data Checks and Decisions

Before the analysis, the data was checked to see how far it can be trusted. Each section below shows **the query**, **what was found** and **why it matters**. Full queries: [`sql/02_data_checks.sql`](../sql/02_data_checks.sql).

> [!IMPORTANT]
> **Verdict: the data is reliable.** Problems are small and appear in specific places. No raw data is deleted. Problem records are left out only of the measures they would distort.

| | Check | Result |
|---|---|---|
| 🟦 | [Keys](#-1-keys) | Customers must be counted as people, not IDs |
| 🟪 | [Links between tables](#-2-links-between-tables) | 775 orders have no items: canceled or unavailable |
| 🟨 | [Missing values](#-3-missing-values) | Missing dates are expected |
| 🟥 | [Invalid values](#-4-invalid-values) | Unhappy customers give 1 star, not 2 or 3 |
| 🟩 | [Period covered](#-5-period-covered) | Trends use Jan 2017 to Aug 2018 |
| 🟧 | [Outliers](#-6-outliers) | Extreme prices are real; the median is used |
| 🟫 | [Consistency](#-7-consistency) | Payments and items agree in 99.75% of orders |

---

## 🟦 1. Keys

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

## 🟪 2. Links between tables

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

## 🟨 3. Missing values

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

## 🟥 4. Invalid values

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

## 🟩 5. Period covered

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

## 🟧 6. Outliers

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

## 🟫 7. Consistency

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
