# Task 32 — Copybook Customer Import and Report

## Overview

Two COBOL programs share a single copybook (`TASK32`) that defines the customer record layout. `COP1LB32` reads customer records from a PS input file and loads them into a VSAM KSDS master file. `COP2LB32` reads a region filter from SYSIN via `ACCEPT`, scans the KSDS sequentially, and writes all active customers matching the region to a PS output file with final statistics (count, total balance, total credit limit) displayed on SYSOUT. Both programs use `COPY TASK32` in both FD sections and Working-Storage.

---

## Copybook

### [`TASK32.cpy`](COPYLIB/TASK32.cpy)

Shared by both programs. Used in FD sections of both input and output files, and referenced by field names in the PROCEDURE DIVISION.

| Field | PIC | Position | Description |
|---|---|---|---|
| `CUST-ID` | `X(6)` | 1–6 | **Primary key** |
| `CUST-NAME` | `X(30)` | 7–36 | Customer name |
| `CUST-REGION` | `X(2)` | 37–38 | Region code |
| `CUST-STATUS` | `X(1)` | 39 | `A` (Active) or `I` (Inactive) |
| `CUST-CREDIT-LIMIT` | `9(7)V99` | 40–48 | Credit limit |
| `CUST-CURRENT-BAL` | `9(7)V99` | 49–57 | Current balance |
| `LAST-ACT-DATE` | `X(8)` | 58–65 | Last activity date `YYYYMMDD` |

---

## Program 1 — [`COP1LB32.cbl`](COBOL/COP1LB32.cbl) — PS to VSAM Import

### Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | [`CUST.IN.PS`](DATA/CUST.IN.PS) | PS | INPUT | Customer input file |
| `MASTDD` | [`CUST.MSTER.VSAM`](DATA/CUST.MSTER.VSAM) | KSDS | OUTPUT | VSAM master file |

### Business Logic

| Phase | Condition | Action |
|---|---|---|
| 1 — Read PS input | Record read OK | Proceed to write |
| 1 — Read PS input | Read error | Display status, `STOP RUN` |
| 2 — Write to KSDS | Write OK | `ADD 1 TO WS-LOAD-COUNT` |
| 2 — Write to KSDS | Write error | Display status + `CUST-ID`, `STOP RUN` |
| 3 — Statistics | EOF reached | `DISPLAY 'TOTAL LOADED: '` with count |

### Program Flow

1. **OPEN** — `CUST-IN-FILE` (INPUT), `CUST-MASTER-FILE` (OUTPUT).
2. **Read loop** — read `CUST-IN-FILE` until EOF; for each record: `MOVE CUST-IN-REC TO CUST-MASTER-REC`, `WRITE CUST-MASTER-REC`, `ADD 1 TO WS-LOAD-COUNT`.
3. **CLOSE** all files.
4. **Display** total loaded count.
5. **STOP RUN**.

---

## Program 2 — [`COP2LB32.cbl`](COBOL/COP2LB32.cbl) — VSAM Filtered Report

### Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `MASTDD` | [`CUST.MSTER.VSAM`](DATA/CUST.MSTER.VSAM) | KSDS | INPUT | VSAM master file |
| `OUTDD` | [`CUST.OUT.PS`](DATA/CUST.OUT.PS) | PS | OUTPUT | Filtered report file |

### SYSIN Filter Parameter

| Field | PIC | Description |
|---|---|---|
| `WS-REGION-FILTER` | `X(2)` | Region code to filter by; read via `ACCEPT` |

### Business Logic

| Phase | Condition | Action |
|---|---|---|
| 1 — Read filter | — | `ACCEPT WS-REGION-FILTER` from SYSIN |
| 2 — Scan KSDS | `CUST-STATUS ≠ 'A'` | Skip record |
| 2 — Scan KSDS | `CUST-REGION ≠ WS-REGION-FILTER` | Skip record |
| 2 — Scan KSDS | Both conditions pass | Write record; accumulate count, balance, credit limit |
| 2 — Scan KSDS | Write error | Display status + `CUST-ID`, `STOP RUN` |
| 3 — Statistics | EOF reached | Display count, total balance, total credit limit |

### Program Flow

