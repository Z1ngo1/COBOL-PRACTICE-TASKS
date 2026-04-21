# Task 23 — VSAM KSDS Credit Approval System

## Overview

Implements a two-program COBOL batch system that evaluates loan requests by performing random-access lookups against a VSAM KSDS customer master file and delegating credit scoring rules to a subprogram. Approved and rejected decisions are written to a sequential approval log.

The two programs work together:
- **[`JOBSUB23`](COBOL/JOBSUB23.cbl)** (Main) — reads [`LOAN.REQUESTS`](DATA/LOAN.REQUESTS), performs a VSAM random read on [`CREDIT.MASTER`](DATA/CREDIT.MASTER) for each request, calls [`SUB1JB23.cbl`](COBOL/SUB1JB23.cbl) and writes the decision to [`APPROVAL.LOG`](DATA/APPROVAL.LOG).
- **[`SUB1JB23`](COBOL/SUB1JB23.cbl)** (Credit Checker) — receives credit score, late payments, current debt, and loan amount; returns APPROVED or REJECTED with a reason code.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `LOANDD` | [`LOAN.REQUESTS`](DATA/LOAN.REQUESTS) | PS | INPUT | Sequential loan request file, RECFM=F, LRECL=80 |
| `MASTERDD` | [`CREDIT.MASTER`](DATA/CREDIT.MASTER) | KSDS | I-O | VSAM indexed customer master, Key pos 1–6 |
| `LOGDD` | [`APPROVAL.LOG`](DATA/APPROVAL.LOG) | PS | OUTPUT | Sequential approval/rejection log |

### Input Record Layout — (`LOANDD`), LRECL=80, RECFM=F

| Field | Position | Format | Description |
|---|---|---|---|
| `CUST-ID` | 1–6 | `X(6)` | Customer identifier (used as KSDS lookup key) |
| `LOAN-AMT` | 7–14 | `9(6)V99` | Requested loan amount |
| `FILLER` | 15–80 | `X(66)` | Reserved |

### VSAM Record Layout — (`MASTERDD`), LRECL=80, Key=1–6

| Field | Position | Format | Description |
|---|---|---|---|
| `CUST-ID` | 1–6 | `X(6)` | **KSDS primary key** — Customer ID |
| `CREDIT-SCORE` | 7–9 | `9(3)` | FICO-like credit score (0–999) |
| `LATE-PAYMENTS` | 10–11 | `9(2)` | Number of late payment occurrences |
| `CURRENT-DEBT` | 12–19 | `9(6)V99` | Total current outstanding debt |
| `FILLER` | 20–80 | `X(61)` | Reserved |

### Output Record Layout — (`LOGDD`)

| Field | Picture | Description |
|---|---|---|
| `LOG-LINE` | `X(80)` | One line per request: `<CUST-ID> <DECISION> <REASON>` |

Decision messages:
- `APPROVED CLIENT QUALIFIES`
- `REJECTED POOR CREDIT SCORE`
- `REJECTED TOO MANY LATE PAYMENTS`
- `REJECTED DEBT EXCEEDS LIMIT`
- `REJECTED CUSTOMER NOT FOUND`

---

## Business Logic

### Phase 1 — VSAM Lookup

For each loan request, the main program performs a random read on `CREDIT.MASTER` using `CUST-ID` as the key:
- **FILE STATUS `00`** — record found; pass data to `SUB1JB23`.
- **FILE STATUS `23`** — key not found; log `REJECTED CUSTOMER NOT FOUND` and skip.
- **Any other FILE STATUS** — log error and terminate the program.

### Phase 2 — Credit Evaluation (`SUB1JB23`)

The subprogram applies four rules **in order**. The first failing rule determines the rejection reason:

| Rule | Condition | Decision |
|---|---|---|
| 1 | `CREDIT-SCORE < 600` | `REJECTED POOR CREDIT SCORE` |
| 2 | `LATE-PAYMENTS >= 3` | `REJECTED TOO MANY LATE PAYMENTS` |
| 3 | `CURRENT-DEBT + LOAN-AMT > CREDIT-SCORE × 200` | `REJECTED DEBT EXCEEDS LIMIT` |
| 4 | All checks pass | `APPROVED CLIENT QUALIFIES` |

