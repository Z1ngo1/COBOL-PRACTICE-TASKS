# Task 29 — ESDS Operation Log: KSDS and DB2 Reconciliation

## Overview

Reads a daily operation log stored in an ESDS sequential file. For each operation record, validates input fields, looks up the account in a VSAM KSDS master file, fetches the current balance from DB2, and verifies business logic. All results (OK / ERROR / SKIPPED) are written to a PS reconciliation report file. No data is updated — this is a read-only reconciliation program.

---

## DB2 Table

### [`TB_ACCOUNT_BAL`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_ACCOUNT_BAL (     
   ACCT_ID CHAR(6) NOT NULL,      
   BALANCE DECIMAL(11,2),         
   LAST_DATE DATE,                
   PRIMARY KEY(ACCT_ID)           
) IN DATABASE Z73460;    
```

| Column | Type | Description |
|---|---|---|
| `ACCT_ID` | `CHAR(6)` | **Primary key**  |
| `BALANCE` | `DECIMAL(11,2)` | account balance |
| `LAST_DATE` | `DATE` | DATE |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `OPR` | [`OPR.LOG.ESDS`](DATA/OPR.LOG.ESDS) | ESDS | INPUT | Daily operation log |
| `ACCTDD` | [`ACCT.MSTER.KSDS`](DATA/ACCT.MSTER.KSDS) | KSDS | INPUT | Account master file |
| `RECN` | [`RECON.LOG`](DATA/RECON.LOG) | PS | OUTPUT | Reconciliation report |

### Operation Log Record Layout (`OPR`) — ESDS, LRECL=80

| Field | PIC | Position | Description |
|---|---|---|---|
| `OPR-ACCT-ID` | `X(6)` | 1–6 | Account ID |
| `OPR-DATE` | `X(8)` | 7–14 | Operation date `YYYYMMDD` |
| `OPR-TYPE` | `X(1)` | 15 | Operation type: `D` (Debit) or `C` (Credit) |
| `OPR-AMT` | `9(7)V99` | 16–24 | Operation amount |
| `OPR-ID` | `X(6)` | 25–30 | Operation ID |
| FILLER | `X(50)` | 31–80 | Unused |

### Account Master Record Layout (`ACCTDD`) — KSDS, LRECL=80

| Field | PIC | Position | Description |
|---|---|---|---|
| `ACCT-MAST-ID` | `X(6)` | 1–6 | **Primary key** |
| `ACCT-CUST-NAME` | `X(25)` | 7–31 | Customer name |
| `ACCT-STATUS` | `X(1)` | 32 | Account status: `A` (Active), `C` (Closed) |
| `ACCT-LIMIT` | `9(7)V99` | 33–41 | Credit limit |
| FILLER | `X(39)` | 42–80 | Unused |

### Reconciliation Report Layout (`RECN`) — PS, LRECL=80, RECFM=FB

| Field | Description |
|---|---|
| OPR-ID | Operation identifier |
| ACCT-ID | Account number |
| Status | `OK`, `ERROR`, or `SKIPPED` |
| Detail | Reason message |

---

## Business Logic

The program processes each operation record through four sequential phases. No files or tables are modified.

### Phase 1 — Validate Input Fields

| Condition | Result | Detail |
|---|---|---|
| `OPR-TYPE` not `D` or `C` | ERROR | `INVALID INPUT DATA` |
| `OPR-AMT <= 0` | ERROR | `INVALID INPUT DATA` |

### Phase 2 — KSDS Account Lookup

| Condition | Result | Detail |
|---|---|---|
| File status `23` (not found) | ERROR | `ACCOUNT NOT FOUND IN KSDS` |
| `ACCT-STATUS = 'C'` (closed) | SKIPPED | `ACCOUNT STATUS CLOSED` |

### Phase 3 — DB2 Balance Fetch

| SQLCODE | Result | Detail |
|---|---|---|
| `0` | Proceed to Phase 4 | Balance retrieved |
| `100` | ERROR | `DB2 ROW MISSING` |
| `< 0` | ERROR | `DB2 ERROR: <SQLCODE>` |

### Phase 4 — Balance Logic Check

| Condition | Result | Detail |
|---|---|---|
| `OPR-TYPE = 'D'` and `BALANCE < OPR-AMT` | ERROR | `NEGATIVE BALANCE AFTER OPR` |
| `OPR-TYPE = 'D'` and `BALANCE >= OPR-AMT` | OK | `BALANCE CHECK PASSED` |
| `OPR-TYPE = 'C'` | OK | `BALANCE CHECK PASSED` |

---

## Program Flow

1. **OPEN** — `OPR-LOG` (INPUT), `ACCT-MASTER` (INPUT), `RECON-LOG` (OUTPUT).
2. **READ** next record from ESDS sequentially until EOF.
3. **Phase 1** — Validate `OPR-TYPE` and `OPR-AMT`; write ERROR and skip remaining phases if invalid.
4. **Phase 2** — Random READ of KSDS by `ACCT-MAST-ID`; write ERROR or SKIPPED if account not found or closed.
5. **Phase 3** — Execute DB2 `SELECT BALANCE` for `ACCT_ID`; write ERROR if row missing or SQL error.
6. **Phase 4** — Check debit amount against current balance; write OK or ERROR.
7. Go to step 2 (Read Next).
8. **CLOSE** all files.
9. **DISPLAY SUMMARY** — print totals to SYSOUT.

---

## Test Data

Input and output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`OPR.LOG.ESDS`](DATA/OPR.LOG.ESDS) | 9 operation records (various scenarios) |
| [`ACCT.MSTER.KSDS`](DATA/ACCT.MSTER.KSDS) | 5 account records (active, closed, missing in DB2) |
| [`RECON.LOG`](DATA/RECON.LOG) | Expected reconciliation report output |
| [`TB.TB_ACCOUNT_BAL`](DATA/TB.TB_ACCOUNT_BAL) | DB2 table data (4 accounts with balances) |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
OPERATION SUMMARY
========================================
TOTAL OPERATIONS READ:     9
OPERATIONS OK:             3
OPERATIONS ERROR:          5
OPERATIONS SKIPPED:        1
RECORDS WRITTEN:           9
========================================
```

