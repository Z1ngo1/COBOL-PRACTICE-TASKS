# Task 18 — VSAM Alternate Index: Library Book Finder

## Overview

Reads author names from a search request file [`SEARCH.REQ`](DATA/SEARCH.REQ), and for each author performs a VSAM `START` on the Alternate Index (`VSAM-AUTHOR`) to position on the first matching book. Then uses `READ NEXT` to browse all books by that author in AIX order. Found books are written to a result report file [`RESULT.RPT`](DATA/RESULT.RPT). Authors not found in the catalog trigger a NOT FOUND line. A summary of statistics is printed to SYSOUT at the end.

The core technique is **VSAM Dynamic Access with an Alternate Index (AIX)**: `START` positions on the AIX key, and `READ NEXT` browses records in AIX order until the author field changes — allowing retrieval of all books by a given author without knowing their ISBNs.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `LIBRARY.MASTER.VSAM` | VSAM KSDS | INPUT | Base cluster — accessed via PATH (AIX) |
| `VSAMDD1` | `LIBRARY.MASTER.VSAM.PATH` | VSAM PATH | INPUT | PATH over AIX — used for AIX-based START/READ NEXT |
| `SRCHDD` | `SEARCH.REQ` | PS | INPUT | Author search requests, RECFM=FB, LRECL=80 |
| `RSLTDD` | `RESULT.RPT` | PS | OUTPUT | Search results report, RECFM=VB, LRECL=84 |

### Input Record Layout — `SEARCH.REQ` (`SRCHDD`), LRECL=80, RECFM=FB

| Field | Picture | Offset | Description |
|---|---|---|---|
| `SEARCH-AUTHOR` | `X(20)` | 1 | Author name to search |
| FILLER | `X(60)` | 21 | Unused |

### VSAM Record Layout — `LIBRARY.MASTER.VSAM` (`VSAMDD`), LRECL=64

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ISBN` | `X(10)` | 1 | Primary key (ISBN) |
| `VSAM-AUTHOR` | `X(20)` | 11 | Alternate key (AIX key) |
| `VSAM-TITLE` | `X(30)` | 31 | Book title |
| `VSAM-YEAR` | `X(4)` | 61 | Publication year |
| FILLER | `X(16)` | 65 | Unused (padded to RECORDSIZE 64,64) |

### Output Record Layout — `RESULT.RPT` (`RSLTDD`), RECFM=VB, LRECL=84

| Field | Picture | Description |
|---|---|---|
| `RESULT-REC` | `X(80)` | One output line (header / detail / not-found / separator) |

---

## Business Logic: Four-Phase Processing

The program is driven by `MAIN-LOGIC` which calls four paragraphs in sequence. Each phase has a distinct responsibility: open files, iterate over search requests, perform AIX browse per author, and close files.

```cobol
MAIN-LOGIC.
    PERFORM OPEN-ALL-FILES.
    PERFORM READ-SEARCH-AUTHOR.
    PERFORM PROCESS-ALL-SEARCHES.
    PERFORM CLOSE-ALL-FILES.
    PERFORM DISPLAY-SUMMARY.
    STOP RUN.
```

### Phase 1 — `OPEN-ALL-FILES`

Opens `VSAM-FILE` (INPUT), `SEARCH-FILE` (INPUT), and `RESULT-FILE` (OUTPUT). Checks FILE STATUS after each OPEN — if not `'00'`, displays an error and stops.

### Phase 2 — `PROCESS-ALL-SEARCHES` (main loop)

Loops over all author names from `SEARCH-FILE`. Blank lines (`SEARCH-AUTHOR = SPACES`) are skipped silently. For each valid author the program delegates to `SEARCH-AUTHOR-BOOKS`.

```
PROCESS-ALL-SEARCHES:
  PERFORM UNTIL EOF
    IF SEARCH-AUTHOR NOT = SPACES
      ADD 1 TO SEARCHES-PROCESSED
      PERFORM SEARCH-AUTHOR-BOOKS
    END-IF
    PERFORM READ-SEARCH-AUTHOR
  END-PERFORM
```

`READ-SEARCH-AUTHOR` reads one record from `SEARCH-FILE`, increments `READ-COUNTER`, and sets `EOF` flag at end of file.

### Phase 3 — `SEARCH-AUTHOR-BOOKS` (AIX search per author)

For each author writes a HEADER-LINE to `RESULT-FILE`, then performs a VSAM `START` on the Alternate Index to position on the first matching book.

```
SEARCH-AUTHOR-BOOKS:
  WRITE HEADER-LINE ("SEARCH FOR: <author>")
  START VSAM-FILE KEY IS EQUAL TO VSAM-AUTHOR
    INVALID KEY:
      ADD 1 TO AUTHORS-NOT-FOUND
      WRITE NOT-FOUND-LINE
    NOT INVALID KEY:
      ADD 1 TO AUTHORS-FOUND
      PERFORM READ-MATCHING-BOOKS
  END-START
  WRITE SEPARATOR-LINE (40 dashes)
