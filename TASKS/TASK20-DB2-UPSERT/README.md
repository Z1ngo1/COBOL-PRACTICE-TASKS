# Task 20 — DB2 Upsert: Employee Directory Synchronization

## Overview

Synchronizes an external employee data file [`EMP.UPDATE`](DATA/EMP.UPDATE) with DB2 table `TB_EMPLOYEES`. For each incoming record, the program performs a "Check-and-Apply" (Upsert) logic: if the employee exists, it updates their record and logs any salary changes; if the employee is new, it inserts a new record. Business validation ensures data integrity before any DB2 operations. Commits are performed in batches of 50 operations.

The core technique is **Conditional DB2 Upsert (SELECT → UPDATE/INSERT)**: the program first queries the row to determine its state, then branch logic decides whether to execute an `UPDATE` or an `INSERT`.

---

## DB2 Table

### [`TB_EMPLOYEES`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_EMPLOYEES (
  EMP_ID    CHAR(5)       NOT NULL PRIMARY KEY,
  EMP_NAME  VARCHAR(20)   NOT NULL,
  DEPT      CHAR(3),
  SALARY    DECIMAL(7,2),
  HIRE_DATE DATE,
  STATUS    CHAR(1)       CHECK (STATUS IN ('A', 'I'))
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `EMP_ID` | `CHAR(5)` | **Primary key** — Employee ID |
| `EMP_NAME` | `VARCHAR(20)` | Full name |
| `DEPT` | `CHAR(3)` | Department code |
| `SALARY` | `DECIMAL(7,2)` | Monthly salary |
| `HIRE_DATE` | `DATE` | Date of hire (YYYY-MM-DD) |
| `STATUS` | `CHAR(1)` | 'A' for Active, 'I' for Inactive |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | `EMP.UPDATE` | PS | INPUT | External sync data, RECFM=F, LRECL=44 |
| `OUTDD` | `SYNC.LOG` | PS | OUTPUT | Sync results log, RECFM=VB, LRECL=84 |

### Input Record Layout — `EMP.UPDATE` (`INDD`), LRECL=44, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `EMP-ID` | `X(5)` | 1 | Employee ID — mandatory |
| `EMP-NAME` | `X(20)` | 6 | Employee name — mandatory |
| `EMP-DEPT` | `X(3)` | 26 | Department code |
| `EMP-SALARY` | `S9(5)V99` | 29 | Salary (numeric, > 0) |
| `EMP-HIRE-DATE`| `9(8)` | 36 | Hire date (YYYYMMDD) |
| `EMP-STATUS` | `X(1)` | 44 | Status ('A' or 'I') |

### Output Record Layout — `SYNC.LOG` (`OUTDD`), RECFM=VB, LRECL=84

| Field | Picture | Description |
|---|---|---|
| `LOG-REC` | `X(80)` | One log line: `<EMP-ID> <EMP-NAME> <STATUS-MESSAGE>` |

Status messages:
- `INSERTED (NEW EMPLOYEE)` — successful INSERT
- `UPDATE (SALARY CHANGE FROM <old> TO <new>)` — successful UPDATE with change
- `UPDATED (NO SALARY CHANGE: <salary>)` — successful UPDATE without salary change
- `ID VALIDATION ERROR: ID IS EMPTY`
- `VALIDATION ERROR: NAME IS EMPTY`
- `SALARY VALIDATION ERROR: <reason>` (NON-NUMERIC / NEGATIVE / ZERO)
- `STATUS VALIDATION ERROR` (neither 'A' nor 'I')

---

## Business Logic: Three-Phase Processing

The program implements a three-phase pipeline: validate each incoming record, determine whether to insert or update via a DB2 existence check, then manage transaction commits in controlled batches.

The program is driven by `MAIN-LOGIC`:

```cobol
MAIN-LOGIC.
    PERFORM OPEN-ALL-FILES.
    PERFORM PROCESS-ALL-RECORDS.
    PERFORM CLOSE-ALL-FILES.
    PERFORM DISPLAY-SUMMARY.
    STOP RUN.
```

### Phase 1 — Validation

For each record read from `EMP-FILE`, the program executes four validation paragraphs. If any fail, `RECORDS-ERRORS` is incremented and the record is skipped.

```
VALIDATE-ID:     Check EMP-ID NOT = SPACES
VALIDATE-NAME:   Check EMP-NAME NOT = SPACES
VALIDATE-SALARY: Check IS NUMERIC, NOT NEGATIVE, NOT ZERO
VALIDATE-STATUS: Check IS 'A' OR 'I'
```

### Phase 2 — Existence Check & Action (Upsert)

If validation passes, the program queries DB2 to see if the record exists:

```sql
EXEC SQL
    SELECT EMP_NAME, SALARY
    INTO :HV-OLD-NAME, :HV-OLD-SALARY
    FROM TB_EMPLOYEES
    WHERE EMP_ID = :HV-EMP-ID
END-EXEC.
```

