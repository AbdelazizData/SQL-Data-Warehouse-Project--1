/* 
=========================================================
DDL Script: Create Gold Views
=========================================================
Description:
This script creates three analytical views in the GOLD layer:

1. dim_customers:
   - Creates a customer dimension with cleaned and enriched data
   - Combines CRM and ERP sources
   - Resolves gender conflicts (CRM is the primary source)

2. dim_products:
   - Creates a product dimension
   - Includes only active products (no end date)
   - Enriches product data with category information

3. fact_sales:
   - Creates a fact table for sales transactions
   - Links customers and products using surrogate keys
   - Contains measures like sales amount, quantity, and price
=========================================================
*/


-- =========================================
-- Create Dimension : gold.dim_customers 
-- =========================================
IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY ci.cst_id)      AS customer_key,
    ci.cst_id                                  AS customer_id,
    ci.cst_key                                 AS customer_number,
    ci.cst_firstname                           AS first_name,
    ci.cst_lastname                            AS last_name,
    ela.cntry                                  AS country,
    ci.cst_marital_status                      AS marital_status,
    CASE 
        WHEN ci.cst_gender <> 'Unknown' 
            THEN ci.cst_gender   -- CRM is the master source
        ELSE COALESCE(ca.gen, 'n/a')
    END                                        AS gender,
    ca.bdate                                   AS birth_date,
    ci.cst_create_date                         AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 ela
    ON ci.cst_key = ela.cid;
GO


-- =========================================
-- Create Dimension : gold.dim_products
-- =========================================
IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id                                                AS product_id,
    pn.prd_key                                               AS product_number,
    pn.prd_nm                                                AS product_name,
    pn.cat_id                                                AS category_id,
    pcg.cat                                                  AS category,
    pcg.subcat                                               AS sub_category,
    pcg.maintenance                                          AS maintenance,
    pn.prd_cost                                              AS product_cost,
    pn.prd_line                                              AS product_line,
    pn.prd_start_dt                                          AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pcg
    ON pn.cat_id = pcg.id
WHERE pn.prd_end_dt IS NULL;
GO


-- =========================================
-- Create Fact : gold.fact_sales
-- =========================================
IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS
SELECT  
    sd.sls_ord_num     AS order_number,
    pr.product_key     AS product_key,
    cr.customer_key    AS customer_key,
    sd.sls_order_dt    AS order_date,
    sd.sls_ship_dt     AS shipping_date,
    sd.sls_due_dt      AS due_date,
    sd.sls_sales       AS sales_amount,
    sd.sls_quantity    AS quantity,
    sd.sls_price       AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr
    ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cr
    ON sd.sls_cust_id = cr.customer_id;
GO
