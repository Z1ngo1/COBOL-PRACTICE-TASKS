# Task 09 — Client Duplicate Detection (VSAM KSDS + SORT + PS Report)

## Overview

Reads a VSAM KSDS client master file (`CLIENT.MASTER`), sorts all records by name and birth date using the internal COBOL `SORT` verb, then groups consecutive records with the same `NAME + BIRTH-DATE` key.
Any group with more than one record is written to a PS duplicate report. A summary is printed to SYSOUT with the total number of records, duplicate groups, and suspicious records found.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `CLIENT.MASTER.FILE` | VSAM KSDS | INPUT | Source client master file, key = `CLIENT-ID` |
| `SRTDD` | Sort work file | SD | WORK | Internal sort work area |
| `REPDD` | `DUPLICATE.REPORT` | PS | OUTPUT | Duplicate records report, LRECL=80, RECFM=F |

### VSAM Record Layout (`VSAMDD`) — LRECL=74

| Field | Picture | Offset | Description |
|---|---|---|---|
| `MAST-ID` | `X(6)` | 1 | **Primary key** — client ID |
| `MAST-NAME` | `X(30)` | 7 | Full name |
| `MAST-BIRTH` | `X(8)` | 37 | Birth date (`YYYYMMDD`) |
| `MAST-PASSPORT` | `X(10)` | 45 | Passport number |
| `MAST-CITY` | `X(20)` | 55 | City |

### Report Record Layout (`REPDD`) — LRECL=80, RECFM=F

| Field | Picture | Content |
|---|---|---|
| `CL-ID` | `X(6)` | Client ID |
| FILLER | `X(1)` | Space |
| `CL-NAME` | `X(30)` | Full name |
| FILLER | `X(1)` | Space |
| `CL-BIRTH` | `X(8)` | Birth date |
| FILLER | `X(1)` | Space |
| `CL-PASSPORT` | `X(10)` | Passport number |
| FILLER | `X(23)` | Spaces (padding to 80) |

---

## Business Logic

### Duplicate Detection Key

Two clients are considered potential duplicates if both conditions match:

| Field | Source |
|---|---|
| `MAST-NAME` | Full name (`X(30)`) |
| `MAST-BIRTH` | Birth date (`X(8)`) |

### Group Processing Rules

| Condition | Action |
|---|---|
| `GROUP-COUNT > 1` after key change | Write all buffered records to `REPDD`, increment `TOTAL-GROUPS` and `TOTAL-DUPS` |
| `GROUP-COUNT = 1` | Skip — no duplicate, nothing written |
| Buffer overflow (`GROUP-COUNT >= 50`) | Warning to SYSOUT, extra record dropped |

---

## Program Flow

1. **PERFORM OPEN-REPORT-FILE** — open `REPDD` as OUTPUT
2. **SORT** `CLIENT-SORT-WORK`:
   - Sort keys: `SRT-NAME ASC`, `SRT-BIRTH ASC`, `SRT-ID ASC`
   - Input: `USING CLIENT-MASTER-FILE` (reads `VSAMDD` automatically)
   - Output: `OUTPUT PROCEDURE IS PRCSS-SORT-REC THRU PROCESS-EXIT`
3. **PRCSS-SORT-REC** (OUTPUT PROCEDURE):
   - **RETURN** first record from sort work — save `WS-CUR-NAME`, `WS-CUR-BIRTH`, call `ADD-TO-GROUP-BUFFER`
   - **PERFORM UNTIL EOF:**
     - **RETURN** next sorted record
     - If `SRT-NAME = WS-CUR-NAME` AND `SRT-BIRTH = WS-CUR-BIRTH`:
       - **PERFORM ADD-TO-GROUP-BUFFER** — append to current group
     - Else (key change):
       - **PERFORM WRITE-DUPLICATE-GROUP** — flush previous group if `COUNT > 1`
       - Reset `WS-CUR-NAME`, `WS-CUR-BIRTH`, `WS-GROUP-COUNT = 0`
       - **PERFORM ADD-TO-GROUP-BUFFER** — start new group
   - After loop: **PERFORM WRITE-DUPLICATE-GROUP** — flush last group
4. Check `SORT-RETURN NOT = 0` — `DISPLAY` error and `STOP RUN`
5. **PERFORM CLOSE-REPORT-FILE**
6. **PERFORM DISPLAY-SUMMARY-REPORT** — print statistics to SYSOUT
7. `STOP RUN`

