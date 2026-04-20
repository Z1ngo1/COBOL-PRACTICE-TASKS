# Task 24 — Balance Reconciliation (DB2 + VSAM + Sequential)

## Overview

Reconciles end-of-day account balances across three data sources to detect discrepancies and orphan records. The program loads yesterday's balances from a VSAM KSDS into an in-memory table, applies today's transactions from a sequential file, then compares the calculated expected balance against the actual balance stored in DB2 `TB_ACCOUNTS`.

The core technique is **Three-Way Reconciliation**:
1. Load yesterday's VSAM balances into memory.
2. Apply today's Credits/Debits from a transaction log to the in-memory table.
3. Query DB2 to compare expected vs. actual balance for each account.
4. Flag orphan accounts present in DB2 but missing from VSAM, and vice versa.

---

## DB2 Table

### `TB_ACCOUNTS`

```sql
CREATE TABLE TB_ACCOUNTS (
    ACCOUNT_ID  CHAR(6)        NOT NULL PRIMARY KEY,
    ACCT_NAME   VARCHAR(20),
    BALANCE     DECIMAL(11,2),
    LAST_UPDATE DATE
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `ACCOUNT_ID` | `CHAR(6)` | **Primary key** — Account identifier |
| `ACCT_NAME` | `VARCHAR(20)` | Account holder name |
| `BALANCE` | `DECIMAL(11,2)` | Current actual balance in DB2 |
| `LAST_UPDATE` | `DATE` | Date of last balance update (YYYY-MM-DD) |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `ACCT.BACKUP` | KSDS | INPUT | Yesterday's account balances, Key pos 1–6 |
| `TRNSDD` | `TRANS.LOG` | PS | INPUT | Today's transaction log, RECFM=F, LRECL=80 |
| `REPDD` | `RECON.REPORT` | PS | OUTPUT | Reconciliation report, RECFM=VB, LRECL=120 |

### VSAM Record Layout — `ACCT.BACKUP` (`VSAMDD`), LRECL=74, Key=1–6

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ACCT-ID` | `X(6)` | 1 | **KSDS primary key** — Account ID |
| `VSAM-YBAL` | `9(9)V99` | 7 | Yesterday's closing balance |
| `VSAM-BDATE` | `9(8)` | 18 | Backup date (YYYYMMDD) |

### Input Record Layout — `TRANS.LOG` (`TRNSDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(6)` | 1 | Account ID |
| `TRANS-TYPE` | `X(1)` | 7 | `C` = Credit, `D` = Debit |
| `TRANS-AMT` | `9(7)V99` | 8 | Transaction amount |

### Output Record Layout — `RECON.REPORT` (`REPDD`), LRECL=120, RECFM=VB

| Field | Picture | Description |
|---|---|---|
| `REPORT-LINE` | `X(116)` | One line per account or orphan entry |

Report line types:
- **Detail line** — `<ACCT-ID>  <YESTERDAY>  <TODAY-TRNS>  <EXPECTED>  <ACTUAL>  <STATUS>  <DIFF>`
- **Orphan line** — `NOT IN VSAM(BUT IN DB2): <ACCT-ID>` or `NOT IN DB2 (BUT IN VSAM/PS): <ACCT-ID>`
- **Footer lines** — summary counters (total checked, reconciled OK, discrepancies, errors)

Status values: `OK` (expected = actual) or `FAIL` (mismatch detected).

---

## Business Logic

### Phase 1 — Load VSAM into Memory

The program reads `ACCT.BACKUP` sequentially at startup and loads all records into an in-memory working storage table (`OCCURS 100`):
- Stores `VSAM-ACCT-ID` and `VSAM-YBAL` for each account.
- Records count of loaded entries (`MEM-COUNT`).
- If more than 100 accounts are found, the program logs an overflow warning and stops loading.

### Phase 2 — Apply Transactions

For each record in `TRANS.LOG`:
- Search the in-memory table for a matching `TRANS-ACCT-ID`.
- If found: apply `C` (add) or `D` (subtract) to the in-memory balance.
- If `TRANS-TYPE` is neither `C` nor `D`: log a transaction type error.
- If account not found in memory: note as orphan candidate.

### Phase 3 — DB2 Comparison

For each entry in the in-memory table:
- Execute `SELECT BALANCE INTO :HV-ACTUAL` from `TB_ACCOUNTS` where `ACCOUNT_ID = :HV-ACCT-ID`.
- **SQLCODE 0** — compare `EXPECTED-BAL` (VSAM + transactions) vs `HV-ACTUAL`:
  - Equal → write `OK` detail line, increment `RECONCILED-OK`.
  - Not equal → write `FAIL` detail line with difference, increment `DISCREPANCIES`.
- **SQLCODE 100** — account in VSAM but not in DB2; write orphan line `NOT IN DB2 (BUT IN VSAM/PS)`, increment `ERRORS-DATA`.

### Phase 4 — DB2 Cursor Scan for Orphans

After processing all in-memory entries, open a DB2 cursor on `TB_ACCOUNTS` to scan all rows:
- For each DB2 row, check whether its `ACCOUNT_ID` exists in the in-memory table.
- If not found → write orphan line `NOT IN VSAM(BUT IN DB2)`, increment `ERRORS-DATA`.

---

## Program Flow

