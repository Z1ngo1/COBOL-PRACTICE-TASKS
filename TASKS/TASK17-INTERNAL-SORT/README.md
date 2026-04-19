# Task 17 — Academic Performance Rating (Internal Sort / INPUT-OUTPUT PROCEDURE)

## Overview

Reads a raw unsorted exam results file (`EXAM.RAW`), filters out failing students (`STUD-SCORE < 50`), sorts the passing students by class ascending and by score descending within each class, and writes the result to an honor roll file (`HONOR.ROLL`).
The core technique is the **COBOL `SORT` statement with `INPUT PROCEDURE` and `OUTPUT PROCEDURE`**: instead of sorting a file externally, the program controls both ends of the sort — the input procedure feeds filtered records into the sort engine via `RELEASE`, and the output procedure consumes sorted records via `RETURN`.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `EXDD` | `EXAM.RAW` | PS | INPUT | Raw exam results — unsorted, may contain failing scores |
| `SRTDD` | `WORK.SORT` | SD | TEMP | Sort work file — temporary, deleted after job |
| `HNRDD` | `HONOR.ROLL` | PS | OUTPUT | Sorted honor roll — passing students only, sorted by class and score |

### Input Record Layout — `EXAM.RAW` (`EXDD`), LRECL=31, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `STUD-ID` | `X(5)` | 1 | Student ID |
| `STUD-NAME` | `X(20)` | 6 | Student name |
| `STUD-CLASS` | `X(3)` | 26 | Class code — primary sort key, ascending |
| `STUD-SCORE` | `9(3)` | 29 | Exam score — secondary sort key, descending; filter threshold |

### Sort Work File Layout — `WORK.SORT` (`SRTDD`), LRECL=31, RECFM=F

Declared as `SD` (Sort Description). Same field layout as `EXAM.RAW`:
`SORT-ID X(5)`, `SORT-NAME X(20)`, `SORT-CLASS X(3)`, `SORT-SCORE 9(3)`.

### Output Record Layout — `HONOR.ROLL` (`HNRDD`), LRECL=31, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `OUT-ID` | `X(5)` | 1 | Student ID |
| `OUT-NAME` | `X(20)` | 6 | Student name |
| `OUT-CLASS` | `X(3)` | 26 | Class code |
| `OUT-SCORE` | `9(3)` | 29 | Exam score |

---

## Three-Phase Processing

The entire program is driven by a single `SORT` statement. There is no explicit `OPEN`/`CLOSE` in `MAIN-LOGIC` — files are managed inside the procedures.

```cobol
MAIN-LOGIC.
    SORT SORT-FILE
        ON ASCENDING  KEY SORT-CLASS
        ON DESCENDING KEY SORT-SCORE
        INPUT  PROCEDURE IS FILTER-INPUT-DATA
        OUTPUT PROCEDURE IS WRITE-SORTED-REPORT.
    PERFORM DISPLAY-SUMMARY.
    STOP RUN.
```

### Phase 1 — `FILTER-INPUT-DATA` (INPUT PROCEDURE)

The INPUT PROCEDURE replaces `USING` — the program manually feeds records to the sort engine.

```
OPEN INPUT EXAM.RAW
PERFORM UNTIL EOF
    READ EXAM.RAW
    ADD 1 TO RECORDS-READ
    IF STUD-SCORE >= 50
        MOVE fields to SORT-REC
        RELEASE SORT-REC        <-- sends record to sort engine
        ADD 1 TO RECORDS-PASSED
    ELSE
        ADD 1 TO RECORDS-FILTERED   <-- record dropped silently
    END-IF
END-PERFORM
CLOSE EXAM.RAW
```

`RELEASE` is the equivalent of `WRITE` for the sort work file — it hands one record to the internal sort engine. Records with `STUD-SCORE < 50` are never released and never appear in the output.

### Phase 2 — Automatic Sort (engine)

After `FILTER-INPUT-DATA` returns, the COBOL sort engine sorts all released records:
- **Primary key:** `SORT-CLASS` — ascending (alphabetical class order)
- **Secondary key:** `SORT-SCORE` — descending (best score first within each class)

No code needed here — the sort engine handles it entirely.

### Phase 3 — `WRITE-SORTED-REPORT` (OUTPUT PROCEDURE)

The OUTPUT PROCEDURE replaces `GIVING` — the program manually consumes sorted records.

