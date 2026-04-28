# Task 30 — SYSIN-Driven Filtered Operation Report

## Overview

Reads filter parameters from a SYSIN stream (date range, minimum amount, operation type), then scans a VSAM KSDS operation log sequentially. For each record, all four filters are applied in sequence with early exit on mismatch. Records that pass all filters are written to a PS filtered report file. No data is updated — this is a read-only filtering program.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|
| `SYSIN` | `SYSIN` | PS | INPUT | JCL inline filter parameters |
| `OPRDD` | [`OPR.LOG.KSDS`](DATA/OPR.LOG.KSDS) | KSDS | INPUT | Operation log (sequential scan) |
| `REPDD` | [`FILTERED.REPORT`](DATA/FILTERED.REPORT) | PS | OUTPUT | Filtered report file |

### Operation Log Record Layout (`OPRDD`) — KSDS, LRECL=80

| Field | PIC | Position | Description |
|---|---|---|---|
| `OPR-ACCT-ID` | `X(6)` | 1–6 | Account ID — part of composite key |
| `OPR-DATE` | `X(8)` | 7–14 | Operation date `YYYYMMDD` — part of composite key |
| `OPR-ID` | `X(6)` | 15–20 | Operation ID — part of composite key |
| `OPR-TYPE` | `X(1)` | 21 | Operation type: `D` (Debit) or `C` (Credit) |
| `OPR-AMOUNT` | `9(7)V99` | 22–30 | Operation amount |
| FILLER | `X(50)` | 31–80 | Unused |

### Filtered Report Layout (`REPDD`) — PS, LRECL=36, RECFM=FB

| Field | PIC | Description |
|---|---|---|
| `WS-REP-ACCT-ID` | `X(6)` | Account ID |
| FILLER | `X(1)` | Space |
| `WS-REP-ORD-DATE` | `X(8)` | Operation date |
| FILLER | `X(1)` | Space |
| `WS-REP-ORD-TYPE` | `X(1)` | Operation type |
| FILLER | `X(1)` | Space |
| `WS-REP-AMOUNT` | `Z(6)9.99` | Formatted amount |
| FILLER | `X(1)` | Space |
| `WS-REP-OPR-ID` | `X(6)` | Operation ID |

---

## SYSIN Filter Parameters

Parameters are passed as inline JCL `DD *` records. Each line must contain `=`. Lines without `=` are silently skipped. Unknown keys are silently ignored.

| Key | Default | Description |
|---|---|---|
| `FROM-DATE` | `00000000` | Minimum operation date (inclusive), format `YYYYMMDD` |
| `TO-DATE` | `99999999` | Maximum operation date (inclusive), format `YYYYMMDD` |
| `MIN-AMOUNT` | `0` | Minimum operation amount (inclusive) |
| `OPR-TYPE` | `*` | Operation type filter: `D`, `C`, or `*` (all types) |

**Example SYSIN block in JCL:**
```
//SYSIN DD *
FROM-DATE=20260101
TO-DATE=20260131
MIN-AMOUNT=000100000
OPR-TYPE=D
/*
```

---

## Business Logic

The program processes records in two sequential phases.

### Phase 1 — Parse SYSIN Parameters

| Condition | Action |
|---|---|
| Line has no `=` | Skip line silently (`EXIT PARAGRAPH`) |
| `FROM-DATE=` | Set `WS-FROM-DATE` (if value not spaces) |
| `TO-DATE=` | Set `WS-TO-DATE` (if value not spaces) |
| `MIN-AMOUNT=` | Set `WS-MIN-AMOUNT-NUM` via `FUNCTION NUMVAL` |
| `OPR-TYPE=` | Set `WS-OPR-TYPE` (if value not spaces) |
| Unknown key | Continue silently |

### Phase 2 — Filtered Scan of KSDS

Each record is checked through four filters in sequence. The first failed filter skips the record immediately (`EXIT PARAGRAPH`).

| Filter | Condition | Action |
|---|---|---|
| 1 — Date from | `OPR-DATE < WS-FROM-DATE` | Skip record |
| 2 — Date to | `OPR-DATE > WS-TO-DATE` | Skip record |
| 3 — Min amount | `OPR-AMOUNT < WS-MIN-AMOUNT-NUM` | Skip record |
| 4 — Type | `WS-OPR-TYPE ≠ '*'` and `OPR-TYPE ≠ WS-OPR-TYPE` | Skip record |
| All passed | — | Write to `FILTERED.REPORT` |

---

## Program Flow

1. **OPEN** — `SYSIN-FILE` (INPUT), `OPR-LOG-FILE` (INPUT), `FILTERED-REPORT-FILE` (OUTPUT).
2. **Phase 1** — Read SYSIN line by line until EOF; call `PARSE-SYSIN-LINE` for each record.
3. **Phase 2** — Read `OPR-LOG-FILE` (KSDS) sequentially until EOF; call `CHECK-WITH-PARAMS` for each record.
4. **CLOSE** all files.
5. **STOP RUN**.

---

## Test Data

Input and output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`OPR.LOG.KSDS`](DATA/OPR.LOG.KSDS) | Operation log records (various dates, amounts, types) |
| [`FILTERED.REPORT`](DATA/FILTERED.REPORT) | Expected filtered report output |

---

## How to Run

1. **Define VSAM KSDS cluster** — run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Compile, load data, and run** — run [`COMPRUN.jcl`](JCL/COMPRUN.jcl) (loads KSDS data via IDCAMS REPRO, compiles COBOL, executes with SYSIN parameters)
3. **Review output** — see [`FILTERED.REPORT`](DATA/FILTERED.REPORT)

---

## Key COBOL Concepts Used

- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS SEQUENTIAL` — KSDS scanned sequentially from first to last record
- `SELECT SYSIN-FILE ASSIGN TO SYSIN` — reading JCL inline parameters as a flat file
- `INSPECT TALLYING ... FOR CHARACTERS BEFORE '='` — locating the `=` delimiter position in each SYSIN line
- `FUNCTION NUMVAL` — converting alphanumeric SYSIN value to numeric for amount comparison
- `EXIT PARAGRAPH` — early exit pattern for multi-filter evaluation without nested `IF`
- `88` level condition names — `EOF-SYSIN` and `EOF-OPR` for clean loop control
- `EVALUATE TRUE` — key-based dispatch when parsing SYSIN parameter names
- `Z(6)9.99` picture — suppressing leading zeros in formatted amount output