1. `OPEN-ALL-FILES` — open `ACCT-BACKUP` (INPUT), `TRANS-FILE` (INPUT), `RECON-REPORT` (OUTPUT); check FILE STATUS.
2. `LOAD-VSAM-TO-MEMORY` — read `ACCT-BACKUP` sequentially until end; populate in-memory table.
3. `APPLY-TRANSACTIONS` — read all records from `TRANS-FILE`; apply credits/debits to in-memory balances.
4. `WRITE-REPORT-HEADER` — write column header line to `RECON-REPORT`.
5. `RECONCILE-ACCOUNTS` — loop through in-memory table:
   - 5.1. `EXEC SQL SELECT BALANCE INTO ... FROM TB_ACCOUNTS WHERE ACCOUNT_ID = :HV-ACCT-ID`.
   - 5.2. SQLCODE 0 — compare expected vs actual; write `OK` or `FAIL` detail line.
   - 5.3. SQLCODE 100 — write `NOT IN DB2` orphan line.
   - 5.4. Negative SQLCODE — log DB2 error and skip.
6. `SCAN-DB2-FOR-ORPHANS` — `EXEC SQL OPEN CURSOR`; fetch all rows; for each, check in-memory table; write `NOT IN VSAM` orphan lines; `EXEC SQL CLOSE CURSOR`.
7. `WRITE-REPORT-FOOTER` — write summary counters to `RECON-REPORT`.
8. `CLOSE-ALL-FILES` — close all three files.
9. `DISPLAY-SUMMARY` — print counters to SYSOUT.
10. `STOP RUN`.

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Account found in DB2 | `0` | Compare expected vs actual balance; write OK or FAIL |
| Account not in DB2 | `100` | Write `NOT IN DB2 (BUT IN VSAM/PS)` orphan line |
| DB2 error on SELECT | `< 0` | Log SQLCODE error and skip account |
| Cursor FETCH end | `100` | Close cursor and proceed to footer |
| Critical DB2 error | `< 0` (cursor) | Log error and `STOP RUN` |

---

## Test Data

All input, VSAM image, and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/ACCT.BACKUP`](DATA/ACCT.BACKUP) | VSAM KSDS image with yesterday's balances (4 accounts) |
| [`DATA/TRANS.LOG`](DATA/TRANS.LOG) | Today's transaction log (Credits and Debits) |
| [`DATA/TB.TB_ACCOUNTS`](DATA/TB.TB_ACCOUNTS) | DB2 table image with current actual balances |
| [`DATA/RECON.REPORT`](DATA/RECON.REPORT) | Reconciliation report after program execution |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
TOTAL ACCOUNTS CHECKED: 4
RECONCILED OK: 1
DISCREPANCIES: 2
ERRORS DATA: 2
```

Expected content of `RECON.REPORT`:

```
ACCOUNT     YESTERDAY   TODAY-TRNS       EXPECTED         ACTUAL   STATUS             DIFF
000100       10200.00      +300.00       10500.00       10500.00   OK                +0.00
000200       50000.00      +100.00       50100.00       47500.00   FAIL           -2600.00
000300       25000.00      -500.00       24500.00       26000.00   FAIL           +1500.00
NOT IN VSAM(BUT IN DB2): 000500
NOT IN DB2 (BUT IN VSAM/PS): 000400

TOTAL ACCOUNTS CHECKED: 4
RECONCILED OK: 1
DISCREPANCIES: 2
ERRORS DATA: 2
```

---

## How to Run

1. **Initialize DB2** — execute [`SQL/CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) to create `TB_ACCOUNTS` and load test rows.
2. **Upload data** — transfer `DATA/ACCT.BACKUP` to `Z73460.TASK24.ACCT.BACKUP` and `DATA/TRANS.LOG` to `Z73460.TASK24.TRANS.LOG`.
3. **Submit JCL** — submit [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl). The job will pre-compile, compile, link, and run the program.
4. Check `Z73460.TASK24.RECON.REPORT` for the reconciliation report.

---

## Key COBOL + DB2 Concepts Used

- **In-Memory Table (`OCCURS 100`)** — all VSAM records are loaded into working storage at startup for fast lookup during transaction and comparison phases.
- **Three-Way Match** — reconciles data across three independent sources (VSAM, PS, DB2) in a single batch run.
- **DB2 Cursor** — `OPEN` / `FETCH` / `CLOSE` pattern used to scan all `TB_ACCOUNTS` rows and detect accounts missing from VSAM.
- **`SELECT ... INTO`** — used for point lookups of individual account balances from DB2.
- **VSAM Sequential Read** — `OPEN INPUT` + sequential `READ` used to load all KSDS records into memory in Phase 1.
- **FILE STATUS + SQLCODE** — both error channels are monitored simultaneously; VSAM operations check FILE STATUS, DB2 operations check SQLCODE.
- **`COMP-3` Arithmetic** — all financial fields use `PACKED-DECIMAL` to maintain decimal precision in balance calculations.

---

## Notes

- The in-memory table is capped at 100 accounts. For production volumes, replace with a DB2-side join or a sort-merge approach.
- Transaction type errors (`TRANS-TYPE` not `C` or `D`) are counted in `ERRORS-DATA` and do not update the in-memory balance.
- Orphan detection is bidirectional: accounts in DB2 but not VSAM, and accounts in VSAM but not DB2, are both reported.
- The `DIFF` column in the report is signed: positive means DB2 balance is higher than expected, negative means it is lower.
- Tested on IBM z/OS with DB2 and Enterprise COBOL.
