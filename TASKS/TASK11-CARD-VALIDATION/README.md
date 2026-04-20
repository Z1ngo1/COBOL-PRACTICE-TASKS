# Task 11 — Credit Card Transaction Validation (VSAM KSDS Random Read + PS Split)

## Overview

Reads a sequential PS transactions file (`TRANS.DAILY`), performs a **random read** into a VSAM KSDS card master (`CARD.MASTER`) for each transaction, and runs three consecutive validation checks:
**existence → status → expiry date**.
Transactions that pass all checks are written to `APPROVED.FILE`; any failure routes the transaction to `DECLINED.FILE` with a reason code (`NOT FOUND`, `BLOCKED`, or `EXPIRED`).
The program obtains the current date from the operating system at startup — no hardcoded dates.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `CARD.MASTER` | VSAM KSDS | INPUT / RANDOM | Card master — owner name, expiry date (MMYY), status; key = `CARD-NUMBER` |
| `TRNSDD` | `TRANS.DAILY` | PS | INPUT | Daily transactions — trans ID, card number, amount; LRECL=80, RECFM=F |
| `APRVDD` | `APPROVED.FILE` | PS | OUTPUT | Approved transactions — trans ID, card number, amount; LRECL=80, RECFM=F |
| `DECLDD` | `DECLINED.FILE` | PS | OUTPUT | Declined transactions — trans ID, card number, amount, reason; LRECL=80, RECFM=F |

### VSAM Record Layout (`VSAMDD`) — LRECL=41

| Field | Picture | Offset | Description |
|---|---|---|---|
| `CARD-NUMBER` | `9(16)` | 1 | **Primary key** — 16-digit card number |
| `CARD-OWNER-NAME` | `X(20)` | 17 | Cardholder full name |
| `CARD-EXPIRY-DATE` | `X(4)` | 37 | Expiry date in **MMYY** format |
| `CARD-STATUS` | `X(1)` | 41 | `A` = Active, `B` = Blocked |

### Transaction Record Layout (`TRNSDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ID` | `X(5)` | 1 | Transaction number |
| `TRANS-CARD-NUM` | `9(16)` | 6 | Card number to look up in VSAM |
| `TRANS-AMOUNT` | `9(5)V99` | 22 | Transaction amount (implicit 2 decimal places) |
| FILLER | `X(52)` | 29 | Padding to 80 bytes |

### Approved Record Layout (`APRVDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `APPROVED-TRANS-ID` | `X(5)` | 1 | Transaction number |
| FILLER | `X(1)` | 6 | Space |
| `APPROVED-CARD-NUM` | `9(16)` | 7 | Card number |
| FILLER | `X(1)` | 23 | Space |
| `APPROVED-AMOUNT` | `$$$$9.99` | 24 | Amount, currency-edited |
| FILLER | `X(49)` | 32 | Padding to 80 bytes |

### Declined Record Layout (`DECLDD`) — LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `DECLINED-TRANS-ID` | `X(5)` | 1 | Transaction number |
| FILLER | `X(1)` | 6 | Space |
| `DECLINED-CARD-NUM` | `9(16)` | 7 | Card number |
| FILLER | `X(1)` | 23 | Space |
| `DECLINED-AMOUNT` | `$$$$9.99` | 24 | Amount, currency-edited |
| FILLER | `X(1)` | 32 | Space |
| `DECLINE-REASON` | `X(10)` | 33 | `NOT FOUND`, `BLOCKED`, or `EXPIRED` |
| FILLER | `X(38)` | 43 | Padding to 80 bytes |

---

## Validation Logic

Each transaction goes through **three checks in sequence**. The first failure immediately routes the record to `DECLINED.FILE` — remaining checks are skipped.

### Check 1 — Card Existence (VSAM FILE STATUS)

| VSAM Status | Meaning | Action |
|---|---|---|
| `'23'` | Card not found in VSAM | Decline — reason: `NOT FOUND` |
| `'00'` | Card found | Proceed to Check 2 |
| Other | I/O error | `DISPLAY` critical error + `STOP RUN` |

### Check 2 — Card Status Field

| `CARD-STATUS` | Meaning | Action |
|---|---|---|
| `'B'` | Card is blocked | Decline — reason: `BLOCKED` |
| `'A'` (or other) | Card is active | Proceed to Check 3 |

### Check 3 — Expiry Date (MMYY format)

