# Task 10 — Invoice Generation (VSAM KSDS Random Read + PS Enrichment)

## Overview

Reads a sequential PS orders file (`ORDERS.DAILY`), performs a **random read** into a VSAM KSDS product master (`PROD.MASTER`) for each order, enriches the record with product name and unit price, calculates `TOTAL-COST = QUANTITY × UNIT-PRICE`, and writes the result to a PS invoice output file (`INVOICE.FILE`).
Orders with unknown product IDs are skipped and logged to SYSOUT. A summary is printed at the end.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `PROD.MASTER` | VSAM KSDS | INPUT / RANDOM | Product master — name and unit price, key = `PRODUCT-ID` |
| `ORDD` | `ORDERS.DAILY` | PS | INPUT | Daily orders — order ID, product ID, quantity; LRECL=80, RECFM=F |
| `OUTDD` | `INVOICE.FILE` | PS | OUTPUT | Enriched invoice lines — order ID, product name, quantity, total cost; LRECL=80, RECFM=F |

### VSAM Record Layout (`VSAMDD`) — LRECL=32

| Field | Picture | Offset | Description |
|---|---|---|---|
| `PRODUCT-ID` | `X(5)` | 1 | **Primary key** — product code |
| `PRODUCT-NAME` | `X(20)` | 6 | Product description |
| `UNIT-PRICE` | `9(5)V99` | 26 | Unit price (implicit 2 decimal places) |

### Orders Record Layout (`ORDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `ORDER-ID` | `X(5)` | 1 | Order number |
| `ORDER-PRODUCT-ID` | `X(5)` | 6 | Product code to look up in VSAM |
| `ORDER-QUANTITY` | `9(3)` | 11 | Quantity ordered |
| FILLER | `X(67)` | 14 | Padding to 80 bytes |

### Invoice Record Layout (`OUTDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `INVOICE-ORDER-ID` | `X(5)` | 1 | Order number |
| FILLER | `X(1)` | 6 | Space |
| `INVOICE-PRODUCT-NAME` | `X(20)` | 7 | Product name (from VSAM) |
| FILLER | `X(1)` | 27 | Space |
| `INVOICE-QUANTITY` | `9(3)` | 28 | Quantity |
| FILLER | `X(1)` | 31 | Space |
| `INVOICE-TOTAL-COST` | `Z(6).99` | 32 | Total cost, edited numeric |
| FILLER | `X(40)` | 40 | Padding to 80 bytes |

---

## Business Logic

### Enrichment Flow (per order record)

| Step | Action |
|---|---|
| 1 | Read next record from `ORDERS.DAILY` sequentially |
| 2 | `MOVE ORDER-PRODUCT-ID TO PRODUCT-ID` — place key into VSAM FD field |
| 3 | `READ PRODUCT-MASTER-FILE` — random read by key |
| 4 | Check `VSAM-STATUS` |

### FILE STATUS Handling

| Status | Meaning | Action |
|---|---|---|
| `'00'` | Found | `COMPUTE WS-TOTAL-COST = UNIT-PRICE * ORDER-QUANTITY` → `WRITE OUT-REC` → increment `TOTAL-INVOICES` |
| `'23'` | Not found | `DISPLAY 'ORDER nnnnn: PRODUCT nnnnn NOT FOUND.'` → skip write → increment `TOTAL-ERRORS` |
| Other | VSAM I/O error | `DISPLAY 'VSAM READ ERROR: ' VSAM-STATUS` → increment `TOTAL-ERRORS` → `STOP RUN` |

---

## Program Flow

1. **PERFORM OPEN-ALL-FILES**
   - `OPEN INPUT PRODUCT-MASTER-FILE` — check `VSAM-STATUS`
   - `OPEN INPUT DAILY-ORDERS-FILE` — check `ORDERS-STATUS`
   - `OPEN OUTPUT INVOICE-OUTPUT-FILE` — check `OUT-STATUS`
   - Any non-`'00'` status → `DISPLAY` error + `STOP RUN`

2. **PERFORM PROCESS-ORDERS**
   - `PERFORM UNTIL EOF`
     - `READ DAILY-ORDERS-FILE AT END SET EOF TO TRUE`
     - If `ORDERS-STATUS = '00'` → increment `TOTAL-ORDERS` → **PERFORM PROCESS-ORDER**
     - Else → `DISPLAY` read error + `STOP RUN`

