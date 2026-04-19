# Task 13 — Master File Synchronization (Old Master + Transactions = New Master)

## Overview

Applies a daily transaction file (`TRANS.FILE`) to an existing customer master file (`OLD.MASTER`) and produces an updated master file (`NEW.MASTER`) plus an error log (`ERROR.REPORT`).
The core technique is the **Match-Merge (Balance Line) algorithm**: both files are read in parallel, their keys are compared on every iteration, and the program routes each situation to the correct action — copy, add, update, delete, or error.
No VSAM, no DB2 — pure sequential processing with two simultaneous read cursors.

---

## ⚠️ Critical Prerequisite: Both Files Must Be Pre-Sorted

> **Both `OLD.MASTER` and `TRANS.FILE` must be sorted by ID (ascending) before this program runs.**

The match-merge algorithm assumes sorted input. Unsorted files will produce **incorrect output without any error message or ABEND**. Use a `SORT` step in the JCL before the program step if your input is not already sorted.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `OLDDD` | `OLD.MASTER` | PS | INPUT | Current customer master — ID, name, balance; LRECL=80, RECFM=F |
| `TRNSDD` | `TRANS.FILE` | PS | INPUT | Daily transactions — ID, action code, data, amount; LRECL=80, RECFM=F |
| `NEWDD` | `NEW.MASTER` | PS | OUTPUT | Updated master file after all transactions applied; LRECL=80, RECFM=F |
| `REPDD` | `ERROR.REPORT` | PS | OUTPUT | Failed transactions logged for review; LRECL=80, RECFM=F |

### Input Record Layout — `OLD.MASTER` (`OLDDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `OLD-ID` | `X(5)` | 1 | **Sort key** — customer ID, ascending |
| `OLD-NAME` | `X(20)` | 6 | Customer name |
| `OLD-BAL` | `9(5)V99` | 26 | Account balance — implicit 2 decimal places |
| FILLER | `X(48)` | 33 | Padding to 80 bytes |

### Input Record Layout — `TRANS.FILE` (`TRNSDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRNS-ID` | `X(5)` | 1 | **Sort key** — customer ID, ascending |
| `TRNS-ACT` | `X(1)` | 6 | Action code: `A` = Add, `U` = Update, `D` = Delete |
| `TRNS-DATA` | `X(20)` | 7 | New customer name (used only for `A`) |
| `TRNS-AMOUNT` | `9(5)V99` | 27 | Amount to add to balance (used for `A` and `U`) |
| FILLER | `X(47)` | 34 | Padding to 80 bytes |

### Output Record Layout — `NEW.MASTER` (`NEWDD`), LRECL=80, RECFM=F

Same layout as `OLD.MASTER` — `NEW-ID X(5)`, `NEW-NAME X(20)`, `NEW-BAL 9(5)V99`, `FILLER X(48)`.

### Output Record Layout — `ERROR.REPORT` (`REPDD`), LRECL=80, RECFM=F

Same layout as `TRANS.FILE` — `REP-ID X(5)`, `REP-ACT X(1)`, `REP-NAME X(20)`, `REP-BAL 9(5)V99`, `FILLER X(47)`.
Each record is the raw failing transaction written as-is for manual review.

---

## Match-Merge Algorithm

This is the core concept of the task. The algorithm processes both sorted files simultaneously using a single loop — it never reads one file inside the loop of the other.

### Key Variables

| Variable | Role |
|---|---|
| `WS-OLD-ID` | Key value of the current OLD.MASTER record (set to `HIGH-VALUES` at EOF) |
| `WS-TRNS-ID` | Key value of the current TRANS.FILE record (set to `HIGH-VALUES` at EOF) |
| `WS-CUR-REC` | Working copy of the current master record in memory — accumulates all updates before being written |
| `WS-DEL-FLAG` | `'Y'` = current master record is marked for deletion; `WRITE-NEW-MASTER-REC` will skip it |

### HIGH-VALUES as EOF Sentinel

