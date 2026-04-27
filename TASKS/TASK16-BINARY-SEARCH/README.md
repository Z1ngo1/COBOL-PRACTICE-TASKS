# Task 16 — Wholesale Warehouse (Binary Search / SEARCH ALL)

## Overview

Reads a parts catalog file [`PARTS.CATALOG`](DATA/PARTS.CATALOG) into an in-memory array (`CATALOG-TABLE`), then processes a customer orders file [`ORDERS.FILE`](DATA/ORDERS.FILE) and writes an invoice output [`INVOICE.TXT`](DATA/INVOICE.TXT) with the calculated order total for each order.
The core technique is **`SEARCH ALL`** (binary search): unlike `SEARCH` which walks the table linearly, `SEARCH ALL` performs a binary search and requires the table to be declared with `ASCENDING KEY` and the input file to be pre-sorted by that key. The table uses `DEPENDING ON PARTS-LOADED` so `SEARCH ALL` scans only the loaded entries.

---

## Critical Prerequisite: [`PARTS.CATALOG`](DATA/PARTS.CATALOG) Must Be Sorted by `PART-ID` Ascending

> **[`PARTS.CATALOG`](DATA/PARTS.CATALOG) must be sorted by `PART-ID` in ascending order before this program runs.**

`SEARCH ALL` (binary search) assumes the table is sorted by the `ASCENDING KEY` declared in the `OCCURS` clause. Unsorted input will produce **incorrect results or missed matches without any error message or ABEND**. Use a `SORT` step in the JCL before the program step if your input is not already sorted.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `PARTDD` | [`PARTS.CATALOG`](DATA/PARTS.CATALOG) | PS | INPUT | Parts catalog — part ID + price; pre-sorted by `PART-ID` ascending |
| `ORDRDD` | [`ORDERS.FILE`](DATA/ORDERS.FILE) | PS | INPUT | Customer orders — order number, part ID, quantity |
| `INVODD` | [`INVOICE.TXT`](DATA/INVOICE.TXT) | PS | OUTPUT | Invoice lines — one line per order with order number and total cost |

### Input Record Layout — (`PARTDD`), LRECL=10, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `PART-ID` | `9(5)` | 1 | Part ID — **sort key**, ascending |
| `PART-PRICE` | `9(3)V99` | 6 | Unit price — implied 2 decimal places |

### Input Record Layout — (`ORDRDD`), LRECL=13, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `ORDR-NUM` | `9(5)` | 1 | Order number |
| `ORDR-ID` | `9(5)` | 6 | Part ID to look up in `CATALOG-TABLE` |
| `ORDR-QUANT` | `9(3)` | 11 | Order quantity |

### Output Record Layout — (`INVODD`), LRECL=80, RECFM=F

| Content | Description |
|---|---|
| `ORDR-NUM` + total cost | Written when part is found: order number and computed total |
| `ORDR-NUM` + `NOT FOUND` | Written when part ID is not in `CATALOG-TABLE` |

---

## Business Logic: Two-Phase Processing

### Phase 1 — Load Catalog Table (Initialization)

The program loads the entire parts catalog into a Working-Storage table before any order is processed.

```
OPEN PARTS.CATALOG
PERFORM UNTIL EOF
    READ PARTS.CATALOG
    ADD 1 TO PARTS-LOADED
    MOVE PART-ID    TO WS-PART-ID(IDX)
    MOVE PART-PRICE TO WS-PRICE(IDX)
END-PERFORM
CLOSE PARTS.CATALOG
```

After this phase the entire catalog lives in `CATALOG-TABLE` in memory. `PARTS-LOADED` serves as the `DEPENDING ON` value — `SEARCH ALL` will only scan entries 1 through `PARTS-LOADED`, so no dummy entries are touched. Table size is bounded by `OCCURS 1 TO 100` — overflow records are ignored with a warning.

### Phase 2 — Process Orders

For each order record the program performs a binary search against the in-memory catalog and writes exactly one invoice line.

```
OPEN ORDERS.FILE, INVOICE.TXT
PERFORM UNTIL EOF
    READ ORDERS.FILE
    ADD 1 TO ORDERS-PROCESSED
    PERFORM SEARCH-PART-PRICE
END-PERFORM
CLOSE ORDERS.FILE, INVOICE.TXT
```

---

## Binary Search Logic (`SEARCH ALL`)

`SEARCH ALL` requires:
1. `ASCENDING KEY IS WS-PART-ID` declared in the `OCCURS` clause
2. Input file pre-sorted by `PART-ID` ascending
3. **No `SET IDX TO 1` before the search** — `SEARCH ALL` manages the index itself

```cobol
SET NOT-FOUND TO TRUE.
SEARCH ALL CATALOG-ENTRY
    AT END
        CONTINUE
    WHEN WS-PART-ID(IDX) = ORDR-ID
        SET FOUND TO TRUE
        COMPUTE WS-TOTAL-COST = WS-PRICE(IDX) * ORDR-QUANT
END-SEARCH.
PERFORM WRITE-INVOICE-RECORD.
```

### `SEARCH ALL` vs `SEARCH` (PERFORM VARYING)

| Feature | `SEARCH` (linear) | `SEARCH ALL` (binary) |
|---|---|---|
| Algorithm | Sequential scan, index 1 → N | Binary split, O(log N) |
| Requires sorted input | No | **Yes** |
| Requires `ASCENDING KEY` clause | No | **Yes** |
| `SET IDX TO 1` before search | Required | **Not needed** |
| Works with partial table (`DEPENDING ON`) | Yes | Yes |
| Match type | First entry satisfying condition | Exact key equality only |

