# Task 13 — Master File Synchronization (Old Master + Transactions = New Master)

## Overview

Applies a daily transaction file [`TRANS.FILE`](./DATA/TRANS.FILE) to an existing customer master file [`OLD.MASTER`](./DATA/OLD.MASTER) and produces an updated master file [`NEW.MASTER`](./DATA/NEW.MASTER) plus an error log [`ERROR.REPORT`](./DATA/ERROR.REPORT).
The core technique is the **Match-Merge (Balance Line) algorithm**: both files are read in parallel, their keys are compared on every iteration, and the program routes each situation to the correct action — copy, add, update, delete, or error.
No VSAM, no DB2 — pure sequential processing with two simultaneous read cursors.

---

## Critical Prerequisite: Both Files Must Be Pre-Sorted

> **Both [`OLD.MASTER`](./DATA/OLD.MASTER) and [`TRANS.FILE`](./DATA/TRANS.FILE) must be sorted by ID (ascending) before this program runs.**

The match-merge algorithm assumes sorted input. Unsorted files will produce **incorrect output without any error message or ABEND**. Use a `SORT` step in the JCL before the program step if your input is not already sorted.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `OLDDD` | [`OLD.MASTER`](./DATA/OLD.MASTER) | PS | INPUT | Current customer master — ID, name, balance; LRECL=80, RECFM=F |
| `TRNSDD` | [`TRANS.FILE`](./DATA/TRANS.FILE) | PS | INPUT | Daily transactions — ID, action code, data, amount; LRECL=80, RECFM=F |
| `NEWDD` | [`NEW.MASTER`](./DATA/NEW.MASTER) | PS | OUTPUT | Updated master file after all transactions applied; LRECL=80, RECFM=F |
| `REPDD` | [`ERROR.REPORT`](./DATA/ERROR.REPORT) | PS | OUTPUT | Failed transactions logged for review; LRECL=80, RECFM=F |

### Input Record Layout — (`OLDDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `OLD-ID` | `X(5)` | 1 | **Sort key** — customer ID, ascending |
| `OLD-NAME` | `X(20)` | 6 | Customer name |
| `OLD-BAL` | `9(5)V99` | 26 | Account balance — implicit 2 decimal places |
| FILLER | `X(48)` | 33 | Padding to 80 bytes |

### Input Record Layout — (`TRNSDD`), LRECL=80, RECFM=F

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

Same layout as `TRANS.FILE` — `REP-ID X(5)`, `REP-ACT X(1)`, `REP-NAME X(20)`, `REP-BAL 9(5)V99`, `FILLER X(47)`. Each record is the raw failing transaction written as-is for manual review.

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

When a file reaches end-of-file, its key is set to `HIGH-VALUES` (all `X'FF'` bytes — the highest possible value in EBCDIC). This means any real key from the other file is always **less than** `HIGH-VALUES`, so the loop naturally drains both files without special EOF handling inside `PROCESS-MERGE-LOGIC`. The loop exits only when **both** keys equal `HIGH-VALUES`.

### Three-Way Key Comparison

```cobol
PERFORM PROCESS-MERGE-LOGIC
  UNTIL WS-OLD-ID = HIGH-VALUES AND WS-TRNS-ID = HIGH-VALUES

PROCESS-MERGE-LOGIC:
  EVALUATE TRUE
    WHEN WS-TRNS-ID > WS-OLD-ID  --> Case 1: no more transactions for this master record
    WHEN WS-TRNS-ID < WS-OLD-ID  --> Case 2: orphan transaction (no master match)
    WHEN WS-TRNS-ID = WS-OLD-ID  --> Case 3: match — apply transaction
  END-EVALUATE
```

### Case 1 — TRANS-ID > MASTER-ID (no more transactions for this master record)

**Meaning**: All transactions for `OLD-ID` are done (or there were none).
**Action**: Write `WS-CUR-REC` to `NEW.MASTER` (unless `WS-DEL-FLAG = 'Y'`). Reset `WS-DEL-FLAG` to 'N'.
**Read**: Read next `OLD.MASTER` record → update `WS-OLD-ID`.

This also handles the tail of `OLD.MASTER` after `TRANS.FILE` is exhausted (`WS-TRNS-ID = HIGH-VALUES > any real master key`).

### Case 2 — TRANS-ID < MASTER-ID (orphan transaction)

**Meaning**: A transaction arrived for an ID that does not exist in `OLD.MASTER`.

| Action code | Result |
|---|---|
| `A` (Add) | **Valid** — build new record from `TRNS-DATA` + `TRNS-AMOUNT`, write to `NEW.MASTER` |
| `U` (Update) | **Error** — cannot update non-existent record; log to `ERROR.REPORT` |
| `D` (Delete) | **Error** — cannot delete non-existent record; log to `ERROR.REPORT` |

**Read**: Read next `TRANS.FILE` record → update `WS-TRNS-ID`. (Master cursor does NOT move.)

This also handles the tail of `TRANS.FILE` after `OLD.MASTER` is exhausted (`WS-OLD-ID = HIGH-VALUES > any real trans key`).

### Case 3 — TRANS-ID = MASTER-ID (match — apply transaction)

**Meaning**: Transaction targets an existing master record.

