# Task 19 — DB2 Bulk Insert: Customer Data Import with Validation

## Overview

Reads new customer data from a sequential file [`NEW.CUSTOMER`](DATA/NEW.CUSTOMER), validates each record against business rules (ID not empty, EMAIL contains `@`, PHONE is 10 digits), and inserts valid records into DB2 table `TB_CUSTOMERS`. Invalid records are logged to an error file [`SUCCESS.LOG`](DATA/SUCCESS.LOG). Commits are performed in batches of 100 successful inserts to optimize transaction performance. Critical DB2 errors (SQLCODE < -900) trigger an immediate ROLLBACK and STOP RUN.

The core technique is **batch commit strategy with embedded SQL validation**: validate-then-insert per record, COMMIT every 100 successful inserts, and handle duplicate keys (-803) gracefully without stopping the job.

---

## DB2 Table

### [`TB_CUSTOMERS`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_CUSTOMERS (
  CUST_ID      CHAR(6)       NOT NULL PRIMARY KEY,
  CUST_NAME    VARCHAR(30)   NOT NULL,
  EMAIL        VARCHAR(40),
  PHONE        CHAR(10),
  CREDIT_LIMIT DECIMAL(7,2)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `CUST_ID` | `CHAR(6)` | **Primary key** — customer ID |
| `CUST_NAME` | `VARCHAR(30)` | Full customer name |
| `EMAIL` | `VARCHAR(40)` | Email address (validated: must contain `@`) |
| `PHONE` | `CHAR(10)` | Phone number (validated: 10 numeric digits) |
| `CREDIT_LIMIT` | `DECIMAL(7,2)` | Credit limit in dollars |

DCLGEN host variable structure is declared in `DCLGEN/TASK19.cpy` (`DCLGEN/TASK19.cpy`) and included via `EXEC SQL INCLUDE TASK19 END-EXEC`.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | `NEW.CUSTOMER` | PS | INPUT | New customer records, RECFM=FB, LRECL=93 |
| `OUTDD` | `SUCCESS.LOG` | PS | OUTPUT | Import results log, RECFM=VB, LRECL=84 |

### Input Record Layout — `NEW.CUSTOMER` (`INDD`), LRECL=93, RECFM=FB

| Field | Picture | Offset | Description |
|---|---|---|---|
| `INP-ID` | `X(6)` | 1 | Customer ID — **mandatory**, cannot be SPACES |
| `INP-NAME` | `X(30)` | 7 | Customer full name |
| `INP-EMAIL` | `X(40)` | 37 | Email address — must contain exactly one `@` |
| `INP-PHONE` | `X(10)` | 77 | Phone number — must be 10 numeric digits |
| `INP-LIMIT` | `9(5)V99` | 87 | Credit limit (unpacked decimal) |

### Output Record Layout — `SUCCESS.LOG` (`OUTDD`), RECFM=VB, LRECL=84

| Field | Picture | Description |
|---|---|---|
| `OUTPUT-REC` | `X(80)` | One log line: `<CUST_ID> <STATUS_MESSAGE>` |

Status messages:
- `INSERTED OK` — successful INSERT (SQLCODE = 0)
- `VALIDATION ERROR: ID IS NULL` — `INP-ID` was SPACES
- `VALIDATION ERROR: INVALID EMAIL` — `INP-EMAIL` does not contain exactly one `@`
- `VALIDATION ERROR: INVALID PHONE` — `INP-PHONE` length ≠ 10 or not numeric
- `DB2 ERROR: DUPLICATE PRIMARY KEY` — SQLCODE = -803
- `DB2 ERROR SQLCODE: <value>` — other non-critical DB2 errors

---

## Business Logic: Four-Phase Processing

The program implements a robust four-phase data import pipeline, featuring a multi-stage validation cascade and high-performance batch commit management.

The program is driven by `MAIN-PARA` which calls four paragraphs in sequence. Each phase has a distinct responsibility: open files, validate and insert records with batch commits, perform the final commit and close files, then display the summary.

```cobol
MAIN-PARA.
    PERFORM OPEN-ALL-FILES.
    PERFORM PROCESS-ALL-RECORDS.
    PERFORM CLOSE-ALL-FILES.
    PERFORM DISPLAY-SUMMARY.
    STOP RUN.
```

### Phase 1 — `OPEN-ALL-FILES`

Opens `INPUT-FILE` (NEW.CUSTOMER) for INPUT and `OUTPUT-FILE` (SUCCESS.LOG) for OUTPUT. Stops on any non-zero FILE STATUS.

### Phase 2 — `PROCESS-ALL-RECORDS` (main loop)

Reads `INPUT-FILE` until EOF and applies a validation cascade before each INSERT. Every record produces exactly one log line in `SUCCESS.LOG`.

```
PROCESS-ALL-RECORDS:
    PERFORM UNTIL EOF
        READ INPUT-FILE
        ADD 1 TO RECORDS-PROCESSED
        IF INP-ID = SPACES
            PERFORM REPORT-ID-ERROR
        ELSE
            PERFORM VALIDATE-EMAIL
        END-IF
    END-READ
END-PERFORM
```

