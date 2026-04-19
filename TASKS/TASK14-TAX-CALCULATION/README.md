# Task 14 — Tax Calculation (Table Lookup / In-Memory Array)

## Overview

Reads a small tax-rate reference file (`TAX.RATES`) into an in-memory array (`TAX-TABLE`), then processes an employee salary file (`EMP.SALARY`) and writes a payroll output (`PAYROLL.TXT`) with the calculated tax amount for each employee.
The core technique is the **Table Lookup** pattern: instead of reading two files simultaneously, the reference data is loaded into memory once and searched on every salary record — much simpler than a match-merge and appropriate when the lookup table is small (10–50 entries).

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `TAXDD` | `TAX.RATES` | PS | INPUT | Tax rate table — region code + rate; loaded into memory at startup |
| `EMPDD` | `EMP.SALARY` | PS | INPUT | Employee salary records — ID, name, region code, salary |
| `OUTDD` | `PAYROLL.TXT` | PS | OUTPUT | Payroll results — one line per employee with tax amount |

### Input Record Layout — `TAX.RATES` (`TAXDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TAX-REGION-CODE` | `X(2)` | 1 | Region code — lookup key |
| `RATE` | `V999` | 3 | Tax rate — implied 3 decimal places (e.g. `200` = 0.200 = 20%) |
| FILLER | `X(75)` | 4 | Padding to 80 bytes |

### Input Record Layout — `EMP.SALARY` (`EMPDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `EMP-ID` | `X(5)` | 1 | Employee ID |
| `EMP-NAME` | `X(20)` | 6 | Employee name |
| `EMP-REGION-CODE` | `X(2)` | 26 | Region code — matched against `TAX-TABLE` |
| `EMP-SALARY` | `9(5)V99` | 28 | Employee salary — implied 2 decimal places |
| FILLER | `X(46)` | 35 | Padding to 80 bytes |

### Output Record Layout — `PAYROLL.TXT` (`OUTDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `OUT-ID` | `X(5)` | 1 | Employee ID |
| `OUT-REGION` | `X(2)` | 6 | Region code used for lookup |
| `OUT-TAX` | `9(5)V99` | 8 | Calculated tax amount |
| FILLER | `X(66)` | 15 | Padding to 80 bytes |

---

## Two-Phase Processing

### Phase 1 — Load Tax Table (Initialization)

```
OPEN TAX.RATES
PERFORM UNTIL EOF
    READ TAX.RATES
    ADD 1 TO TAX-RATES-LOADED
    MOVE TAX-REGION-CODE TO WS-REGION(IDX)
    MOVE RATE            TO WS-RATE(IDX)
END-PERFORM
CLOSE TAX.RATES
```

After this phase the entire rate table lives in `TAX-TABLE` in memory. `TAX-RATES-LOADED` holds the number of loaded entries and is used as the upper bound for all subsequent searches. Table size is bounded by `OCCURS 50 TIMES` — if `TAX.RATES` has more than 50 records the program displays a warning and ignores the excess.

### Phase 2 — Process Salary File

```
OPEN EMP.SALARY, PAYROLL.TXT
PERFORM UNTIL EOF
    READ EMP.SALARY
    ADD 1 TO EMPLOYEES-PROCESSED
    PERFORM LOOKUP-TAX-RATE
    IF WS-FOUND = 'Y'
        COMPUTE OUT-TAX = EMP-SALARY * WS-RATE(IDX)
    ELSE
        PERFORM APPLY-DEFAULT-RATE
    WRITE PAYROLL-REC
END-PERFORM
CLOSE EMP.SALARY, PAYROLL.TXT
```

---

## Table Lookup Logic

The lookup searches `TAX-TABLE` from index 1 to `TAX-RATES-LOADED` comparing `EMP-REGION-CODE` against each `WS-REGION` entry.

### Using `PERFORM VARYING`

