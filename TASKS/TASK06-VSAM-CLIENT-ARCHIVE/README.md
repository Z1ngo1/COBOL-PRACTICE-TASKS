# Task 06 — Client Database Cleanup and Archiving (VSAM Dynamic + Delete)

## Overview

Reads all records from a VSAM KSDS client master file [`CLIENT.MASTER`](DATA/CLIENT.MASTER.BEFORE) sequentially using dynamic access mode. Inactive clients whose last activity date is before or equal to a cutoff date are deleted from the VSAM file and written to a PS archive file. A summary report is printed to SPOOL at the end of the job.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | [`PARAM.FILE`](DATA/PARAM.FILE) | PS | INPUT | Cutoff date parameter (1 record) |
| `CLTDD` | [`CLIENT.MASTER`](DATA/CLIENT.MASTER.BEFORE) | KSDS | I-O | Client master file (read + delete) |
| `OUTDD` | [`ARCHIVE.OLD`](DATA/ARCHIVE.OLD) | PS | OUTPUT | Archive file for deleted clients |

### Cutoff Parameter Record Layout (`INDD`) — LRECL=80, RECFM=F

| Field | PIC | Position | Description |
|---|---|---|---|
| `PARAM-DATE` | `X(8)` | 1–8 | Cutoff date in `YYYYMMDD` format |
| FILLER | `X(72)` | 9–80 | Unused |

### Client Master Record Layout (`CLTDD`) — KSDS, LRECL=34

| Field | PIC | Position | Description |
|---|---|---|---|
| `CLIENT-ID` | `X(6)` | 1–6 | **Primary key** |
| `CLIENT-NAME` | `X(20)` | 7–26 | Client full name |
| `CLIENT-LAST-DATE` | `9(8)` | 27–34 | Last activity date `YYYYMMDD` (numeric) |

### Archive Record Layout (`OUTDD`) — PS, LRECL=34, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `ARCH-ID` | `X(6)` | 1–6 | Client ID |
| `ARCH-NAME` | `X(20)` | 7–26 | Client name |
| `ARCH-DATE` | `9(8)` | 27–34 | Activity date |
| FILLER | `X(46)` | 35–80 | Unused |

---

## Business Logic: Cleanup and Archiving Logic

The program implements a conditional deletion logic where records are compared against a user-provided cutoff date. Valid records (active) remain in the master file, while obsolete records (inactive) are physically removed and preserved in an archive.

| Condition | Action | Reason |
|---|---|---|
| `CLIENT-LAST-DATE <= PARAM-DATE` | `WRITE` to Archive + `DELETE` from VSAM | Record is obsolete (inactive) |
| `CLIENT-LAST-DATE > PARAM-DATE` | Skip `DELETE` | Record is still active |

---

## Program Flow

1. **OPEN** — `PARAM.FILE` (INPUT), `CLIENT.MASTER` (I-O), and `ARCHIVE.OLD` (OUTPUT).
2. **READ** cutoff date from `PARAM.FILE` into `WS-CUTOFF-DATE`.
3. **START** VSAM master at the beginning of the file (Key >= Low-Values); check FILE STATUS.
4. **READ NEXT** record from VSAM:
   - If EOF, go to step 7.
   - If success, continue to step 5.
5. **Compare dates:**
   - If `CLIENT-LAST-DATE <= WS-CUTOFF-DATE`:
     - Move record to archive buffer.
     - **WRITE** to `ARCHIVE.OLD`.
     - **DELETE** record from `CLIENT.MASTER` (KSDS).
     - Increment `REC-DELETE`.
   - If `CLIENT-LAST-DATE > WS-CUTOFF-DATE`:
     - Skip deletion.
     - Increment `REC-KEPT`.
6. Go to step 4 (Read Next).
7. **DISPLAY SUMMARY** — print totals for records read, deleted, and kept.
8. **CLOSE** all files → **STOP RUN**.

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`PARAM.FILE`](DATA/PARAM.FILE) | 1 record: `20231231` (Cutoff date) |
| [`CLIENT.MASTER.BEFORE`](DATA/CLIENT.MASTER.BEFORE) | 10 client records with various dates |
| [`CLIENT.MASTER.AFTER`](DATA/CLIENT.MASTER.AFTER) | VSAM state after cleanup (only active clients) |
| [`ARCHIVE.OLD`](DATA/ARCHIVE.OLD) | Expected archive file (deleted clients) |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
DATE IS: 20231231                       
ARCH AND DELETE: 000100                 
ARCH AND DELETE: 000105                 
ARCH AND DELETE: 000110                 
ARCH AND DELETE: 000130                 
ARCH AND DELETE: 000135                 
----------------------------------------
STATISTIC REPORT:                       
RECORDS READ:      10                   
RECORDS DELETE:     5                   
RECORDS KEPT:       5                   
----------------------------------------
```

---

## How to Run

1. **Define VSAM cluster** — run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load [`CLIENT.MASTER.BEFORE`](DATA/CLIENT.MASTER.BEFORE) into the KSDS cluster either via REPRO (see DATAVSAM.jcl) or manually through File Manager in ISPF
3. **Compile and run** — run [`COMPRUN.jcl`](JCL/COMPRUN.jcl)
4. **Compare output files and sysout** - see [`CLIENT.MASTER.AFTER`](DATA/CLIENT.MASTER.AFTER), [`ARCHIVE.OLD`](DATA/ARCHIVE.OLD) AND [`SYSOUT.txt`](OUTPUT/SYSOUT.txt)

> **PROC reference:** [`COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ACCESS MODE IS DYNAMIC` — allows combining `START` (random positioning) and `READ NEXT` (sequential browsing)
- `DELETE` — removes the record most recently read by a successful sequential READ
- `START` — used here to position the cursor at the first record of the KSDS cluster
- Date comparison — numeric comparison of `YYYYMMDD` format (higher values = newer dates)

---

## Notes

- The program uses `READ NEXT` instead of `READ` because `ACCESS MODE IS DYNAMIC` is specified
- `DELETE` statement in COBOL does not require a key if the file was read sequentially; it deletes the "current" record
- If the VSAM file is empty, `START` will return FILE STATUS `23` (record not found) or `10` (EOF) depending on context
- Tested on IBM z/OS with Enterprise COBOL
