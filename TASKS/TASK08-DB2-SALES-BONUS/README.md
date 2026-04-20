# Task 08 - Sales Bonus Indexing System (DB2 Cursor + Region Rules)

## Overview

Reads all sales employee records from DB2 table [`TB_SALES_BONUS`](DATA/TB.TB_SALES_BONUS.BEFORE) via a cursor, calculates a new bonus based on region code and annual sales volume, applies a maximum cap of 20,000, updates each row in place using `UPDATE WHERE CURRENT OF`, and writes a bonus change report to a PS file.
Commits every 50 records. Any SQL error triggers a full `ROLLBACK` and `STOP RUN`.

---

## DB2 Table

### [`TB_SALES_BONUS`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_SALES_BONUS (
  EMP_ID      CHAR(6)       NOT NULL,
  EMP_NAME    VARCHAR(30),
  REGION_CODE CHAR(2),
  YEAR_SALES  DECIMAL(11,2),
  BONUS_AMT   DECIMAL(9,2),
  PRIMARY KEY(EMP_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `EMP_ID` | `CHAR(6)` | **Primary key** |
| `EMP_NAME` | `VARCHAR(30)` | Employee full name |
| `REGION_CODE` | `CHAR(2)` | Region code (`EU`, `NE`, `AS`, `SW`) |
| `YEAR_SALES` | `DECIMAL(11,2)` | Annual sales volume |
| `BONUS_AMT` | `DECIMAL(9,2)` | Current bonus amount (updated by program) |

DCLGEN host variable structure is declared in [`DCLGEN/TASK8.cpy`](DCLGEN/TASK8.cpy) and included via `EXEC SQL INCLUDE TASK8 END-EXEC`.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `OUTDD` | [`BONUS.REPORT.FILE`](DATA/BONUS.REPORT) | PS | OUTPUT | Bonus change report, LRECL=80 |

---

## Business Logic

### Step 1 - Base Increase by Region

| Region (`REGION_CODE`) | Formula | Increase |
|---|---|---|
| `EU` | `CALC_BONUS = OLD_BONUS * 1.12` | +12% |
| `NE` | `CALC_BONUS = OLD_BONUS * 1.10` | +10% |
| `AS` | `CALC_BONUS = OLD_BONUS * 1.08` | +8% |
| `SW` | `CALC_BONUS = OLD_BONUS * 1.05` | +5% |
| Other | `ROLLBACK` -> `STOP RUN` | Unknown region is a fatal error |

### Step 2 - High Sales Boost

| Condition | Action |
|---|---|
| `YEAR_SALES >= 150000.00` | `CALC_BONUS = CALC_BONUS * 1.05` (+5% on top of region increase) |

### Step 3 - Cap and Status Assignment

Status is assigned after all calculations are complete, in priority order:

| Priority | Condition | Status |
|---|---|---|
| 1 | `CALC_BONUS > 20000` | `CAP` - bonus capped at 20,000 |
| 2 | `CALC_BONUS < 2000` | `LOW` - small bonus |
| 3 | `YEAR_SALES >= 150000` | `HIGHSAL` - high sales boost applied |
| 4 | Otherwise | `OK` - standard increase |

---

## Program Flow

1. **PERFORM OPEN-FILES:**
   - `OPEN OUTPUT BONUS-REPORT-FILE` - write header line
   - `OPEN CUR-BONUS`:
     ```sql
     DECLARE CUR-BONUS CURSOR WITH HOLD FOR
     SELECT * FROM TB_SALES_BONUS
     FOR UPDATE OF BONUS_AMT
     ```
2. **PERFORM UNTIL EOF:**
   - **FETCH** `CUR-BONUS INTO :DCLTB-SALES-BONUS`
     - `SQLCODE = 0` -> continue
     - `SQLCODE = 100` -> set EOF, exit loop
     - Other -> `ROLLBACK` -> `STOP RUN`
   - **PERFORM PROCESS-BONUS:**
     - Save `OLD-BONUS`, apply region multiplier via `EVALUATE`
     - Unknown region -> `ROLLBACK` -> `STOP RUN`
     - If `YEAR-SALES >= 150000` -> `CALC-BONUS = CALC-BONUS * 1.05`
     - Assign `WS-STATUS-TEXT` via `EVALUATE` (CAP / LOW / HIGHSAL / OK)
     - **UPDATE** `TB_SALES_BONUS SET BONUS_AMT = :CALC-BONUS WHERE CURRENT OF CUR-BONUS`
       - Error -> `ROLLBACK` -> `STOP RUN`
     - Increment `TOTAL-REC-UPDATED` and `COMMIT-COUNT`
     - **PERFORM WRITE-REPORT-LINE** - write detail line to `OUTDD`
     - If `COMMIT-COUNT >= 50` -> **PERFORM INTERMEDIATE-COMMIT**, reset `COMMIT-COUNT = 0`
3. **PERFORM CLOSE-FILES:**
   - **COMMIT WORK** - final commit
   - **CLOSE** cursor `CUR-BONUS` (`SQLCODE -501` = already closed, not an error)
   - Write footer line `TOTAL: NNNNN ROWS UPDATED` to `OUTDD`
   - **CLOSE** report file -> `DISPLAY` completion message

---

## Test Data

SQL scripts and expected output are stored in [`SQL/`](SQL/) and [`DATA/`](DATA/) folders:

| File | Description |
|---|---|
| [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) | DDL to create `TB_SALES_BONUS` table |
| [`INSERT.DATA.sql`](SQL/INSERT.DATA.sql) | DML to load 10 test employee records |
| [`TB.TB_SALES_BONUS.BEFORE`](DATA/TB.TB_SALES_BONUS.BEFORE) | Table state before bonus indexing |
| [`TB.TB_SALES_BONUS.AFTER`](DATA/TB.TB_SALES_BONUS.AFTER) | Expected table state after bonus indexing |
| [`BONUS.REPORT`](DATA/BONUS.REPORT) | Expected report output file |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
BONUS UPDATE COMPLETED: 00010
```

---

## How to Run

1. **Create DB2 table** - run [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) via SPUFI or DSNTEP2
2. **Load test data** - run [`INSERT.DATA.sql`](SQL/INSERT.DATA.sql) via SPUFI or DSNTEP2
3. **Compile and run** - run [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl)

---

## Key COBOL/DB2 Concepts Used

- `DECLARE CURSOR WITH HOLD` - keeps cursor open across `COMMIT` statements; required for batch updates with intermediate commits
- `FOR UPDATE OF BONUS_AMT` - locks only the `BONUS_AMT` column for update, signals intent to DB2 optimizer
- `UPDATE ... WHERE CURRENT OF` - updates the exact row pointed to by the cursor without a key in the `WHERE` clause
- `FETCH INTO :DCLTB-SALES-BONUS` - bulk fetch into DCLGEN host variable structure
- `SQLCODE = 100` - standard DB2 end-of-cursor indicator
- `SQLCODE = -501` - cursor already closed; handled as non-fatal in `CLOSE-FILES`
- `COMMIT WORK` every 50 records - prevents long-running unit of work and log space exhaustion
- `ROLLBACK WORK` on any error - ensures data consistency on failure
- `EVALUATE TRUE` - used for both region rate selection and status assignment
- Two-step bonus calculation - region multiplier applied first, then HIGHSAL boost on top

---

## Notes

- `CURSOR WITH HOLD` survives `COMMIT` - cursor position is preserved after each intermediate commit, so `FETCH` continues from where it left off
- `UPDATE WHERE CURRENT OF` requires the cursor to be declared `FOR UPDATE OF` - without it DB2 returns an error
- Status priority matters: `CAP` is checked before `LOW` and `HIGHSAL` - a capped record always gets `CAP`, even if sales were high
- `COMMIT-COUNT` is reset to `0` after each intermediate commit - it counts records since the last commit, not total records
- An unknown `REGION_CODE` is treated as a fatal error - program rolls back and stops immediately
- Tested on IBM z/OS with Enterprise COBOL and DB2 for z/OS

> **Warning:** On error, `ROLLBACK` only undoes changes since the last intermediate `COMMIT`. Records processed in prior committed batches (every 50 rows) are permanently updated and cannot be rolled back. Full recovery requires restoring from backup or manual correction.