1. **OPEN** — `CUST-MASTER-FILE` (INPUT), `CUST-OUT-FILE` (OUTPUT).
2. **ACCEPT** — read `WS-REGION-FILTER` (2 bytes) from SYSIN.
3. **Read loop** — read `CUST-MASTER-FILE` sequentially until EOF; for each record: check `CUST-STATUS = 'A'` AND `CUST-REGION = WS-REGION-FILTER`; if both pass — write to `CUST-OUT-FILE`, accumulate totals.
4. **CLOSE** all files.
5. **Display** total active count, total balance, total credit limit.
6. **STOP RUN**.

---

## Test Data

Input and output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`CUST.IN.PS`](DATA/CUST.IN.PS) | 10 customer records (various regions and statuses) |
| [`CUST.MSTER.VSAM`](DATA/CUST.MSTER.VSAM) | VSAM master file — output of Program 1, input of Program 2 |
| [`CUST.OUT.PS`](DATA/CUST.OUT.PS) | Filtered report — active customers for the selected region |

---

## Expected SYSOUT

Actual job output is stored in [`FIRST.SYSOUT.txt`](OUTPUT/FIRST.SYSOUT.txt) and [`SECOND.SYSOUT.txt`](OUTPUT/SECOND.SYSOUT.txt).

**Program 1 — COP1LB32:**
```
TOTAL LOADED: 10
```

**Program 2 — COP2LB32 (region filter `US`):**
```
TOTAL ACTIVE IN REGION US: 3
TOTAL BALANCE: 15000.00
TOTAL CREDIT LIMIT: 30000.00
```

---

## How to Run

1. **Define VSAM KSDS cluster** — run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Compile and run both programs** — run [`COMPRUN.jcl`](JCL/COMPRUN.jcl) (compiles `COP1LB32` and `COP2LB32`, loads PS input data, runs Program 1 then Program 2 with region filter in SYSIN)
3. **Review output** — see [`CUST.OUT.PS`](DATA/CUST.OUT.PS) and SYSOUT files in [`OUTPUT/`](OUTPUT/)

---

## Key COBOL Concepts Used

- **`COPY TASK32` in FD sections** — the same copybook is used directly inside `01 CUST-IN-REC`, `01 CUST-MASTER-REC`, and `01 CUST-OUT-REC`; this means all three FD record areas share identical field names, which requires the `OF` qualifier (`CUST-ID OF CUST-MASTER-REC`) to disambiguate in the PROCEDURE DIVISION
- **`MOVE CUST-IN-REC TO CUST-MASTER-REC`** — because both records are defined by the same copybook and have identical length, a single group MOVE copies the entire record without field-by-field assignments
- **`ACCEPT WS-REGION-FILTER`** — Program 2 reads the 2-byte region code directly from the SYSIN stream using `ACCEPT` instead of opening and parsing a file; this is simpler than the SYSIN file approach used in Task 30 but only works for a single short value
- **Two-filter inline condition** — `CUST-STATUS = 'A' AND CUST-REGION = WS-REGION-FILTER` is evaluated in a single `IF` without a separate paragraph or `EXIT PARAGRAPH`; both conditions must pass before the record is written or accumulated
- **Accumulator pattern** — `WS-TOTAL-BAL` and `WS-TOTAL-LIMIT` accumulate packed decimal values record by record; at end of file they are moved to display pictures (`Z(8)9.99`) and trimmed with `FUNCTION TRIM` before `DISPLAY`
- **`COPYLIB` as a separate PDS** — `TASK32.cpy` lives in its own `COPYLIB` dataset referenced in JCL via `SYSLIB DD`; the compiler resolves `COPY TASK32` by searching this library, which is how copybooks work in production z/OS environments

---

## Notes

- `CUST.MSTER.VSAM` is the link between the two programs — Program 1 writes it, Program 2 reads it; they must run in sequence within the same job
- The copybook is included in four FD `01` records across two programs; any change to the record layout requires recompiling both programs
- Program 2 opens the KSDS with `ACCESS MODE IS SEQUENTIAL` and `OPEN INPUT` — it cannot do random lookups; it reads every record from the cluster and filters in COBOL logic
- `ACCEPT WS-REGION-FILTER` reads exactly 2 bytes from the SYSIN stream; if the value in the JCL SYSIN DD is shorter or has trailing spaces, the region comparison may fail silently
- Tested on IBM z/OS with Enterprise COBOL
