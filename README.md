# Lotus Group Retail — SQL Data Modeling & Analytics Project

## Overview

This project takes a retail transaction dataset (Lotus Group Retail — a 9-table Star Schema
dataset simulating a multi-store retail business in Egypt) through a full analyst workflow:
data cleaning and standardization in **MySQL**, followed by category/store performance
analysis and dashboarding in **Tableau**.

The goal of this project is to demonstrate an end-to-end analytics skill set: relational
data modeling, SQL-based data cleaning, exploratory analysis, and BI dashboard development —
skills relevant to Category Analyst / Retail Insights Analyst roles that work with syndicated
retail scanner and panel data.

## Dataset

**Source:** [Lotus Group Retail — Star Schema BI Dataset](https://www.kaggle.com/) (Kaggle)

An educational dataset simulating a retail business across Egypt, intentionally containing
common real-world data quality issues (duplicate records, inconsistent formats, missing
values) to practice a full cleaning → modeling → analysis → dashboard workflow.

| Metric | Value |
|---|---|
| Total tables | 9 |
| Time period | Jan 2022 – Dec 2024 |
| Stores | 15 |
| Governorates | 13 |
| Customers | 3,050 (raw) |
| Products | 345 |
| Employees | 216 |
| Order details | 25,099 |
| Returns | 1,056 |

### Schema

The dataset follows a **Star Schema**: fact tables at the center, connected to surrounding
dimension tables via foreign keys.

**Dimension tables** (fixed/slow-changing attributes):
`dim_customers`, `dim_products`, `dim_stores`, `dim_employees`, `dim_date`

**Fact tables** (business events + measures):
`fact_orders_2022_2023`, `fact_orders_2024`, `fact_order_details`, `fact_returns`

*ER diagram — to be added here (`/diagrams/erd.png`).*

## Tools

- **MySQL / MySQL Workbench** — data cleaning, transformation, and querying
- **Tableau** — dashboarding and visualization

## Methodology

Before writing any cleaning logic, every table is put through two verification checks to
confirm the underlying keys can actually be trusted:

1. **Consistency check** — when an ID repeats, do its fixed attributes stay the same across
   every occurrence? (If not, the ID isn't reliable and can't be used for joins/deduping.)
2. **Referential integrity check** — does every foreign key in a fact table actually resolve
   to a row in the corresponding dimension table?

Only after a table passes these checks does cleaning proceed — and every destructive change
(`DELETE`, `UPDATE`) is previewed as a `SELECT` first and verified against an expected row
count before being executed.

## Known Data Quality Issues (per dataset documentation)

The dataset's official documentation flags the following intentional data quality issues,
listed here in their original Power Query terms alongside the SQL equivalent used in this
project:

| Issue (Power Query term) | SQL equivalent | Affected table(s) |
|---|---|---|
| Remove Duplicates | `GROUP BY` + surrogate key `DELETE` | `dim_customers` |
| Handle Missing Values | `IS NULL` checks, `UPDATE ... SET ... = NULL` | `dim_customers`, `fact_orders` |
| Change Data Types | `ALTER TABLE ... MODIFY COLUMN` | `dim_customers`, `dim_products` |
| Split Columns | `SUBSTRING()` / `LOCATE()` | `dim_customers`, `dim_products` |
| Trim Text | `TRIM()` / `REPLACE()` | `dim_customers`, `fact_orders` |
| Standardize Text Case | `UPPER()` / `LOWER()` / `CONCAT()` | `dim_customers` |
| Append Queries (stack rows) | `UNION` | `fact_orders` (2022–2023 + 2024 → combined) |
| Merge Queries (join columns) | `JOIN` | `fact_returns` (join back to `fact_order_details` to recover order-level detail) |

Tables not listed above (`dim_stores`, `dim_employees`, `dim_date`, `fact_order_details`)
are not flagged as having known issues — each will still go through the same verification
checks (see Methodology) before being confirmed clean, but no cleaning is assumed by default.

## Progress

| Table | Known issues to address | Status |
|---|---|---|
| `dim_customers` | Duplicates, missing values, data types, split columns, trim text, text casing | ✅ Cleaned |
| `dim_products` | Data types, split columns | ✅ Cleaned |
| `dim_stores` | None flagged — verify only | ✅ Verified clean |
| `dim_employees` | None flagged — verify only | ✅ Verified clean |
| `dim_date` | None flagged — verify only | ✅ Verified clean |
| `fact_orders_2022_2023` + `fact_orders_2024` | Missing values, trim text, append (UNION) into one table | ✅ Cleaned (combined into `fact_orders_all`) |
| `fact_order_details` | None flagged — verify only | ✅ Verified clean |
| `fact_returns` | Merge (JOIN) with `fact_order_details` to recover order-level detail | ⏸ Deferred — cleaning deferred until used in analysis |

---

## Case Study: Cleaning `dim_customers`

This table required the most extensive cleaning of the dataset and illustrates the full
methodology applied to every table in this project.

**Issues found and resolved:**

1. **Duplicate records (50 pairs / 100 rows)** — verified as true duplicates (not ID
   conflicts) by grouping on `customer_id` + every other column, then confirming no
   `customer_id` split across multiple distinct attribute combinations. Removed using an
   `AUTO_INCREMENT` surrogate key (`row_id`) after an initial attempt using
   `customer_id IN (...)` incorrectly deleted both copies of each duplicate (100 rows
   instead of the intended 50) — `customer_id` alone can't target a single row since it's
   not unique per row.
2. **`full_name`** — split into `first_name` / `last_name` using `LOCATE()` + `SUBSTRING()`,
   with edge cases (missing space, multiple names) knowingly left unhandled since these
   fields aren't used in aggregate trend analysis.
3. **`gender`** — inconsistent casing (`MALE`, `male`, `Male`) standardized to title case.
   Note: MySQL's default case-insensitive collation made `GROUP BY gender` *appear* clean
   (2 groups) even though 793 rows had inconsistent raw casing — a good reminder that
   `GROUP BY` results can mask underlying data issues.
4. **`birth_date`** — stored as text in two mixed formats (`YYYY-MM-DD` and `DD/MM/YYYY`,
   2,440 vs. 560 rows, identified via `REGEXP_REPLACE` pattern matching). Standardized to
   `YYYY-MM-DD` via conditional string parsing, verified with zero `NULL` results after
   conversion, then the column type was converted from `TEXT` to `DATE`.
5. **`phone`** — inconsistent spacing removed via `REPLACE()`; verified all numbers are a
   consistent 11 digits post-cleaning.
6. **`email`** — 374 missing values (stored as empty strings, not `NULL`). Checked all other
   tables for a possible email reference to backfill from — none exists — so missing values
   were standardized to `NULL`.
7. **Column types** — finalized appropriate `VARCHAR` lengths per column (e.g., `gender
   VARCHAR(10)`, `email VARCHAR(50)`) instead of leaving all text columns as unconstrained
   `TEXT`.

*Full SQL and reasoning: see [`/sql/01_dim_customers_cleaning.sql`](./sql/lotus_datacleaning.sql)*

---

## Case Study: Cleaning `dim_products`

**Issues found and resolved:**

1. **`product_name_raw` mixed formats** — investigated by splitting rows on the presence of
   a `|` delimiter: 308 rows (clothing) follow a pipe-delimited `"Name | Color | Size"`
   pattern; 37 rows (electronics) don't use a delimiter and follow no consistent structure.
2. **Split columns (clothing, 308 rows)** — added `product_name_cleaned`, `product_variant`,
   and `product_spec` columns. Used `LOCATE()` to find the position of the first and second
   `|`, then `SUBSTRING()`/`LEFT()` (applied in two passes rather than one deeply nested
   expression, for readability) to extract each segment, with `REPLACE()`/`TRIM()` to clean
   residual pipe characters and whitespace.
   - `product_variant` and `product_spec` are intentionally generic names (not
     `product_color`/`product_size`) since the same columns also apply to electronics
     (model / storage-capacity) if extended in the future.
3. **Split columns (electronics, 37 rows / ~11%)** — evaluated and **deliberately left
   unsplit**. These rows use highly inconsistent naming (varying segment counts, no reliable
   delimiter — e.g. `"iPhone 14 128GB"` vs. `"Logitech MX Master 3S"` vs.
   `"WD My Passport 2TB"`), so `product_variant`/`product_spec` remain `NULL` for this subset
   rather than forcing an unreliable split. This doesn't affect category/store-level trend
   analysis; electronics rows remain fully queryable via `WHERE category = 'Electronics'`.
4. **`unit_price_text` vs. `unit_price`** — confirmed the numeric portion of
   `unit_price_text` (e.g. `"EGP 510"`) duplicates the existing `unit_price` column, so no
   extra numeric column was created from it.

*Full SQL and reasoning: see [`/sql/02_dim_products_cleaning.sql`](./sql/lotus_datacleaning.sql)*

---

## Case Study: Combining & Cleaning `fact_orders_all`

**Issues found and resolved:**

1. **Two separate tables (`fact_orders_2022_2023`, `fact_orders_2024`)** — before combining,
   verified both tables share identical column names, order, and data types via
   `information_schema.columns` (rather than assuming they matched). Combined using
   `UNION ALL` (not `UNION`) into a new table, `fact_orders_all`, to explicitly control for
   duplicates rather than let an automatic dedupe hide whether any existed. Row count
   verified: 7,942 + 4,058 = 12,000, confirmed no rows were dropped or duplicated.
2. **Duplicate check** — grouped on `order_id` post-merge; zero rows returned, confirming no
   order appears in both source tables.
3. **`employee_id` missing values (632 rows / ~5%)** — checked all other tables for a
   possible reference to backfill from (none exists), then verified the format of non-missing
   values was 100% consistent (`EMP####` pattern via `REGEXP_REPLACE`) before confirming the
   632 missing rows were stored as empty strings (`LENGTH = 0`), not `NULL` — then
   standardized to `NULL`.
4. **`payment_method`** — trimmed leading/trailing whitespace with `TRIM()`.
5. **Referential integrity** — verified every `date_id` and `store_id` in `fact_orders_all`
   resolves to a row in `dim_date` and `dim_stores` respectively (0 unmatched rows for both),
   confirming these foreign keys are reliable.
6. **Column types** — `order_date` converted to `DATE`; ID columns converted to `VARCHAR`
   (kept as identifiers, not used for arithmetic); `total_revenue`/`total_cost` converted
   from `DOUBLE` to `DECIMAL(12,2)` after confirming (via `FLOOR()` comparison) that these
   columns do contain genuine decimal values — unlike `dim_products.unit_price`, which
   contains only whole numbers and was intentionally left as `INT`. Type choice was driven by
   each column's actual data, not by matching types across tables for consistency's sake.

*Full SQL and reasoning: see [`/sql/03_fact_orders_cleaning.sql`](./sql/lotus_datacleaning.sql)*

---

## Next Steps

- fact_returns received the same lightweight inspection as the other unflagged tables (dim_stores, dim_employees, dim_date, fact_order_details) — no issues observed, but not run through the full verification checklist used on dim_customers, dim_products, and fact_orders_all. Any issues that surface once these tables are actually used in analysis will be cleaned at that point, consistent with the pattern already applied throughout the project (e.g. deferring the electronics subset of dim_products).
- Write analysis queries: sales trends by store/category, top/underperforming SKUs,
  customer purchasing patterns
- Build Tableau dashboards connected to the cleaned MySQL database
