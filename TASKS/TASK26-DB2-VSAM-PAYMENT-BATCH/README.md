# Task 26 — Robust Batch Processing (Error Handling + Return Codes)

## Overview

Batch COBOL program that processes a payment input file (PS), validates each record, looks up the customer account in VSAM, and updates the customer balance in the DB2 table `TB_CUSTOMER_BALANCE`. The program is designed for maximum robustness, implementing multi-level error handling and returning a specific job return code based on the severity and count of encountered errors.

---

## DB2 Table

### [`TB_CUSTOMER_BALANCE`](SQL/CREATE.TABLE.sql)

```sql
CREATE TABLE TB_CUSTOMER_BALANCE (     
   CUST_ID CHAR(5) NOT NULL,           
   CUST_BALANCE DECIMAL(9,2),          
   LAST_PAYMENT TIMESTAMP WITH DEFAULT,
   PRIMARY KEY (CUST_ID)               
) IN DATABASE Z73460;            
```

| Column | Type | Description |
|---|---|---|
| `CUST_ID` | `CHAR(5)` | **Primary key** — Customer identifier |
| `CUST_BALANCE` | `DECIMAL(9,2)` | Current account balance |
| `LAST_PAYMENT` | `TIMESTAMP` | Timestamp of the last successful payment update |

---

## Files

| DD Name | File | Org | Mode | Description |
|---|---|---|---|---|
| `INPDD` | [`PAYMENTS`](DATA/PAYMENT.INPUT) | PS | INPUT | Payment transaction records, RECFM=F, LRECL=80 |
| `VSAMDD` | `CUSTOMER.MST` | KSDS | INPUT | Customer master for account status check |
| `LOGDD` | `PAYMENT.LOG` | PS | OUTPUT | Detailed processing log with summary, RECFM=V, LRECL=80 |

### Input Record Layout — `PAYMENTS` (`INPDD`), LRECL=80, RECFM=F

| Field | Picture | Offset | Description |
|---|---|---|---|
| `PAYMENT-ID` | `X(6)` | 1 | Unique payment identifier |
| `PMT-CUST-ID` | `X(5)` | 7 | Customer ID to match VSAM/DB2 |
| `PMT-AMOUNT` | `9(5)V99` | 12 | Payment amount (must be > 0) |
| `PAYMENT-TYPE` | `X(1)` | 19 | `C` = Credit, `T` = Transfer, `A` = Adjustment |
| `FILLER` | `X(61)` | 20 | Unused padding |

### VSAM Record Layout — `CUSTOMER.MST` (`VSAMDD`), KSDS, Key=1–5

| Field | Picture | Offset | Description |
|---|---|---|---|
| `VSAM-ID` | `X(5)` | 1 | **Primary key** — Customer ID |
| `VSAM-CUST-NAME` | `X(25)` | 6 | Full name for logging |
| `VSAM-ACCT-STATUS` | `X(1)` | 31 | `A` = Active, `S` = Suspended |

---

## Business Logic: Robust Four-Level Processing

The program implements a hierarchical error handling strategy. Any level failure increments counters and may trigger a job return code escalation.

### Level 1 — Validation of Input Data

Checks the basic integrity of the `PAYMENTS` record:
- **`PAYMENT-ID`** must not be spaces.
- **`PMT-AMOUNT`** must be greater than zero.
- **`PAYMENT-TYPE`** must be one of `C` (Credit), `T` (Transfer), or `A` (Adjustment).
- *Failure*: logs "VALIDATION ERROR", increments `SKIP-COUNT`, proceeds to next record.

### Level 2 — VSAM Lookup

Performs a random read of `CUSTOMER.MST` by `PMT-CUST-ID`:
- **Status `23` (Not Found)**: logs "NOT FOUND", increments `SKIP-COUNT`, proceeds to next.
- **Other non-zero status**: logs "VSAM ERROR", increments `ERROR-COUNT`, issues `ROLLBACK`, sets `RC=12`, and stops the loop.

### Level 3 — Account Status Check

If VSAM record exists, checks `VSAM-ACCT-STATUS`:
- **`S` (Suspended)**: logs "ACCOUNT SUSPENDED", increments `SKIP-COUNT`, proceeds to next.
- **`A` (Active)**: proceeds to DB2 update.

### Level 4 — DB2 Update

Updates `CUST_BALANCE` and `LAST_PAYMENT` in `TB_CUSTOMER_BALANCE`:
- **SQLCODE `0` (Success)**: increments `SUCCESS-COUNT`, logs success.
- **SQLCODE `-911` (Deadlock)**: logs "DEADLOCK", increments `ERROR-COUNT`, issues `ROLLBACK`, sets `RC=12`, and stops the loop.
- **Any other negative SQLCODE**: logs code, increments `ERROR-COUNT`, issues `ROLLBACK`, sets `RC=8`, and stops the loop.

---

## Return Code Logic (Finalization)

The job return code (RC) is set based on processing outcomes:

| Severity | Condition | Final RC | Description |
|---|---|---|---|
| **High** | Fatal VSAM/DB2 error or Deadlock | **12** | Program stopped early; partial rollback executed |
| **High** | DB2 update error | **8** | Program stopped early; partial rollback executed |
| **Medium** | `ERROR-COUNT > 10` | **16** | Too many processing errors; investigate data quality |
| **Low** | `ERROR-COUNT > 0` | **4** | Completed with minor errors/warnings |
| **Success** | `ERROR-COUNT = 0` | **0** | Clean execution |

---

## Program Flow

1. `OPEN-PARA` — open `PAYMENTS` (INPUT), `CUSTOMER.MST` (INPUT), `PAYMENT.LOG` (OUTPUT); check FILE STATUS
2. `INITIALIZE-PARA` — zero counters, set `RETURN-CODE = 0`
3. `READ-PS-PARA` — main loop until EOF or `WS-ERROR`:
   - 3.1. `READ PAYMENT-FILE`
   - 3.2. **Level 1**: check spaces, amount, and type; if fail → log, skip
   - 3.3. **Level 2**: `READ VSAM-FILE` by key; if status 23 → log, skip; if other error → log, `ROLLBACK`, `RC=12`, stop
   - 3.4. **Level 3**: check status; if 'S' → log, skip
   - 3.5. **Level 4**: `EXEC SQL UPDATE`; if SQLCODE 0 → log success; if -911 → `ROLLBACK`, `RC=12`, stop; if other negative → `ROLLBACK`, `RC=8`, stop
4. `FINAL-PARA` — if `RC` still 0, evaluate `ERROR-COUNT` to set final RC (0, 4, or 16)
5. `FINAL-LOG` — write summary footer and counters to `PAYMENT.LOG`
6. `CLOSE-PARA` — `EXEC SQL COMMIT WORK` (if no fatal error); close files
7. `STOP RUN`

---

## SQL Handling

| Scenario | SQLCODE | Logic Branch |
|---|---|---|
| Update Successful | `0` | Log success; increment `SUCCESS-COUNT` |
| Deadlock / Timeout | `-911` | Log error; `ROLLBACK`; `RC=12`; `STOP RUN` |
| Any other error | `< 0` | Log code; `ROLLBACK`; `RC=8`; `STOP RUN` |

---

## Test Data

All input and output files are in the [`DATA/`](DATA/) folder.

| File | Description |
|---|---|
| [`DATA/PAYMENT.INPUT`](DATA/PAYMENT.INPUT) | PS input — test payments with valid and invalid records |
| [`DATA/VSAM.ACCOUNTS`](DATA/VSAM.ACCOUNTS) | VSAM KSDS — customer statuses (Active/Suspended) |
| [`DATA/TB.TB_CUSTOMER_BALANCE`](DATA/TB.TB_CUSTOMER_BALANCE) | DB2 table image — balance before and after updates |

---

## Expected SYSOUT (PAYMENT.LOG)

```text
000001 SUCCESS: PAYMENT PROCESSED
000002 VALIDATION ERROR: INVALID PAYMENT RECORD
000003 NOT FOUND: CUSTOMER ID 99999
000004 ACCOUNT SUSPENDED: PAYMENT REJECTED
-------------------------------------
TOTAL PROCESSED: 4
SUCCESSFUL:      1
ERRORS:          0
SKIPPED:         3
RETURN CODE:     0
```

---

## How to Run

1. Execute SQL in [`SQL/CREATE.TABLE.sql`](SQL/CREATE.TABLE.sql) to create `TB_CUSTOMER_BALANCE`
2. Upload test data to your mainframe datasets
3. Submit [`JCL/COBDB2CP.jcl`](JCL/COBDB2CP.jcl) to run the batch process

---

## Key COBOL + DB2 Concepts Used

- **Tiered Error Handling** — systematic validation at each stage (Input → VSAM → Logic → DB2)
- **Dynamic Return Codes** — using `RETURN-CODE` to signal job status to the scheduler/JCL
- **VSAM Random Read** — `ACCESS MODE IS RANDOM` used for status checks by key
- **Atomic Updates** — `UPDATE ... SET ... WHERE` ensures balance changes are atomic
- **Deadlock Handling** — explicit check for SQLCODE `-911` with controlled termination
- **Structured Variable-Length Logging** — `RECFM=V` log file for detailed transaction auditing
- **`TIMESTAMP` updates** — using DB2 `CURRENT TIMESTAMP` for audit trail tracking

---

## Notes

- The program stops the loop (`SET WS-ERROR TO TRUE`) on any fatal VSAM or DB2 error to prevent further data corruption
- `SUCCESS-COUNT` only increments if the DB2 update returns SQLCODE `0`
- `SKIP-COUNT` tracks records that failed validation, status checks, or were missing from VSAM
- Tested on IBM z/OS with DB2 and Enterprise COBOL
