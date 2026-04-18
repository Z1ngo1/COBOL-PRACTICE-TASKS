# Task 05 — Banking Transaction System (VSAM KSDS Update)

## Overview

Reads a sequential transaction file (PS) and updates customer account balances in a VSAM KSDS master file.
Invalid transactions (account not found, insufficient funds) are written to a separate error report file.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | `TRANS.FILE` | PS | INPUT | Transaction input records |
| `EMPDD` | `ACCT.MASTER` | KSDS | I-O | Account master file (read + rewrite) |
| `REPDD` | `REPORT.FILE` | PS | OUTPUT | Error report output |

### Transaction Record Layout (`INDD`) — LRECL=80, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(5)` | 1–5 | Account ID (matches `ACCT-ID` key in VSAM) |
| `TRANS-TYPE` | `X(1)` | 6 | `D` = Deposit, `W` = Withdrawal |
| `TRANS-AMOUNT` | `9(5)V99` | 7–13 | Amount (implied 2 decimal places) |
| FILLER | `X(67)` | 14–80 | Unused |

### Account Master Record Layout (`EMPDD`) — LRECL=32, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `ACCT-ID` | `X(5)` | 1–5 | **Primary key** |
| `ACCT-NAME` | `X(20)` | 6–25 | Account holder name |
| `ACCT-BAL` | `9(5)V99` | 26–32 | Balance (implied 2 decimal places) |

### Error Report Record Layout (`REPDD`) — LRECL=80, RECFM=FB

| Field | PIC | Content |
|---|---|---|
| `REP-MSG-CONST` | `X(13)` | `TRANS ERROR: ` (constant) |
| `REP-ID` | `X(5)` | Account ID from failed transaction |
| FILLER | `X(1)` | Space |
| `REP-DESC` | `X(61)` | `ACCOUNT NOT FOUND` or `INSUFFICIENT FUNDS` |

---

## VSAM KSDS Definition

Кластер определяется так (`DEFKSDS.jcl`):

```
DEFINE CLUSTER (NAME(Z73460.TASK5.ACCT.MASTER.VSAM)
    RECORDSIZE(32,32)
    TRACKS(15)
    KEYS(5 0)
    CISZ(4096)
    FREESPACE(10,20)
    INDEXED)
```

Run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to create the cluster.

---

## Business Logic

| Transaction Type | Condition | Action |
|---|---|---|
| `D` (Deposit) | Always | `ACCT-BAL = ACCT-BAL + TRANS-AMOUNT` → REWRITE |
| `W` (Withdrawal) | `ACCT-BAL >= TRANS-AMOUNT` | `ACCT-BAL = ACCT-BAL - TRANS-AMOUNT` → REWRITE |
| `W` (Withdrawal) | `ACCT-BAL < TRANS-AMOUNT` | Write error: `INSUFFICIENT FUNDS` — balance unchanged |
| Any | Account not in VSAM | Write error: `ACCOUNT NOT FOUND` — FILE STATUS `23` |

> Unknown transaction types (not `D` or `W`) are silently ignored — no update, no error logged.

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/)) folder:

| File | Description |
|---|---|
| [`TRANS.FILE.INPUT`](DATA/TRANS.FILE.INPUT) | Input transactions — format: `ACCT-ID(5) + TYPE(1) + AMOUNT(7)` |
| [`ACCT.MASTER.BEFORE`](DATA/ACCT.MASTER.BEFORE) | Initial state of VSAM master — format: `ID(5) + NAME(20) + BAL(7)` |
| [`ACCT.MASTER.AFTER`](DATA/ACCT.MASTER.AFTER) | Expected VSAM state after all transactions are applied |
| [`ERROR.REPORT.OUTPUT`](DATA/ERROR.REPORT.OUTPUT) | Expected error report — rejected transactions with reason |

---

## How to Run

1. **Define VSAM cluster** — run [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load `ACCT.MASTER.BEFORE` into the KSDS cluster either via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF (option 3.4 → open VSAM dataset → edit records directly)
3. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMPGO` is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS RANDOM` — random access to KSDS by key
- `READ ... INVALID KEY` — handles FILE STATUS `23` (record not found)
- `REWRITE` — updates an existing VSAM record in place (must follow a successful READ on same key)
- `88` level condition names — `EOF`, `FOUND`, `NOT-FOUND` for readable flow control
- FILE STATUS checks on every I/O operation with explicit `STOP RUN` on unexpected codes

---

## Notes

- VSAM file stays open in `I-O` mode throughout the entire job — do not open/close per transaction
- Each transaction is fully independent: one error does not stop processing of subsequent records
- `REWRITE` requires a prior successful `READ` on the same key — without it, REWRITE will fail
- Zero-amount transactions (`D0000000`, `W0000000`) are processed without errors — no guard needed
- Tested on IBM z/OS with Enterprise COBOL
