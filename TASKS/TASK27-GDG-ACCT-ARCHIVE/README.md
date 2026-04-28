Task 27 — GDG Lifecycle Management (Account Archiving)
======================================================

Overview
--------

Batch COBOL program that processes a daily account file (PS), cross-references transaction history in a VSAM KSDS, and automatically partitions records into one of three Generation Data Groups (GDGs) based on their activity status. The program implements a dynamic 180-day retention policy to distinguish between active and stagnant accounts, while separately capturing orphaned records that have no historical footprint.

Files
-----

| DD Name | File | Org | Mode | Description |
| :--- | :--- | :--- | :--- | :--- |
| `INPSDD` | [`ACCT.DATA`](DATA/ACCT.DATA) | PS | INPUT | Daily account input, RECFM=F, LRECL=58 |
| `VSAMDD` | [`ACCT.HISTORY.VSAM`](DATA/ACCT.HISTORY.VSAM) | KSDS | INPUT | Historical master file, Random access by ACCT-ID |
| `GDGDD1` | [`ACCT.ACTIVE.GDG.G0001V00`](DATA/ACCT.ACTIVE.GDG.G0001V00) | GDG | OUTPUT | Active accounts (last txn within 180 days), LRECL=48 |
| `GDGDD2` | [`ARCHIVE.OLD.GDG.G0001V00`](DATA/ARCHIVE.OLD.GDG.G0001V00) | GDG | OUTPUT | Stagnant accounts (last txn > 180 days ago), LRECL=48 |
| `GDGDD3` | [`UNMATCH.GDG.G0001V00`](DATA/UNMATCH.GDG.G0001V00) | GDG | OUTPUT | Orphaned accounts (not in VSAM), LRECL=48 |
| `REPPSDD` | [`PROCESS.REPORT`](DATA/PROCESS.REPORT) | PS | OUTPUT | Processing summary, RECFM=V, LRECL=54 |

### Input Record Layout — (`INPSDD`), LRECL=58, RECFM=F

| Field | Picture | Offset | Description |
| :--- | :--- | :--- | :--- |
| `DATA-ACCT-ID` | `X(6)` | 1 | Account Identifier |
| `DATA-CUST-NAME` | `X(25)` | 7 | Customer Name |
| `DATA-LAST-ACTV-DATE` | `9(8)` | 32 | Last activity date (YYYYMMDD) |
| `DATA-BALANCE` | `9(7)V99` | 40 | Account balance |
| `FILLER` | `X(10)` | 49 | Padding |

### VSAM Record Layout — (`VSAMDD`), KSDS, Key=1–6

| Field | Picture | Offset | Description |
| :--- | :--- | :--- | :--- |
| `HIST-ACCT-ID` | `X(6)` | 1 | **Primary Key** — Account ID |
| `HIST-LAST-TRNS-DATE` | `9(8)` | 7 | Last transaction date in history |
| `HIST-TRNS-COUNT` | `9(4)` | 15 | Total transaction count |

### Output GDG Layout — (`GDGDD1/2/3`), LRECL=48, RECFM=F

| Field | Picture | Description |
| :--- | :--- | :--- |
| `OUT-ACCT-ID` | `X(6)` | Account Identifier |
| `OUT-CUST-NAME` | `X(25)` | Customer Name |
| `OUT-LAST-ACTV-DATE` | `9(8)` | Last activity date |
| `OUT-BALANCE` | `9(7)V99` | Account balance |

Business Logic
--------------

The program performs temporal classification and routing in three phases:

### Phase 1 — History Cross-Reference
For each record in the daily input, the program performs a random read of the `ACCT.HISTORY.VSAM` file using the Account ID.
*   • **Not Found (Status '23')**: The record is classified as \"Orphaned\" and routed to the Unmatched GDG.
*   • **Found (Status '00')**: The program retrieves the historical transaction date and proceeds to Phase 2.

### Phase 2 — Temporal Retention Analysis
The program calculates a **Cutoff Date** (Today - 180 Days) using COBOL intrinsic functions `INTEGER-OF-DATE` and `DATE-OF-INTEGER`.
*   • **Active**: If `HIST-LAST-TRNS-DATE >= Cutoff`, the account is considered current.
*   • **Archive**: If `HIST-LAST-TRNS-DATE < Cutoff`, the account is flagged for archiving.

### Phase 3 — Generation Routing
Records are written to their respective GDG generation (`+1` in JCL):
*   • **Active GDG**: Current business-as-usual accounts.
*   • **Archived GDG**: Stagnant accounts moved to long-term storage.
*   • **Unmatched GDG**: Exception records for data integrity investigation.

