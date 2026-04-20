# Task 15 — Commission Tiers (Tiered Table Lookup / In-Memory Array)

## Overview

Reads a commission tiers reference file [`COMM.TIERS`](./DATA/COMM.TIERS) into an in-memory array (`TIER-TABLE`), then processes an employee salary file [`SALES.WEEKLY`](./DATA/SALES.WEEKLY) and writes a commission output [`PAYOUT.RPT`](./DATA/PAYOUT.RPT) with the calculated commission for each employee.
The core technique is a **Tiered Table Lookup**: instead of a simple key match, the program finds the first tier where `WS-LIMIT >= SAL-AMT` — the salary bracket determines the commission rate.
The tier table is loaded once into memory before any salary record is processed.

---

## Critical Prerequisite: `COMM.TIERS` Must Be Sorted by `COMM-LIMIT` Ascending

> **`COMM.TIERS` must be sorted by `COMM-LIMIT` in ascending order before this program runs.**

The lookup algorithm selects the **first tier where `WS-LIMIT >= SAL-AMT`**. If the tiers are unsorted, a lower limit may match a salary that should fall into a higher tier — producing an incorrect commission rate **without any error message or ABEND**. Use a `SORT` step in the JCL before the program step if your input is not already sorted.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `COMMDD` | `COMM.TIERS` | PS | INPUT | Commission tiers table — salary limit + commission rate; loaded into memory at startup |
| `SALDD` | `SALES.WEEKLY` | PS | INPUT | Employee salary records — ID and weekly sales amount |
| `OUTDD` | `PAYOUT.RPT` | PS | OUTPUT | Commission results — one line per employee with salary, rate, and commission amount |

### Input Record Layout — `COMM.TIERS` (`COMMDD`), LRECL=9, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `COMM-LIMIT` | `9(6)` | 1 | Salary upper bound for this tier |
| `COMM-PCT` | `V999` | 7 | Commission rate — implied 3 decimal places (e.g. `020` = 0.020 = 2%) |

### Input Record Layout — `SALES.WEEKLY` (`SALDD`), LRECL=13, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `SAL-ID` | `9(5)` | 1 | Employee ID |
| `SAL-AMT` | `9(6)V99` | 6 | Weekly sales amount — implied 2 decimal places |

### Output Record Layout — `PAYOUT.RPT` (`OUTDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `OUT-ID` | `9(5)` | 1 | Employee ID |
| FILLER | `X(1)` | 6 | Separator |
| `OUT-SAL-AMT` | `9(6)V99` | 7 | Weekly sales amount |
| FILLER | `X(1)` | 15 | Separator |
| `OUT-PCT` | `V999` | 16 | Applied commission rate |
| FILLER | `X(1)` | 17 | Separator |
| `OUT-RES` | `9(6)V99` | 18 | Calculated commission amount |
| FILLER | `X(53)` | 26 | Padding to 80 bytes |

---

## Business Logic: Two-Phase Processing

### Phase 1 — Load Commission Table (Initialization)

The program loads the entire tiers file into a Working-Storage table.

```cobol
OPEN COMM.TIERS
PERFORM UNTIL EOF
  READ COMM.TIERS
  ADD 1 TO TIERS-LOADED
  MOVE COMM-LIMIT TO WS-LIMIT(IDX)
  MOVE COMM-PCT TO WS-PCT(IDX)
END-PERFORM
CLOSE COMM.TIERS
```

After this phase, the `TIER-TABLE` lives in memory. `TIERS-LOADED` holds the entry count. The table is bounded by `OCCURS 20 TIMES`.

### Phase 2 — Process Salary File (Tiered Lookup)

For each salary record, the program finds the correct bracket.

```cobol
OPEN SALES.WEEKLY, PAYOUT.RPT
PERFORM UNTIL EOF
  READ SALES.WEEKLY
  PERFORM CALCULATE-COMMISSION
END-PERFORM
CLOSE SALES.WEEKLY, PAYOUT.RPT
```

