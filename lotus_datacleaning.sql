USE lotus_retail;

# Imported `dim_customers_stage` as back up table, stay untouched
# Data Cleaning
# 1. Identify duplicates

SELECT *
FROM lotus_retail.dim_customers;

# 1. Identify duplicates
SELECT customer_id, COUNT(customer_id)
FROM lotus_retail.dim_customers
GROUP BY customer_id
HAVING COUNT(customer_id) > 1
;
-- total 50 rows returned, all HAVING COUNT(customer_id) = 2


# Check if every duplicate combo is the same person, or if a single id assign to different people
SELECT *
FROM lotus_retail.dim_customers
WHERE customer_id IN (
SELECT customer_id
FROM lotus_retail.dim_customers
GROUP BY customer_id
HAVING COUNT(customer_id) > 1)
ORDER BY customer_id ASC
;
-- 100 rows returned, looks like 50 * 2 for each customer_id

SELECT customer_id
FROM (
SELECT customer_id,
ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY customer_id) AS row_num
FROM lotus_retail.dim_customers) AS table_row
WHERE row_num > 2 
;


SELECT customer_id, full_name, gender, birth_date, email, city, region, loyalty_tier, registration_date, COUNT(customer_id)
FROM lotus_retail.dim_customers
GROUP BY customer_id, full_name, gender, birth_date, email, city, region, loyalty_tier, registration_date
HAVING COUNT(customer_id) > 1
;
-- Group by customer_id + all attributes to check if each duplicate customer_id 
-- 50 rows all HAVING COUNT(customer_id) = 2

SELECT customer_id, COUNT(*)
FROM (
    SELECT customer_id, full_name, gender, birth_date, email, city, region, loyalty_tier, registration_date, COUNT(customer_id) AS cnt
    FROM lotus_retail.dim_customers
    GROUP BY customer_id, full_name, gender, birth_date, email, city, region, loyalty_tier, registration_date
    HAVING COUNT(customer_id) > 1
) AS grouped_result
GROUP BY customer_id
HAVING COUNT(*) > 1
;
-- 0 rows returned: each of the 50 duplicate customer_ids resolves to exactly one 

# Delete Duplicates
-- INCORRECT APPROACH
-- This DELETE removed 100 rows, not only the "extra" duplicate row (row_num > 1),
-- customer_id is NOT unique per row 
-- both the row_num=1 and row_num = 2 copies share the same customer_id value. 
-- So "WHERE customer_id IN (...)" matches and deletes ALL rows with that customer_id, not just the intended duplicate. 
-- This mistake caused 100 rows to be deleted instead of the intended 50.
-- Solution: assign a row_id for each record as primary key and use it as reference to trace records
DELETE FROM lotus_retail.dim_customers
WHERE customer_id IN          
( SELECT customer_id
FROM (
SELECT customer_id,
ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY customer_id) AS row_num
FROM lotus_retail.dim_customers) AS table_row
WHERE row_num > 1
);

# Assign new Primary Key
ALTER TABLE lotus_retail.dim_customers
ADD COLUMN row_id INT AUTO_INCREMENT PRIMARY KEY;

SELECT COUNT(row_id)
FROM lotus_retail.dim_customers;
-- return 3050 --

SELECT row_id, row_num
FROM (
SELECT row_id,
ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY customer_id) AS row_num
FROM lotus_retail.dim_customers) AS table_row
WHERE row_num > 1
-- 50 rows with row_num = 2

DELETE FROM lotus_retail.dim_customers
WHERE row_id IN (
SELECT row_id
FROM (
SELECT row_id,
ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY customer_id) AS row_num
FROM lotus_retail.dim_customers) AS table_row
WHERE row_num > 1)
;

SELECT COUNT(row_id)
FROM lotus_retail.dim_customers;
-- return 3000, 50 duplicated deleted sucessfully

SELECT *
FROM lotus_retail.dim_customers;

# 2. Standardizing data
# 1）Break up full name into first and last name
# 2）Gender: letter case, capitalize the first letter only
# 3）Birthdate: make them 1 format
# 4）phone: make them 1 format
# 5）Email: If no email address, put it as Null, but need to check other tables to see if we can pop up email address


# 1）Break up full name into first and last name

# Check if there is a full name witouht any space
SELECT full_name,space_position
FROM (
SELECT full_name,
LOCATE(' ', full_name) AS space_position
FROM lotus_retail.dim_customers
) space_check
WHERE space_position = 0 ;
-- nothing returns

