# Task 21: DB2 Order Loader with Foreign Key Validation

## Overview
This task implements a COBOL-DB2 batch program that loads order records from a sequential file into a DB2 table while performing multi-stage validation, including referential integrity checks and duplicate detection.

---

## Business Logic
The program processes a batch of orders with the following rules:
1. **Field Validation**:
   - `ORDER-ID` must not be spaces.
   - `ORDER-DATE` month must be between '01' and '12'.
   - `QUANTITY` must be greater than 0.
2. **Referential Integrity**:
   - Before inserting an order, the program must verify that the `PROD-ID` exists in the `TB_PRODUCTS` master table.
3. **Duplicate Prevention**:
   - **In-Memory Check**: The program tracks the first 100 successful `ORDER-ID`s in an internal array to catch duplicates quickly.
   - **Database Check**: For all records, DB2 `-803` SQLCODE handling is used to prevent duplicate primary keys in the table.
4. **Transaction Control**:
   - Issues a `COMMIT` every 100 successful inserts to balance performance and recovery.
   - Performs a `ROLLBACK` if a critical SQL error or file status failure occurs.

---

## Program Flow
1. **Initialization**: Open input file and connect to DB2.
2. **Main Process**:
   - Read each record from the input sequential file.
   - **Validation Phase**: Check basic field constraints and in-memory duplicate array.
   - **Lookup Phase**: Query `TB_PRODUCTS` for `PROD_NAME` and `UNIT_PRICE`. If not found (`SQLCODE 100`), reject the record.
   - **Insertion Phase**: Convert date to `YYYY-MM-DD` and insert into `TB_ORDERS`.
   - **Batch Control**: Increment counters and issue `COMMIT` every 100 records.
3. **Termination**: Print execution summary (SYSOUT), close files, and disconnect from DB2.

---

## Files
- `COBOL/DB2JOB21.cbl`: Main COBOL-DB2 program logic.
- `JCL/COBDB2CP.jcl`: Job to create input data, compile, and run the program.
- `SQL/CREATE.TB_PRODUCTS.sql`: DDL for the product master table.
- `SQL/CREATE.TB_ORDERS.sql`: DDL for the orders table with Foreign Key constraint.
- `SQL/INSERT.TB_PRODUCTS.sql`: Initial data for the products table.
- `DATA/ORDERS.txt`: (Included in JCL) Sample order records.
- `OUTPUT/SYSOUT.txt`: Execution summary and processing statistics.

---

## Test Data

### Input Order Record (80 bytes)
| Field | Position | Format | Description |
|---|---|---|---|
| `ORDER-ID` | 1-6 | `X(6)` | Unique Order Identifier |
| `ORDER-DATE` | 7-14 | `9(8)` | Date in YYYYMMDD format |
| `PROD-ID` | 15-19 | `X(5)` | Product Identifier |
| `QUANTITY` | 20-23 | `9(4)` | Order Quantity |
| `FILLER` | 24-80 | `X(57)` | Reserved |

### Expected Output (SYSOUT)
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
1. **Database Setup**: Execute the SQL scripts in the `SQL/` directory to create tables and load initial product data.
2. **Execution**: Submit `JCL/COBDB2CP.jcl`. This job will:
   - Create the input dataset (`STEPINS`).
   - Pre-compile, compile, and link the COBOL program (`PREP`).
   - Run the program using `IKJEFT01` (`RUNPROG`).

---

## Key COBOL + DB2 Concepts Used
- **Manual Referential Integrity**: Using `SELECT` to verify parent record existence.
- **In-Memory Tracking**: Using an `OCCURS` clause for fast duplicate detection.
- **Dynamic Date Conversion**: Reformatting strings for DB2 `DATE` compatibility.
- **SQL Error Handling**: Managing `SQLCODE 100` (not found) and `-803` (duplicate key).
- **Batch Commit/Rollback**: Managing transaction boundaries for data consistency.

---

## Notes
- The in-memory duplicate check is optimized for the first 100 records; subsequent duplicates are handled by DB2.
- Critical errors trigger a full `ROLLBACK` to ensure the database remains in a consistent state.
- Tested on IBM z/OS with DB2.