3. **PROCESS-ORDER**
   - `MOVE SPACES TO OUT-REC`
   - `MOVE ORDER-PRODUCT-ID TO PRODUCT-ID`
   - `READ PRODUCT-MASTER-FILE` (random, no key clause needed — key already in FD field)
   - `EVALUATE TRUE` on `VSAM-STATUS`:
     - `'00'` → **PERFORM WRITE-INVOICE-LINE**
     - `'23'` → log to SYSOUT, skip
     - `OTHER` → log error, `STOP RUN`

4. **WRITE-INVOICE-LINE**
   - `COMPUTE WS-TOTAL-COST = UNIT-PRICE * ORDER-QUANTITY`
   - Move fields: `ORDER-ID`, `PRODUCT-NAME`, `ORDER-QUANTITY`, `WS-TOTAL-COST` → `OUT-REC`
   - `WRITE OUT-REC` — check `OUT-STATUS`; error → `STOP RUN`
   - Increment `TOTAL-INVOICES`

5. **PERFORM CLOSE-ALL-FILES** — close all three files, check each status (warning only on close errors)

6. **PERFORM DISPLAY-SUMMARY** — print totals to SYSOUT

7. `STOP RUN`

---

## Test Data

Input data and expected output are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`PROD.MASTER.VSAM`](DATA/PROD.MASTER.VSAM) | 10 product records loaded into VSAM KSDS |
| [`ORDERS.DAILY`](DATA/ORDERS.DAILY) | 12 order records (10 valid, 2 with unknown product IDs) |
| [`INVOICE.FILE`](DATA/INVOICE.FILE) | Expected invoice output — 10 enriched lines |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
ORDER 10006: PRODUCT 99999 NOT FOUND.
ORDER 10010: PRODUCT 88888 NOT FOUND.
========================================
INVOICE GENERATION SUMMARY
========================================
TOTAL ORDERS PROCESSED:    12
TOTAL INVOICES CREATED:    10
TOTAL ERRORS:               2
========================================
```

---

## How to Run

1. **Define VSAM cluster** — run [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load [`DATA/PROD.MASTER.VSAM`](DATA/PROD.MASTER.VSAM) into the KSDS cluster either via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF
3. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ACCESS MODE IS RANDOM` on KSDS — enables direct lookup by key without scanning the file sequentially; each `READ` goes straight to the record matching the key field
- Random read pattern — `MOVE key-value TO vsam-key-field` then `READ vsam-file` (no `KEY IS` clause needed when the key is already in the FD record area)
- `FILE STATUS IS` — two-character code set after every I/O operation; must be checked explicitly since COBOL does not raise an exception on `'23'` (record not found) by default
- `EVALUATE TRUE` on status — cleaner than nested `IF`; handles `'00'`, `'23'`, and unexpected statuses in one block
- `COMPUTE` with `V99` (implicit decimal) — `UNIT-PRICE PIC 9(5)V99` stores price as integer internally (e.g., `0002050` = 20.50); `COMPUTE` handles the decimal alignment automatically
- `Z(6).99` edited picture — suppresses leading zeros in the output total cost; `205.00` not `000205.00`
- `COMP-3` (packed decimal) for `WS-TOTAL-COST` — efficient internal format for arithmetic on mainframe; no performance cost for `COMPUTE`
- Three separate `FILE STATUS` variables — `VSAM-STATUS`, `ORDERS-STATUS`, `OUT-STATUS` — one per file; avoids one status overwriting another during the same paragraph

---

## Notes

- The VSAM file must be opened as `INPUT` with `ACCESS MODE IS RANDOM` — `DYNAMIC` would also work for random reads, but `RANDOM` is sufficient here since no sequential scan is needed
- The key is placed into the `PRODUCT-ID` field inside the `FD` record area (`VSAM-REC`) before each `READ` — this is the standard COBOL random read pattern; there is no separate `KEY IS` clause on the `READ` statement when the primary key is used
- `FILE STATUS '23'` means the record was not found — the program logs it and continues; this is intentional (not a fatal error) because invalid orders should not stop the batch
- Any other non-zero VSAM status (e.g., `'97'` — open error, `'92'` — logic error) is treated as fatal and causes `STOP RUN`
- `WS-TOTAL-COST` is declared as `COMP-3` — packed decimal is the standard for arithmetic fields on IBM z/OS; it reduces storage and speeds up decimal operations
- Tested on IBM z/OS with Enterprise COBOL
