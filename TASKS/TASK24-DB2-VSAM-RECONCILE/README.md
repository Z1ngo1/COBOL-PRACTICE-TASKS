# Task 24 — Balance Reconciliation (DB2 + VSAM + Sequential)

## Overview
Reconciles end-of-day account balances across three different sources to ensure data integrity. The program flags accounts where the current DB2 balance does not match the sum of yesterday's VSAM balance and today's transactions from a sequential file.

The core technique is **Three-Way Reconciliation**:
1.  **Phase 1**: Load yesterday's balances from a VSAM KSDS into an in-memory table.
2.  **Phase 2**: Apply today's transactions (Credits/Debits) from a PS file to the memory table.
3.  **Phase 3**: Compare the calculated "Expected" balance against the "Actual" balance in the DB2 `TB_ACCOUNTS` table.
4.  **Phase 4**: Identify "Orphan" records (present in DB2 but not in VSAM, or vice versa).

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `VSAMDD` | `ACCT.BACKUP` | KSDS | INPUT | Yesterday's balances (ID, Balance, Date) |
| `TRNSDD` | `TRANS.LOG` | PS | INPUT | Today's transaction log (ID, Type, Amount) |
| `REPDD` | `RECON.REPORT` | PS | OUTPUT | Detailed reconciliation report with status (OK/FAIL) |

## DB2 Objects
- **Table**: `TB_ACCOUNTS`
- **Columns**: `ACCOUNT_ID` (CHAR 6), `BALANCE` (DECIMAL 11,2)

---

## Input Record Layouts

### VSAM KSDS (`VSAMDD`) - LRECL=74, RECFM=F
| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ACCT-ID` | `X(6)` | 1 | Account ID (Primary Key) |
| `VSAM-YBAL` | `9(9)V99` | 7 | Yesterday's balance |
| `VSAM-BDATE` | `9(8)` | 18 | Backup date (YYYYMMDD) |

### Transaction Log (`TRNSDD`) - LRECL=80, RECFM=F
| Field | Picture | Offset | Description |
|---|---|---|---|
| `TRANS-ACCT-ID` | `X(6)` | 1 | Account ID |
| `TRANS-TYPE` | `X(1)` | 7 | 'C' (Credit) or 'D' (Debit) |
| `TRANS-AMT` | `9(7)V99` | 8 | Transaction amount |

---

## Output Report Layout (`REPDD`) - LRECL=120, RECFM=V
The report contains a header, detailed lines for each account, and a statistics footer.

**Sample Output Line:**
```text
ACCOUNT   YESTERDAY   TODAY-TRNS   EXPECTED      ACTUAL     STATUS      DIFF
100001     5000.00      +200.00     5200.00     5200.00     OK        +0.00
100002     1500.00      -500.00     1000.00     1100.00     FAIL    +100.00
NOT IN VSAM(BUT IN DB2): 100005
NOT IN DB2 (BUT IN VSAM/PS): 100009
```

---

## How to Run
1.  **Initialize DB2**: Run the SQL script in `SQL/CREATE.TABLE.sql` to setup the test table.
2.  **Upload Data**: Upload `DATA/ACCT.BACKUP` and `DATA/TRANS.LOG` to your mainframe.
3.  **Submit JCL**: Submit `JCL/COBDB2CP.jcl`.

---

## Key COBOL + DB2 Concepts Used
*   **In-Memory Table (`OCCURS 100`)**: Stores VSAM records for fast lookup during transaction processing.
*   **Three-Way Match**: Synchronizes data across VSAM, PS, and DB2.
*   **DB2 Cursor**: Used to scan the entire DB2 table to find accounts missing from the VSAM backup.
*   **Status Codes**: Handles both File Status (VSAM/PS) and SQLCODE (DB2) for robust error management.

---

## Notes
*   **Memory Limit**: The current program is limited to 100 accounts in memory. For production, a dynamic approach or a DB2-to-DB2 comparison might be used.
*   **Transaction Integrity**: 'C' (Credit) adds to the balance, 'D' (Debit) subtracts. Any other code is logged as an error.
*   **Precision**: Uses `COMP-3` for financial calculations to maintain decimal precision.
