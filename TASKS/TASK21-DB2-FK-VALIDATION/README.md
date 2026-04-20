# Task 21 — DB2 Order Loader with Foreign Key Validation

## Overview

Implements a COBOL-DB2 batch program that loads order records from a sequential input file into the `TB_ORDERS` table while enforcing field-level validation, reference checks against a product master table, duplicate detection, and controlled transaction commits.

The core technique is **Foreign Key Validation with Pre-Insert Lookup**: before inserting an order row, the program verifies that the referenced product exists in `TB_PRODUCTS`. Referential integrity is therefore enforced both by application logic and by the DB2 foreign key constraint.

---

## DB2 Tables

### `TB_PRODUCTS` (Master Table)

```sql
CREATE TABLE TB_PRODUCTS (
    PROD_ID     CHAR(5) NOT NULL,
    PROD_NAME   VARCHAR(30),
    UNIT_PRICE  DECIMAL(7, 2),
    STOCK_QTY   INTEGER,
    PRIMARY KEY (PROD_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `PROD_ID` | `CHAR(5)` | **Primary key** — Product ID used by orders |
| `PROD_NAME` | `VARCHAR(30)` | Product display name |
| `UNIT_PRICE` | `DECIMAL(7,2)` | Unit price used for order pricing |
| `STOCK_QTY` | `INTEGER` | Current stock quantity in units |

### `TB_ORDERS` (Transaction Table)

```sql
CREATE TABLE TB_ORDERS (
    ORDER_ID    CHAR(6) NOT NULL,
    ORDER_DATE  DATE,
    PROD_ID     CHAR(5),
    QUANTITY    INTEGER,
    PRIMARY KEY (ORDER_ID),
    FOREIGN KEY (PROD_ID) REFERENCES TB_PRODUCTS(PROD_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `ORDER_ID` | `CHAR(6)` | **Primary key** — Unique order identifier |
| `ORDER_DATE` | `DATE` | Order date (YYYY-MM-DD) |
| `PROD_ID` | `CHAR(5)` | Product ID; must exist in `TB_PRODUCTS.PROD_ID` |
| `QUANTITY` | `INTEGER` | Ordered quantity; must be greater than zero |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `ORDIN` | `ORDERS.FILE` | PS | INPUT | Sequential order input, RECFM=F, LRECL=80 |
| `ORDLOG` | `ORDER.LOG` | PS | OUTPUT | Order load log with error and success messages |

### Input Record Layout — `ORDERS.FILE` (`ORDIN`), LRECL=80, RECFM=F

| Field | Position | Format | Description |
|---|---|---|---|
| `ORDER-ID` | 1–6 | `X(6)` | Unique Order Identifier (must not be spaces) |
| `ORDER-DATE` | 7–14 | `9(8)` | Date in `YYYYMMDD` format (month 01–12) |
| `PROD-ID` | 15–19 | `X(5)` | Product Identifier (foreign key to `TB_PRODUCTS`) |
| `QUANTITY` | 20–23 | `9(4)` | Order Quantity (> 0) |
| `FILLER` | 24–80 | `X(57)` | Reserved |

### Output Record Layout — `ORDER.LOG` (`ORDLOG`)

| Field | Picture | Description |
|---|---|---|
| `LOG-REC` | `X(120)` | One log line per input record with order id, product id, and status message |

Typical status messages include:
- `INSERTED (VALID ORDER)` — successful insert into `TB_ORDERS`
- `REJECTED: PROD-ID NOT FOUND IN TB_PRODUCTS` — failed referential check
- `VALIDATION ERROR: ORDER-ID EMPTY`
- `VALIDATION ERROR: ORDER-DATE MONTH INVALID`
- `VALIDATION ERROR: QUANTITY NOT > 0`
- `DUPLICATE ORDER-ID (IN-MEMORY)`
- `DUPLICATE ORDER-ID (DB2 -803)`

---

## Business Logic

The program applies a multi-stage pipeline to each order record: field validation, duplicate detection, master lookup, insert, and batch commit.

1. **Field Validation**
   - Check `ORDER-ID` is not spaces.
   - Check `ORDER-DATE` is 8 digits with month between `01` and `12`.
   - Check `QUANTITY` is numeric and greater than zero.

2. **Referential Integrity (Foreign Key Validation)**
   - Before insert, perform a `SELECT` on `TB_PRODUCTS` using `PROD-ID`.
   - If `SQLCODE = 0`: product exists, continue.
   - If `SQLCODE = 100`: product does not exist → log error and skip insert.

3. **Duplicate Prevention**
   - **In-Memory Check**: Maintain an internal array for the first 100 successfully inserted `ORDER-ID`s to detect duplicates quickly within the job.
   - **Database Check**: Rely on DB2 `-803` (duplicate key on `ORDER_ID`) to catch any additional duplicates at table level and log them.

4. **Transaction Control**
   - Issue `COMMIT` after every 100 successful inserts.
   - On critical SQL errors (e.g., severe negative SQLCODE) or file status failure, perform `ROLLBACK` and terminate to keep DB consistent.

---

## Program Flow

1. **Initialization**
   - Open input and log files.
   - Initialize DB2 connection and counters.

2. **Main Processing Loop**
   - Read next record from `ORDERS.FILE`.
   - Perform field validation on `ORDER-ID`, `ORDER-DATE`, and `QUANTITY`.
   - Check in-memory duplicate array for `ORDER-ID`.
   - Perform DB2 `SELECT` on `TB_PRODUCTS` with `PROD-ID` to verify parent exists.
   - If all checks pass, convert `ORDER-DATE` from `YYYYMMDD` to `YYYY-MM-DD`.
   - Execute `INSERT` into `TB_ORDERS`.
   - Handle `SQLCODE`:
     - `0` — success, update counters, update in-memory array, and log success.
     - `-803` — duplicate key; log duplicate and increment error counter.
     - `< 0` (critical, not handled explicitly) — log, `ROLLBACK`, and terminate.
   - After each successful insert, increment commit counter; when it reaches 100, issue `COMMIT` and reset.

3. **Termination**
   - After end-of-file, issue final `COMMIT` for any remaining successful inserts.
   - Print summary to SYSOUT.
   - Close all files and disconnect from DB2.

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Product exists in `TB_PRODUCTS` | `0` (on product lookup) | Proceed to insert into `TB_ORDERS` |
| Product not found | `100` (on product lookup) | Log referential error and skip insert |
| Order insert successful | `0` (on `INSERT`) | Count insert and possibly commit |
| Duplicate order key | `-803` | Log duplicate and skip record |
| Critical SQL error | `< 0` (other than handled cases) | `ROLLBACK` + terminate |

---

## Test Data

All sample data and resulting table images are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/ORDERS.FILE`](DATA/ORDERS.FILE) | Sample order input file (10 records) |
| [`DATA/ORDER.LOG`](DATA/ORDER.LOG) | Log of validation failures and successful inserts |
| [`DATA/TB.TB_PRODUCTS`](DATA/TB.TB_PRODUCTS) | Image of the `TB_PRODUCTS` table after loading master data |
| [`DATA/TB.TB_ORDERS`](DATA/TB.TB_ORDERS) | Image of the `TB_ORDERS` table after program execution |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
----------------------------------------
ORDER LOAD SUMMARY
----------------------------------------
RECORDS PROCESSED: 10
RECORDS INSERTED:  4
RECORDS ERRORS:    6
COMMIT BATCHES:    1
----------------------------------------
```

---

## How to Run

1. **Database Setup**
   - Execute the SQL scripts in the [`SQL/`](SQL/) directory to create and populate DB2 tables:
     - [`SQL/CREATE.TB_PRODUCTS.sql`](SQL/CREATE.TB_PRODUCTS.sql)
     - [`SQL/INSERT.TB_PRODUCTS.sql`](SQL/INSERT.TB_PRODUCTS.sql)
     - [`SQL/CREATE.TB_ORDERS.sql`](SQL/CREATE.TB_ORDERS.sql)

2. **Program Execution**
   - Submit [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl).
   - The job will:
     - Create the input dataset and load `ORDERS.FILE` (step `STEPINS`).
     - Pre-compile, compile, and link the COBOL-DB2 program (step `PREP`).
     - Run the program under `IKJEFT01` (step `RUNPROG`).

---

## Key COBOL + DB2 Concepts Used

- **Foreign Key Validation via Lookup** — uses `SELECT` against `TB_PRODUCTS` to ensure `PROD-ID` exists before insert.
- **In-Memory Duplicate Detection** — `OCCURS` table for the first 100 `ORDER-ID`s to catch duplicates without going to DB2.
- **DB2 Duplicate Key Handling (`-803`)** — relies on DB2 primary key constraint to catch any remaining duplicates.
- **Date Conversion** — transforms `YYYYMMDD` string into DB2 `DATE` format `YYYY-MM-DD` before insert.
- **Batch Commit / Rollback** — controlled commits every 100 records and rollback on severe errors to keep data consistent.

---

## Notes

- Application-level referential and duplicate checks complement DB2 constraints, making behavior explicit in logs and summary counters.
- The in-memory duplicate table is intentionally limited to 100 entries to keep storage simple; DB2 still protects table integrity beyond that.
- Critical SQL or file errors trigger a rollback and controlled termination so the DB2 state always reflects full commit units.
- Tested on IBM z/OS with DB2 and Enterprise COBOL.