---

## Program Flow

1. `OPEN-FILES` — open `LOAN-FILE` (INPUT), `CREDIT-MASTER` (I-O), `APPROVAL-LOG` (OUTPUT); check FILE STATUS for all.
2. `READ` first record from `LOAN-FILE`.
3. `PROCESS-ALL-RECORDS` — main loop until `AT END`:
   - 3.1. `READ CREDIT-MASTER KEY IS CUST-ID` — random VSAM lookup.
   - 3.2. FILE STATUS `23` — log `REJECTED CUSTOMER NOT FOUND`, increment error counter, skip to next record.
   - 3.3. Other non-zero FILE STATUS — log fatal error and `STOP RUN`.
   - 3.4. `CALL 'SUB1JB23' USING CREDIT-SCORE, LATE-PAYMENTS, CURRENT-DEBT, LOAN-AMT, WS-DECISION, WS-REASON`.
   - 3.5. Format and `WRITE` output line to `APPROVAL-LOG`.
   - 3.6. Increment appropriate counter (approved / rejected).
   - 3.7. `READ` next record from `LOAN-FILE`.
4. `CLOSE-FILES` — close all three files.
5. `DISPLAY-SUMMARY` — print records processed, approved, rejected to SYSOUT.
6. `STOP RUN`.

---

## Test Data

All input, master, and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`LOAN.REQUESTS`](DATA/LOAN.REQUESTS) | 7 loan request records (input) |
| [`CREDIT.MASTER`](DATA/CREDIT.MASTER) | VSAM customer master image (5 customers loaded) |
| [`APPROVAL.LOG`](DATA/APPROVAL.LOG) | Approval/rejection log after program execution |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
TOTAL: 7
ERROR: 5
SUCCESS: 2
```

---

## How to Run

1. **Define the VSAM cluster** — submit [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to create the [`CREDIT.MASTER`](DATA/CREDIT.MASTER) KSDS cluster via IDCAMS.
2. **Load customer data** — use IDCAMS REPRO or a separate load step to populate [`CREDIT.MASTER`](DATA/CREDIT.MASTER) with initial records.
3. **Compile and run** — submit [`COMPRUN.jcl`](JCL/COMPRUN.jcl). The job will:
   - Delete previous datasets (`STEP005`).
   - Populate `LOAN.REQUESTS` via `IEBGENER` (`STEP010`).
   - Compile the credit subprogram `SUB1JB23` (`STEP013`).
   - Compile and link `JOBSUB23` with `SUB1JB23`, then execute (`STEP015`).
4. Check `Z73460.TASK23.APPROVAL.LOG` for results.

---

## Key COBOL Concepts Used

- **VSAM KSDS Random Access** — `SELECT ... ORGANIZATION IS INDEXED ACCESS MODE IS RANDOM` with `READ ... KEY IS` for direct lookup by customer ID.
- **FILE STATUS Checking** — `23` for key-not-found, other codes for fatal errors; all VSAM operations are guarded.
- **`CALL ... USING`** — passes credit parameters by reference to the subprogram and receives back the decision and reason.
- **`LINKAGE SECTION`** — defines the parameter interface inside `SUB1JB23`.
- **Rule-Based Evaluation** — sequential rule checks in the subprogram ensure the first failing condition terminates evaluation early.
- **`STRING` with `FUNCTION TRIM`** — builds formatted log lines from customer ID, decision, and reason fields.

---

## Notes

- The VSAM cluster must exist before submitting `COMPRUN.jcl`; the program will abend if `CREDIT.MASTER` is not defined.
- `SUB1JB23` must be compiled before the main program link step; the JCL handles this with `STEP013` running before `STEP015`.
- Customers not found in `CREDIT.MASTER` are rejected immediately without calling the subprogram.
- Tested on IBM z/OS with Enterprise COBOL and VSAM.