- **SQLCODE 0 (Found)**:
  - Calls `UPDATE-EMPLOYEE`
  - Compares `HV-OLD-SALARY` with `HV-SALARY`
  - Logs specific message based on whether salary changed
- **SQLCODE 100 (Not Found)**:
  - Calls `INSERT-EMPLOYEE`
  - Logs `INSERTED (NEW EMPLOYEE)`
- **Negative SQLCODE**: Logs DB2 error and skips record.

### Phase 3 — Commit Strategy

The program uses a batch commit approach to optimize performance:

- **Batch size**: 50 operations (`COMMIT-COUNTER >= 50`)
- **Final commit**: Executed in `CLOSE-ALL-FILES` for any remaining records
- **Rollback**: Critical errors (SQLCODE < -900) trigger immediate `ROLLBACK` and `STOP RUN`

---

## Program Flow

1. `OPEN-ALL-FILES` — open `EMP-FILE` (INPUT) and `SYNC-LOG` (OUTPUT); check FILE STATUS for both
2. `READ` first record from `EMP-FILE`
3. `PROCESS-ALL-RECORDS` — main loop until `AT END`:
   - 3.1. `VALIDATE-ID` — skip record with error log if EMP-ID is blank
   - 3.2. `VALIDATE-NAME` — skip record with error log if EMP-NAME is blank
   - 3.3. `VALIDATE-SALARY` — skip if non-numeric, negative, or zero
   - 3.4. `VALIDATE-STATUS` — skip if not 'A' or 'I'
   - 3.5. `EXEC SQL SELECT` — check existence in `TB_EMPLOYEES`
   - 3.6. SQLCODE 0 → `UPDATE-EMPLOYEE` + log salary change or no-change message
   - 3.7. SQLCODE 100 → `INSERT-EMPLOYEE` + log `INSERTED (NEW EMPLOYEE)`
   - 3.8. Negative SQLCODE < -900 → `ROLLBACK` + `STOP RUN`
   - 3.9. Increment `COMMIT-COUNTER`; if `>= 50` → `EXEC SQL COMMIT`, reset counter
   - 3.10. `READ` next record
4. `CLOSE-ALL-FILES` — `EXEC SQL COMMIT` for remaining records; close both files
5. `DISPLAY-SUMMARY` — print records processed, inserted, updated, errors, commit batches
6. `STOP RUN`

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Employee Exists | `0` | `PERFORM UPDATE-EMPLOYEE` |
| New Employee | `100` | `PERFORM INSERT-EMPLOYEE` |
| Duplicate Key | `-803` | Log error (race condition) |
| Critical Error | `< -900` | `ROLLBACK` + `STOP RUN` |

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`EMP.UPDATE`](DATA/EMP.UPDATE) | External employee sync data (24 records) |
| [`SYNC.LOG`](DATA/SYNC.LOG) | Sync results log with validation and DB2 action messages |
| [`TB.TB_EMPLOYEES`](DATA/TB.TB_EMPLOYEES) | Final state of DB2 table after synchronization |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
       EMPLOYEE UPSERT SUMMARY
========================================
RECORDS PROCESSED:  24
RECORDS INSERTED:   15
RECORDS UPDATED:    3
RECORDS ERRORS:     6
COMMIT BATCHES:     1
========================================
```

---

## How to Run

1. Execute SQL in [`SQL/CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) to prepare the DB2 table
2. Upload input data [`EMP.UPDATE`](DATA/EMP.UPDATE) to dataset or use pre-prepared test data in jcl
3. Submit [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl) to run the sync process

---

## Key COBOL + DB2 Concepts Used

- **`SELECT ... INTO`** — used to check existence and retrieve old values for change logging
- **Upsert Logic** — the combination of conditional branching based on SQLCODE `0` vs `100`
- **`FUNCTION TRIM` + `FUNCTION REVERSE`** — used for VARCHAR length calculation and log formatting
- **Date Formatting** — converts `YYYYMMDD` input string to DB2-compatible `YYYY-MM-DD` format
- **Batch Commit** — `COMMIT-COUNTER` ensures commits occur every 50 records to minimize overhead
- **Atomicity Note** — The SELECT-then-UPDATE/INSERT pattern is non-atomic. In a concurrent environment, a race condition between the SELECT and INSERT could cause -803 (duplicate key) errors on INSERT, which will be logged as errors and skipped. For production use, consider replacing with a single atomic MERGE statement.

---

## Notes

- Critical errors (deadlocks, timeouts, DB2 down) trigger a full `ROLLBACK` to ensure the table state remains consistent with the last batch
- Salary changes are logged with old and new values for audit purposes: `UPDATE (SALARY CHANGE FROM 5000.00 TO 5500.00)`
- Validation errors do not stop the program; they are logged, and the program proceeds to the next record
- Tested on IBM z/OS with DB2 and Enterprise COBOL