### ADD-TO-GROUP-BUFFER
- If `WS-GROUP-COUNT < 50`: increment counter, store `SRT-ID`, `SRT-NAME`, `SRT-BIRTH`, `SRT-PASSPORT` into `WS-GROUP-TABLE(WS-GROUP-COUNT)`
- Else: `DISPLAY 'WARNING: GROUP BUFFER OVERFLOW'`

### WRITE-DUPLICATE-GROUP
- If `WS-GROUP-COUNT > 1`: increment `TOTAL-GROUPS`, loop through buffer, write each record to `REPDD`, increment `TOTAL-DUPS` per record

---

## Test Data

Input data and expected output are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`DATA/CLIENT.MAST.VSAM`](DATA/CLIENT.MAST.VSAM) | 10 test client records loaded into VSAM |
| [`DATA/DUPLCT.REPORT`](DATA/DUPLCT.REPORT) | Expected duplicate report output |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
DUPLICATE REPORT SUMMARY
========================================
TOTAL RECORDS PROCESSED:     10
GROUPS WITH DUPLICATES:        3
SUSPICIOUS RECORDS FOUND:      8
========================================
```

### Expected Report (`REPDD`)

```
000101 IVANOV IVAN                    19991201 AB1234567
000103 IVANOV IVAN                    19991201 ZZ9999999
000109 IVANOV IVAN                    19991201 CD9876543
000102 POPOVA ANNA                    19870305 OP5555555
000106 POPOVA ANNA                    19870305 MN4444444
000110 POPOVA ANNA                    19870305 QR6666666
000105 SMIRNOVA MARIA                 20010415 GH1111111
000108 SMIRNOVA MARIA                 20010415 IJ2222222
```

Groups are written in sort order (`NAME ASC, BIRTH ASC, ID ASC`). Records with unique name+birth combinations (`PETROV`, `KUZNETSOV`) are not included in the report.

---

## How to Run

1. **Define and load the VSAM cluster** — use JCL in [`JCL/`](JCL/) to define `CLIENT.MASTER.FILE` and load test data from [`DATA/CLIENT.MAST.VSAM`](DATA/CLIENT.MAST.VSAM)
2. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMP`](../../JCLPROC/MYCOMP.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMP` is available in your system’s `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `SORT ... USING ... OUTPUT PROCEDURE IS` — internal COBOL sort with a custom output procedure; the `USING` clause reads `CLIENT-MASTER-FILE` automatically, no explicit `OPEN`/`READ`/`CLOSE` needed for the input file
- `SD` (Sort Description) — describes the sort work file record layout used as sort keys
- `RETURN ... AT END` — equivalent of `READ` inside an output procedure; fetches the next sorted record one at a time
- `OUTPUT PROCEDURE ... THRU` — defines a range of paragraphs that process sorted records; must end with `GO TO PROCESS-EXIT` to avoid fall-through
- `OCCURS 50 TIMES` — internal table used as a group buffer; stores up to 50 records per duplicate group before flushing to the report
- Control-break pattern — key-change detection (`IF NAME = CURRENT AND BIRTH = CURRENT`) with end-of-file flush of the last group; classic batch accumulation technique
- `SORT-RETURN` — system field set by COBOL after `SORT`; `0` = success, non-zero = failure
- `ACCESS MODE IS SEQUENTIAL` on KSDS — reads records in primary key order; combined with the sort, guarantees deterministic output order

---

## Notes

- The VSAM file is sorted by `CLIENT-ID` (primary key), but duplicates are detected on `NAME + BIRTH-DATE` — that is why an internal `SORT` is required before grouping
- The group buffer holds up to **50 records** per group; if a group exceeds this limit, extra records are dropped with a warning to SYSOUT but do not stop the job
- The last group is flushed **after** the `PERFORM UNTIL EOF` loop ends — without this final `PERFORM WRITE-DUPLICATE-GROUP`, the last group would never be written (classic end-of-file accumulation bug)
- Records with `GROUP-COUNT = 1` are silently skipped and never appear in the report — only confirmed duplicates (2+ records with the same key) are reported
- `SORT-RETURN` is checked after the `SORT` statement completes; a non-zero return code means the sort work file failed or ran out of space
- Tested on IBM z/OS with Enterprise COBOL