| Action code | Result |
|---|---|
| `U` (Update) | **Valid** — `ADD TRNS-AMOUNT TO WS-CUR-BAL`. Record stays in memory, **not written yet** |
| `D` (Delete) | **Valid** — `MOVE 'Y' TO WS-DEL-FLAG`. Record will be skipped when written |
| `A` (Add) | **Error** — duplicate add on existing ID; log to `ERROR.REPORT` |

> **Why not write immediately on Update?** The next transaction may also target the same ID (e.g., a second `U`, or a `D`). The record stays in `WS-CUR-REC` until `TRANS-ID > MASTER-ID` (Case 1) triggers the write.

**Read**: Read next `TRANS.FILE` record → update `WS-TRNS-ID`. (Master cursor does NOT move.)

---

## Program Flow

1.  **PERFORM OPEN-ALL-FILES** — opens `OLDDD` (INPUT), `TRNSDD` (INPUT), `NEWDD` (OUTPUT), and `REPDD` (OUTPUT). If any status is not `'00'`, displays an error and stops the run.
2.  **PERFORM READ-OLD-MASTER** — reads the first record from `OLDDD` into `WS-CUR-REC` and sets `WS-OLD-ID`. If the file is empty, sets `WS-OLD-ID` to `HIGH-VALUES`.
3.  **PERFORM READ-TRANSACTION** — reads the first record from `TRNSDD` and sets `WS-TRNS-ID`. If empty, sets to `HIGH-VALUES`.
4.  **PERFORM PROCESS-MERGE-LOGIC** — the main loop that continues until both `WS-OLD-ID` and `WS-TRNS-ID` reach `HIGH-VALUES`.
    *   **Case 1 (TRNS > OLD):** Finalizes the current master record. Calls `WRITE-NEW-MASTER-REC` (which skips if `WS-DEL-FLAG = 'Y'`), resets flags, and reads the next `OLD.MASTER`.
    *   **Case 2 (TRNS < OLD):** Handles orphan transactions. If action is `A`, writes a new record directly; otherwise, logs an error. Reads the next `TRANS.FILE`.
    *   **Case 3 (TRNS = OLD):** Updates the record in memory. If action is `U`, adds the amount to the balance; if `D`, marks for deletion. Reads the next `TRANS.FILE`.
5.  **DISPLAY-SUMMARY** — prints final statistics to SYSOUT (records read, added, updated, deleted, and errors).
6.  **PERFORM CLOSE-ALL-FILES** — closes all four datasets and stops the program.

---

## Test Data

All input and expected output files are in the [`DATA/`](./DATA) folder.

| File | Description |
|---|---|
| [`OLD.MASTER`](./DATA/OLD.MASTER) | 7 test customer records (pre-sorted by ID) |
| [`TRANS.FILE`](./DATA/TRANS.FILE) | 15 daily transactions (pre-sorted by ID) |
| [`NEW.MASTER`](./DATA/NEW.MASTER) | Expected updated master output — 9 records |
| [`ERROR.REPORT`](./DATA/ERROR.REPORT) | Expected error log — 3 failed transactions |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](./OUTPUT/SYSOUT.txt).

```text
========================================
 MASTER FILE UPDATE SUMMARY
========================================
 OLD MASTER RECORDS READ:       7
 TRANSACTIONS PROCESSED:       15
 NEW MASTER RECORDS:            9
   ADDED:                       4
   UPDATED:                     5
   DELETED:                     2
 ERRORS LOGGED:                 3
========================================
```

---

## How to Run

1.  Upload [`OLD.MASTER`](./DATA/OLD.MASTER) and [`TRANS.FILE`](./DATA/TRANS.FILE) to your mainframe datasets manually through option '3.4 and edit your dataset' or
2.  Submit [`COMPRUN.jcl`](./JCL/COMPRUN.jcl) — it includes a insert data step
3.  Compare output files and sysout - see [`NEW.MASTER`](./DATA/NEW.MASTER), [`ERROR.REPORT`](./DATA/ERROR.REPORT)  and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt)

> **PROC reference:** [`COMPRUN.jcl`](./JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure.

---

## Key COBOL Concepts Used

*   **Match-Merge (Balance Line) algorithm** — processing two sorted sequential files in a single loop with two independent read cursors.
*   **`HIGH-VALUES` as EOF sentinel** — simplifies loop termination and logic.
*   **Deferred write pattern** — accumulating updates in memory (`WS-CUR-REC`) until all transactions for a key are processed.
*   **`WS-DEL-FLAG` with post-delete guard** — prevents updates or re-deletes on already-removed records.

---

## Notes

*   **EBCDIC HIGH-VALUES:** The use of `X'FF'` as an EOF sentinel is a standard mainframe pattern. It ensures the exhausted file always \"loses\" the comparison, allowing the remaining file to be drained naturally by the same loop logic.
*   **Sequential Sync Pattern:** This is the most efficient way to synchronize two large sequential files without using a database. It only requires one pass through each file.
*   **Transaction Integrity:** Multiple updates to the same record are accumulated correctly in `WS-CUR-REC`. The record is only written to the new master file once the transaction key moves to a higher value.
*   **Error Reporting:** Any invalid transaction (e.g., updating a non-existent record or adding an existing one) is preserved in its raw format in the `ERROR.REPORT` file for manual review.