**Validation cascade**:
1. `INP-ID` not SPACES → proceed to `VALIDATE-EMAIL`
2. `INP-EMAIL` contains exactly one `@` → proceed to `VALIDATE-PHONE`
3. `INP-PHONE` length = 10 AND numeric → proceed to `INSERT-CUSTOMER`
4. Any validation failure → write error line to `SUCCESS.LOG`, skip INSERT, continue to next record

### Phase 3 — `INSERT-CUSTOMER` (DB2 insert with batch commit)

Moves input fields to host variables (VARCHAR length calculated via `FUNCTION REVERSE` + `INSPECT TALLYING`), executes `INSERT INTO TB_CUSTOMERS`, evaluates SQLCODE:

```
INSERT-CUSTOMER:
    MOVE fields to HV-CUST-ID, HV-CUST-NAME, HV-EMAIL, HV-PHONE, HV-CREDIT
    EXEC SQL
        INSERT INTO TB_CUSTOMERS (CUST_ID, CUST_NAME, EMAIL, PHONE, CREDIT_LIMIT)
        VALUES (:HV-CUST-ID, :HV-CUST-NAME, :HV-EMAIL, :HV-PHONE, :HV-CREDIT)
    END-EXEC
    EVALUATE SQLCODE
        WHEN 0
            PERFORM REPORT-SUCCESS
            ADD 1 TO COMMIT-COUNTER
            IF COMMIT-COUNTER >= 100
                EXEC SQL COMMIT WORK END-EXEC
                ADD 1 TO COMMIT-BATCHES
                MOVE 0 TO COMMIT-COUNTER
            END-IF
        WHEN -803
            PERFORM REPORT-DUPLICATE-KEY
        WHEN OTHER
            PERFORM REPORT-DB2-ERROR
    END-EVALUATE
```

**Batch commit logic**: `COMMIT-COUNTER` tracks successful inserts. When it reaches 100, executes `COMMIT WORK`, increments `COMMIT-BATCHES`, resets `COMMIT-COUNTER` to 0. Final commit is performed in `CLOSE-ALL-FILES` for any remaining uncommitted inserts.

### Phase 4 — `CLOSE-ALL-FILES` (final commit + close)

If `COMMIT-COUNTER > 0`, commits remaining uncommitted inserts before closing files to ensure no data is lost.

```
CLOSE-ALL-FILES:
    IF COMMIT-COUNTER > 0
        EXEC SQL COMMIT WORK END-EXEC
        ADD 1 TO COMMIT-BATCHES
        MOVE 0 TO COMMIT-COUNTER
    END-IF
    CLOSE INPUT-FILE
    CLOSE OUTPUT-FILE
```

---

## Validation Rules

| Field | Rule | Error Message |
|---|---|---|
| `INP-ID` | NOT = SPACES | `VALIDATION ERROR: ID IS NULL` |
| `INP-EMAIL` | INSPECT TALLYING for `@` = 1 | `VALIDATION ERROR: INVALID EMAIL` |
| `INP-PHONE` | `FUNCTION LENGTH(FUNCTION TRIM(INP-PHONE)) = 10` AND `IS NUMERIC` | `VALIDATION ERROR: INVALID PHONE` |

---

## SQLCODE Handling

| SQLCODE | Meaning | Action |
|---|---|---|
| `0` | Success | Write `INSERTED OK` to log, increment `COMMIT-COUNTER`, check if >= 100 for batch commit |
| `-803` | Duplicate primary key | Write `DB2 ERROR: DUPLICATE PRIMARY KEY` to log, increment `RECORDS-ERRORS`, continue |
| `< -900` | **Critical DB2 error** (deadlock, timeout, system error) | DISPLAY error message, `EXEC SQL ROLLBACK WORK`, `STOP RUN` |
| Other negative | Non-critical DB2 error | Write `DB2 ERROR SQLCODE: <value>` to log, increment `RECORDS-ERRORS`, continue |

**Critical SQLCODE threshold**: `-900` is the boundary — errors more severe than `-900` (e.g., `-911`, `-913`) are considered unrecoverable and trigger immediate ROLLBACK + STOP RUN.

---

## Program Flow

