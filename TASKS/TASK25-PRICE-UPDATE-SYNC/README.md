# Task 25 — Price Update Sync (PS + VSAM + DB2 Audit)

## Overview

Reads a daily price update file (PS sequential), updates product prices in a VSAM KSDS master file via random I-O, and inserts each change as an audit record into the DB2 [`TB_PRICE_HISTORY`](DATA/TB.TB_PRICE_HISTORY) table.

The core technique is **Three-Source Price Sync**: for every incoming price record the program performs a VSAM random read, saves the old price, rewrites the VSAM record with the new price, then inserts the old/new pair into DB2 for a full audit trail. Commits are batched every 50 records.

---

## DB2 Table

### [`TB_PRICE_HISTORY`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_PRICE_HISTORY (          
  PROD_ID CHAR(5) NOT NULL,              
  OLD_PRICE DECIMAL(7,2),                
  NEW_PRICE DECIMAL(7,2),                
  CHANGE_DATE DATE NOT NULL WITH DEFAULT,
  PRIMARY KEY (PROD_ID,CHANGE_DATE)      
) IN DATABASE Z73460;       
```

| Column | Type | Description |
|---|---|---|
| `PROD_ID` | `CHAR(5)` | **Part of PK** — Product identifier |
| `OLD_PRICE` | `DECIMAL(7,2)` | Price before the update |
| `NEW_PRICE` | `DECIMAL(7,2)` | Price after the update |
| `CHANGE_DATE` | `DATE` | Date of change, defaults to current date |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | [`PRICE.UPDATE`](DATA/PRICE.UPDATE) | PS | INPUT | Daily price update records, RECFM=F, LRECL=80 |
| `VSAMDD` | `PRODUCT.MASTER` | KSDS | I-O | Product master file, random access by PROD-ID |
| `OUTDD` | [`UPDATE.LOG`](DATA/UPDATE.LOG) | PS | OUTPUT | Update result log, RECFM=F, LRECL=80 |

### Input Record Layout — (`INDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `IN-PROD-ID` | `X(5)` | 1 | Product ID — used as VSAM key |
| `IN-NEW-PRICE` | `9(5)V99` | 6 | New price to apply |
| `FILLER` | `X(68)` | 13 | Unused padding |

### VSAM Record Layout — (`VSAMDD`), KSDS, Key=1–5

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-PROD-ID` | `X(5)` | 1 | **Primary key** — Product ID |
| `VSAM-PROD-NAME` | `X(20)` | 6 | Product name |
| `VSAM-CURR-PRICE` | `9(5)V99` | 26 | Current price (overwritten on update) |
| `FILLER` | `X(48)` | 33 | Unused padding |

### Output Record Layout — (`OUTDD`), LRECL=80, RECFM=F

| Field | Picture | Description |
|---|---|---|
| `OUT-REC` | `X(80)` | One log line per processed record: `<PROD-ID> <MESSAGE>` |

Log message types:
- `OLD_PRICE: <old> NEW_PRICE: <new> UPDATED` — successful price update
- `PRODUCT NOT FOUND IN VSAM` — VSAM FILE STATUS `23`, record skipped
- `DB2 INSERT FAILED` — DB2 error on INSERT, triggers ROLLBACK + STOP RUN

---

## Business Logic

The program implements a four-phase pipeline: read input, update VSAM, write DB2 audit, batch commit.

### Phase 1 — Read PS Price Update File

Reads `PRICE.UPDATE` sequentially to EOF. For each record calls `READ-VSAM-PARA` and increments `WS-CNT-PROCESSED`. A batch commit fires every 50 records (`COMMIT-COUNT >= 50`).

### Phase 2 — VSAM Random Read & Rewrite

Moves `IN-PROD-ID` to `VSAM-PROD-ID` (the RECORD KEY) then issues a random `READ VSAM-FILE`:

| VSAM STATUS | Condition | Action |
|---|---|---|
| `00` | Product found | Save `VSAM-CURR-PRICE` to `WS-OLD-PRICE`; move `IN-NEW-PRICE` to `VSAM-CURR-PRICE`; call `WRITE-DB2-PARA`; call `REWRITE-VSAM-PARA` |
| `23` | Product not found | Write `PRODUCT NOT FOUND IN VSAM` to log; increment `WS-CNT-NOT-FOUND`; skip |
| Other | VSAM I/O error | `ROLLBACK` + `STOP RUN` |

> **DB2 INSERT intentionally precedes VSAM REWRITE.** If the DB2 INSERT fails, a `ROLLBACK` is issued and `STOP RUN` terminates the job — VSAM has not yet been rewritten, so both sources remain consistent.

### Phase 3 — DB2 Audit INSERT

Inserts one row into `TB_PRICE_HISTORY`:

| SQLCODE | Condition | Action |
|---|---|---|
| `0` | Insert OK | Increment `WS-CNT-UPDATED` and `COMMIT-COUNT`; write success log line |
| Other | DB2 error | Write `DB2 INSERT FAILED` log line; `ROLLBACK`; `STOP RUN` |

### Phase 4 — Batch Commit Strategy

- **Batch size**: 50 records (`COMMIT-COUNT >= 50`)
- **Final commit**: executed in `CLOSE-ALL-FILES` if `COMMIT-COUNT > 0`
- **Rollback**: any DB2 or VSAM critical error triggers immediate `EXEC SQL ROLLBACK WORK` before `STOP RUN`

---

## Program Flow

1. `OPEN-ALL-FILES` — open `IN-FILE` (INPUT), `VSAM-FILE` (I-O), `OUT-FILE` (OUTPUT); check FILE STATUS for all three
2. `PROCESS-PRICE-UPDATES` — main loop until EOF:
   - 2.1. `READ IN-FILE` — check IN-STATUS; on error `ROLLBACK` + `STOP RUN`
   - 2.2. `READ-VSAM-PARA` — random read by `IN-PROD-ID`:
     - STATUS `23` → log not-found, skip
     - Other non-zero → `ROLLBACK` + `STOP RUN`
     - Found → save old price, call `WRITE-DB2-PARA`, call `REWRITE-VSAM-PARA`
   - 2.3. Increment `WS-CNT-PROCESSED`
   - 2.4. If `COMMIT-COUNT >= 50` → `EXEC SQL COMMIT WORK`; on error `ROLLBACK` + `STOP RUN`; reset `COMMIT-COUNT`
3. `CLOSE-ALL-FILES` — final `EXEC SQL COMMIT WORK` if `COMMIT-COUNT > 0`; close all three files
4. `DISPLAY-SUMMARY` — print COMMIT COUNT, RECORDS PROCESSED, RECORDS UPDATED, RECORDS NOT FOUND to SYSOUT
5. `STOP RUN`

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Audit INSERT OK | `0` | Increment counters; write success log line |
| Audit INSERT error | non-zero | Write `DB2 INSERT FAILED`; `ROLLBACK`; `STOP RUN` |
| Batch COMMIT OK | `0` | Increment `WS-CNT-COMMITS`; reset `COMMIT-COUNT` |
| Batch COMMIT error | non-zero | `ROLLBACK`; `STOP RUN` |
| Final COMMIT error | non-zero | `ROLLBACK`; `STOP RUN` |

---

## Test Data

All input and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`PRICE.UPDATE`](DATA/PRICE.UPDATE) | PS input — 52 price update records |
| [`PRODUCT.MASTER`](DATA/PRODUCT.MASTER) | VSAM KSDS image — product master before run |
| [`UPDATE.LOG`](DATA/UPDATE.LOG) | Expected update log after program execution |
| [`TB.TB_PRICE_HISTORY`](DATA/TB.TB_PRICE_HISTORY) | DB2 audit table state after run |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
PRICE UPDATE SUMMARY
========================================
COMMIT COUNT:        2
RECORDS PROCESSED:  52
RECORDS UPDATED:    51
RECORDS NOT FOUND:   1
========================================
```