```

### Phase 4 — `READ-MATCHING-BOOKS` (AIX browse)

Reads records sequentially via `READ NEXT` in AIX order while `VSAM-AUTHOR` matches `SEARCH-AUTHOR`. Stops when the author field changes or end-of-file is reached.

```
READ-MATCHING-BOOKS:
  SET NOT-EOF-AUTHOR TO TRUE
  PERFORM UNTIL EOF-AUTHOR
    READ VSAM-FILE NEXT RECORD
      AT END: SET EOF-AUTHOR TO TRUE
      NOT AT END:
        IF VSAM-AUTHOR NOT = SEARCH-AUTHOR
          SET EOF-AUTHOR TO TRUE    <-- author changed, stop browsing
        ELSE
          ADD 1 TO BOOKS-FOUND
          WRITE DETAIL-LINE ("  FOUND: <title> (<year>)")
        END-IF
    END-READ
  END-PERFORM
```

---

## AIX Architecture

| Component | Dataset Name | Description |
|---|---|---|
| Base Cluster | `LIBRARY.MASTER.VSAM` | KSDS keyed by `VSAM-ISBN` (10 bytes, offset 0) |
| Alternate Index | `LIBRARY.MASTER.VSAM.AIX` | Keyed by `VSAM-AUTHOR` (20 bytes, offset 10), NONUNIQUEKEY |
| PATH | `LIBRARY.MASTER.VSAM.PATH` | Logical link between AIX and base cluster — used in COBOL as `VSAMDD1` |

`NONUNIQUEKEY` (= `WITH DUPLICATES` in COBOL) allows multiple books to share the same author key. `UPGRADE` keeps the AIX synchronized automatically when the base cluster is updated.

---

## `START` and `READ NEXT` vs Normal VSAM Read

| Operation | Random access | AIX browse |
|---|---|---|
| Position | `READ` with primary key | `START KEY IS EQUAL TO <alt-key>` |
| Traverse | — | `READ NEXT` (returns records in AIX key order) |
| End detection | FILE STATUS `'23'` (not found) | Author field changes OR AT END |
| Access mode required | RANDOM | DYNAMIC |

`ACCESS MODE IS DYNAMIC` in FILE-CONTROL is mandatory — it enables both random (`START`) and sequential (`READ NEXT`) access in the same program.

---

## Program Flow

1.  **PERFORM OPEN-ALL-FILES** — opens `VSAMDD` (INPUT), `SRCHDD` (INPUT), and `RSLTDD` (OUTPUT); checks FILE STATUS after each open.
2.  **PERFORM READ-SEARCH-AUTHOR** — reads first record from `SEARCH-FILE`; sets EOF flag if file is empty.
3.  **PERFORM PROCESS-ALL-SEARCHES** — main loop `UNTIL EOF` on `SEARCH-FILE`.
    *   **IF `SEARCH-AUTHOR = SPACES`** → skip silently; increment `READ-COUNTER` only.
    *   **ELSE** → increment `SEARCHES-PROCESSED`; **PERFORM SEARCH-AUTHOR-BOOKS**.
        *   **WRITE HEADER-LINE** — writes `"SEARCH FOR: <author>"` to `RESULT-FILE`.
        *   **START VSAM-FILE KEY IS EQUAL TO VSAM-AUTHOR**.
            *   **INVALID KEY** → increment `AUTHORS-NOT-FOUND`; write NOT-FOUND-LINE.
            *   **NOT INVALID KEY** → increment `AUTHORS-FOUND`; **PERFORM READ-MATCHING-BOOKS**.
                *   **READ VSAM-FILE NEXT RECORD** in a loop until author changes or AT END.
                *   **IF author matches** → increment `BOOKS-FOUND`; write DETAIL-LINE.
                *   **IF author changes** → set EOF-AUTHOR flag; exit browse loop.
        *   **WRITE SEPARATOR-LINE** — writes 40 dashes after each author block.
    *   **PERFORM READ-SEARCH-AUTHOR** — reads next record from `SEARCH-FILE`.
4.  **PERFORM CLOSE-ALL-FILES** — closes `VSAMDD`, `SRCHDD`, and `RSLTDD`.
5.  **PERFORM DISPLAY-SUMMARY** — prints final statistics to SYSOUT (searches read, processed, authors found/not found, books found).
6.  **STOP RUN**.

---

## JCL Steps (`ALLSTEPS.jcl`)

| Step | Program | COND | Description |
|---|---|---|---|
| STEP005 | IDCAMS | — | Delete existing VSAM cluster (SET MAXCC=0 to suppress RC=8 if not found), then DEFINE new KSDS cluster |
| STEP010 | IDCAMS | (04,LT) | REPRO inline data into `LIBRARY.MASTER.VSAM` — loads 14 book records |
| STEP015 | IDCAMS | (04,LT) | DEFINE AIX on `VSAM-AUTHOR` field (KEYS(20 10), NONUNIQUEKEY, UPGRADE) |
| STEP020 | IDCAMS | (04,LT) | DEFINE PATH connecting the AIX to the base cluster |
| STEP025 | IDCAMS | (04,LT) | BLDINDEX — physically builds the AIX from the loaded base cluster |
| STEP030 | IEFBR14 | (04,LT) | Delete `SEARCH.REQ` if it already exists (MOD,DELETE,DELETE) |
| STEP035 | IEBGENER | (04,LT) | Create `SEARCH.REQ` from inline SYSIN — 7 author names (includes 2 not in catalog) |
| STEP040 | IEFBR14 | (04,LT) | Delete `RESULT.RPT` if it already exists |
| STEP045 | IGYWCL | (04,LT) | Compile and link-edit `VSAM18` COBOL source from `Z73460.COB.PRAC(VSAM18)` |
| STEP050 | VSAM18 | (04,LT) | Execute the search program — reads `SEARCH.REQ`, searches VSAM via AIX, writes `RESULT.RPT` |

`COND=(04,LT)` means: skip this step if any previous step RC > 4 (i.e., run only if all previous steps passed cleanly).

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`LIBRARY.MASTER`](DATA/LIBRARY.MASTER) | 14 book records loaded into VSAM base cluster |
| [`SEARCH.REQ`](DATA/SEARCH.REQ) | 7 author search requests (created by STEP035) |
| [`RESULT.RPT`](DATA/RESULT.RPT) | Expected output |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
LIBRARY SEARCH SUMMARY
========================================
SEARCHES READ:          8
SEARCHES PROCESSED:     7
AUTHORS FOUND:          5
AUTHORS NOT FOUND:      2
BOOKS FOUND (TOTAL):   14
========================================
```

