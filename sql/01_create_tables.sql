/* 01_create_tables.sql
   Creates the Olist database and its 8 tables.
   Safe to run again: existing objects are kept.

   Type choices
   - Dates          : datetime2 (date arithmetic and sorting work)
   - Money          : decimal(10,2) (exact values)
   - IDs, zip codes : varchar (labels, not numbers; zip codes keep leading zeros)
   - Names, texts   : nvarchar (keeps accents, e.g. São Paulo)
*/

IF DB_ID('Olist') IS NULL
    CREATE DATABASE Olist;
GO
USE Olist;
GO

-- One row = one product category (Portuguese -> English)
IF OBJECT_ID('dbo.category_translation') IS NULL
CREATE TABLE dbo.category_translation (
    product_category_name         nvarchar(100) NOT NULL,
    product_category_name_english varchar(100)  NULL,
    CONSTRAINT PK_category_translation PRIMARY KEY (product_category_name)
);
GO

-- One row = the customer record of one order
IF OBJECT_ID('dbo.customers') IS NULL
CREATE TABLE dbo.customers (
    customer_id              varchar(50)   NOT NULL,
    customer_unique_id       varchar(50)   NULL,
    customer_zip_code_prefix varchar(10)   NULL,
    customer_city            nvarchar(100) NULL,
    customer_state           varchar(2)    NULL,
    CONSTRAINT PK_customers PRIMARY KEY (customer_id)
);
GO

-- One row = one product
IF OBJECT_ID('dbo.products') IS NULL
CREATE TABLE dbo.products (
    product_id                 varchar(50)   NOT NULL,
    product_category_name      nvarchar(100) NULL,
    product_name_lenght        int           NULL,  -- spelling as in the source file
    product_description_lenght int           NULL,  -- spelling as in the source file
    product_photos_qty         int           NULL,
    product_weight_g           int           NULL,
    product_length_cm          int           NULL,
    product_height_cm          int           NULL,
    product_width_cm           int           NULL,
    CONSTRAINT PK_products PRIMARY KEY (product_id)
);
GO

-- One row = one seller
IF OBJECT_ID('dbo.sellers') IS NULL
CREATE TABLE dbo.sellers (
    seller_id              varchar(50)   NOT NULL,
    seller_zip_code_prefix varchar(10)   NULL,
    seller_city            nvarchar(100) NULL,
    seller_state           varchar(2)    NULL,
    CONSTRAINT PK_sellers PRIMARY KEY (seller_id)
);
GO

-- One row = one order
IF OBJECT_ID('dbo.orders') IS NULL
CREATE TABLE dbo.orders (
    order_id                      varchar(50)  NOT NULL,
    customer_id                   varchar(50)  NOT NULL,
    order_status                  varchar(20)  NOT NULL,
    order_purchase_timestamp      datetime2(7) NOT NULL,
    order_approved_at             datetime2(7) NULL,
    order_delivered_carrier_date  datetime2(7) NULL,
    order_delivered_customer_date datetime2(7) NULL,
    order_estimated_delivery_date datetime2(7) NOT NULL,
    CONSTRAINT PK_orders PRIMARY KEY (order_id)
);
GO

-- One row = one item line in an order
IF OBJECT_ID('dbo.order_items') IS NULL
CREATE TABLE dbo.order_items (
    order_id            varchar(50)   NULL,
    order_item_id       int           NULL,
    product_id          varchar(50)   NULL,
    seller_id           varchar(50)   NULL,
    shipping_limit_date datetime2(7)  NULL,
    price               decimal(10,2) NULL,
    freight_value       decimal(10,2) NULL
);
GO

-- One row = one payment of an order
IF OBJECT_ID('dbo.payments') IS NULL
CREATE TABLE dbo.payments (
    order_id             varchar(50)   NULL,
    payment_sequential   int           NULL,
    payment_type         varchar(20)   NULL,
    payment_installments int           NULL,
    payment_value        decimal(10,2) NULL
);
GO

-- One row = one review linked to an order
IF OBJECT_ID('dbo.reviews') IS NULL
CREATE TABLE dbo.reviews (
    review_id               varchar(50)   NULL,
    order_id                varchar(50)   NULL,
    review_score            int           NULL,
    review_comment_title    nvarchar(max) NULL,
    review_comment_message  nvarchar(max) NULL,
    review_creation_date    datetime2(7)  NULL,
    review_answer_timestamp datetime2(7)  NULL
);
GO

/* Data load
   Each CSV in data/raw/ is loaded into the table with the same name
   (SSMS: Import Flat File). The geolocation file is not used.
   The import wizard reads the header of the category translation file
   as a data row; remove it after loading: */
DELETE FROM dbo.category_translation
WHERE product_category_name = 'product_category_name';
GO

-- Row count check: each table should match its CSV file
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM dbo.orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM dbo.order_items
UNION ALL SELECT 'customers',            COUNT(*) FROM dbo.customers
UNION ALL SELECT 'payments',             COUNT(*) FROM dbo.payments
UNION ALL SELECT 'reviews',              COUNT(*) FROM dbo.reviews
UNION ALL SELECT 'products',             COUNT(*) FROM dbo.products
UNION ALL SELECT 'sellers',              COUNT(*) FROM dbo.sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM dbo.category_translation;
-- orders 99,441 | order_items 112,650 | customers 99,441 | payments 103,886
-- reviews 99,224 | products 32,951 | sellers 3,095 | category_translation 71


/* Indexes
   order_items, payments and reviews have several rows per order and no primary key.
   An index on order_id lets joins and lookups by order avoid reading the whole table.
*/
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_order_items_order_id')
    CREATE INDEX IX_order_items_order_id ON dbo.order_items (order_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_payments_order_id')
    CREATE INDEX IX_payments_order_id ON dbo.payments (order_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_reviews_order_id')
    CREATE INDEX IX_reviews_order_id ON dbo.reviews (order_id);
GO