# Check if there is a full name has 2 spaces
SELECT full_name, space_count
FROM
(SELECT full_name, 
       LENGTH(full_name) - LENGTH(REPLACE(full_name, ' ', '')) AS space_count
FROM lotus_retail.dim_customers
) AS length_check
WHERE space_count > 1
-- nothing returns

# Breaking up full name
SELECT full_name,
TRIM(LEFT(full_name,LOCATE(' ', full_name))) AS first_name,
TRIM(SUBSTRING(full_name,LOCATE(' ', full_name))) AS last_name
FROM lotus_retail.dim_customers
;

ALTER TABLE lotus_retail.dim_customers
ADD COLUMN first_name VARCHAR(50),
ADD COLUMN last_name VARCHAR(50)
;

SELECT *
FROM lotus_retail.dim_customers;

UPDATE lotus_retail.dim_customers
SET first_name = TRIM(LEFT(full_name,LOCATE(' ', full_name)));

UPDATE lotus_retail.dim_customers
SET last_name = TRIM(SUBSTRING(full_name,LOCATE(' ', full_name)));
-- both columns updated sucessfully 

# 2）Gender: letter case, capitalize the first letter only

SELECT gender
FROM lotus_retail.dim_customers;

SELECT TRIM(UPPER(LEFT(LOWER(gender),1)))
FROM lotus_retail.dim_customers;

SELECT LOWER(SUBSTRING(gender,2))
FROM lotus_retail.dim_customers;

SELECT TRIM(CONCAT(UPPER(LEFT(LOWER(gender),1)), LOWER(SUBSTRING(gender,2))))
FROM lotus_retail.dim_customers;

SELECT gender, COUNT(*) 
FROM lotus_retail.dim_customers 
GROUP BY gender;

UPDATE lotus_retail.dim_customers
SET gender = TRIM(CONCAT(UPPER(LEFT(LOWER(gender),1)), LOWER(SUBSTRING(gender,2))));

# 3）Birthdate: make them 1 format
# Check how many pattern types are there
SELECT REGEXP_REPLACE(birth_date, '[0-9]', 'N') AS date_pattern, COUNT(*) 
FROM lotus_retail.dim_customers
GROUP BY date_pattern;
-- NNNN-NN-NN 2440, NN/NN/NNNN 560

SELECT birth_date
FROM lotus_retail.dim_customers
WHERE birth_date LIKE '%/%';

SELECT birth_date
FROM lotus_retail.dim_customers
WHERE birth_date LIKE '%-%';


SELECT birth_date, DATE_FORMAT(birth_date,'%Y-%m-%d')
FROM lotus_retail.dim_customers
WHERE DATE_FORMAT(birth_date,'%M %d %Y') IS NULL
;
-- Note: birth_date has inconsistent formats and some unsure day/month values, 09/06/1979.
-- Most values seems in a format: DD/MM/YYYY, so I will treat all values are in this format
-- Only flip day/month when the assumed month position exceeds 12

SELECT month
FROM (
SELECT birth_date, SUBSTRING(birth_date,1,2) AS date, SUBSTRING(birth_date,4,2) AS month, SUBSTRING(birth_date,7,4) as year
FROM lotus_retail.dim_customers
WHERE DATE_FORMAT(birth_date,'%Y-%m-%d') IS NULL
) AS null_birth_dates
WhERE month > 12 ;
-- 0 row returned, so I will assume all values in month coloumn are correct.

SELECT birth_date, DATE_FORMAT(birth_date,'%Y-%m-%d')
FROM lotus_retail.dim_customers;

SELECT birth_date
FROM(
SELECT birth_date,
CASE 
	WHEN birth_date LIKE '%/%' THEN DATE_FORMAT(CONCAT(SUBSTRING(birth_date,7,4),'-',SUBSTRING(birth_date,4,2),'-',SUBSTRING(birth_date,1,2)),'%Y-%m-%d')
    ELSE DATE_FORMAT(birth_date,'%Y-%m-%d')
END AS new_birth_date
FROM lotus_retail.dim_customers) as birth_date_cleaned
WHERE new_birth_date IS NULL
; -- 0 row return, all dates should be identical date format

UPDATE lotus_retail.dim_customers
SET birth_date = 
CASE 
	WHEN birth_date LIKE '%/%' THEN DATE_FORMAT(CONCAT(SUBSTRING(birth_date,7,4),'-',SUBSTRING(birth_date,4,2),'-',SUBSTRING(birth_date,1,2)),'%Y-%m-%d')
    ELSE DATE_FORMAT(birth_date,'%Y-%m-%d')
END; -- 560 rows affacted

# change the datetype from text to date
ALTER TABLE lotus_retail.dim_customers
MODIFY COLUMN birth_date DATE;