```cobol
MOVE 'N' TO WS-FOUND
PERFORM VARYING IDX FROM 1 BY 1
        UNTIL IDX > TAX-RATES-LOADED OR WS-FOUND = 'Y'
    IF EMP-REGION-CODE = WS-REGION(IDX)
        MOVE 'Y' TO WS-FOUND
        COMPUTE OUT-TAX = EMP-SALARY * WS-RATE(IDX)
        MOVE EMP-ID          TO OUT-ID
        MOVE WS-REGION(IDX)  TO OUT-REGION
        ADD 1 TO RATE-FOUND-COUNT
    END-IF
END-PERFORM
```

### Using `SEARCH` (alternative)

```cobol
SEARCH TAX-ENTRY
    AT END
        MOVE WS-FOUND TO WS-FOUND  *> falls through to APPLY-DEFAULT-RATE
    WHEN WS-REGION(IDX) = EMP-REGION-CODE
        COMPUTE OUT-TAX = EMP-SALARY * WS-RATE(IDX)
END-SEARCH
```

> `SEARCH` requires the table index to be defined with `INDEXED BY` and reset to 1 before each call. `PERFORM VARYING` is simpler when the table is small and not sorted.

### Default Rate (Region Not Found)

If no matching `EMP-REGION-CODE` is found in `TAX-TABLE`, the program applies `DEF-TAX-RATE = 0.200` (20%) via `APPLY-DEFAULT-RATE`. The output record is written normally — `OUT-REGION` will show the unmatched code so it can be spotted during review.

---

## Tax Calculation

```
OUT-TAX = EMP-SALARY x WS-RATE(IDX)   (or DEF-TAX-RATE if region not found)
```

`COMPUTE` is used to avoid truncation on the implied decimal positions.

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/TAX.RATES`](DATA/TAX.RATES) | 7 region tax rate entries |
| [`DATA/EMP.SALARY`](DATA/EMP.SALARY) | 10 employee salary records |
| [`DATA/PAYROLL.TXT`](DATA/PAYROLL.TXT) | Expected payroll output with tax amounts |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
TAX CALCULATION SUMMARY
========================================
TAX RATES LOADED:          7
EMPLOYEES PROCESSED:      10
PAYROLL RECORDS WRITTEN:  10
RATE FOUND:                8
DEFAULT RATE USED:         2
========================================
```

---

## How to Run

1. Upload [`DATA/TAX.RATES`](DATA/TAX.RATES) and [`DATA/EMP.SALARY`](DATA/EMP.SALARY) to your mainframe datasets manually through option '3.4 and edit your dataset' or with pre-prepared data
2. Submit [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) with pre-prepared data

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMPGO` is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- **`OCCURS` + `INDEXED BY`** — defines `TAX-TABLE` as a fixed-size array (`OCCURS 50 TIMES`) of region/rate pairs loaded entirely into working-storage before any salary record is processed
- **`PERFORM VARYING`** — linear search through `TAX-TABLE` from index 1 to `TAX-RATES-LOADED`; stops at the first matching entry or exhausts the table for the default rate fallback
- **Two-phase design** — strict initialization phase (load `TAX-TABLE`, close `TAX.RATES`) before opening `EMP.SALARY`; `TAX.RATES` is read exactly once regardless of how many salary records exist
- **`DEF-TAX-RATE` fallback** — when no entry in `TAX-TABLE` matches `EMP-REGION-CODE` the program applies `DEF-TAX-RATE` (0.200) and continues normally without stopping or logging an error

---

## Notes

- Tax table loading does not check for duplicate region codes — if `TAX.RATES` contains duplicate entries for the same region, only the **first** occurrence will be matched during lookup; ensure the tax rates file has unique region codes per entry
- The table size is bounded by the `OCCURS` limit in working-storage (`OCCURS 50 TIMES`) — if `TAX.RATES` has more than 50 records the program displays a warning and skips the excess; increase the `OCCURS` value if a larger table is needed
- `TAX.RATES` is closed after Phase 1 and never reopened — all lookups in Phase 2 are purely in-memory
- Tested on IBM z/OS with Enterprise COBOL
