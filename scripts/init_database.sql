/*
========================================================
Description:
This script creates a database called "DataWarehouse"
and then creates three schemas inside it:

1- bronze : Raw data layer
2- silver : Cleaned and processed data layer
3- gold   : Business-ready data layer for analytics

⚠ WARNING:
This script will DROP the "DataWarehouse" database
if it already exists. This means ALL existing data
inside the database will be permanently deleted.

Use this script only in:
- Development environments
- Testing environments

Avoid running it directly in Production.
========================================================
*/

-- Switch to the system database
USE master;
GO

-- Check if the DataWarehouse database already exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouse;
END;
GO

-- Create the DataWarehouse database
CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

-- Create Schemas
CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO 