SELECT *
FROM lotus_retail.dim_customers;

# 4）phone: make them 1 format
# All customers have a phone number on file, which will be standardized into a single consistent format next
SELECT REGEXP_REPLACE(phone, '[0-9]', 'N') AS phone_pattern, COUNT(*) 
FROM lotus_retail.dim_customers
GROUP BY phone_pattern
HAVING phone_pattern LIKE '% %';
-- without Having clause, it has 4 patterms; with Having clause, it has 3 patterns
-- looks like all patterns only have a space, no other symbols

SELECT phone, LENGTH(REPLACE(phone,' ',''))
FROM lotus_retail.dim_customers
WHERE LENGTH(REPLACE(phone,' ','')) != 11;
-- 0 row returned

UPDATE lotus_retail.dim_customers
SET phone = REPLACE(phone,' ','');

SELECT REGEXP_REPLACE(phone, '[0-9]', 'N') AS phone_pattern, LENGTH(phone), COUNT(*) 
FROM lotus_retail.dim_customers
GROUP BY phone_pattern, LENGTH(phone);
-- now it only has 1 pattern, same length, 3000 counts. 


# 5）Email: If no email address, put it as Null, but need to check other tables to see if we can pop up email address
# Checked all other tables for potential email references — none exist, so missing emails are set to NULL rather than backfilled. 

SELECT check_email, COUNT(*)
FROM (
SELECT email,
CASE 
	WHEN email LIKE '%@%' THEN 'has email'
    ELSE 'no emmail'
END AS check_email
FROM lotus_retail.dim_customers) AS count_emails
GROUP BY check_email;
-- saying 2626 has email; 374 no email
-- For 374 no email, give it a NULL

SELECT email, LENGTH(email), COUNT(*)
FROM lotus_retail.dim_customers
WHERE email NOT LIKE '%@%'
GROUP BY email, LENGTH(email)
; -- 374 emails' length = 0 

UPDATE lotus_retail.dim_customers
SET email = NULL 
WHERE LENGTH(email) = 0;
-- 374 rows affacted

#3. Change Datatype for Columns

SELECT *
FROM lotus_retail.dim_customers;

# Check if loyalty_tier and registration_date need to cleaning
# Both look good

SELECT loyalty_tier, LENGTH(loyalty_tier), COUNT(*)
FROM lotus_retail.dim_customers
GROUP BY loyalty_tier, LENGTH(loyalty_tier); 

SELECT REGEXP_REPLACE(registration_date, '[0-9]', 'N') AS date_pattern, COUNT(*) 
FROM lotus_retail.dim_customers
GROUP BY date_pattern;

ALTER TABLE lotus_retail.dim_customers
MODIFY COLUMN customer_id VARCHAR(50),
MODIFY COLUMN full_name VARCHAR(100),
MODIFY COLUMN gender VARCHAR(10),
MODIFY COLUMN phone VARCHAR(11),
MODIFY COLUMN email VARCHAR(50),
MODIFY COLUMN city VARCHAR(50),
MODIFY COLUMN region VARCHAR(50),
MODIFY COLUMN loyalty_tier VARCHAR(10),
MODIFY COLUMN registration_date DATE;


SELECT *
FROM lotus_retail.dim_customers;

# Cleaning dim_products, imported `dim_products_stage` as back up table, stay untouched
# Per dataset documentation, known issues: Change Data Types, Split Columns.
# Will verify actual column contents first before assuming this is the complete list of issues.

SELECT * 
FROM lotus_retail.dim_products;

#1. Clean the product_name_raw column
#Check the product types and format patterns

SELECT 
    CASE WHEN product_name_raw LIKE '%|%' THEN 'clothing_format' 
    ELSE 'other_format' END AS format_type,
    COUNT(*)
FROM lotus_retail.dim_products
GROUP BY format_type;

SELECT *
FROM lotus_retail.dim_products
WHERE product_name_raw NOT LIKE '%|%';
-- all are electronics

# will split and add 2 columns
-- product_variant: color (clothing) or model (electronics) — "which version of this product"
-- product_spec: size (clothing) or storage/capacity (electronics) — "which specification/configuration"

ALTER TABLE lotus_retail.dim_products
ADD COLUMN product_name_cleaned VARCHAR(100),
ADD COLUMN product_variant VARCHAR(50),
ADD COLUMN product_spec VARCHAR(50);

SELECT
REPLACE(product_name_raw,SUBSTRING(product_name_raw, (LOCATE('|', product_name_raw, LOCATE('|', product_name_raw) +1))),''),
REPLACE(SUBSTRING(product_name_raw, (LOCATE('|', product_name_raw, LOCATE('|', product_name_raw) +1))),'|','')
FROM lotus_retail.dim_products