### Not Found Handling

If `ORDR-ID` is not in `CATALOG-TABLE`, `AT END` fires, `WS-FOUND` stays `'N'`, and `WRITE-INVOICE-RECORD` writes a `NOT FOUND` line. The order is still counted in `INVOICES-WRITTEN` and `PARTS-NOT-FOUND`.

---

## Invoice Calculation

```
WS-TOTAL-COST = WS-PRICE(IDX) * ORDR-QUANT   (when part found)
```

`COMPUTE` is used to avoid truncation on the implied decimal position of `WS-PRICE`.

---

## Program Flow

1.  **PERFORM OPEN-CATALOG-FILE** — opens `PARTDD` (INPUT) for initialization.
2.  **PERFORM LOAD-CATALOG-TABLE** — reads `PARTS.CATALOG` into `CATALOG-TABLE` until EOF. Increments `PARTS-LOADED` for each record; records beyond 100 are skipped with a warning.
3.  **PERFORM CLOSE-CATALOG-FILE** — closes `PARTDD`; the catalog is never reopened.
4.  **PERFORM OPEN-ORDER-FILES** — opens `ORDRDD` (INPUT) and `INVODD` (OUTPUT).
5.  **PERFORM PROCESS-ORDERS** — main loop `UNTIL EOF` on `ORDERS.FILE`.
    *   **READ ORDERS-FILE**.
    *   **PERFORM SEARCH-PART-PRICE** — executes `SEARCH ALL CATALOG-ENTRY` using `ORDR-ID` as the lookup key.
    *   **IF FOUND** → `COMPUTE WS-TOTAL-COST`, format invoice line, and **WRITE INVOICE-REC**.
    *   **IF NOT FOUND** → write `NOT FOUND` line; increment `PARTS-NOT-FOUND`.
6.  **DISPLAY-SUMMARY** — prints final statistics to SYSOUT (parts loaded, orders processed, invoices written, found vs. not-found counts).
7.  **PERFORM CLOSE-ORDER-FILES** — closes `ORDRDD` and `INVODD`.
8.  **STOP RUN**.

---

## Test Data

All input and expected output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`PARTS.CATALOG`](DATA/PARTS.CATALOG) | 9 part entries, sorted by `PART-ID` ascending |
| [`ORDERS.FILE`](DATA/ORDERS.FILE) | 12 customer order records |
| [`INVOICE.TXT`](DATA/INVOICE.TXT) | Expected invoice output |

---

## Expected SYSOUT

Actual job output is stored in [`SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
========================================
INVOICE GENERATION SUMMARY
========================================
PARTS LOADED:          9
ORDERS PROCESSED:     12
INVOICES WRITTEN:     12
PARTS FOUND:           6
PARTS NOT FOUND:       6
========================================
```

---

## How to Run

1. Upload [`PARTS.CATALOG`](DATA/PARTS.CATALOG) and [`ORDERS.FILE`](DATA/ORDERS.FILE) to your mainframe datasets manually through option '3.4 and edit your dataset' or with pre-prepared data
2. Submit [`COMPRUN.jcl`](JCL/COMPRUN.jcl) with pre-prepared data
3. Compare output files and sysout - see [`INVOICE.TXT`](DATA/INVOICE.TXT) and [`SYSOUT.txt`](OUTPUT/SYSOUT.txt)

> **PROC reference:** [`COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- **`SEARCH ALL`** — binary search on `CATALOG-TABLE`; the compiler generates a bisection algorithm instead of a linear scan; requires `ASCENDING KEY IS WS-PART-ID` in the `OCCURS` clause and pre-sorted input; the index is managed internally — no `SET IDX TO 1` before the call
- **`OCCURS ... DEPENDING ON`** — `CATALOG-ENTRY OCCURS 1 TO 100 DEPENDING ON PARTS-LOADED` limits the active table size to the number of loaded entries; `SEARCH ALL` respects this boundary and never reads uninitialized slots
- **`ASCENDING KEY IS`** — mandatory clause for `SEARCH ALL`; tells the compiler which field is the sort key and enables the binary search algorithm; without it the program will not compile
- **Two-phase design** — strict initialization phase (load `CATALOG-TABLE`, close `PARTS.CATALOG`) before opening `ORDERS.FILE`; the catalog is read exactly once regardless of how many orders exist
- **`AT END` / `WHEN` in `SEARCH ALL`** — `AT END` fires when the part is not found (binary search exhausted); `WHEN` fires on an exact match; only one `WHEN` clause is allowed in `SEARCH ALL` and it must use `=` equality

---

## Notes

- `PARTS.CATALOG` must be sorted **ascending** by `PART-ID` — `SEARCH ALL` does not validate sort order; unsorted input silently produces wrong results
- The table is bounded by `OCCURS 1 TO 100` — if `PARTS.CATALOG` has more than 100 records the program displays a warning and ignores the excess; increase both the `OCCURS` maximum and the `PARTS-LOADED` `PIC` size if a larger catalog is needed
- `PARTS.CATALOG` is closed after Phase 1 and never reopened — all lookups in Phase 2 are purely in-memory
- Every order record produces exactly one output line in `INVOICE.TXT` regardless of found/not-found result
- Tested on IBM z/OS with Enterprise COBOL
