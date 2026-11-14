# Olist E-Commerce: Growth, Delivery and Customer Retention

SQL Server and Power BI analysis of 100k Olist e-commerce orders: KPI tracking, delivery performance, cohort retention and RFM segmentation.

> Work in progress.

## Business question

**Are we growing? Do our customers come back? Which customers and which problems should we focus on?**

| | Question |
|---|---|
| A | Are we growing, and where does growth come from? |
| B | Are we delivering on time, and does it affect customer satisfaction? |
| C | Do customers come back? |
| D | Which customers should we focus on? |

## Data

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle): about 100k orders from 2016 to 2018, amounts in Brazilian real (BRL). The CSV files are not stored in this repo; download them from Kaggle into `data/raw/`.

## SQL scripts

Run in order:

| File | Content |
|---|---|
| `sql/01_create_tables.sql` | Database and table definitions, row count check |
| `sql/02_data_checks.sql` | Data checks: keys, links, missing and invalid values, period, outliers, consistency |
| `sql/03_clean_views.sql` | Analysis-ready views with flags for sales, analysis window and valid deliveries |

## Data checks and decisions

What was checked, what was found and what was decided: [docs/decision_log.md](docs/decision_log.md)