---

## How to Run

1. Execute SQL in [`CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) to create `TB_PRICE_HISTORY`
2. Upload [`PRICE.UPDATE`](DATA/PRICE.UPDATE) and [`PRODUCT.MASTER`](DATA/PRODUCT.MASTER) to your mainframe datasets
3. Submit [`COBDB2CP.jcl`](JCL/COBDB2CP.jcl) — the job pre-compiles, compiles, link-edits, and runs [`DB2VSM25`](COBOL/DB2VSM25.cbl)

---

## Key COBOL + DB2 Concepts Used

- **VSAM KSDS Random Read / Rewrite** — `ACCESS MODE IS RANDOM` with `READ ... INVALID KEY` and `REWRITE` for in-place price updates
- **DB2 INSERT** — inserts one audit row per successful price change into `TB_PRICE_HISTORY`
- **Write-ahead audit** — DB2 INSERT is executed *before* VSAM REWRITE; if the INSERT fails, ROLLBACK leaves VSAM untouched, guaranteeing consistency
- **Batch Commit** — `COMMIT-COUNT` triggers `EXEC SQL COMMIT WORK` every 50 records to limit lock contention and log space
- **DCLGEN** — host variable declarations included via `EXEC SQL INCLUDE TASK25 END-EXEC`
- **FILE STATUS + SQLCODE** — VSAM operations use FILE STATUS (`23` = not found), DB2 operations use SQLCODE
- **`COMP-3` arithmetic** — `WS-OLD-PRICE PIC S9(5)V9(2) COMP-3` used for packed-decimal price storage

---

## Notes

- If `PRODUCT NOT FOUND IN VSAM` (status `23`), the record is skipped and counted in `RECORDS NOT FOUND`; no DB2 insert or VSAM rewrite occurs
- Any VSAM I/O error other than `23` is fatal: `ROLLBACK` + `STOP RUN`
- Any DB2 INSERT error is fatal: `ROLLBACK` + `STOP RUN`; since VSAM has not yet been rewritten at that point, both sources remain in sync
- `CHANGE_DATE` in `TB_PRICE_HISTORY` defaults to the current date at INSERT time — no explicit date is passed from COBOL
- Tested on IBM z/OS with DB2 and Enterprise COBOL
