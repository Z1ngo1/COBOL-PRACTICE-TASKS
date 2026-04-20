# Task 22 — Sales Commission Payout with Subprogram Calls

## Overview

Implements a modular COBOL batch system that reads employee sales records from a sequential file, computes commission and tax amounts by calling two specialized subprograms, and writes a formatted payout report. The system demonstrates inter-program communication via `CALL ... USING` and the `LINKAGE SECTION`.

The three programs work together:
- **`JOBSUB22`** (Main) — reads [`SALES.DATA`](DATA/SALES.DATA), calls `SUB1JB22` and `SUB2JB22` for each record, writes results to [`COMM.PAYOUT`](DATA/COMM.PAYOUT).
- **`SUB1JB22`** (Commission Calculator) — receives region and sales amount; returns commission amount based on regional base rate and volume bonus.
- **`SUB2JB22`** (Tax Calculator) — receives commission amount; returns tax amount based on bracket rules.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `SALESDD` | `SALES.DATA` | PS | INPUT | Sequential sales input, RECFM=F, LRECL=80 |
| `PAYOUTDD` | `COMM.PAYOUT` | PS | OUTPUT | Formatted commission payout report |

### Input Record Layout — `SALES.DATA` (`SALESDD`), LRECL=80, RECFM=F

| Field | Position | Format | Description |
|---|---|---|---|
| `EMP-ID` | 1–5 | `X(5)` | Employee identifier |
| `REGION` | 6–7 | `X(2)` | Sales region code (`NY`, `CA`, `TX`, or other) |
| `SALES-AMT` | 8–15 | `9(6)V99` | Total sales amount in dollars |
| `FILLER` | 16–80 | `X(65)` | Reserved |

### Output Record Layout — `COMM.PAYOUT` (`PAYOUTDD`)

| Field | Picture | Description |
|---|---|---|
| `PAYOUT-LINE` | `X(80)` | Formatted line: `<EMP-ID> COMMISSION: <amt>, TAX: <amt>, NET: <amt>` |

---

## Business Logic

### Phase 1 — Commission Calculation (`SUB1JB22`)

Commission is calculated as: `COMMISSION = SALES-AMT × (BASE-RATE + BONUS-RATE)`

**Base rate by region:**

| Region | Base Rate |
|---|---|
| `NY` | 5% |
| `CA` | 7% |
| `TX` | 3% |
| Other | 4% |

**Volume bonus (applied on top of base rate):**

| Sales Amount | Bonus |
|---|---|
| >= $100,000 | +2% |
| >= $50,000 | +1% |
| < $50,000 | 0% |

### Phase 2 — Tax Calculation (`SUB2JB22`)

Tax is deducted from the calculated commission:

| Commission Range | Tax Rate |
|---|---|
| < $1,000 | 15% |
| $1,000 – $4,999.99 | 20% |
| >= $5,000 | 25% |

### Phase 3 — Net Payout

Main program computes: `NET-PAYOUT = COMMISSION - TAX`

Each record produces one formatted output line written to `COMM.PAYOUT`.

---

## Program Flow

1. `OPEN-FILES` — open `SALES-FILE` (INPUT) and `PAYOUT-FILE` (OUTPUT); check FILE STATUS for both.
2. `READ` first record from `SALES-FILE`.
3. `PROCESS-ALL-RECORDS` — main loop until `AT END`:
   - 3.1. Move `SALES-AMT` and `REGION` to linkage parameters.
   - 3.2. `CALL 'SUB1JB22' USING WS-REGION, WS-SALES-AMT, WS-COMMISSION` — receive commission amount.
   - 3.3. `CALL 'SUB2JB22' USING WS-COMMISSION, WS-TAX` — receive tax amount.
   - 3.4. Compute `WS-NET = WS-COMMISSION - WS-TAX`.
   - 3.5. Format and `WRITE` output line to `PAYOUT-FILE`.
   - 3.6. Increment records-processed counter.
   - 3.7. `READ` next record.
4. `CLOSE-FILES` — close both files.
5. `DISPLAY-SUMMARY` — print records processed to SYSOUT.
6. `STOP RUN`.

---

## Test Data

All input and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`SALES.DATA`](DATA/SALES.DATA) | 7 employee sales records (input) |
| [`COMM.PAYOUT`](DATA/COMM.PAYOUT) | Commission payout report (output) |

---

## How to Run

1. Submit [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl). The job will:
   - Delete previous datasets (`STEP005`).
   - Populate `SALES.DATA` via `IEBGENER` (`STEP010`).
   - Compile all three COBOL programs, link them into one load module, and run (`STEP015`).
2. Check `Z73460.TASK22.COMM.PAYOUT` for the payout report.

---

## Key COBOL Concepts Used

- **`CALL ... USING`** — passes data areas by reference between the main program and subprograms.
- **`LINKAGE SECTION`** — defines the parameter interface inside each subprogram (`SUB1JB22`, `SUB2JB22`).
- **Modular Design** — separates I/O logic (main), commission rules (SUB1), and tax rules (SUB2) into independent compilation units.
- **`EVALUATE` Statement** — used in both subprograms to handle multiple region codes and tax brackets cleanly.
- **`STRING` with `FUNCTION TRIM`** — builds formatted output lines dynamically from computed numeric values.

---

## Notes

- All three programs are compiled and linked into a single load module by the JCL; `SUB1JB22` and `SUB2JB22` must be present at link time.
- An unrecognised region code defaults to a 4% base rate — no validation error is raised.
- The volume bonus thresholds ($50,000 and $100,000) are evaluated in descending order so the higher bonus is applied first.
- Tested on IBM z/OS with Enterprise COBOL.