The lookup logic within `CALCULATE-COMMISSION`:
```cobol
PERFORM VARYING IDX FROM 1 BY 1 
  UNTIL IDX > TIERS-LOADED OR WS-FOUND = 'Y'
  IF WS-LIMIT(IDX) >= SAL-AMT
    MOVE 'Y' TO WS-FOUND
    COMPUTE OUT-RES = SAL-AMT * WS-PCT(IDX)
    ...
  END-IF
END-PERFORM
```

---

## Program Flow

1.  **PERFORM OPEN-COMM-FILE** — opens `COMMDD` (INPUT) for initialization.
2.  **PERFORM LOAD-COMM-TABLE** — reads `COMM.TIERS` into `WS-TIER-TABLE` until EOF. Increments `TIERS-LOADED`.
3.  **PERFORM CLOSE-COMM-FILE** — closes `COMMDD`.
4.  **PERFORM OPEN-SALES-FILES** — opens `SALDD` (INPUT) and `OUTDD` (OUTPUT).
5.  **PERFORM PROCESS-SALES-RECORDS** — main loop `UNTIL EOF` on `SALES.WEEKLY`.
    *   **READ SALES-FILE**.
    *   **PERFORM LOOKUP-TIER** — linear search in `WS-TIER-TABLE` using `WS-LIMIT(IDX) >= SAL-AMT`.
    *   **IF FOUND** --> `COMPUTE OUT-RES`, format output line, and **WRITE COMMISSION-REC**.
    *   **IF NOT FOUND** --> Increment `NO-TIER-MATCH` (record skipped).
6.  **DISPLAY-SUMMARY** — prints final statistics to SYSOUT (tiers loaded, employees processed, matches vs. no-matches).
7.  **PERFORM CLOSE-SALES-FILES** — closes `SALDD` and `OUTDD`.
8.  **STOP RUN**.

---

## Test Data

All input and expected output files are in the [`DATA/`](./DATA) folder.

| File | Description |
|---|---|
| [`COMM.TIERS`](./DATA/COMM.TIERS) | 5 commission tier entries |
| [`SALES.WEEKLY`](./DATA/SALES.WEEKLY) | 12 employee salary records |
| [`PAYOUT.RPT`](./DATA/PAYOUT.RPT) | Expected commission output |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](./OUTPUT/SYSOUT.txt).

```text
========================================
 COMMISSION CALCULATION SUMMARY
========================================
 COMMISSION TIERS LOADED:       5
 EMPLOYEES PROCESSED:          12
 RECORDS WRITTEN:              12
 TIER MATCHED:                 12
 NO TIER MATCH:                 0
========================================
```

---

## How to Run

1.  Upload [`DATA/COMM.TIERS`](./DATA/COMM.TIERS) and [`DATA/SALES.WEEKLY`](./DATA/SALES.WEEKLY) to your mainframe datasets.
2.  Submit [`JCL/COMPRUN.jcl`](./JCL/COMPRUN.jcl).

---

## Key COBOL Concepts Used

*   **`OCCURS` + `INDEXED BY`** — defining a Working-Storage table for tiered data.
*   **Tiered (Bracket) Lookup** — using `>=` comparison in a linear search to find the correct range.
*   **Two-phase processing** — loading reference data into memory once to avoid repeated file I/O.
*   **Linear Search via `PERFORM VARYING`** — iterating through the table until the first condition match.

---

## Notes

*   **Sort Order Importance:** The tiers **must** be sorted ascending by limit. If they are out of order, a salary of 5000 might match a "10000" limit tier before it reaches a "5000" limit tier, leading to wrong calculations.
*   **Catch-all Tier:** It is a best practice to have a final tier with a very high limit (e.g., 999999) to ensure all possible salaries are covered.
*   **Memory Efficiency:** Like TASK14, this is highly efficient for small tables (up to 20-50 entries). For significantly larger tables, a binary search or VSAM would be preferred.
*   **Precision:** `COMPUTE` ensures that the implied decimal positions in the sales amount and commission rate are handled correctly during multiplication.
