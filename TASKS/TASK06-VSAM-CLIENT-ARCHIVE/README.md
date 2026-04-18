# Task 06 — Client Database Cleanup and Archiving (VSAM Dynamic + Delete)

## Overview

Reads all records from a VSAM KSDS client master file (`CLIENT.MASTER`) sequentially using dynamic access mode.
Inactive clients whose last activity date is before a cutoff date are deleted from the VSAM file and written to a PS archive file on tape.
A summary report is printed to SPOOL at the end of the job.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `PARMDD` | `CUTOFF.PARM` | PS | INPUT | Cutoff date parameter (1 record) |
| `CLIENTDD` | `CLIENT.MASTER` | KSDS | I-O | Client master file (read + delete) |
| `ARCHDD` | `CLIENT.ARCHIVE` | PS | OUTPUT | Archive file for deleted clients |

### Cutoff Parameter Record Layout (`PARMDD`) — LRECL=8, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `WS-CUTOFF-DATE` | `X(8)` | 1–8 | Cutoff date in `YYYYMMDD` format |

### Client Master Record Layout (`CLIENTDD`) — LRECL=60, RECFM=FB

| Field | PIC | Position | Description |
|---|---|---|---|
| `CLIENT-ID` | `X(6)` | 1–6 | **Primary key** |
| `CLIENT-NAME` | `X(30)` | 7–36 | Client full name |
| `CLIENT-LAST-DATE` | `X(8)` | 37–44 | Last activity date `YYYYMMDD` |
| `CLIENT-STATUS` | `X(1)` | 45 | `A` = Active, `I` = Inactive |
| FILLER | `X(15)` | 46–60 | Unused |

### Archive Record Layout (`ARCHDD`) — LRECL=60, RECFM=FB

| Field | PIC | Content |
|---|---|---|
| Same layout as `CLIENT.MASTER` | — | Exact copy of deleted client record |

---

## VSAM KSDS Definition

Кластер определяется так (`DEFKSDS.jcl`):

```
DEFINE CLUSTER (NAME(Z73460.TASK6.CLIENT.MASTER.VSAM)
    RECORDSIZE(60,60)
    TRACKS(15)
    KEYS(6 0)
    CISZ(4096)
    FREESPACE(10,20)
    INDEXED)
```

Run [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to create the cluster.

---

## Business Logic

| Condition | Action |
|---|---|
| `CLIENT-LAST-DATE < WS-CUTOFF-DATE` | WRITE record to archive PS file → DELETE from VSAM → increment deleted counter |
| `CLIENT-LAST-DATE >= WS-CUTOFF-DATE` | Skip — record stays in VSAM unchanged |

> Comparison is string-based on `YYYYMMDD` format — lexicographic order equals chronological order for this format.

## Program Flow

1. **OPEN** — parameter file (`PARMDD`) as INPUT, VSAM master (`CLIENTDD`) as I-O, archive file (`ARCHDD`) as OUTPUT
2. **READ** cutoff date from `PARMDD` into `WS-CUTOFF-DATE` — close `PARMDD`
3. **START** — position VSAM cursor at the very first record:
   ```
   START CLIENTDD KEY IS >= LOW-VALUES
   ```
4. **PERFORM UNTIL** EOF (`FILE STATUS = '10'`):
   - **READ CLIENTDD NEXT** — read next record sequentially
   - Check FILE STATUS: `'00'` → continue; `'10'` → exit loop; other → `STOP RUN`
   - Increment `WS-TOTAL-COUNT`
   - **IF** `CLIENT-LAST-DATE < WS-CUTOFF-DATE`:
     - **WRITE** current record to `ARCHDD`
     - **DELETE CLIENTDD** — deletes the record that was just read
     - Increment `WS-DELETE-COUNT`
   - **ELSE** — do nothing, move to next record
5. **DISPLAY** summary to SPOOL:
   - Total records scanned
   - Total records deleted and archived
6. **CLOSE** all files → `STOP RUN`

---

## Test Data

Input and expected output files are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`CUTOFF.PARM`](DATA/CUTOFF.PARM) | Cutoff date — format: `YYYYMMDD` (e.g. `20230101`) |
| [`CLIENT.MASTER.BEFORE`](DATA/CLIENT.MASTER.BEFORE) | Initial state of VSAM master — format: `ID(6) + NAME(30) + DATE(8) + STATUS(1) + FILLER(15)` |
| [`CLIENT.MASTER.AFTER`](DATA/CLIENT.MASTER.AFTER) | Expected VSAM state after cleanup — only active clients remain |
| [`CLIENT.ARCHIVE.OUTPUT`](DATA/CLIENT.ARCHIVE.OUTPUT) | Expected archive file — all deleted inactive client records |

---

## How to Run

1. **Define VSAM cluster** — run [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load `CLIENT.MASTER.BEFORE` into the KSDS cluster via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF (option 3.4 → open VSAM dataset → edit records directly)
3. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMPGO` is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ORGANIZATION IS INDEXED` + `ACCESS MODE IS DYNAMIC` — enables both sequential (`READ NEXT`) and keyed access in the same program
- `START ... KEY IS >= LOW-VALUES` — positions the internal cursor at the very first record in the KSDS
- `READ ... NEXT` — reads the next record sequentially in key order; without `NEXT` in dynamic mode COBOL attempts a keyed read
- `DELETE` — removes the record that was most recently read; no key argument needed after a sequential `READ NEXT`
- `88` level condition names — `WS-EOF` for clean loop termination
- FILE STATUS checks on every I/O operation with explicit `STOP RUN` on unexpected codes

---

## Notes

- VSAM file is opened in `I-O` mode for the entire job — this allows both `READ NEXT` and `DELETE` in one open
- `DELETE` after `READ NEXT` in dynamic mode is valid — COBOL deletes the last-read record automatically
- Do **not** issue another `READ NEXT` before `DELETE` — the cursor must still point to the target record
- Date comparison works correctly only if dates are stored in `YYYYMMDD` format — lexicographic `<` equals chronological `<`
- After `DELETE`, `READ NEXT` automatically moves to the next remaining record — no repositioning with `START` needed
- Tested on IBM z/OS with Enterprise COBOL