```
OPEN OUTPUT HONOR.ROLL
PERFORM UNTIL OUT-EOF
    RETURN SORT-FILE AT END SET OUT-EOF TO TRUE  <-- reads from sort engine
    NOT AT END
        MOVE SORT-ID    TO OUT-ID
        MOVE SORT-NAME  TO OUT-NAME
        MOVE SORT-CLASS TO OUT-CLASS
        MOVE SORT-SCORE TO OUT-SCORE
        WRITE HONOR-REC
END-PERFORM
CLOSE HONOR.ROLL
```

`RETURN` is the equivalent of `READ` for the sort work file — it retrieves the next sorted record from the sort engine. `AT END` fires when all sorted records have been consumed.

---

## Sort Keys

| Priority | Field | Direction | Effect |
|---|---|---|---|
| Primary | `SORT-CLASS` | ASCENDING | Groups students by class in alphabetical order |
| Secondary | `SORT-SCORE` | DESCENDING | Within each class, highest score appears first |

---

## Filtering Logic

| Condition | Action |
|---|---|
| `STUD-SCORE >= 50` | `RELEASE SORT-REC` — record enters sort engine |
| `STUD-SCORE < 50` | Record discarded, `RECORDS-FILTERED` incremented |

No output line is written for filtered students — they do not appear in `HONOR.ROLL` at all.

---

## `RELEASE` and `RETURN` vs `WRITE` and `READ`

| Operation | Normal file | Sort work file |
|---|---|---|
| Send record | `WRITE` | `RELEASE` |
| Receive record | `READ` | `RETURN` |
| File opened by | `OPEN OUTPUT` | Sort engine (automatic) |
| EOF handling | `AT END` on `READ` | `AT END` on `RETURN` |

The sort work file (`SD`) is **never opened or closed manually** — the sort engine controls it entirely. Attempting to `OPEN` or `CLOSE` the `SD` file directly will cause a compile error.

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/EXAM.RAW`](DATA/EXAM.RAW) | 20 student exam records, unsorted, mixed passing/failing scores |
| [`DATA/HONOR.ROLL`](DATA/HONOR.ROLL) | Expected output — 15 passing students sorted by class asc, score desc |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
HONOR ROLL GENERATION SUMMARY
========================================
RECORDS READ:         20
RECORDS FILTERED:      5
RECORDS PASSED:       15
RECORDS WRITTEN:      15
========================================
```

---

## How to Run

1. Upload [`DATA/EXAM.RAW`](DATA/EXAM.RAW) to your mainframe dataset manually through option '3.4 and edit your dataset' or with pre-prepared data
2. Submit [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) with pre-prepared data

> **PROC reference:** `COMPRUN.jcl` uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure `MYCOMPGO` is available in your system's `PROCLIB` before submitting.

> **Note:** `WORK.SORT` (`SRTDD`) is defined as `DISP=(NEW,DELETE,DELETE)` in the JCL — it is a temporary dataset that is automatically deleted after the job completes regardless of return code.

---

## Key COBOL Concepts Used

- **`SORT` with `INPUT PROCEDURE` / `OUTPUT PROCEDURE`** — the most powerful form of the `SORT` statement; replaces `USING`/`GIVING` with full procedural control over both ends of the sort; allows filtering, transformation, or counting before and after the sort
- **`RELEASE`** — the only way to feed a record into an active sort from an INPUT PROCEDURE; equivalent to `WRITE` for the SD file; the sort engine collects all released records before sorting
- **`RETURN`** — the only way to retrieve a sorted record inside an OUTPUT PROCEDURE; equivalent to `READ` for the SD file; fires `AT END` when the sorted stream is exhausted
- **`SD` (Sort Description)** — special file description for the sort work file; unlike `FD`, the SD file is never opened or closed manually — the sort engine manages it; the `ASCENDING KEY` / `DESCENDING KEY` fields are declared in the `SORT` statement, not in the SD
- **Filter-before-sort pattern** — records rejected in the INPUT PROCEDURE are never added to the sort engine, so they consume no sort resources and never appear in output; more efficient than filtering in the OUTPUT PROCEDURE

---

## Notes

- `EXAM.RAW` does not need to be pre-sorted — the COBOL sort engine handles ordering entirely; unsorted input is expected and normal
- The `WORK.SORT` dataset is temporary (`DISP=(NEW,DELETE,DELETE)`) — it does not need to exist before the job runs and is automatically cleaned up after
- `EXAM.RAW` is opened and closed inside `FILTER-INPUT-DATA`, and `HONOR.ROLL` is opened and closed inside `WRITE-SORTED-REPORT`; neither file is opened in `MAIN-LOGIC`
- Students with `STUD-SCORE = 50` are included (threshold is `>= 50`)
- Tested on IBM z/OS with Enterprise COBOL