UPDATE lotus_retail.dim_products
SET product_name_cleaned = REPLACE(product_name_raw,SUBSTRING(product_name_raw, (LOCATE('|', product_name_raw, LOCATE('|', product_name_raw) +1))),''),
    product_spec = TRIM(REPLACE(SUBSTRING(product_name_raw, (LOCATE('|', product_name_raw, LOCATE('|', product_name_raw) +1))),'|',''))
WHERE product_name_raw LIKE '%|%';
-- columns updated successfully

SELECT TRIM(REPLACE(LEFT(product_name_cleaned, LOCATE('|', product_name_cleaned)),'|','')),
TRIM(REPLACE(SUBSTRING(product_name_cleaned, LOCATE('|', product_name_cleaned)),'|',''))
FROM lotus_retail.dim_products
WHERE product_name_raw LIKE '%|%';

UPDATE lotus_retail.dim_products
SET product_name_cleaned = TRIM(REPLACE(LEFT(product_name_cleaned, LOCATE('|', product_name_cleaned)),'|',''))
WHERE product_name_raw LIKE '%|%';
-- updated sucessfully


SELECT SUBSTRING(product_name_raw,LOCATE('|', product_name_raw))
FROM lotus_retail.dim_products;

UPDATE lotus_retail.dim_products
SET product_variant = SUBSTRING(product_name_raw,LOCATE('|', product_name_raw))
WHERE product_name_raw LIKE '%|%';
-- updated sucessfully

SELECT REPLACE(LEFT(product_variant,LOCATE('|',product_variant, LOCATE('|',product_variant)+1)),'|','')
FROM lotus_retail.dim_products
WHERE product_name_raw LIKE '%|%';

UPDATE lotus_retail.dim_products
SET product_variant = REPLACE(LEFT(product_variant,LOCATE('|',product_variant, LOCATE('|',product_variant)+1)),'|','')
WHERE product_name_raw LIKE '%|%';
-- updated sucessfully
-- All product names with '|', now start working on names without '|'

SELECT *
FROM lotus_retail.dim_products
WHERE product_name_raw NOT LIKE '%|%';

-- Note: product_variant / product_spec are only populated for the 308 clothing rows 
-- (pipe-delimited "Name | Color | Size" format). The 37 electronics rows (~11%) use without '|', are highly inconsistent naming conventions 
-- e.g. "iPhone 14 128GB" vs "Logitech MX Master 3S" vs "WD My Passport 2TB") and are left with NULL variant/spec values rather than force an unreliable split. 
-- This does not affect category/store-level trend analysis, which does not depend on these fields. 
-- Electronics rows can still be isolated directly via WHERE category = 'Electronics' when needed.

#2. Clean unit_price_text

#1) Check if there is any currency except 'EGP'
SELECT 
    CASE WHEN unit_price_text LIKE 'EGP%' THEN 'EGP' 
    ELSE 'other_currency' END AS currency_type,
    COUNT(*)
FROM lotus_retail.dim_products
GROUP BY currency_type;
-- no other currency type

#2) Add new column: currency
ALTER TABLE lotus_retail.dim_products
ADD COLUMN currency VARCHAR(10);

#3) Extract the currency code, and insert it into the currency column
SELECT TRIM(LEFT(unit_price_text, LOCATE(' ', unit_price_text)))
FROM lotus_retail.dim_products;

UPDATE lotus_retail.dim_products
SET currency = TRIM(LEFT(unit_price_text, LOCATE(' ', unit_price_text)));
-- updated sucessfully

#4) Extract prices from `unit_price_text`, check if they are identical with `unit_price`.
#If yes, will keep unit_price as it is.

SELECT CONVERT(TRIM(SUBSTRING(unit_price_text, LOCATE(' ', unit_price_text))),UNSIGNED)
FROM lotus_retail.dim_products;

SELECT * 
FROM lotus_retail.dim_products
WHERE CONVERT(TRIM(SUBSTRING(unit_price_text, LOCATE(' ', unit_price_text))),UNSIGNED) != unit_price;
-- 0 row returned, so no need to extract the prices from `unit_price_text`

ALTER TABLE lotus_retail.dim_products
MODIFY COLUMN product_id VARCHAR(20),
MODIFY COLUMN product_name_raw VARCHAR(100),
MODIFY COLUMN category VARCHAR(20),
MODIFY COLUMN subcategory VARCHAR(50),
MODIFY COLUMN brand VARCHAR(50),
MODIFY COLUMN unit_price_text VARCHAR(20);