---

## How to Run

1. **Define VSAM KSDS cluster** — run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Define ESDS cluster** — run [`DEFESDS.jcl`](JCL/DEFESDS.jcl)
3. **Create DB2 table and insert data** — run [`CREATE.TABLE`](SQL/CREATE.TABLE.sql) and [`INSERT.DATA`](SQL/INSERT.DATA.sql) from [`SQL/`](SQL/) folder
4. **Load data, compile, and run** — run [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl) (performs all steps: delete old output, load KSDS and ESDS data via IDCAMS REPRO, compile with DB2 precompile, execute under DB2 subsystem DBDG)
5. **Review output** — see [`RECON.LOG`](DATA/RECON.LOG) and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt)

---

## Key COBOL Concepts Used

- `ORGANIZATION IS SEQUENTIAL` (ESDS) — entry-sequenced dataset read via sequential access
- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS RANDOM` — KSDS random lookup by account key
- `EXEC SQL ... END-EXEC` — embedded DB2 SQL with SQLCA for return code handling
- `EXEC SQL INCLUDE SQLCA END-EXEC` — SQL Communication Area for SQLCODE checking
- `EXEC SQL INCLUDE TASK29 END-EXEC` — DCLGEN-generated host variable declaration
- `EVALUATE TRUE` — multi-branch SQLCODE evaluation (0 / 100 / negative)
- `STRING ... INTO` — dynamic report line construction
- `PERFORM UNTIL EOF` — sequential read loop with AT END clause

---

## Notes

- No records are updated or deleted; the program is strictly read-only
- ESDS does not support random access or deletion — records are always read sequentially
- The KSDS is opened with `ACCESS MODE IS RANDOM` to allow single-record lookup by key without sequential scan
- If `OPR-STATUS` is non-zero on read (other than EOF), the program abends with `STOP RUN`
- Tested on IBM z/OS with Enterprise COBOL and DB2 subsystem DBDG