1. **PERFORM OPEN-ALL-FILES** — opens `INDD` (INPUT) and `OUTDD` (OUTPUT); stops on non-zero FILE STATUS.
2. **PERFORM PROCESS-ALL-RECORDS** — main loop `UNTIL EOF` on `NEW.CUSTOMER`.
   * **READ INPUT-FILE** — increments `RECORDS-PROCESSED`.
   * **IF `INP-ID = SPACES`** → **PERFORM REPORT-ID-ERROR** — writes validation error to `SUCCESS.LOG`; skips INSERT.
   * **ELSE** → **PERFORM VALIDATE-EMAIL**.
   * **IF email invalid** → write `VALIDATION ERROR: INVALID EMAIL`; skip INSERT.
   * **ELSE** → **PERFORM VALIDATE-PHONE**.
   * **IF phone invalid** → write `VALIDATION ERROR: INVALID PHONE`; skip INSERT.
   * **ELSE** → **PERFORM INSERT-CUSTOMER**.
   * **`EXEC SQL INSERT`** — inserts record into `TB_CUSTOMERS`.
   * **SQLCODE = 0** → write `INSERTED OK`; increment `COMMIT-COUNTER`.
   * **IF `COMMIT-COUNTER >= 100`** → `EXEC SQL COMMIT WORK`; increment `COMMIT-BATCHES`; reset counter.
   * **SQLCODE = -803** → write `DB2 ERROR: DUPLICATE PRIMARY KEY`; continue.
   * **SQLCODE < -900** → DISPLAY error; `EXEC SQL ROLLBACK WORK`; `STOP RUN`.
   * **Other SQLCODE** → write `DB2 ERROR SQLCODE: <value>`; continue.
3. **PERFORM CLOSE-ALL-FILES** — if `COMMIT-COUNTER > 0`, executes final `EXEC SQL COMMIT WORK`; closes `INDD` and `OUTDD`.
4. **PERFORM DISPLAY-SUMMARY** — prints final statistics to SYSOUT (processed, inserted, errors, commit batches).
5. **STOP RUN**.

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`NEW.CUSTOMER`](DATA/NEW.CUSTOMER) | 20 test customer records (including valid and invalid ones) |
| [`SUCCESS.LOG`](DATA/SUCCESS.LOG) | Log file containing validation and DB2 results |
| [`TB.TB_CUSTOMERS.AFTER`](DATA/TB.TB_CUSTOMERS.AFTER) | State of DB2 table after successful import |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
       CUSTOMER IMPORT SUMMARY
========================================
RECORDS PROCESSED:  20
RECORDS INSERTED:   10
RECORDS ERRORS:     10
COMMIT BATCHES:     1
========================================
```

---

## How to Run

1. Create the DB2 table by executing the SQL in [`SQL/CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) (if not already created)
2. Upload customer data [`DATA/NEW.CUSTOMER`](DATA/NEW.CUSTOMER) to dataset or use pre-prepared test data in jcl
3. Submit [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl) — it handles DB2 precompile, COBOL compile, and program execution

---

## Key COBOL + DB2 Concepts Used

- **`EXEC SQL INCLUDE SQLCA END-EXEC`** — includes the SQL Communication Area for SQLCODE inspection
- **`EXEC SQL INCLUDE TASK19 END-EXEC`** — includes DCLGEN-generated host variable declarations for `TB_CUSTOMERS`
- **VARCHAR host variables** — `HV-CUST-NAME` and `HV-EMAIL` are VARCHAR structures (`49 length PIC S9(4) COMP-5`, `49 text PIC X(n)`); length is calculated dynamically by trimming trailing spaces
- **`FUNCTION REVERSE` + `INSPECT TALLYING`** — counts trailing spaces to compute actual VARCHAR length: `COMPUTE HV-CUST-NAME-LEN = 30 - WS-NAME-LEN` where `WS-NAME-LEN` counts leading spaces in the reversed string
- **Batch commit strategy** — instead of committing after every INSERT (slow) or at the very end (risky if job abends), commits every 100 successful inserts to balance transaction performance and recoverability
- **`COMMIT-COUNTER` vs `COMMIT-BATCHES`** — `COMMIT-COUNTER` tracks uncommitted inserts (resets to 0 after each COMMIT); `COMMIT-BATCHES` counts total number of commits executed
- **Graceful duplicate key handling** — SQLCODE `-803` does not stop the job; the program logs the error and continues processing remaining records
- **Critical error detection** — `IF SQLCODE < -900` detects severe DB2 errors (deadlock `-911`, timeout `-913`, system errors) and triggers immediate ROLLBACK + STOP RUN to prevent data corruption

---

## Notes

- On SQLCODE `-911` (deadlock/timeout), DB2 has already rolled back the unit of work automatically. The program's explicit `ROLLBACK` is a safe no-op in this case.
- The program does **not** use DB2 LOAD utility — it performs row-by-row INSERT via embedded SQL, which is slower but allows per-record validation and granular error handling
- `SUCCESS.LOG` is written sequentially — one line per input record (either success or error). No summary line is written to this file; the summary appears only in SYSOUT
- The validation cascade (ID → EMAIL → PHONE) stops at the first failure. For example, if ID is SPACES, the program does not check EMAIL or PHONE for that record
- `FUNCTION TRIM` removes leading and trailing spaces from `INP-PHONE` before checking length, so `"1234567890"` (with trailing spaces) passes validation
- The final COMMIT in `CLOSE-ALL-FILES` handles the remainder: if 150 records were inserted, the first 100 are committed in batch 1, and the remaining 50 are committed at the end (batch 2)
- Tested on IBM z/OS with DB2 for z/OS and Enterprise COBOL
