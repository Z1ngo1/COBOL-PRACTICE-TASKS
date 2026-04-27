# Task 24 — Balance Reconciliation (DB2 + VSAM + Sequential)

## Overview

Reconciles end-of-day account balances across three data sources to detect discrepancies and orphan records. The program loads yesterday's balances from a VSAM KSDS into an in-memory table, applies today's transactions from a sequential file, then compares the calculated expected balance against the actual balance stored in DB2 [`TB_ACCOUNTS`](DATA/TB.TB_ACCOUNTS).

The core technique is **Three-Way Reconciliation**:
1. Load yesterday's VSAM balances into memory.
2. Apply today's Credits/Debits from a transaction log to the in-memory table.
3. Query DB2 to compare expected vs. actual balance for each account.
4. Flag orphan accounts present in DB2 but missing from VSAM, and vice versa.

---

## DB2 Table

### [`TB_ACCOUNTS`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_ACCOUNTS (       
    ACCOUNT_ID CHAR(6) NOT NULL,  
    BALANCE    DECIMAL (11,2),    
    LAST_UPDATE TIMESTAMP,        
    PRIMARY KEY (ACCOUNT_ID)      
 ) IN DATABASE Z73460;         
```

| Column | Type | Description |
|---|---|---|
| `ACCOUNT_ID` | `CHAR(6)` | **Primary key** — Account identifier |
| `BALANCE` | `DECIMAL(11,2)` | Current actual balance in DB2 |
| `LAST_UPDATE` | `DATE` | Date of last balance update (YYYY-MM-DD) |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | [`ACCT.BACKUP`](DATA/ACCT.BACKUP) | KSDS | INPUT | Yesterday's account balances, Key pos 1–6 |
| `TRNSDD` | [`TRANS.LOG`](DATA/TRANS.LOG) | PS | INPUT | Today's transaction log, RECFM=F, LRECL=80 |
| `REPDD` | [`RECON.REPORT`](DATA/RECON.REPORT) | PS | OUTPUT | Reconciliation report, RECFM=V, LRECL=120 |

### VSAM Record Layout — (`VSAMDD`), LRECL=80, Key=1–6

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ACCT-ID` | `X(6)` | 1 | **KSDS primary key** — Account ID |
| `VSAM-YBAL` | `9(9)V99` | 7 | Yesterday's closing balance |
| `VSAM-BDATE` | `9(8)` | 18 | Backup date (YYYYMMDD) |
| `FILLER` | `X(55)` | 26 | Unused |

### Input Record Layout — (`TRNSDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(6)` | 1 | Account ID |
| `TRANS-TYPE` | `X(1)` | 7 | `C` = Credit, `D` = Debit |
| `TRANS-AMT` | `9(7)V99` | 8 | Transaction amount |
| `FILLER` | `X(64)` | 17 | Unused |

### Output Record Layout — (`REPDD`), LRECL=120, RECFM=V

| Field | Picture | Description |
|---|---|---|
| `REPORT-LINE` | `X(120)` | One line per account or orphan entry |

Report line types:
- **Header line** — `ACCOUNT  YESTERDAY  TODAY-TRNS  EXPECTED  ACTUAL  STATUS  DIFF`
- **Detail line** — `<ACCOUNT> <YESTERDAY> <TODAY-TRNS> <EXPECTED> <ACTUAL> <STATUS> <DIFF>`
- **Orphan line** — `NOT IN VSAM(BUT IN DB2): <ACCOUNT>` or `NOT IN DB2 (BUT IN VSAM/PS): <ACCOUNT>`
- **Footer lines** — summary counters (total checked, reconciled OK, discrepancies, errors)

Status values: `OK` (expected = actual) or `FAIL` (mismatch detected).

---

## Business Logic

### Phase 1 — Load VSAM into Memory

The program reads `ACCT.BACKUP` (VSAM-FILE) sequentially at startup and loads all records into an in-memory working storage table (`OCCURS 100`):

- Stores `VSAM-ACCT-ID` and `VSAM-YBAL` for each account.
- Records count of loaded entries (`WS-TABLE-COUNT`).
- If more than 100 accounts are found, the program logs an overflow warning and stops loading.

### Phase 2 — Apply Transactions

For each record in `TRANS.LOG` (TRNS-FILE):

- Search the in-memory table for a matching `TRANS-ACCT-ID`.
- If found: apply `C` (add) or `D` (subtract) to the in-memory balance.
- If `TRANS-TYPE` is neither `C` nor `D`: log a transaction type error to SYSOUT.
- If account not found in memory: skip transaction (orphan candidate will be detected in Phase 4).

### Phase 3 — DB2 Comparison

For each entry in the in-memory table:

- Execute `SELECT BALANCE INTO :HV-ACTUAL-BALANCE` from `TB_ACCOUNTS` where `ACCOUNT_ID = :HV-ACCT-ID`.
- **SQLCODE 0** — compare `EXPECTED-BAL` (VSAM + transactions) vs `HV-ACTUAL-BALANCE`:
  - Equal → write `OK` detail line, increment `RECONCILED-OK`.
  - Not equal → write `FAIL` detail line with difference, increment `DISCREPANCIES-CNT`.
- **SQLCODE 100** — account in VSAM but not in DB2; mark as unprocessed for Phase 4.
- **SQLCODE < 0** — DB2 error; log error to report, increment `ERRORS-DATA`.

### Phase 4 — DB2 Cursor Scan for Orphans

After processing all in-memory entries:

1. Open a DB2 cursor on `TB_ACCOUNTS` to scan all rows.
2. For each DB2 row, check whether its `ACCOUNT_ID` exists in the in-memory table.
3. If not found → write orphan line `NOT IN VSAM(BUT IN DB2)`, increment `NOT-IN-VSAM-CNT` and `ERRORS-DATA`.
4. Close cursor.
5. Write orphan lines for all unprocessed accounts in memory (`ACCT-PROCESSED = 'N'`): `NOT IN DB2 (BUT IN VSAM/PS)`, increment `NOT-IN-DB2-CNT` and `ERRORS-DATA`.

---

## Program Flow

1. **OPEN-ALL-FILES** — open `VSAM-FILE` (INPUT), `TRNS-FILE` (INPUT), `REP-FILE` (OUTPUT); check FILE STATUS. Write report header line.
2. **READ-VSAM** — read `VSAM-FILE` sequentially until end; populate in-memory table `ACCOUNT-TABLE`.
3. **READ-TRNS** — read all records from `TRNS-FILE`; call `PROCESS-TRANS` to apply credits/debits to in-memory balances.
4. **RECONCILE** — loop through in-memory table; for each entry call `COMPARE-DB2`:
   - 4.1. `EXEC SQL SELECT BALANCE INTO :HV-ACTUAL-BALANCE FROM TB_ACCOUNTS WHERE ACCOUNT_ID = :HV-ACCT-ID`.
   - 4.2. SQLCODE 0 — compare expected vs actual; write `OK` or `FAIL` detail line.
   - 4.3. SQLCODE 100 — mark account as unprocessed (to be logged in footer).
   - 4.4. Negative SQLCODE — log DB2 error and skip.
5. **FIND-NOT-IN-VSAM** — `EXEC SQL OPEN DB2-CURSOR`; fetch all rows; for each, call `CHECK-IN-VSAM`; if not found in memory, write `NOT IN VSAM` orphan line; `EXEC SQL CLOSE DB2-CURSOR`.
6. **WRITE-FOOTER** — loop through in-memory table; for each unprocessed account (`ACCT-PROCESSED = 'N'`), write `NOT IN DB2` orphan line. Write summary counters to `REP-FILE`.
7. **CLOSE-ALL-FILES** — close all three files.
8. **STOP RUN**.

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Account found in DB2 | `0` | Compare expected vs actual balance; write OK or FAIL |
| Account not in DB2 | `100` | Mark as unprocessed; log in footer |
| DB2 error on SELECT | `< 0` | Log SQLCODE error to report; skip account |
| Cursor FETCH end | `100` | Close cursor and proceed to footer |
| Critical DB2 error | `< -900` | Log error and `STOP RUN` |

---

## Test Data

All input, VSAM image, and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`ACCT.BACKUP`](DATA/ACCT.BACKUP) | VSAM KSDS image with yesterday's balances (4 accounts) |
| [`TRANS.LOG`](DATA/TRANS.LOG) | Today's transaction log (Credits and Debits) |
| [`TB.TB_ACCOUNTS`](DATA/TB.TB_ACCOUNTS) | DB2 table image with current actual balances |
| [`RECON.REPORT`](DATA/RECON.REPORT) | Reconciliation report after program execution |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
 ERROR: INCORRECT TYPE
```

---

## How to Run

1. **Initialize DB2** — execute [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) to create `TB_ACCOUNTS` and load test rows.
2. **Upload data** — Load [`ACCT.BACKUP`](DATA/ACCT.BACKUP) and [`TRANS.LOG`](DATA/TRANS.LOG) to your mainframe datasets manually through option '3.4 and edit your dataset' or with pre-prepared data
3. **Submit JCL** — submit [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl). The job will pre-compile, compile, link, and run the program.
4. Check [`RECON.REPORT`](DATA/RECON.REPORT) and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt) for the reconciliation report.

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
- Transaction type errors (`TRANS-TYPE` not `C` or `D`) are logged to SYSOUT and do not update the in-memory balance.
- Orphan detection is bidirectional: accounts in DB2 but not VSAM, and accounts in VSAM but not DB2, are both reported.
- The `DIFF` column in the report is signed: positive means DB2 balance is higher than expected, negative means it is lower.
- Tested on IBM z/OS with DB2 and Enterprise COBOL.
