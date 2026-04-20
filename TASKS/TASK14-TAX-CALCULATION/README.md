# Task 14 — Tax Calculation (Table Lookup / In-Memory Array)

## Overview

Reads a small tax-rate reference file [`TAX.RATES`](./DATA/TAX.RATES) into an in-memory array (`TAX-TABLE`), then processes an employee salary file [`EMP.SALARY`](./DATA/EMP.SALARY) and writes a payroll output [`PAYROLL.TXT`](./DATA/PAYROLL.TXT) with the calculated tax amount for each employee.
The core technique is the **Table Lookup** pattern: instead of reading two files simultaneously, the reference data is loaded into memory once and searched on every salary record — much simpler than a match-merge and appropriate when the lookup table is small (10–50 entries).

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `TAXDD` | [`TAX.RATES`](./DATA/TAX.RATES) | PS | INPUT | Tax rate table — region code + rate; loaded into memory at startup |
| `EMPDD` | [`EMP.SALARY`](./DATA/EMP.SALARY) | PS | INPUT | Employee salary records — ID, name, region code, salary |
| `OUTDD` | [`PAYROLL.TXT`](./DATA/PAYROLL.TXT) | PS | OUTPUT | Payroll results — one line per employee with tax amount |

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

## Business Logic: Two-Phase Processing

### Phase 1 — Load Tax Table (Initialization)

The program starts by loading the entire tax rate reference file into a Working-Storage table.

```cobol
OPEN TAX.RATES
PERFORM UNTIL EOF
  READ TAX.RATES
  ADD 1 TO TAX-RATES-LOADED
  MOVE TAX-REGION-CODE TO WS-REGION(IDX)
  MOVE RATE TO WS-RATE(IDX)
END-PERFORM
CLOSE TAX.RATES
```

After this phase, the `TAX-TABLE` lives in memory. `TAX-RATES-LOADED` holds the count of entries and is used as the upper bound for all subsequent searches. The table size is limited by `OCCURS 50 TIMES`.

### Phase 2 — Process Salary File

For each employee record, the program performs a linear search in the in-memory table.

```cobol
OPEN EMP.SALARY, PAYROLL.TXT
PERFORM UNTIL EOF
  READ EMP.SALARY
  PERFORM LOOKUP-TAX-RATE
  IF WS-FOUND = 'Y'
    COMPUTE OUT-TAX = EMP-SALARY * WS-RATE(IDX)
  ELSE
    PERFORM APPLY-DEFAULT-RATE
  END-IF
  WRITE PAYROLL-REC
END-PERFORM
CLOSE EMP.SALARY, PAYROLL.TXT
```

---

## Program Flow

1.  **PERFORM OPEN-TAX-FILE** — opens `TAXDD` (INPUT) for initialization.
2.  **PERFORM LOAD-TAX-TABLE** — reads `TAX.RATES` record-by-record into `WS-TAX-TABLE` until EOF or table capacity is reached.
3.  **PERFORM CLOSE-TAX-FILE** — closes `TAXDD` once loading is complete.
4.  **PERFORM OPEN-PAYROLL-FILES** — opens `EMPDD` (INPUT) and `OUTDD` (OUTPUT).
5.  **PERFORM PROCESS-SALARY-RECORDS** — main processing loop `UNTIL EOF` on `EMP.SALARY`.
    *   **READ EMP-SALARY-FILE**.
    *   **PERFORM LOOKUP-TAX-RATE** — searches `WS-TAX-TABLE` for a matching `EMP-REGION-CODE`.
    *   **IF FOUND** --> `COMPUTE OUT-TAX` using the specific rate from the table.
    *   **ELSE** --> `PERFORM APPLY-DEFAULT-RATE` (uses a hardcoded 20% rate).
    *   **WRITE PAYROLL-REC** — formats and writes the result line to `OUTDD`.
6.  **DISPLAY-SUMMARY** — prints final statistics to SYSOUT (rates loaded, employees processed, default rates applied).
7.  **PERFORM CLOSE-PAYROLL-FILES** — closes `EMPDD` and `OUTDD`.
8.  **STOP RUN**.

---

## Test Data

All input and expected output files are in the [`DATA/`](./DATA) folder.

| File | Description |
|---|---|
| [`TAX.RATES`](./DATA/TAX.RATES) | 7 region tax rate entries |
| [`EMP.SALARY`](./DATA/EMP.SALARY) | 10 employee salary records |
| [`PAYROLL.TXT`](./DATA/PAYROLL.TXT) | Expected payroll output with tax amounts |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](./OUTPUT/SYSOUT.txt).

```text
========================================
 TAX CALCULATION SUMMARY
========================================
 TAX RATES LOADED:              7
 EMPLOYEES PROCESSED:          10
 PAYROLL RECORDS WRITTEN:      10
 RATE FOUND:                    8
 DEFAULT RATE USED:             2
========================================
```

---

## How to Run

1.  Upload [`TAX.RATES`](./DATA/TAX.RATES) and [`EMP.SALARY`](./DATA/EMP.SALARY) to your mainframe datasets.
2.  Submit [`COMPRUN.jcl`](./JCL/COMPRUN.jcl).
3.  Compare output files and sysout - see [`PAYROLL.TXT`](./DATA/PAYROLL.TXT) and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt)

> **PROC reference:** [`COMPRUN.jcl`](./JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure.

---

## Key COBOL Concepts Used

*   **`OCCURS` + `INDEXED BY`** — defining a Working-Storage table to hold reference data.
*   **Linear Search via `PERFORM VARYING`** — searching the table from index 1 to the current load count.
*   **Two-phase processing** — strictly separating the initialization (loading) phase from the main processing phase.
*   **Fallback logic** — providing a default value when a lookup fails to prevent program termination or incorrect zero calculations.

---

## Notes

*   **Table Capacity:** The table size is bounded by `OCCURS 50 TIMES`. If the input file has more records, the excess is ignored with a warning.
*   **Memory Efficiency:** This pattern is ideal for small lookup tables. For tables with thousands of entries, a sorted table with `SEARCH ALL` (binary search) or a VSAM KSDS would be more appropriate.
*   **Data Integrity:** The program assumes region codes are unique in the reference file. If duplicates exist, only the first match is used.
*   **Decimal Handling:** Implicit decimal positions (`V999`, `V99`) are handled via `COMPUTE` to ensure mathematical accuracy before moving to edited output fields.