Program Flow
------------

*   1\. **INITIALIZE**: Calculate dynamic cutoff date (Current - 180 days); zero out counters.
*   2\. **OPEN**: Open PS Input, VSAM KSDS, and three GDG output files; verify FILE STATUS.
*   3\. **PROCESS LOOP**: Read `ACCT.DATA` until EOF:
    *   ◦ **PERFORM CHECK-ACCT-HIST** — Random read of VSAM Master.
    *   ◦ **ON STATUS '23'** — Increment `UNMATCH-COUNT`, call `WRITE-UNMATCHED`.
    *   ◦ **ON FOUND** — Compare `HIST-LAST-TRNS-DATE` to Cutoff.
    *   ◦ **IF >= CUTOFF** — Increment `ACTIVE-COUNT`, call `WRITE-ACTIVE`.
    *   ◦ **IF < CUTOFF** — Increment `ARCHIVE-COUNT`, call `WRITE-ARCHIVE`.
*   4\. **FINAL-REPORT**: Write summary counts and processing status to `PROCESS.REPORT`.
*   5\. **RETURN-CODE**: Set RC=0 (Clean), RC=4 (<10 Unmatched), or RC=12 (10+ Unmatched).
*   6\. **CLOSE**: Close all files and terminate.

Return Codes
------------

| RC | Condition | Severity |
| :--- | :--- | :--- |
| `0` | Clean execution, no unmatched records | Success |
| `4` | Unmatched records count < 10 | Warning |
| `12` | Unmatched records count >= 10 | Critical (Data Integrity Issue) |

Test Data
---------

| File | Description |
| :--- | :--- |
| [`ACCT.DATA`](DATA/ACCT.DATA) | Input containing mix of active, old, and non-existent Account IDs |
| [`ACCT.HISTORY.VSAM`](DATA/ACCT.HISTORY.VSAM) | Master history KSDS used for date comparisons |
| [`ACCT.ACTIVE.GDG.G0001V00`](DATA/ACCT.ACTIVE.GDG.G0001V00) | Resulting generation for active accounts |
| [`ARCHIVE.OLD.GDG.G0001V00`](DATA/ARCHIVE.OLD.GDG.G0001V00) | Resulting generation for archived accounts |
| [`UNMATCH.GDG.G0001V00`](DATA/UNMATCH.GDG.G0001V00) | Resulting generation for unmatched accounts |
| [`PROCESS.REPORT`](DATA/PROCESS.REPORT) | Summary showing counts for Active, Archived, and Unmatched pools |

How to Run
----------

*   1\. **Define GDGs** — Submit [`DEFGDG.jcl`](JCL/DEFGDG.jcl) to define the base clusters for Active, Archive, and Unmatch generations.
*   2\. **Setup VSAM** — Submit [`DEFKSDS.jcl`](JCL/DEFKSDS.jcl) to initialize the history KSDS.
*   3\. **Load VSAM Data** — Submit [`DATAVSAM.jcl`](../../JCL%20SAMPLES/DATAVSAM.jcl) to populate the historical master file with initial test data.
*   4\. **Execute Batch** — Submit [`COMPRUN.jcl`](JCL/COMPRUN.jcl). This JCL handles data generation, compilation, and the execution step using `GDG (+1)` logic.
*   5\. **Verify Results** — Check summary counts in [`PROCESS.REPORT`](DATA/PROCESS.REPORT) and verify generation versioning in the GDG clusters.

Key Concepts Used
-----------------

*   • **Multi-GDG Routing** — Manages three simultaneous generation updates (`GDGDD1/2/3`) in a single execution pass.
*   • **Dynamic Temporal Partitioning** — Automates the 180-day lifecycle window by calculating the cutoff at runtime using intrinsic functions.
*   • **Tri-State Lifecycle Logic** — Implements a record state machine: *Active* (Operational), *Stagnant* (Archived), or *Orphaned* (Unmatched).
*   • **Generation Integrity** — Exception records (unmatched) are preserved in versioned GDGs for forensic audit trails.
*   • **LRECL Compaction** — Demonstrates data trimming during the archiving process (Input 58 -> Output 48).

Notes
-----

*   • **Input-to-Output Mapping** — The program acts as a router; it does not modify the data content except for removing trailing fillers during the routing phase.
*   • **Date Logic** — Cutoff is calculated based on the system date at the moment of execution.
*   • **Error Threshold** — The RC=12 threshold is specifically designed to catch large-scale synchronization failures between the daily feed and the master history.