`CARD-EXPIRY-DATE` is stored as 4 characters: positions 1–2 = `MM`, positions 3–4 = `YY`.
The program extracts `WS-CUR-YY` from the system date (`YYYY` → last 2 digits via reference modification `(3:2)`).

| Condition | Meaning | Action |
|---|---|---|
| `WS-CARD-YY < WS-CUR-YY` | Expired year | Decline — reason: `EXPIRED` |
| `WS-CARD-YY = WS-CUR-YY` AND `WS-CARD-MM < WS-CUR-MM` | Same year, past month | Decline — reason: `EXPIRED` |
| `WS-CARD-YY = WS-CUR-YY` AND `WS-CARD-MM >= WS-CUR-MM` | Valid through end of current month | **Approve** |
| `WS-CARD-YY > WS-CUR-YY` | Future year | **Approve** |

> A card expiring `02/26` (MMYY = `0226`) is **valid** if the current month is February 2026 — it expires at the end of that month, not at the start.

---

## Program Flow

1. **PERFORM INIT-PROCESS**
   - `ACCEPT WS-CUR-DATE-GROUP FROM DATE YYYYMMDD` — reads system date into `YYYY`, `MM`, `DD` sub-fields
   - `MOVE WS-CUR-YYYY(3:2) TO WS-CUR-YY` — extracts 2-digit year for comparison
   - Displays current date and comparison values to SYSOUT

2. **PERFORM OPEN-ALL-FILES**
   - Opens all four files; any non-`'00'` status → `DISPLAY` error + `STOP RUN`

3. **PERFORM READ-TRANS-LOOP**
   - `PERFORM UNTIL EOF`
   - `MOVE SPACES` to both output records before each iteration (prevents data bleeding between writes)
   - `READ DAILY-TRANS-FILE AT END SET EOF TO TRUE`
   - If `TRANS-STATUS = '00'` → increment `TOTAL-TRANSACTIONS` → **PERFORM PROCESS-TRANSACTION**
   - Else → `DISPLAY` read error + `STOP RUN`

4. **PROCESS-TRANSACTION**
   - `MOVE TRANS-CARD-NUM TO CARD-NUMBER` — places lookup key into VSAM FD field
   - `READ CARD-MASTER-FILE` (random)
   - `'23'` → `MOVE 'NOT FOUND' TO WS-DECLINE-REASON` → **WRITE-DECLINED-TRANS**
   - `'00'` → **PERFORM VALIDATE-STATUS**
   - Other → `DISPLAY` critical error + `STOP RUN`

5. **VALIDATE-STATUS**
   - `IF CARD-STATUS = 'B'` → `MOVE 'BLOCKED'` → **WRITE-DECLINED-TRANS**
   - Else → **PERFORM VALIDATE-EXPIRY**

6. **VALIDATE-EXPIRY**
   - `MOVE CARD-EXPIRY-DATE(1:2) TO WS-CARD-MM`
   - `MOVE CARD-EXPIRY-DATE(3:2) TO WS-CARD-YY`
   - Year/month comparison (see Check 3 table above)
   - Expired → **WRITE-DECLINED-TRANS** / Valid → **WRITE-APPROVED-TRANS**

7. **WRITE-APPROVED-TRANS** — moves fields to `APPROVED-REC`, `WRITE`, checks `APPROVED-STATUS`, increments `TOTAL-APPROVED`

8. **WRITE-DECLINED-TRANS** — moves fields + reason to `DECLINED-REC`, `WRITE`, checks `DECLINED-STATUS`, increments `TOTAL-DECLINED` + specific breakdown counter (`TOTAL-NOT-FOUND` / `TOTAL-BLOCKED` / `TOTAL-EXPIRED`) via `EVALUATE`

9. **PERFORM CLOSE-ALL-FILES** — closes all four files; errors are warnings only (no `STOP RUN`)

10. **PERFORM DISPLAY-SUMMARY** — prints totals with decline breakdown to SYSOUT

11. `STOP RUN`

---

## Test Data

Input data and expected output are stored in the [`DATA/`](DATA/) folder:

| File | Description |
|---|---|
| [`DATA/CARD.MASTER`](DATA/CARD.MASTER) | 8 card records loaded into VSAM KSDS |
| [`DATA/TRANS.DAILY`](DATA/TRANS.DAILY) | 9 transaction records |
| [`DATA/APPROVED.FILE`](DATA/APPROVED.FILE) | Expected approved output — 2 records |
| [`DATA/DECLINED.FILE`](DATA/DECLINED.FILE) | Expected declined output — 7 records with reason codes |

