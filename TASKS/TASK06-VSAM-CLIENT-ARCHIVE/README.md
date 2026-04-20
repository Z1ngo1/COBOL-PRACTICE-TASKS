# Task 06 — Client Database Cleanup and Archiving (VSAM Dynamic + Delete)

## Overview

Reads all records from a VSAM KSDS client master file (`CLIENT.MASTER`) sequentially using dynamic access mode.
Inactive clients whose last activity date is before or equal to a cutoff date are deleted from the VSAM file and written to a PS archive file.
A summary report is printed to SPOOL at the end of the job.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INDD` | `PARAM.FILE` | PS | INPUT | Cutoff date parameter (1 record) |
| `CLTDD` | `CLIENT.MASTER` | KSDS | I-O | Client master file (read + delete) |
| `OUTDD` | `ARCHIVE.OLD` | PS | OUTPUT | Archive file for deleted clients |

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

### Archive Record Layout (`OUTDD`) — LRECL=80, RECFM=F

| Field | PIC | Position | Description |
|---|---|---|---|
| `ARCH-ID` | `X(6)` | 1–6 | Client ID (copied from `CLIENT-ID`) |
| `ARCH-NAME` | `X(20)` | 7–26 | Client name (copied from `CLIENT-NAME`) |
| `ARCH-DATE` | `9(8)` | 27–34 | Last activity date (copied from `CLIENT-LAST-DATE`) |
| FILLER | `X(46)` | 35–80 | Unused |

> Archive record is written via `WRITE ARCH-REC FROM CLIENT-REC` — direct copy of the VSAM record.

---

## Business Logic

| Condition | Action |
|---|---|
| `CLIENT-LAST-DATE <= WS-CUTOFF-DATE` | WRITE record to archive PS file → DELETE from VSAM → increment `REC-DELETE` |
| `CLIENT-LAST-DATE > WS-CUTOFF-DATE` | Skip — record stays in VSAM → increment `REC-KEPT` |

> Comparison is numeric (`9(8)`) — `YYYYMMDD` numeric ordering equals chronological ordering.

## Program Flow

1. **OPEN** — VSAM master (`CLTDD`) as I-O, parameter file (`INDD`) as INPUT, archive file (`OUTDD`) as OUTPUT
2. **READ** cutoff date from `INDD` into `WS-CUTOFF-DATE` — close `INDD` after read
3. **START** — position VSAM cursor at the very first record:
   ```
   MOVE LOW-VALUES TO CLIENT-ID
   START CLIENT-FILE KEY IS NOT LESS THAN CLIENT-ID
   ```
4. **PERFORM UNTIL** EOF (`AT END` on READ NEXT):
   - **READ CLIENT-FILE NEXT RECORD** — read next record sequentially
   - Check FILE STATUS: `'00'` → continue; `AT END` → exit loop; other → `STOP RUN`
   - Increment `REC-READ`
   - **PERFORM CHECK-CLIENT-DATE:**
     - **IF** `CLIENT-LAST-DATE <= WS-CUTOFF-DATE` → **PERFORM ARCHIVE-AND-DELETE-RECORD:**
       - **WRITE** `ARCH-REC FROM CLIENT-REC` to `OUTDD`
       - **DELETE CLIENT-FILE** — deletes the record just read
       - Increment `REC-DELETE`
     - **ELSE** → increment `REC-KEPT`
5. **CLOSE** all files
6. **DISPLAY** summary to SPOOL:
   - `RECORDS READ`
   - `RECORDS DELETE`
   - `RECORDS KEPT`

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`PARAM.FILE`](DATA/PARAM.FILE) | Cutoff date — format: `YYYYMMDD` + 72 spaces, LRECL=80 |
| [`CLIENT.MASTER.BEFORE`](DATA/CLIENT.MASTER.BEFORE) | Initial state of VSAM master — format: `ID(6) + NAME(20) + DATE(8)` |
| [`CLIENT.MASTER.AFTER`](DATA/CLIENT.MASTER.AFTER) | Expected VSAM state after cleanup — only clients with date > cutoff remain |
| [`ARCHIVE.OLD`](DATA/ARCHIVE.OLD) | Expected archive file — all deleted client records |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

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

1. **Define VSAM cluster** — run [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load [`CLIENT.MASTER.BEFORE`](DATA/CLIENT.MASTER.BEFORE) into the KSDS cluster via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF 
3. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS DYNAMIC` — enables both sequential (`READ NEXT`) and keyed access in the same program
- `MOVE LOW-VALUES TO CLIENT-ID` + `START ... KEY IS NOT LESS THAN` — positions cursor at the very first record in the KSDS
- `READ CLIENT-FILE NEXT RECORD` — reads next record sequentially in key order; without `NEXT` in dynamic mode COBOL attempts a keyed read
- `DELETE CLIENT-FILE` — removes the record that was most recently read via `READ NEXT`; no key needed
- `WRITE ARCH-REC FROM CLIENT-REC` — copies entire VSAM record directly into archive PS file
- `88 EOF` condition name — clean loop termination on `AT END`
- FILE STATUS checks on every I/O operation with explicit `STOP RUN` on unexpected codes

---

## Notes

- VSAM file is opened in `I-O` mode for the entire job — required for both `READ NEXT` and `DELETE`
- `DELETE` after `READ NEXT` in dynamic mode is valid — COBOL deletes the last-read record automatically without needing to specify the key
- Do **not** issue another `READ NEXT` before `DELETE` — the cursor must still point to the target record
- After `DELETE`, the next `READ NEXT` automatically moves to the next remaining record — no `START` repositioning needed
- Date field is `PIC 9(8)` (numeric) — comparison `<=` works correctly for `YYYYMMDD` format
- Tested on IBM z/OS with Enterprise COBOL

> **Warning:** Archive and delete are not atomic. If the job abends between `WRITE` to `ARCH-FILE` and `DELETE` from VSAM, the client record will be archived but NOT deleted. Manual cleanup may be required on restart.

> **Note:** If `CLIENT-MASTER` is empty (STATUS `'23'` on `START`), the program exits cleanly with zero records processed.
