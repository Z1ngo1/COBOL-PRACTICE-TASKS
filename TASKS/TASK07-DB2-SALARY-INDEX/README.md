# Task 07 — Employee Salary Indexing System (DB2 Cursor + Update)

## Overview

Reads all employee records from DB2 table `TB_EMP_SALARY` via a scrollable cursor, applies a salary increase by department, caps the result at 100,000, updates each row in place using `UPDATE WHERE CURRENT OF`, and writes a salary change report to a PS file.
Commits every 100 records to avoid long-running units of work. Any SQL error triggers a full `ROLLBACK` and `STOP RUN`.

---

## DB2 Table

### `TB_EMP_SALARY`

```sql
CREATE TABLE TB_EMP_SALARY (
  EMP_ID    CHAR(5)      NOT NULL,
  EMP_NAME  VARCHAR(30),
  DEPT_CODE CHAR(3),
  SALARY    DECIMAL(9,2),
  PRIMARY KEY(EMP_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `EMP_ID` | `CHAR(5)` | **Primary key** |
| `EMP_NAME` | `VARCHAR(30)` | Employee full name |
| `DEPT_CODE` | `CHAR(3)` | Department code (`IT`, `SAL`, or other) |
| `SALARY` | `DECIMAL(9,2)` | Current salary |

DCLGEN host variable structure is declared in [`DCLGEN/TASK7.cpy`](DCLGEN/TASK7.cpy) and included via `EXEC SQL INCLUDE TASK7 END-EXEC`.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `OUTDD` | `REPORT.FILE` | PS | OUTPUT | Salary change report, LRECL=80 |

### Report Record Layout (`OUTDD`) — LRECL=80, RECFM=F

| Field | Content |
|---|---|
| Header line | `EMPID   OLD_SAL    NEW_SAL  STATUS` |
| Detail line | `EMP-ID + OLD_SALARY + NEW_SALARY + STATUS-TEXT` |
| Footer line | `TOTAL: NNN RECORDS UPDATED` |

---

## Business Logic

### Salary Increase by Department

| Department (`DEPT_CODE`) | Formula | Increase |
|---|---|---|
| `IT` | `NEW_SALARY = OLD_SALARY * 1.10` | +10% |
| `SAL` | `NEW_SALARY = OLD_SALARY * 1.05` | +5% |
| Any other | `NEW_SALARY = OLD_SALARY * 1.03` | +3% |

### Salary Cap

| Condition | Action |
|---|---|
| `NEW_SALARY > 100000` | Cap at `100000`, set `STATUS-TEXT = 'MAXCAP'` |
| `NEW_SALARY <= 100000` | Keep calculated value, set `STATUS-TEXT = 'OK'` |

---

## Program Flow

1. **OPEN** report file `OUTDD` as OUTPUT — write header line
2. **OPEN** cursor `CUR-SALARY`:
   ```sql
   DECLARE CUR-SALARY CURSOR WITH HOLD FOR
   SELECT * FROM TB_EMP_SALARY
   FOR UPDATE OF SALARY
   ```
3. **PERFORM UNTIL EOF:**
   - **FETCH** `CUR-SALARY INTO :DCLTB-EMP-SALARY`
     - `SQLCODE = 0` → continue
     - `SQLCODE = 100` → set EOF, exit loop
     - Other → `ROLLBACK` → `STOP RUN`
   - **PERFORM UPDATE-EMPLOYEE-SALARY:**
     - Save `OLD-SALARY`, apply department multiplier via `EVALUATE`
     - If `NEW-SALARY > 100000` → cap at `100000`, set `STATUS-TEXT = 'MAXCAP'`
     - **UPDATE** `TB_EMP_SALARY SET SALARY = :NEW-SALARY WHERE CURRENT OF CUR-SALARY`
       - Error → `ROLLBACK` → `STOP RUN`
     - Increment `TOTAL-RECORDS-UPDATED` and `COMMIT-COUNT`
     - **PERFORM WRITE-REPORT-LINE** — write detail line to `OUTDD`
     - If `COMMIT-COUNT >= 100` → **COMMIT WORK**, reset `COMMIT-COUNT = 0`
4. **COMMIT WORK** — final commit after all records
5. **CLOSE** cursor `CUR-SALARY`
6. Write footer line `TOTAL: NNN RECORDS UPDATED` to `OUTDD`
7. **CLOSE** report file → `DISPLAY` completion message → `STOP RUN`

---

## Test Data

SQL scripts and expected output are stored in [`SQL/`](SQL/) and [`DATA/`](DATA/) folders:

| File | Description |
|---|---|
| [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) | DDL to create `TB_EMP_SALARY` table |
| [`INSERT.DATA.sql`](SQL/INSERT.DATA.sql) | DML to load 10 test employee records |
| [`TB.TB_EMP_SALARY.BEFORE`](DATA/TB.TB_EMP_SALARY.BEFORE) | Table state before salary indexing |
| [`TB.TB_EMP_SALARY.AFTER`](DATA/TB.TB_EMP_SALARY.AFTER) | Expected table state after salary indexing |
| [`SALARY.REPORT`](DATA/SALARY.REPORT) | Expected report output file |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
SALARY INDEXING COMPLETED:  10
```

---

## How to Run

1. **Create DB2 table** — run [`SQL/CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) via SPUFI or DSNTEP2
2. **Load test data** — run [`SQL/INSERT.DATA.sql`](SQL/INSERT.DATA.sql) via SPUFI or DSNTEP2
3. **Compile and run** — run [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl)

---

## Key COBOL/DB2 Concepts Used

- `DECLARE CURSOR WITH HOLD` — keeps cursor open across `COMMIT` statements; required for batch updates with intermediate commits
- `FOR UPDATE OF SALARY` — locks only the `SALARY` column for update, signals intent to DB2 optimizer
- `UPDATE ... WHERE CURRENT OF` — updates the exact row pointed to by the cursor without needing a key in the `WHERE` clause
- `FETCH INTO :DCLTB-EMP-SALARY` — bulk fetch into DCLGEN host variable structure
- `SQLCODE = 100` — standard DB2 end-of-cursor indicator
- `COMMIT WORK` every 100 records — prevents long-running unit of work and log space exhaustion
- `ROLLBACK WORK` on any error — ensures data consistency on failure
- `EXEC SQL INCLUDE TASK7 END-EXEC` — includes DCLGEN copybook with host variable declarations
- `EVALUATE TRUE` — clean multi-branch logic for department salary rules

---

## Notes

- `CURSOR WITH HOLD` survives `COMMIT` — cursor position is preserved after each intermediate commit, so `FETCH` continues from where it left off
- `UPDATE WHERE CURRENT OF` requires the cursor to be declared `FOR UPDATE OF` — without it DB2 returns an error
- All SQL errors trigger immediate `ROLLBACK` followed by `STOP RUN` — no partial updates are left in the table
- `COMMIT-COUNT` is reset to `0` after each intermediate commit — it counts records since the last commit, not total records
- Records where `NEW-SALARY` exactly equals `100000` after the multiplier (not capped) get status `OK`, not `MAXCAP`
- Tested on IBM z/OS with Enterprise COBOL and DB2 for z/OS

> **Warning:** On error, `ROLLBACK` only undoes changes since the last intermediate `COMMIT`. Records processed in prior committed batches (every 100 rows) are permanently updated and cannot be rolled back. Full recovery requires restoring from backup or manual correction.
