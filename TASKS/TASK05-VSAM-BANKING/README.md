# Task 05 - Banking Transaction System (VSAM KSDS Update)

## Overview

Reads a sequential transaction file (PS) and updates customer account balances in a VSAM KSDS master file. Invalid transactions (account not found, insufficient funds) are written to a separate error report file.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | [`TRANS.FILE`](DATA/TRANS.FILE.INPUT) | PS | INPUT | Transaction input records |
| `EMPDD` | [`ACCT.MASTER`](DATA/ACCT.MASTER.BEFORE) | KSDS | I-O | Account master file (read + rewrite) |
| `REPDD` | [`REPORT.FILE`](DATA/ERROR.REPORT.OUTPUT) | PS | OUTPUT | Error report output |

### Transaction Record Layout (`INDD`) - LRECL=80, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(5)` | 1–5 | Account ID (matches `ACCT-ID` key in VSAM) |
| `TRANS-TYPE` | `X(1)` | 6 | `D` = Deposit, `W` = Withdrawal |
| `TRANS-AMOUNT` | `9(5)V99` | 7–13 | Amount (implied 2 decimal places) |
| FILLER | `X(67)` | 14–80 | Unused |

### Account Master Record Layout (`EMPDD`) - LRECL=32, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `ACCT-ID` | `X(5)` | 1–5 | **Primary key** |
| `ACCT-NAME` | `X(20)` | 6–25 | Account holder name |
| `ACCT-BAL` | `9(5)V99` | 26–32 | Balance (implied 2 decimal places) |

### Error Report Record Layout (`REPDD`) - LRECL=80, RECFM=FB

| Field | PIC | Content |
|---|---|---|
| `REP-MSG-CONST` | `X(13)` | `TRANS ERROR:` (constant) |
| `REP-ID` | `X(5)` | Account ID from failed transaction |
| FILLER | `X(1)` | Space |
| `REP-DESC` | `X(61)` | `ACCOUNT NOT FOUND` or `INSUFFICIENT FUNDS` |

---

## Business Logic: Transaction Processing

The program implements a sequential update pattern where each transaction is validated against the master file before applying updates or logging errors.

| Transaction Type | Condition | Action |
|---|---|---|
| `D` (Deposit) | Always | `ACCT-BAL = ACCT-BAL + TRANS-AMOUNT` → REWRITE |
| `W` (Withdrawal) | `ACCT-BAL >= TRANS-AMOUNT` | `ACCT-BAL = ACCT-BAL - TRANS-AMOUNT` → REWRITE |
| `W` (Withdrawal) | `ACCT-BAL < TRANS-AMOUNT` | Write error: `INSUFFICIENT FUNDS` - balance unchanged |
| Any | Account not in VSAM | Write error: `ACCOUNT NOT FOUND` - FILE STATUS `23` |

> Unknown transaction types (not `D` or `W`) are silently ignored - no update, no error logged.

---

## Program Flow

1. **OPEN** - transaction file (`INDD`) opened as INPUT, VSAM master (`EMPDD`) opened as I-O, error report (`REPDD`) opened as OUTPUT; check FILE STATUS for all.
2. **READ** next transaction record from `INDD` - if EOF, go to step 7.
3. **READ VSAM** master by key (`TRANS-ACCT-ID` → `ACCT-ID`):
   - FILE STATUS `00` → record found, continue.
   - FILE STATUS `23` → record not found → write `ACCOUNT NOT FOUND` to error report → go to step 2.
   - Any other status → abnormal termination (`STOP RUN`).
4. **Check transaction type:**
   - `D` (Deposit) → `ACCT-BAL = ACCT-BAL + TRANS-AMOUNT` → go to step 5.
   - `W` (Withdrawal) → check balance:
     - `ACCT-BAL >= TRANS-AMOUNT` → `ACCT-BAL = ACCT-BAL - TRANS-AMOUNT` → go to step 5.
     - `ACCT-BAL < TRANS-AMOUNT` → write `INSUFFICIENT FUNDS` to error report → go to step 2.
   - Unknown type → skip silently → go to step 2.
5. **REWRITE** updated record back to VSAM master; check FILE STATUS.
6. Go to step 2.
7. **CLOSE** all files → **STOP RUN**.

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`TRANS.FILE.INPUT`](DATA/TRANS.FILE.INPUT) | Input transactions - format: `ACCT-ID(5) + TYPE(1) + AMOUNT(7)` |
| [`ACCT.MASTER.BEFORE`](DATA/ACCT.MASTER.BEFORE) | Initial state of VSAM master - format: `ID(5) + NAME(20) + BAL(7)` |
| [`ACCT.MASTER.AFTER`](DATA/ACCT.MASTER.AFTER) | Expected VSAM state after all transactions are applied |
| [`ERROR.REPORT.OUTPUT`](DATA/ERROR.REPORT.OUTPUT) | Expected error report - rejected transactions with reason |

---

## How to Run

1. **Define VSAM cluster** - run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** - load [`ACCT.MASTER.BEFORE`](DATA/ACCT.MASTER.BEFORE) into the KSDS cluster either via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF
3. **Compile and run** - run [`COMPRUN.jcl`](JCL/COMPRUN.jcl)
4. **Compare output files** - see [`ACCT.MASTER.AFTER`](DATA/ACCT.MASTER.AFTER) and [`ERROR.REPORT.OUTPUT`](DATA/ERROR.REPORT.OUTPUT)

> **PROC reference:** [`COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS RANDOM` - random access to KSDS by key
- `READ ... INVALID KEY` - handles FILE STATUS `23` (record not found)
- `REWRITE` - updates an existing VSAM record in place (must follow a successful READ on same key)
- `88` level condition names - `EOF`, `FOUND`, `NOT-FOUND` for readable flow control
- FILE STATUS checks on every I/O operation with explicit `STOP RUN` on unexpected codes

---

## Notes

- VSAM file stays open in `I-O` mode throughout the entire job - do not open/close per transaction
- Each transaction is fully independent: one error does not stop processing of subsequent records
- `REWRITE` requires a prior successful `READ` on the same key - without it, REWRITE will fail
- Zero-amount transactions (`D0000000`, `W0000000`) are processed without errors - no guard needed
- Tested on IBM z/OS with Enterprise COBOL
