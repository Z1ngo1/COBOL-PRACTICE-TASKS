# Task 26 — Robust Batch Processing (Error Handling + Return Codes)

## Overview

Batch COBOL program that processes a payment input file (PS), validates each record, looks up the customer account in VSAM, and updates the customer balance in the DB2 table `TB_CUSTOMER_BALANCE`. The program is designed for maximum robustness, implementing multi-level error handling and returning a specific job return code based on the severity and count of encountered errors.

---

## DB2 Table

### [`TB_CUSTOMER_BALANCE`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_CUSTOMER_BALANCE (
    CUST_ID CHAR(5) NOT NULL,
    CUST_BALANCE DECIMAL(9,2),
    LAST_PAYMENT TIMESTAMP WITH DEFAULT,
    PRIMARY KEY (CUST_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `CUST_ID` | `CHAR(5)` | **Primary key** — Customer identifier |
| `CUST_BALANCE` | `DECIMAL(9,2)` | Current account balance |
| `LAST_PAYMENT` | `TIMESTAMP` | Timestamp of the last successful payment |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INPDD` | [`PAYMENTS.FILE`](DATA/PAYMENTS.FILE) | PS | INPUT | Payment input records, RECFM=F, LRECL=80 |
| `VSAMDD` | [`CUSTOMER.VSAM`](DATA/CUSTOMER.VSAM) | KSDS | INPUT | Customer master file, random access by CUST-ID |
| `LOGDD` | [`PROCESS.LOG`](DATA/PROCESS.LOG) | PS | OUTPUT | Execution log, RECFM=V, LRECL=80 |

### Input Record Layout — (`INPDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `PAYMENT-ID` | `X(6)` | 1 | Unique payment identifier |
| `PMT-CUST-ID` | `X(5)` | 7 | Customer ID — used as VSAM key |
| `PMT-AMOUNT` | `9(5)V99` | 12 | Payment amount (format: 99999.99) |
| `PAYMENT-TYPE` | `X(1)` | 19 | Type of payment (C=Cash, T=Transfer, A=Auto) |
| `FILLER` | `X(61)` | 20 | Unused padding |

### VSAM Record Layout — (`VSAMDD`), KSDS, Key=1–5

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ID` | `X(5)` | 1 | **Primary key** — Customer ID |
| `VSAM-CUST-NAME` | `X(25)` | 6 | Customer name |
| `VSAM-ACCT-STATUS` | `X(1)` | 31 | Status (A=Active, S=Suspended) |

---

## Business Logic

The program implements a robust four-level validation and processing pipeline:

### Phase 1 — Input Validation
Checks for basic data integrity:
- `PAYMENT-ID` must not be spaces.
- `PMT-AMOUNT` must be greater than zero.
- `PAYMENT-TYPE` must be one of: 'C', 'T', 'A'.
**Action on failure**: Log error, increment `SKIP-COUNT`, skip to next record.

### Phase 2 — VSAM Account Lookup
Performs a random read of `CUSTOMER.VSAM` using `PMT-CUST-ID`:
- **Status '23'** (Not Found): Log missing customer, increment `SKIP-COUNT`.
- **Other Non-Zero Status**: Log fatal VSAM error, `ROLLBACK`, set `RC=12`, and stop processing.

### Phase 3 — Account Status Check
Evaluates the `VSAM-ACCT-STATUS` for the found customer:
- **'S' (Suspended)**: Log rejected payment, increment `SKIP-COUNT`.
- **'A' (Active)**: Proceed to DB2 update.

### Phase 4 — DB2 Balance Update
Updates `CUST_BALANCE` (addition) and `LAST_PAYMENT` (current timestamp) in `TB_CUSTOMER_BALANCE`:
- **SQLCODE 0**: Success, increment `SUCCESS-COUNT`.
- **SQLCODE -911** (Deadlock): `ROLLBACK`, set `RC=12`, and stop processing.
- **SQLCODE < 0**: Log DB2 error code, `ROLLBACK`, set `RC=8`, and stop processing.

---

## Return Codes

The final job return code is determined by the severity of encountered errors:

| RC | Condition | Severity |
|---|---|---|
| `0` | No errors encountered | Clean run |
| `4` | `ERROR-COUNT` between 1 and 10 | Warnings (recoverable errors) |
| `8` | DB2 update error occurred | Serious error |
| `12` | Fatal VSAM error or DB2 Deadlock (-911) | Fatal (processing stopped) |
| `16` | `ERROR-COUNT` exceeds 10 | Critical failure (high error rate) |

---

## Program Flow

1. **INITIALIZE**: Zero out counters, set default RC=0.
2. **OPEN**: Open PS Input, VSAM KSDS, and Variable-length Log file.
3. **PROCESS LOOP**: Read `PAYMENTS.FILE` until EOF or fatal error:
   - Perform Phase 1-4.
   - Write results for each record to `PROCESS.LOG`.
4. **FINAL-PARA**: Determine final RC if no fatal error occurred.
5. **FINAL-LOG**: Write summary section (Total, Success, Errors, Skipped, RC) to `PROCESS.LOG`.
6. **CLOSE**: Perform final `COMMIT` (if no fatal errors), close all files.

---

## Test Data

The folder [`DATA/`](DATA/) contains the following environment files:
- [`PAYMENTS.FILE`](DATA/PAYMENTS.FILE) — Input test records (including valid and invalid entries).
- [`CUSTOMER.VSAM`](DATA/CUSTOMER.VSAM) — KSDS dataset for customer lookups.
- [`PROCESS.LOG`](DATA/PROCESS.LOG) — Resulting log file after a test run.
- [`TB.TB_CUSTOMER_BALANCE.BEFORE`](DATA/TB.TB_CUSTOMER_BALANCE.BEFORE) — DB2 table state before execution.
- [`TB.TB_CUSTOMER_BALANCE.AFTER`](DATA/TB.TB_CUSTOMER_BALANCE.AFTER) — DB2 table state after execution.

---

## How to Run

1. **DB2 Setup**: Run [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) and [`INSERT.DATA.sql`](SQL/INSERT.DATA.sql).
2. **VSAM Setup**: Run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to define and load the KSDS cluster.
3. **Execution**: Submit [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl). This JCL handles:
   - Deleting old datasets.
   - Creating input `PAYMENTS.FILE` via `IEBGENER`.
   - Compiling `DB2VSM26.cbl` with DB2 pre-compiler.
   - Running the program under TSO batch (`IKJEFT01`).
