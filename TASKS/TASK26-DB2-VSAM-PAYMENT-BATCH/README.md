# Task 26 — Robust Batch Processing (Error Handling + Return Codes)

## Overview

Batch COBOL program that processes a payment input file (PS), validates each record, looks up the customer account in VSAM, and updates the customer balance in the DB2 table `TB_CUSTOMER_BALANCE`. The program is designed for maximum robustness, implementing multi-level error handling and returning a specific job return code based on the severity and count of encountered errors.

---

## DB2 Table

### [`TB_CUSTOMER_BALANCE`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_CUSTOMER_BALANCE (
    CUST_ID      CHAR(5)           NOT NULL,
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

DCLGEN host variable structure is declared in [`DCLGEN/TASK26.cpy`](DCLGEN/TASK26.cpy) and included via `EXEC SQL INCLUDE TASK26 END-EXEC`.

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
- `PAYMENT-TYPE` must be one of: `'C'`, `'T'`, `'A'`.

**Action on failure**: Log error, increment `SKIP-COUNT`, skip to next record.

### Phase 2 — VSAM Account Lookup

Performs a random read of `CUSTOMER.VSAM` using `PMT-CUST-ID`:
- **Status `'00'`** (Found): Proceed to Phase 3.
- **Status `'23'`** (Not Found): Log missing customer, increment `SKIP-COUNT`, skip to next record.
- **Other Non-Zero Status**: Log fatal VSAM error, `ROLLBACK`, set `RC=12`, and stop processing.

### Phase 3 — Account Status Check

Evaluates the `VSAM-ACCT-STATUS` for the found customer:
- **`'S'` (Suspended)**: Log rejected payment, increment `SKIP-COUNT`, skip to next record.
- **`'A'` (Active)**: Proceed to Phase 4 — DB2 update.

### Phase 4 — DB2 Balance Update

Updates `CUST_BALANCE` (addition) and `LAST_PAYMENT` (current timestamp) in `TB_CUSTOMER_BALANCE`:

```sql
EXEC SQL
    UPDATE TB_CUSTOMER_BALANCE
    SET CUST_BALANCE = CUST_BALANCE + :HV-PMT-AMOUNT,
        LAST_PAYMENT = CURRENT TIMESTAMP
    WHERE CUST_ID = :HV-CUST-ID
END-EXEC.
```

| SQLCODE | Meaning | Action |
|---|---|---|
| `0` | Success | Increment `SUCCESS-COUNT` |
| `-911` | Deadlock / timeout | `ROLLBACK`, set `RC=12`, stop processing |
| `< 0` (other) | DB2 error | Log SQLCODE, `ROLLBACK`, set `RC=8`, stop processing |

---

## Return Codes

The final job return code is determined after all records are processed (or after a fatal error). Return code priority: fatal conditions override count-based codes.

| RC | Condition | Severity |
|---|---|---|
| `0` | No errors encountered | Clean run |
| `4` | `ERROR-COUNT` between 1 and 10 | Warnings (recoverable errors) |
| `8` | DB2 update error occurred | Serious error |
| `12` | Fatal VSAM error or DB2 Deadlock (`-911`) | Fatal (processing stopped) |
| `16` | `ERROR-COUNT` exceeds 10 | Critical failure (high error rate) |

> RC `8` and `12` are set immediately on the fatal event and cause `STOP RUN` — the count-based logic (`4` / `16`) is only evaluated in `FINAL-PARA` if no fatal error occurred.

---

## Program Flow

1. **INITIALIZE**: Zero out `SUCCESS-COUNT`, `ERROR-COUNT`, `SKIP-COUNT`, `COMMIT-COUNT`; set default `RC=0`.
2. **OPEN**: Open PS Input (`INPDD`), VSAM KSDS (`VSAMDD`), and Variable-length Log file (`LOGDD`); check FILE STATUS on all.
3. **PROCESS LOOP**: Read `PAYMENTS.FILE` until EOF or fatal error:
   - **PERFORM VALIDATE-INPUT** — Phase 1 checks; on failure log and skip.
   - **PERFORM VSAM-LOOKUP** — Phase 2 random read; on `'23'` log and skip; on other error ROLLBACK + RC=12 + STOP RUN.
   - **PERFORM CHECK-ACCT-STATUS** — Phase 3; on `'S'` log and skip.
   - **PERFORM UPDATE-DB2-BALANCE** — Phase 4 UPDATE; on `-911` RC=12; on other negative SQLCODE RC=8; on error ROLLBACK + STOP RUN.
   - Increment `COMMIT-COUNT`; if `>= 50` → `EXEC SQL COMMIT WORK`, reset `COMMIT-COUNT = 0`.
   - Write per-record result line to `PROCESS.LOG`.
4. **FINAL-PARA**: If no fatal error — determine final RC from `ERROR-COUNT` (0 → RC=0; 1–10 → RC=4; >10 → RC=16).
5. **FINAL-LOG**: Write summary section to `PROCESS.LOG`: Total / Success / Errors / Skipped / Final RC.
6. **CLOSE**: Perform final `COMMIT` (if no fatal errors occurred), close all files. Set `RETURN-CODE = WS-RC`.

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`PAYMENTS.FILE`](DATA/PAYMENTS.FILE) | Input test records — valid and invalid entries (bad ID, zero amount, unknown customer, suspended account) |
| [`CUSTOMER.VSAM`](DATA/CUSTOMER.VSAM) | KSDS dataset loaded with customer master records for lookup |
| [`PROCESS.LOG`](DATA/PROCESS.LOG) | Expected execution log after a clean test run |
| [`TB.TB_CUSTOMER_BALANCE.BEFORE`](DATA/TB.TB_CUSTOMER_BALANCE.BEFORE) | DB2 table state before execution |
| [`TB.TB_CUSTOMER_BALANCE.AFTER`](DATA/TB.TB_CUSTOMER_BALANCE.AFTER) | DB2 table state after execution |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
PAYMENT BATCH PROCESSING SUMMARY
========================================
TOTAL RECORDS  READ:    15
SUCCESSFUL     UPDATES: 10
ERRORS         FOUND:    3
SKIPPED        RECORDS:  2
FINAL RETURN CODE:       4
========================================
```

---

## How to Run

1. **DB2 Setup** — run [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) and [`INSERT.DATA.sql`](SQL/INSERT.DATA.sql) via SPUFI or DSNTEP2.
2. **VSAM Setup** — run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to define the KSDS cluster, then load [`CUSTOMER.VSAM`](DATA/CUSTOMER.VSAM) via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF.
3. **Compile and run** — submit [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl).
4. **Compare output** — see [`PROCESS.LOG`](DATA/PROCESS.LOG), [`TB.TB_CUSTOMER_BALANCE.AFTER`](DATA/TB.TB_CUSTOMER_BALANCE.AFTER), and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).
5. **Check the job return code** — JCL condition code should match the expected RC from the summary log.

---

## Key COBOL/DB2 Concepts Used

---

## Notes