# Cleaning fact_orders_2022_2023 & fact_orders_2024, imported back up tables, stay untouched
# fact_orders known issues: 
# 1). missing employee_id values (checked against all other tables for a possible join to backfill — no reference exists, so will be set to NULL)
# 2). inconsistent text formatting (extra whitespace), and two separate tables (fact_orders_2022_2023, fact_orders_2024) that need to be combined.

SELECT * 
FROM lotus_retail.fact_orders_2022_2023;

SELECT * 
FROM lotus_retail.fact_orders_2024;

SELECT column_name, data_type, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'lotus_retail' AND table_name = 'fact_orders_2022_2023'
ORDER BY ordinal_position;

SELECT column_name, data_type, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'lotus_retail' AND table_name = 'fact_orders_2024'
ORDER BY ordinal_position;

-- Verified both tables have identical column names, order, and data types (via information_schema.columns) 
-- will UNION them first, then clean the combined table.

SELECT * 
FROM lotus_retail.fact_orders_2022_2023
UNION ALL
SELECT * 
FROM lotus_retail.fact_orders_2024;

SELECT COUNT(*)
FROM lotus_retail.fact_orders_2022_2023;
-- 7942 rows

SELECT COUNT(*)
FROM lotus_retail.fact_orders_2024;
-- 4058 rows

SELECT COUNT(*)
FROM (
SELECT * 
FROM lotus_retail.fact_orders_2022_2023
UNION ALL
SELECT * 
FROM lotus_retail.fact_orders_2024) AS fact_orders_all;
-- 12000 rows, all rows combined

CREATE TABLE lotus_retail.fact_orders_all AS
SELECT * 
FROM lotus_retail.fact_orders_2022_2023
UNION ALL
SELECT * 
FROM lotus_retail.fact_orders_2024;

SELECT * 
FROM lotus_retail.fact_orders_all;

# 1. Identify duplicates
SELECT order_id, COUNT(order_id)
FROM lotus_retail.fact_orders_all
GROUP BY order_id
HAVING COUNT(order_id) > 1;
-- no duplicates

# 2. check employee_id patterns and how many rows have empty employee_id, set those empty ones NULL
SELECT REGEXP_REPLACE(employee_id, '[0-9]', 'N') AS employee_pattern, COUNT(*) 
FROM lotus_retail.fact_orders_all
GROUP BY employee_pattern;
-- only 2 patterns:'EMPNNNN' and '';


SELECT check_employee_id, COUNT(*)
FROM (
SELECT employee_id,
CASE 
	WHEN employee_id LIKE '%EMP%' THEN 'has employee_id'
    ELSE 'no employee_id'
END AS check_employee_id
FROM lotus_retail.fact_orders_all) AS count_employee_id
GROUP BY check_employee_id;
-- both returned the same counts

SELECT employee_id, LENGTH(employee_id),COUNT(*)
FROM lotus_retail.fact_orders_all
WHERE employee_id NOT LIKE '%EMP%'
GROUP BY employee_id, LENGTH(employee_id);
-- all 632 rows length = 0 

UPDATE lotus_retail.fact_orders_all
SET employee_id = NULL
WHERE LENGTH(employee_id) = 0;
-- 632 rows updated successfully

SELECT * 
FROM lotus_retail.fact_orders_all;fact_orders_all

SELECT payment_method, TRIM(payment_method)
FROM lotus_retail.fact_orders_all;

UPDATE lotus_retail.fact_orders_all
SET payment_method = TRIM(payment_method);

SELECT date_id
FROM lotus_retail.fact_orders_all
WHERE date_id NOT IN
(SELECT date_id
FROM lotus_retail.dim_date);
-- nothing returned

SELECT store_id
FROM lotus_retail.fact_orders_all
WHERE store_id NOT IN
(SELECT store_id
FROM lotus_retail.dim_stores);
-- nothing returned

ALTER TABLE lotus_retail.fact_orders_all
MODIFY COLUMN order_id VARCHAR(50),
MODIFY COLUMN order_date DATE,
MODIFY COLUMN customer_id VARCHAR(50),
MODIFY COLUMN employee_id VARCHAR(50),
MODIFY COLUMN payment_method VARCHAR(50),
MODIFY COLUMN order_status VARCHAR(50),
MODIFY COLUMN total_revenue DECIMAL(12,2),
MODIFY COLUMN total_cost DECIMAL(12,2);

# Summary
# Cleaning covers all issues flagged in the dataset's documentation, plus additional issues found through independent verification. 
# This isn't a guarantee of a fully clean dataset — any remaining issues will be addressed with targeted cleaning as they surface during analysis.
