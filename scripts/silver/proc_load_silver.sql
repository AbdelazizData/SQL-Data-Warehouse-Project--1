/*
Description:
This stored procedure loads data into the "silver" layer from the "bronze" layer.

Main steps:
1. Truncates (clears) existing silver tables.
2. Inserts cleaned and transformed data from bronze tables into silver tables.
3. Applies data cleansing such as:
   - Removing duplicates using ROW_NUMBER().
   - Standardizing text values (e.g., gender, marital status, country).
   - Handling NULLs and invalid values.
   - Fixing date formats and invalid dates.
   - Calculating missing or incorrect sales values.
4. Tracks execution time for each table and the full batch.
5. Includes error handling using TRY...CATCH.
*/

EXEC silver.load_silver;

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN

    DECLARE 
        @start_time        DATETIME,
        @end_time          DATETIME,
        @batch_start_time  DATETIME,
        @batch_end_time    DATETIME;

    BEGIN TRY

        SET @batch_start_time = GETDATE();

        PRINT '=======================================';
        PRINT '>>Loading Silver Layer ...';
        PRINT '=======================================';
        PRINT '>>Inserting Data Into: CRM TABLES';
        PRINT '=======================================';


        -- =========================================
        -- CRM CUSTOMER INFO
        -- =========================================

        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.crm_cust_info';
        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '>> Inserting Data Into: silver.crm_cust_info';
        INSERT INTO silver.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gender,
            cst_create_date
        )
        SELECT 
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname)  AS cst_lastname,
            CASE 
                WHEN cst_marital_status = 'S' THEN 'Singel'
                WHEN cst_marital_status = 'M' THEN 'Married'
                ELSE 'Unkown'
            END AS cst_marital_status,
            CASE 
                WHEN UPPER(cst_gender) = 'F' THEN 'Female'
                WHEN UPPER(cst_gender) = 'M' THEN 'Male'
                ELSE 'Unknown'
            END AS cst_gender,
            cst_create_date
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY cst_id 
                    ORDER BY cst_create_date DESC
                ) AS flag_last
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) T
        WHERE flag_last = 1;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- =========================================
        -- CRM PRODUCT INFO
        -- =========================================

        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.crm_prd_info';
        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '>> Inserting Data Into: silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT 
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
            SUBSTRING(prd_key, 7, LEN(prd_key))          AS prd_key,
            prd_nm,
            ISNULL(prd_cost, 0)                          AS prd_cost,
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'n/a'
            END AS prd_line,
            CAST(prd_start_dt AS DATE) AS prd_start_dt,
            CAST(
                LEAD(prd_start_dt) OVER (
                    PARTITION BY prd_key 
                    ORDER BY prd_start_dt
                ) - 1 AS DATE
            ) AS prd_end_dt
        FROM bronze.crm_prd_info;

        SELECT * FROM silver.crm_prd_info;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- =========================================
        -- CRM SALES DETAILS
        -- =========================================

        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.crm_sales_details';
        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '>> Inserting Data Into: silver.crm_sales_details';
        INSERT INTO silver.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT 
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE 
                WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END,
            CASE 
                WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END,
            CASE 
                WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
            END,
            CASE 
                WHEN sls_sales IS NULL 
                     OR sls_sales <= 0 
                     OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_price * sls_quantity
                ELSE sls_sales
            END AS sls_sales,
            sls_quantity,
            CASE 
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS sls_price
        FROM bronze.crm_sales_details;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- =========================================
        -- ERP TABLES
        -- =========================================

        PRINT '=======================================';
        PRINT '>>Inserting Data Into: ERP TABLES';
        PRINT '=======================================';


        -- ERP CUSTOMER
        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.erp_cust_az12';
        TRUNCATE TABLE silver.erp_cust_az12;

        PRINT '>> Inserting Data Into: silver.erp_cust_az12';
        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        SELECT 
            CASE 
                WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE cid
            END,
            CASE 
                WHEN bdate > GETDATE() THEN NULL
                ELSE bdate
            END,
            CASE 
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
                ELSE 'n/a'
            END
        FROM bronze.erp_cust_az12;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- ERP LOCATION
        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.erp_loc_a101';
        TRUNCATE TABLE silver.erp_loc_a101;

        PRINT '>> Inserting Data Into: silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101 (
            cid,
            cntry
        )
        SELECT 
            REPLACE(cid, '-', ''),
            CASE 
                WHEN TRIM(cntry) IN ('US', 'USA', 'UNITED STATES') THEN 'United States'
                WHEN TRIM(cntry) IN ('UK', 'UNITED KINGDOM') THEN 'United Kingdom'
                WHEN TRIM(cntry) IN ('DE', 'GERMANY') THEN 'Germany'
                WHEN cntry IS NULL OR TRIM(cntry) = '' THEN 'n/a'
                ELSE cntry
            END
        FROM bronze.erp_loc_a101;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- ERP PRODUCT CATEGORY
        SET @start_time = GETDATE();

        PRINT '>> Trunacating Table: silver.erp_px_cat_g1v2';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2 (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT 
            id,
            cat,
            subcat,
            maintenance
        FROM bronze.erp_px_cat_g1v2;

        SET @end_time = GETDATE();

        PRINT '-------------------';
        PRINT '>> Load Duration: ' 
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) 
            + ' seconds.';
        PRINT '-------------------';


        -- =========================================
        -- FINAL LOG
        -- =========================================

        SET @batch_end_time = GETDATE();

        PRINT '=====================================';
        PRINT 'Inserting Process Is Completed';
        PRINT '    - Total Duration Time : '
            + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR)
            + ' seconds.';
        PRINT '=====================================';

    END TRY

    BEGIN CATCH

        PRINT '=======================================';
        PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER';
        PRINT 'Error Message : ' + ERROR_MESSAGE();
        PRINT 'Error Number  : ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State   : ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '=======================================';

    END CATCH

END;