When a file reaches end-of-file, its key is set to `HIGH-VALUES` (all `X'FF'` bytes — the highest possible value in EBCDIC).
This means any real key from the other file is always **less than** `HIGH-VALUES`, so the loop naturally drains both files without special EOF handling inside `PROCESS-MERGE-LOGIC`.
The loop exits only when **both** keys equal `HIGH-VALUES`.

### Three-Way Key Comparison

```
PERFORM PROCESS-MERGE-LOGIC
    UNTIL WS-OLD-ID = HIGH-VALUES AND WS-TRNS-ID = HIGH-VALUES

PROCESS-MERGE-LOGIC:
  EVALUATE TRUE
    WHEN WS-TRNS-ID > WS-OLD-ID  →  Case 1: no transaction for this master record
    WHEN WS-TRNS-ID < WS-OLD-ID  →  Case 2: orphan transaction (no master match)
    WHEN WS-TRNS-ID = WS-OLD-ID  →  Case 3: match — apply transaction
  END-EVALUATE
```

---

### Case 1 — TRANS-ID > MASTER-ID (no transaction for this master record)

```
Meaning : All transactions for OLD-ID are done (or there were none).
Action  : Write WS-CUR-REC to NEW.MASTER (unless WS-DEL-FLAG = 'Y').
          Reset WS-DEL-FLAG to 'N'.
Read    : Read next OLD.MASTER record → update WS-OLD-ID.
```

This also handles the tail of OLD.MASTER after TRANS.FILE is exhausted
(`WS-TRNS-ID = HIGH-VALUES > any real master key`).

---

### Case 2 — TRANS-ID < MASTER-ID (orphan transaction)

```
Meaning : A transaction arrived for an ID that does not exist in OLD.MASTER.
```

| Action code | Result |
|---|---|
| `A` (Add) | **Valid** — build new record from `TRNS-DATA` + `TRNS-AMOUNT`, write to NEW.MASTER |
| `U` (Update) | **Error** — cannot update non-existent record; log to ERROR.REPORT |
| `D` (Delete) | **Error** — cannot delete non-existent record; log to ERROR.REPORT |

```
Read    : Read next TRANS.FILE record → update WS-TRNS-ID.
          (Master cursor does NOT move — we haven't passed this master record yet.)
```

This also handles the tail of TRANS.FILE after OLD.MASTER is exhausted
(`WS-OLD-ID = HIGH-VALUES > any real trans key`).

---

### Case 3 — TRANS-ID = MASTER-ID (match — apply transaction)

```
Meaning : Transaction targets an existing master record.
```

| Action code | Result |
|---|---|
| `U` (Update) | **Valid** — `ADD TRNS-AMOUNT TO WS-CUR-BAL`. Record stays in memory, **not written yet** |
| `D` (Delete) | **Valid** — `MOVE 'Y' TO WS-DEL-FLAG`. Record will be skipped when written |
| `A` (Add) | **Error** — duplicate add on existing ID; log to ERROR.REPORT |

> **Why not write immediately on Update?**
> The next transaction may also target the same ID (e.g., a second `U`, or a `D`).
> The record stays in `WS-CUR-REC` until `TRANS-ID > MASTER-ID` (Case 1) triggers the write.

```
Read    : Read next TRANS.FILE record → update WS-TRNS-ID.
          (Master cursor does NOT move — more transactions for this ID may follow.)
```

---

### Multiple Transactions for the Same ID

> **Note:** Multiple transactions for the same ID are supported in a single run (e.g., two `U` updates, or `U` followed by `D`). They are applied sequentially in the order they appear in `TRANS.FILE` before the master record is written or skipped.

Example — ID `00800` has two `U` transactions in the test data:
```
00800U  0001000   → WS-CUR-BAL = 0003000 + 100.00 = 0004000 (00040.00)
00800U  0002000   → WS-CUR-BAL = 0004000 + 200.00 = 0006000 (00060.00)
```
The master record for `00800` is only written once, after both updates are accumulated.

