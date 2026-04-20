# Task 28 — Transaction Journal (ESDS) + Client Report

## Overview
This task demonstrates sequential processing of a VSAM Entry-Sequenced Data Set (ESDS). The program reads a master list of client IDs and, for each client, performs a full scan of the transaction journal to calculate total debits, total credits, and the net balance.

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `ACCT` | `ACCT.LIST` | PS | INPUT | List of client IDs to process |
| `AS-TRNS` | `TRANS.LOG.ESDS` | ESDS | INPUT | Sequential transaction log |
| `ACCTREP` | `ACCT.REPORT` | PS | OUTPUT | Final report with debit/credit totals and net |

---

## Record Layouts

### Input: `ACCT.LIST` (80 bytes)
| Field | Picture | Offset | Description |
|---|---|---|---|
| `ACCT-LIST-ID` | `X(6)` | 1 | Client Identifier |
| `FILLER` | `X(74)` | 7 | Padding |

### Input: `TRANS.LOG.ESDS` (100 bytes)
| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(6)` | 1 | Client Identifier |
| `TRANS-DATE` | `X(8)` | 7 | Transaction Date (YYYYMMDD) |
| `TRANS-TYPE` | `X(1)` | 15 | 'D' for Debit, 'C' for Credit |
| `TRANS-AMOUNT` | `9(7)V99` | 16 | Transaction Amount |
| `FILLER` | `X(56)` | 25 | Padding |

### Output: `ACCT.REPORT` (133 bytes)
| Field | Picture | Offset | Description |
|---|---|---|---|
| `R-CLIENT-ID` | `X(6)` | 1 | Client ID |
| `FILLER` | `X(1)` | 7 | Space |
| `R-TOTAL-DEBIT` | `ZZZ9.99` | 8 | Total Debits |
| `FILLER` | `X(1)` | 15 | Space |
| `R-TOTAL-CREDIT`| `ZZZ9.99` | 16 | Total Credits |
| `FILLER` | `X(1)` | 23 | Space |
| `R-NET-BAL` | `+ZZZ9.99` | 24 | Net Balance with Sign |
| `FILLER` | `X(1)` | 32 | Space |
| `R-STATUS` | `X(8)` | 33 | \"OK\" or \"NO TRANS\" |

---

## Business Logic

1. **Client Processing (Outer Loop)**:
   - Read each client ID from `ACCT.LIST`.
   - Initialize accumulators (`WS-TOTAL-DEBIT`, `WS-TOTAL-CREDIT`) to zero.
2. **Transaction Scan (Inner Loop)**:
   - **Open** `TRANS.LOG.ESDS` for sequential input.
   - Read the entire file from start to finish.
   - If `TRANS-ACCT-ID` matches the current client, add the amount to the corresponding accumulator based on `TRANS-TYPE`.
   - **Close** `TRANS.LOG.ESDS` after the scan (this resets the file pointer for the next client).
3. **Reporting**:
   - Calculate `NET-BALANCE = CREDIT - DEBIT`.
   - If both totals are zero, set status to `NO TRANS`, otherwise `OK`.
   - Format and write the record to `ACCT.REPORT`.

---

## Program Flow

*   **MAIN-LOGIC**: Controls the high-level flow (Open -> Read -> Close).
*   **READ-ACCT-LIST**: Outer loop reading the master list of client IDs.
*   **PROCESS-TRANS-LOG**: Inner loop managing the ESDS file lifecycle (Open, Scan, Close).
*   **COMPUTE-NET-STATUS**: Performs financial calculations and determines the line status.
*   **WRITE-ACCT-REPORT**: Formats and writes the summary line using the `STRING` statement.

---

## Test Data & Expected Results

### Input: `ACCT.LIST`
```
100001
100002
100003
```

### Input: `TRANS.LOG.ESDS`
```
100001 20260101 C 000150000 (Credit +1500.00)
100001 20260105 D 000050000 (Debit  -500.00)
100002 20260110 C 000200000 (Credit +2000.00)
```

### Expected Output (`ACCT.REPORT`)
```
100001  500.00 1500.00 +1000.00 OK
100002    0.00 2000.00 +2000.00 OK
100003    0.00    0.00   +0.00 NO TRANS
```

---

## Key COBOL + VSAM Concepts
- **VSAM ESDS**: Records are processed in the order they were written. Since there is no index, searching for specific records requires a full file scan.
- **Nested File Operations**: Demonstrates re-opening a file inside a loop to reset the sequential access pointer.
- **Financial Editing**: Using sign-sensitive pictures (`+ZZZ9.99`) and zero suppression for clean reports.
- **Complexity**: Note that this approach is **O(N*M)**, where N is clients and M is transactions.

---

## How to Run
1. **Define ESDS**: Submit `DEFESDS.jcl` to create the VSAM cluster.
2. **Prepare Data**: Load test records into `ACCT.LIST` and `TRANS.LOG.ESDS`.
3. **Execution**: Run the job `ESDS28`.
4. **Verification**: Verify the results in the `ACCTREP` output dataset.