---

## Expected SYSOUT

Actual job output is stored in [`OUTPUT/SYSOUT.txt`](OUTPUT/SYSOUT.txt).

```
CURRENT DATE: 2026/02/23
COMPARE YEAR:  26
COMPARE MONTH: 02
========================================
CARD VALIDATION SUMMARY
========================================
TOTAL TRANSACTIONS:     9
APPROVED:               2
DECLINED:               7
  NOT FOUND:            2
  BLOCKED:              2
  EXPIRED:              3
========================================
```
---

## How to Run

1. **Define VSAM cluster** — run [`JCL/DEFKSDS.jcl`](JCL/DEFKSDS.jcl)
2. **Load initial master data** — load [`DATA/CARD.MASTER`](DATA/CARD.MASTER) into the KSDS cluster either via REPRO (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)) or manually through **File Manager** in ISPF
3. **Compile and run** — run [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl)

> **PROC reference:** [`JCL/COMPRUN.jcl`](JCL/COMPRUN.jcl) uses the [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) catalogued procedure for compilation and execution. Make sure [`MYCOMPGO`](../../JCLPROC/MYCOMPGO.jcl) is available in your system's `PROCLIB` before submitting.

---

## Key COBOL Concepts Used

- `ACCEPT ... FROM DATE YYYYMMDD` — reads the system date in 8-digit format (`YYYYMMDD`) directly into a group item split into `YYYY`, `MM`, `DD` sub-fields; no manual string parsing needed
- Reference modification `(3:2)` — `WS-CUR-YYYY(3:2)` extracts characters 3–4 from the 4-digit year to get the 2-digit `YY` for comparison with the MMYY expiry field; the full syntax is `data-name(start:length)`
- `ACCESS MODE IS RANDOM` on KSDS — each `READ` performs a direct keyed lookup; `MOVE key TO vsam-key-field` before `READ` is the standard pattern (no `KEY IS` clause needed when using the primary key)
- `FILE STATUS '23'` — record not found; not a fatal error, the program continues and logs the decline reason
- `MOVE SPACES TO output-record` before each loop iteration — prevents stale data from a previous write bleeding into the next output record, especially important when two different output records (`APPROVED-REC` / `DECLINED-REC`) share the same loop
- `$$$$9.99` edited picture — floating dollar sign suppresses leading zeros and prints `$100.00` instead of `0000100.00`; the number of `$` signs sets the maximum field width
- `EVALUATE WS-DECLINE-REASON` in `WRITE-DECLINED-TRANS` — increments the correct breakdown counter (`TOTAL-NOT-FOUND` / `TOTAL-BLOCKED` / `TOTAL-EXPIRED`) without nested `IF`; one `EVALUATE` handles all three reason codes cleanly
- Four separate `FILE STATUS` variables (`CARD-FILE-STATUS`, `TRANS-STATUS`, `APPROVED-STATUS`, `DECLINED-STATUS`) — one per file; prevents one file's status from overwriting another's within the same paragraph
- Close errors as warnings — `CLOSE` failures print a `WARNING:` message but do not `STOP RUN`; data is already written, so a close error is non-fatal and the summary still prints

---

## Notes

- The expiry comparison is done in **YY** (2-digit year), not YYYY — this is consistent with the MMYY format stored in `CARD-EXPIRY-DATE`; a 4-digit year is unnecessary since all cards in practice span a narrow window around the current year
- A card with `MMYY = 0226` run on `2026/02/23` is **approved** — the card is valid through the end of February; it would only be declined if the current month were March 2026 or later
- `CARD-STATUS = 'B'` is checked **before** expiry — a blocked card is declined immediately regardless of its expiry date; this matches real-world authorization logic (a blocked card cannot be used even if technically not expired)
- `CARD-STATUS = 'A'` is not explicitly tested — the program falls to the `ELSE` branch of `IF CARD-STATUS = 'B'`, so any non-`B` status is treated as active; this is intentional for simplicity
- Transactions for cards not in VSAM (`STATUS '23'`) are declined as `NOT FOUND` and never reach the status or expiry checks — the checks are a strict cascade, not parallel tests
- Tested on IBM z/OS with Enterprise COBOL; run date was `2026/02/23`
