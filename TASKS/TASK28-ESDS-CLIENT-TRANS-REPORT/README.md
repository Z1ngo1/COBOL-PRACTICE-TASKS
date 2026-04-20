# Task 28 — Transaction Journal (ESDS) + Client Report

## Overview

Processes a client list (PS) and for each client performs a full sequential scan of a transaction log (VSAM ESDS) to calculate financial totals. This task demonstrates the specificity of **ESDS (Entry-Sequenced Data Set)**: since records have no keys, individual account lookups require a full file scan from beginning to end.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `ACCT` | `ACCT.LIST` | PS | INPUT | List of client IDs to process |
| `AS-TRNS` | `TRANS.LOG.ESDS` | ESDS | INPUT | Sequential transaction log |
| `ACCTREP` | `ACCT.REPORT` | PS | OUTPUT | Final report with debit/credit totals and net |

### Input Record Layout — `ACCT.LIST` (80 bytes)

| Field | Picture | Offset | Description |
|---|---|---|---|
| `ACCT-LIST-ID` | `X(6)` | 1 | Client Identifier |
| `FILLER` | `X(74)` | 7 | Padding |

### Input Record Layout — `TRANS.LOG.ESDS` (100 bytes)

| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(6)` | 1 | Client Identifier |
| `TRANS-DATE` | `X(8)` | 7 | Transaction Date (YYYYMMDD) |
| `TRANS-TYPE` | `X(1)` | 15 | 'D' for Debit, 'C' for Credit |
| `TRANS-AMOUNT` | `9(7)V99` | 16 | Transaction Amount |
| `FILLER` | `X(56)` | 25 | Padding |

---

## Business Logic

The program processes accounts sequentially from a master list. For each account, it must traverse the entire transaction history stored in an ESDS file.

1. **Outer Loop**: Read `ACCT.LIST` (PS).
2. **Inner Loop**: For each `ACCT-ID`:
    - **Open** `TRANS.LOG.ESDS` for sequential input.
    - **Read Next** until EOF.
    - If `TRANS-ACCT-ID` matches `WS-ACCT-ID`:
        - If Type = 'D' (Debit) -> Add to `WS-TOTAL-DEBIT`.
        - If Type = 'C' (Credit) -> Add to `WS-TOTAL-CREDIT`.
    - **Close** `TRANS.LOG.ESDS` (Preparing for the next client scan).
3. **Report Generation**:
    - **Net Result** = Total Credit - Total Debit.
    - **Status**:
        - Both totals = 0 -> `NO TRANS`
        - Any total != 0 -> `OK`
    - Write report line: `ACCT-ID`, `DEBIT`, `CREDIT`, `NET`, `STATUS`.

---

## Program Flow

1. **MAIN-LOGIC**: Initializes files and starts the master processing loop.
2. **READ-ACCT-LIST**: Sequentially reads the client list and triggers account processing.
3. **PROCESS-TRANS-LOG**: 
    - Resets totals for the current client.
    - Opens the ESDS file.
    - Performs the full sequential scan.
    - Closes the ESDS file.
4. **COMPUTE-NET-STATUS**: Calculates financial results and determines the report status.
5. **WRITE-ACCT-REPORT**: Formats and writes the summary line to the output PS file.

---

## Key COBOL + VSAM Concepts Used

- **VSAM ESDS (Entry-Sequenced Data Set)**: Records are stored in arrival order. No key access is possible; access is strictly sequential or via RBA (Relative Byte Address).
- **Nested I/O Operations**: Opening and closing a file within a loop to perform multiple sequential passes.
- **Financial Accumulation**: Using `COMP-3` (Packed Decimal) for efficient financial calculations with implied decimal points.
- **STRING Statement**: Dynamically building a variable-length report line for the output PS file.

---

## Notes

- **Performance Tip**: In a real-world scenario with millions of records, this "O(N*M)" approach (scanning the entire ESDS for every client) would be inefficient. One would typically use a KSDS or an AIX (Alternate Index) for direct access, or sort both files by ID to use a single-pass Merge logic. However, this task focuses on understanding **pure ESDS sequential behavior**.
- **Error Handling**: The program stops immediately (`STOP RUN`) if any mandatory file fails to open or read (Status != '00').