If `WS-DEL-FLAG = 'Y'` and another transaction arrives for the same ID, it is logged as an error — you cannot update or re-delete an already-deleted record within the same run.

---

### Full Algorithm Flowchart

```
OPEN all files
READ first OLD.MASTER  → WS-OLD-ID  (HIGH-VALUES if empty)
READ first TRANS.FILE  → WS-TRNS-ID (HIGH-VALUES if empty)

PERFORM UNTIL WS-OLD-ID = HIGH-VALUES AND WS-TRNS-ID = HIGH-VALUES
  │
  ├─ TRNS-ID > OLD-ID  ──────────────────────────────── Case 1
  │    PERFORM WRITE-NEW-MASTER-REC                      (writes if DEL-FLAG='N')
  │    PERFORM READ-OLD-MASTER                           → advance master cursor
  │
  ├─ TRNS-ID < OLD-ID  ──────────────────────────────── Case 2
  │    IF TRNS-ACT = 'A'
  │       write new record to NEW.MASTER
  │    ELSE
  │       PERFORM LOG-ERROR-TRANSACTION
  │    PERFORM READ-TRANSACTION                          → advance trans cursor
  │
  └─ TRNS-ID = OLD-ID  ──────────────────────────────── Case 3
       IF DEL-FLAG = 'Y'
          PERFORM LOG-ERROR-TRANSACTION                  (post-delete trans = error)
       ELSE
          IF TRNS-ACT = 'U' → ADD TRNS-AMOUNT TO WS-CUR-BAL
          IF TRNS-ACT = 'D' → MOVE 'Y' TO WS-DEL-FLAG
          IF TRNS-ACT = 'A' → PERFORM LOG-ERROR-TRANSACTION (duplicate)
       PERFORM READ-TRANSACTION                          → advance trans cursor only

CLOSE all files
DISPLAY-SUMMARY to SYSOUT
STOP RUN
```

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/OLD.MASTER`](DATA/OLD.MASTER) | 7 test customer records (pre-sorted by ID) |
| [`DATA/TRANS.FILE`](DATA/TRANS.FILE) | 15 daily transactions (pre-sorted by ID) |
| [`DATA/NEW.MASTER`](DATA/NEW.MASTER) | Expected updated master output — 9 records |
| [`DATA/ERROR.REPORT`](DATA/ERROR.REPORT) | Expected error log — 3 failed transactions |

---

## Run Statistics (SYSOUT)

```
========================================
MASTER FILE UPDATE SUMMARY
========================================
OLD MASTER RECORDS READ:      7
TRANSACTIONS PROCESSED:      15
NEW MASTER RECORDS:           9
ADDED:                        4
UPDATED:                      5
DELETED:                      2
ERRORS LOGGED:                3
========================================
```

---

## How to Run

1. Upload [`DATA/OLD.MASTER`](DATA/OLD.MASTER) and [`DATA/TRANS.FILE`](DATA/TRANS.FILE) to your mainframe datasets
2. Submit [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMP`](../../JCLPROC/MYCOMP.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMP` is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- **Match-Merge (Balance Line) algorithm** — the central pattern of this task; two sorted sequential files are processed in a single loop with two independent read cursors; on each iteration exactly one cursor advances depending on the key comparison result
- **`HIGH-VALUES` as EOF sentinel** — when a file is exhausted its key is set to `HIGH-VALUES` (`X'FF...'`); because no real key can exceed it, the remaining records of the other file drain naturally without any extra EOF branching inside the loop
- **Deferred write pattern** — on a match (`=` case) the master record is never written immediately; it stays in `WS-CUR-REC` so that subsequent transactions for the same ID keep accumulating; the write fires only when the trans cursor finally moves past this master ID (Case 1)
- **`WS-DEL-FLAG` with post-delete guard** — a `'Y'`/`'N'` flag that suppresses the write for a deleted record; if another transaction arrives for the same ID while the flag is `'Y'`, it is rejected as an error — preventing updates or re-deletes on an already-removed record within the same run
