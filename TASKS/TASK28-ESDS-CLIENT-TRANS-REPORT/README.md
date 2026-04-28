Task 28 — ESDS Transaction Log & Client Reporting
==============================================

Overview
--------

Batch COBOL program that processes a transaction log stored in a VSAM ESDS (Entry Sequenced Data Set). Since ESDS files do not support key-based access, the program performs a full sequential scan of the entire log for every client listed in a PS input file. It calculates total debits, total credits, and a net balance for each client, generating a summary report.

Files
-----

| DD Name | File | Org | Mode | Description |
| :--- | :--- | :--- | :--- | :--- |
| `ACCT` | [`ACCT.LIST`](DATA/ACCT.LIST) | PS | INPUT | List of Client IDs to report on, LRECL=80 |
| `AS-TRNS` | [`TRANS.LOG.ESDS`](DATA/TRANS.LOG.ESDS) | ESDS | INPUT | Sequential transaction log, LRECL=80 |
| `ACCTREP` | [`ACCT.REPORT`](DATA/ACCT.REPORT) | PS | OUTPUT | Client summary report, RECFM=VB, LRECL=64 |

### Input Record Layout — (`ACCT`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
| :--- | :--- | :--- | :--- |
| `ACCT-LIST-ID` | `X(6)` | 1 | Client Account Identifier |
| `FILLER` | `X(74)` | 7 | Padding |

### ESDS Record Layout — (`AS-TRNS`), LRECL=80

| Field | Picture | Offset | Description |
| :--- | :--- | :--- | :--- |
| `TRANS-ACCT-ID` | `X(6)` | 1 | Account ID linked to transaction |
| `TRANS-DATE` | `X(8)` | 7 | Transaction Date (YYYYMMDD) |
| `TRANS-TYPE` | `X(1)` | 15 | Type: `D` (Debit) or `C` (Credit) |
| `TRANS-AMOUNT` | `9(7)V99` | 16 | Transaction Amount |
| `FILLER` | `X(56)` | 25 | Padding |

### Report Record Layout — (`ACCTREP`), LRECL=60, RECFM=VB

| Field | Picture | Description |
|---|---|---|
| `ACCT-REPORT-REC` | `X(80)` | One line per operation |

Business Logic
--------------

The program operates on the core principle of sequential log processing, where data is accessed in the order it was written.

### Phase 1 — Client Enumeration
The program reads the `ACCT.LIST` file sequentially. For every `ACCT-ID` found, it initiates a dedicated processing cycle.

### Phase 2 — Nested ESDS Scan (Per Client)
For each specific client, the program resets its internal accumulators and performs a complete pass of the `TRANS.LOG.ESDS`:
*   • **OPEN**: The ESDS file is opened for `INPUT`.
*   • **READ**: Every record is read from top to bottom.
*   • **MATCH**: If the `TRANS-ACCT-ID` matches the current client being processed:
    *   ◦ If `TRANS-TYPE = 'D'`, the amount is added to `WS-TOTAL-DEBIT`.
    *   ◦ If `TRANS-TYPE = 'C'`, the amount is added to `WS-TOTAL-CREDIT`.
*   • **CLOSE**: The ESDS file is closed once the end-of-file is reached.

### Phase 3 — Net Calculation & Status
After the scan, the program computes the `NET-BALANCE`:
*   • `NET = TOTAL-CREDIT - TOTAL-DEBIT`.
*   • If both totals are zero, the status is set to `NO TRANS`.
*   • Otherwise, the status is set to `OK`.

Program Flow
------------

*   1\. **INITIALIZE**: Open `ACCT.LIST` (PS) and `ACCT.REPORT` (PS).
*   2\. **OUTER LOOP**: Read `ACCT.LIST` until EOF:
    *   ◦ Reset `WS-TOTAL-DEBIT`, `WS-TOTAL-CREDIT`, and buffers.
    *   ◦ **INNER LOOP (PROCESS-TRANS-LOG)**:
        *   ▪ Open `TRANS.LOG.ESDS`.
        *   ▪ Read ESDS sequentially until EOF.
        *   ▪ Accumulate values for matching `ACCT-ID`.
        *   ▪ Close ESDS.
    *   ◦ Calculate `WS-NET`.
    *   ◦ **WRITE-REPORT**: Format and write result line to `ACCTREP`.
*   3\. **TERMINATE**: Close PS files and end program.

Return Codes
------------

| RC | Condition | Severity |
| :--- | :--- | :--- |
| `0` | Successful generation of all requested client reports | Success |
| `Non-Zero` | File status error on PS or ESDS files | Fatal |

Test Data
---------

| File | Description |
| :--- | :--- |
| [`ACCT.LIST`](DATA/ACCT.LIST) | Input PS file with client IDs (e.g., A00001, A00002) |
| [`TRANS.LOG.ESDS`](DATA/TRANS.LOG.ESDS) | ESDS file containing a mixed history of transactions for various clients |
| [`ACCT.REPORT`](DATA/ACCT.REPORT) | Generated report showing the calculated totals per client |

How to Run
----------

1. **Define ESDS** — Submit [`DEFESDS.jcl`](JCL/DEFESDS.jcl) to define the VSAM ESDS cluster.
2. **Load Log** — Use a REPRO or custom JCL to load transaction data into the ESDS (see [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl)).
3. **Execute Job** — Submit [`COMPRUN.jcl`](JCL/COMPRUN.jcl). This JCL generates the client list, compiles the program, and executes the reporting logic.
4. **Check Output** — Review the resulting [`ACCT.REPORT`](DATA/ACCT.REPORT) dataset.

Key Concepts Used
-----------------

• **Entry Sequenced Access** — Demonstrates the fundamental "log-style" nature of ESDS where records are retrieved sequentially without keys.  
• **Nested File Processing** — Uses a multi-pass approach (re-opening/re-scanning the same file for different criteria).  
• **Accumulation Logic** — Classic batch reporting pattern: Reset -> Accumulate -> Report.  
• **Computational Efficiency Trade-offs** — While O(N*M) complexity is used here for training, it highlights the need for indexing (KSDS) or sorting in production scenarios.  
• **Variable-Length Report Formatting** — Uses `VB` file organization to handle report lines efficiently.  

Notes
-----

• **Performance** — Re-scanning the ESDS for *every* client is an intentional exercise to emphasize ESDS sequential-only characteristics.  
• **Transaction Integrity** — Any transaction type other than 'D' or 'C' is ignored by the logic to ensure data robustness.  
• **Data Source** — The ESDS is opened as `INPUT` only, ensuring the transaction log remains immutable during the report generation.  
• Tested on IBM z/OS with DB2 and Enterprise COBOL  
