# Task 21: DB2 Order Loader with Foreign Key Validation

## Overview
This task implements a COBOL-DB2 batch program that loads order records from a sequential file into a DB2 table while performing multi-stage validation:
1.  **Field Validation**: Checks for empty Order IDs, valid date months, and positive quantities.
2.  **Referential Integrity (Foreign Key)**: Manually verifies that the product exists in the `TB_PRODUCTS` table before attempting an insert.
3.  **Duplicate Detection**: Uses both an in-memory array (for the first 100 records) and DB2 `-803` SQLCODE handling to prevent duplicate `ORDER_ID` entries.
4.  **Batch Processing**: Implements transaction control with `COMMIT` every 100 successful inserts.

## Files
- `COBOL/DB2JOB21.cbl`: Main COBOL-DB2 program logic.
- `JCL/COBDB2CP.jcl`: Job to create input data, compile, and run the program.
- `SQL/CREATE.TB_PRODUCTS.sql`: DDL for the product master table.
- `SQL/CREATE.TB_ORDERS.sql`: DDL for the orders table with Foreign Key constraint.
- `SQL/INSERT.TB_PRODUCTS.sql`: Initial data for the products table.
- `DATA/ORDERS.txt`: (Included in JCL) Sample order records.
- `OUTPUT/SYSOUT.txt`: Execution summary and processing statistics.

## Record Layouts
### Input Order Record (80 bytes)
| Field | Position | Format | Description |
| :--- | :--- | :--- | :--- |
| `ORDER-ID` | 1-6 | `X(6)` | Unique Order Identifier |
| `ORDER-DATE` | 7-14 | `9(8)` | Date in YYYYMMDD format |
| `PROD-ID` | 15-19 | `X(5)` | Product Identifier |
| `QUANTITY` | 20-23 | `9(4)` | Order Quantity |
| `FILLER` | 24-80 | `X(57)` | Reserved for future use |

## Processing Phases
1.  **Phase 1: Validation**
    - `ORDER-ID` must not be spaces.
    - `ORDER-ID` must not have been processed in the current batch (checked against `PROCESSED-ORDERS` array).
    - `ORDER-DATE` month must be between '01' and '12'.
    - `QUANTITY` must be greater than 0.
2.  **Phase 2: Product Lookup**
    - Program selects `PROD_NAME` and `UNIT_PRICE` from `TB_PRODUCTS`.
    - If `SQLCODE 100`, record is rejected (Referential Integrity check).
3.  **Phase 3: DB2 Insert**
    - Inserts valid records into `TB_ORDERS`.
    - Converts `YYYYMMDD` input date to `YYYY-MM-DD` DB2 format.
    - Handles `-803` for duplicate primary keys.
4.  **Phase 4: Transaction Control**
    - Issues `COMMIT` every 100 successful inserts.
    - Performs `ROLLBACK` on critical SQL errors or file status failures.

## JCL Steps
1.  **`DELREP`**: Deletes old output datasets.
2.  **`STEPINS`**: Creates the input sequential file using `IEBGENER`.
3.  **`PREP`**: DB2 Pre-compile, COBOL Compile, and Link-edit.
4.  **`RUNPROG`**: Executes the program using `IKJEFT01` within the `DBDG` subsystem.

## Key COBOL + DB2 Concepts Used
- **Manual FK Validation**: Using `SELECT` to verify parent record existence before child record `INSERT`.
- **In-Memory Tracking**: Using an `OCCURS 100` array to detect duplicates within the same file without querying DB2.
- **Dynamic Date Formatting**: Converting `YYYYMMDD` from file to `YYYY-MM-DD` for DB2 DATE columns.
- **Transaction Control**: Balancing performance with batch commits every 100 records.

## Output
### Execution Summary (SYSOUT)
```
----------------------------------------
ORDER LOAD SUMMARY
----------------------------------------
RECORDS PROCESSED: 10
RECORDS INSERTED: 4
RECORDS ERRORS: 6
COMMIT BATCHES: 1
----------------------------------------
```

## How to Run
1.  Initialize products in `TB_PRODUCTS` using `SQL/INSERT.TB_PRODUCTS.sql`.
2.  Ensure tables are created via `SQL/CREATE.TB_ORDERS.sql` and `SQL/CREATE.TB_PRODUCTS.sql`.
3.  Submit `JCL/COBDB2CP.jcl` to load and validate orders.

## Notes
- **Note**: In-memory duplicate order ID check covers only the first 100 successfully inserted orders. Beyond that, duplicate detection falls through to DB2 -803 handling, which still rejects duplicates correctly but bypasses the in-memory array.
- The `ORDER.LOG` contains both the record-level status and a final summary of total processed/inserted/rejected counts.
- Critical errors during lookup or insertion trigger a full `ROLLBACK` to maintain batch consistency.
- Tested on IBM z/OS with DB2 for z/OS.