---

## How to Run

1. Submit [`JCL/ALLSTEPS.jcl`](JCL/ALLSTEPS.jcl) — it handles everything end-to-end: defines VSAM, loads data, builds AIX, creates search file, compiles and runs the program

> **Note:** The JCL compiles source from `Z73460.COB.PRAC(VSAM18)` using the `IGYWCL` procedure and loads the compiled module into `Z73460.LOAD(VSAM18)`. Make sure your source PDS and load library names match your system before submitting.

> **Note:** `RESULT.RPT` (`RSLTDD`) is defined as `RECFM=VB, LRECL=84` — variable-blocked format with 4-byte RDW prefix. The COBOL program writes 80-byte logical records via `RESULT-REC PIC X(80)`.
>
> **Alternative:** To run individual steps separately:

2. [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl) — Define VSAM cluster (STEP005)
3. [`JCL/DATAVSAM.jcl`](JCL/DATAVSAM.jcl) — Load data into base cluster (STEP010)
4. [`JCL/DEFAIX.jcl`](JCL/DEFAIX.jcl) — Define Alternate Index (STEP015)
5. [`JCL/DEFPATH.jcl`](JCL/DEFPATH.jcl) — Define PATH (STEP020)
6. [`JCL/BLDINDX.jcl`](JCL/BLDINDX.jcl) — Build the AIX (STEP025)
7. [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) — Compile and run VSAM18 program (STEP030-STEP050)

---

## Key COBOL Concepts Used

- **`ACCESS MODE IS DYNAMIC`** — mandatory for combining `START` (random positioning) and `READ NEXT` (sequential browsing) on the same file in the same program; without DYNAMIC, you can only do one or the other
- **`ALTERNATE RECORD KEY IS VSAM-AUTHOR WITH DUPLICATES`** — declares the AIX key in FILE-CONTROL; `WITH DUPLICATES` allows multiple records to share the same alternate key value (multiple books per author)
- **`START KEY IS EQUAL TO`** — positions the file cursor on the first AIX record matching the given author; does not read a record — only positions; `INVALID KEY` fires if no matching record exists
- **`READ NEXT`** — after a successful `START`, each `READ NEXT` returns the next record in AIX key order; records with the same AIX key (same author) are returned consecutively
- **`NONUNIQUEKEY` / `WITH DUPLICATES`** — the AIX allows multiple base cluster records to map to the same alternate key; without this, each author could have only one book
- **`UPGRADE`** — the AIX is automatically rebuilt whenever the base cluster is updated; without UPGRADE, the AIX must be rebuilt manually with BLDINDEX after each load
- **`PATH`** — a logical name that ties together the AIX and the base cluster; the COBOL program references the PATH via `VSAMDD1` DD name for AIX-based access

---

## Notes

- `SET MAXCC=0` in STEP005 prevents the job from failing with RC=8 if the VSAM cluster does not yet exist at delete time
- The program checks FILE STATUS after every OPEN, WRITE, and key error — bad status causes immediate `STOP RUN` with a descriptive message
- Blank lines in `SEARCH.REQ` are skipped silently (`IF SEARCH-AUTHOR NOT = SPACES`) but still counted in `READ-COUNTER`
- `READ-COUNTER` counts all records read from `SEARCH-FILE` (including blank lines); `SEARCHES-PROCESSED` counts only non-blank author names actually searched
- The AIX browse stops as soon as `VSAM-AUTHOR` changes — this works correctly because AIX returns records in author-key order, so all books by the same author are consecutive
- Tested on IBM z/OS with Enterprise COBOL
