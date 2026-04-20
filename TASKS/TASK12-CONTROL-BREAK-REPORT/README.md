# Task 12 — Multi-Level Sales Report (Control Break / Level Break)

## Overview

Reads a pre-sorted sequential PS sales file (`SALES.DATA`) and generates a formatted report (`SALES.REPORT`) with **three levels of totals**: shop subtotal → region subtotal → grand total.
The core technique is the **Control Break algorithm**: the program detects when the sort key changes (region or shop), flushes the current subtotal to the report, resets the accumulator, and continues.
No VSAM, no DB2 — pure sequential processing with holder variables.

---

## Critical Prerequisite: Input Must Be Pre-Sorted

> **[`SALES.DATA`](DATA/SALES.DATA) must be sorted by `SALES-REGION` (ASC), then `SALES-SHOP` (ASC) before this program runs.**

The program does **not** validate sort order. Unsorted input will silently produce wrong subtotals and a wrong grand total — no error message, no ABEND. Use a `SORT` step in the JCL **before** the program step ([`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) already includes this step).

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `PSSDD` | `SALES.DATA` | PS | INPUT | Pre-sorted sales records — region, shop, amount; LRECL=80, RECFM=F |
| `REPDD` | `SALES.REPORT` | PS | OUTPUT | Formatted report with detail lines, shop/region subtotals, grand total; LRECL=80, RECFM=F |

### Input Record Layout (`PSSDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `SALES-REGION` | `X(5)` | 1 | **Major sort key** — region code (e.g. `NORTH`, `SOUTH`, `EAST `, `WEST `) |
| `SALES-SHOP` | `X(5)` | 6 | **Minor sort key** — shop code within region (e.g. `SHOP1`, `SHOP2`) |
| `SALES-AMOUNT` | `9(5)V99` | 11 | Sale amount — implicit 2 decimal places, 7 digits packed as 7 characters |
| FILLER | `X(63)` | 18 | Padding to 80 bytes |

### Output (`REPDD`)

The report file contains plain text lines (80-byte fixed records):

| Line type | Format | Example |
|---|---|---|
| Detail line | `RECORD: <REGION> <SHOP>: <AMOUNT>` | `RECORD: NORTH SHOP1: 100.00` |
| Shop subtotal | `   --> SUM FOR SHOP: <AMOUNT>` | `   --> SUM FOR SHOP: 150.00` |
| Region subtotal | `====== TOTAL FOR <REGION>: <AMOUNT> (SHOPS: <N>)` | `====== TOTAL FOR NORTH: 350.00 (SHOPS: 2)` |
| Separator | *(blank line)* | |
| Grand total block | `********************************` / `GRAND TOTAL SALES: <AMOUNT>` | `GRAND TOTAL SALES: 2250.00` |
| Statistics | `REGIONS: <N>` / `TOTAL SHOPS: <N>` / `TOTAL RECORDS: <N>` | `REGIONS: 4` |

---

## Control Break Logic

This is the **most important concept** in this task. The algorithm works because the input is sorted — all records for the same shop are grouped together, and all shops for the same region are grouped together.

### Holder Variables

Two Working-Storage variables remember the **previous** sort key values:

| Variable | Initialized from | Purpose |
|---|---|---|
| `PREV-REGION` | First record read | Detects when region changes (Level 1 / major break) |
| `PREV-SHOP` | First record read | Detects when shop changes (Level 2 / minor break) |

### Break Hierarchy

```
Level 1 (MAJOR) — Region break
    └── Level 2 (MINOR) — Shop break
```

When a **major break** fires (region changes), the minor break **must also fire first** — the old shop ended at the same time as the old region.
When a **minor break** fires alone (shop changes, region stays), only the shop total is printed.

### Algorithm Walkthrough

```
1. OPEN files
2. READ first record
   ├── EOF → exit (empty file)
   └── OK  → MOVE SALES-REGION TO PREV-REGION
              MOVE SALES-SHOP    TO PREV-SHOP
              accumulate + print detail line for record 1
3. PERFORM UNTIL EOF
   │
   ├─ IF SALES-REGION ≠ PREV-REGION   (Level 1 break)
   │    ├── PERFORM PRINT-SHOP-TOTAL    ← flush shop first!
   │    ├── PERFORM PRINT-REGION-TOTAL  ← flush region
   │    ├── MOVE SALES-REGION TO PREV-REGION
   │    ├── MOVE SPACES TO PREV-SHOP    ← force shop break on next record
   │    └── reset SHOP-COUNT
   │
   ├─ IF SALES-SHOP ≠ PREV-SHOP      (Level 2 break)
   │    ├── PERFORM PRINT-SHOP-TOTAL
   │    ├── write blank separator line
   │    ├── MOVE SALES-SHOP TO PREV-SHOP
   │    └── increment SHOP-COUNT
   │
   ├─ ADD SALES-AMOUNT TO TOTAL-SHOP
   ├─ ADD SALES-AMOUNT TO TOTAL-REGION
   ├─ print detail line
   └─ READ next record

4. AT END-OF-FILE (inside AT END branch):
   ├── PERFORM PRINT-SHOP-TOTAL    ← flush last shop
   ├── PERFORM PRINT-REGION-TOTAL  ← flush last region
   └── print GRAND TOTAL + statistics
```

> **Why read the first record separately?**
> The holders (`PREV-REGION`, `PREV-SHOP`) must be seeded from real data before the loop starts.
> If the file is empty the program exits cleanly. If the first read used `VALUE SPACES` as the seed,
> the very first record would always trigger a false break and print a zero shop/region total.

### PRINT-SHOP-TOTAL Guard (`IF TOTAL-SHOP > 0`)

On a region break, the program calls `PRINT-SHOP-TOTAL` **and then** `PRINT-REGION-TOTAL`.
`PRINT-REGION-TOTAL` resets `TOTAL-REGION` to zero.
If the next region also starts a new shop immediately, `PRINT-SHOP-TOTAL` would be called again with an empty accumulator.
The guard `IF TOTAL-SHOP > 0` prevents printing a `SUM FOR SHOP: 0.00` line in that situation.

---

## Program Flow

1. **PERFORM OPEN-ALL-FILES** — opens `PSSDD` (INPUT) and `REPDD` (OUTPUT); non-`'00'` status → `DISPLAY` error + `STOP RUN`

2. **PERFORM INIT-FIRST-RECORD**
   - `READ SALES-DATA-FILE AT END SET EOF TO TRUE`
   - If OK: seeds `PREV-REGION`, `PREV-SHOP`; initializes `REGION-COUNT = 1`, `SHOP-COUNT = 1`
   - If file empty: `EOF` is set, main logic skips `PROCESS-SALES`

3. **PERFORM PROCESS-FIRST-RECORD** *(only if NOT EOF)*
   - Increments `REC-COUNTER`
   - Adds `SALES-AMOUNT` to `TOTAL-SHOP` and `TOTAL-REGION`
   - Formats detail line via `STRING` and `WRITE`

4. **PERFORM PROCESS-SALES** — `PERFORM UNTIL EOF` loop:
   - `READ SALES-DATA-FILE AT END SET EOF → PERFORM PRINT-FINAL-TOTALS`
   - `NOT AT END → PERFORM PROCESS-SALES-RECORD`

5. **PROCESS-SALES-RECORD**
   - Increment `REC-COUNTER`
   - Level 1 check: `IF SALES-REGION NOT = PREV-REGION` → flush shop + region, update holders
   - Level 2 check: `IF SALES-SHOP NOT = PREV-SHOP` → flush shop, write blank separator, update holders
   - Accumulate amounts, format and write detail line

6. **PRINT-SHOP-TOTAL** — prints `--> SUM FOR SHOP: <TOTAL-SHOP>`; resets `TOTAL-SHOP` to zero; guarded by `IF TOTAL-SHOP > 0`

7. **PRINT-REGION-TOTAL** — prints `====== TOTAL FOR <PREV-REGION>: <TOTAL-REGION> (SHOPS: <SHOP-COUNT>)`; adds `TOTAL-REGION` to `GRAND-TOTAL`; resets `TOTAL-REGION` to zero; writes blank separator

8. **PRINT-FINAL-TOTALS** — called from `AT END` branch:
   - Flushes last shop and last region (same calls as during the loop)
   - Prints `GRAND TOTAL SALES`, `REGIONS`, `TOTAL SHOPS`, `TOTAL RECORDS`

9. **PERFORM CLOSE-ALL-FILES** — close errors are warnings only (no `STOP RUN`)

10. `STOP RUN`

---

## Test Data

Input and expected output are in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`SALES.DATA`](DATA/SALES.DATA) | 12 sorted sales records across 4 regions, 2 shops each |
| [`SALES.REPORT`](DATA/SALES.REPORT) | Expected report output |

---

## How to Run

1. Upload [`DATA/SALES.DATA`](DATA/SALES.DATA) to your mainframe dataset manually through option '3.4 and edit your dataset' or
2. Submit [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) — it includes a SORT step before the program step

> **PROC reference:** [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system’s `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- **Control Break (Level Break) pattern** — the classic sequential-file technique for grouped reports; requires sorted input and holder variables; widely used in mainframe batch reporting to this day
- **Holder variables** (`PREV-REGION`, `PREV-SHOP`) — store the key values from the *previous* record; a break is detected when `CURRENT-KEY ≠ PREV-KEY`; after printing the subtotal, the holder is updated to the new key
- **Break hierarchy rule** — on a major (region) break, the minor (shop) break **must fire first**; the old shop ended at the same time; failing to do this produces a shop subtotal that combines the last shop of one region with the first shop of the next
- **First-record priming read** — the program reads record 1 separately before the loop to seed `PREV-REGION` and `PREV-SHOP` from real data; this avoids a false break on the very first iteration that would print a zero subtotal
- **End-of-file flush** — the `AT END` branch calls `PRINT-FINAL-TOTALS`, which explicitly flushes the last shop and last region; without this step the last group’s totals are never printed — the most common Control Break bug
- **`TOTAL-SHOP > 0` guard in `PRINT-SHOP-TOTAL`** — prevents printing a `SUM FOR SHOP: 0.00` line when `PRINT-SHOP-TOTAL` is called twice in a row (once from a region break and then again when the next shop change is detected with an empty accumulator)
- **`MOVE SPACES TO PREV-SHOP` after region break** — after updating `PREV-REGION`, `PREV-SHOP` is forced to spaces so that the very next record (first record of the new region) always triggers a shop break and correctly increments `SHOP-COUNT` for the new region
- **`STRING ... DELIMITED BY SIZE ... INTO`** — builds variable-length report lines by concatenating literal text, field values, and `FUNCTION TRIM()` results into `OUTPUT-LINE`; `DELIMITED BY SIZE` copies the entire sending field including trailing spaces, `FUNCTION TRIM()` removes them
- **`FUNCTION TRIM()`** — removes leading and trailing spaces from a field before appending to the string; used here so that edited numeric output (`DISP-AMOUNT`) does not leave gaps in the report line
- **`Z(4)9.99` and `Z(6)9.99` edited pictures** — zero-suppress leading digits and insert the decimal point; `DISP-AMOUNT` handles shop and region totals up to 99999.99; `DISP-GRAND` handles the grand total up to 9999999.99

---

## Notes

- The program processes exactly **two sort levels** (region → shop); adding a third level (e.g. salesperson within shop) would require a third holder variable, a third accumulator, and a third break check inside the loop — the same pattern applied one more time
- `SALES-REGION` is `X(5)` — values like `EAST` and `WEST` are stored with a trailing space (`EAST `, `WEST `) to fill 5 characters; this is why the report shows `EAST ` and `WEST ` in the region total line
- The SORT step in the JCL sorts on bytes 1–10 (region + shop, both ascending); if your test data is already sorted you can bypass the sort step, but leaving it in is harmless and safer
- Tested on IBM z/OS with Enterprise COBOL
