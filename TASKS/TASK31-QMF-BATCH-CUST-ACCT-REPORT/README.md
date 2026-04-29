# Task 31 — QMF Batch Customer Account Report

## Overview

Runs two QMF queries against DB2 tables in batch mode using the QMF batch executor (`DSQQMFE`). Query 1 counts active customers grouped by region and segment. Query 2 calculates total balances and account counts per account type and region, joining `T_ACCOUNT` and `T_CUSTOMER`. Both query outputs are exported to PS datasets, then merged and assembled into a single dated final report using DFSORT. There is no COBOL program in this task — the entire pipeline is driven by JCL, a QMF PROC, QMF queries, and QMF forms.

---

## DB2 Tables

### [`T_CUSTOMER`](SQL/CREATE.T_CUSTOMER.sql)

```sql
CREATE TABLE T_CUSTOMER (
   CUST_ID   CHAR(6)      NOT NULL,
   CUST_NAME VARCHAR(40),
   REGION    CHAR(2),
   SEGMENT   CHAR(1),
   STATUS    CHAR(1),
   PRIMARY KEY(CUST_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `CUST_ID` | `CHAR(6)` | **Primary key** |
| `CUST_NAME` | `VARCHAR(40)` | Customer name |
| `REGION` | `CHAR(2)` | Region code |
| `SEGMENT` | `CHAR(1)` | Customer segment |
| `STATUS` | `CHAR(1)` | `A` (Active) or `I` (Inactive) |

### [`T_ACCOUNT`](SQL/CREATE.T_ACCOUNT.sql)

```sql
CREATE TABLE T_ACCOUNT (
   ACCT_ID   CHAR(8)        NOT NULL,
   CUST_ID   CHAR(6)        NOT NULL,
   ACCT_TYPE CHAR(2),
   BALANCE   DECIMAL(11,2),
   OPEN_DATE DATE,
   PRIMARY KEY(ACCT_ID)
) IN DATABASE Z73460;
```

| Column | Type | Description |
|---|---|---|
| `ACCT_ID` | `CHAR(8)` | **Primary key** |
| `CUST_ID` | `CHAR(6)` | Foreign key → `T_CUSTOMER` |
| `ACCT_TYPE` | `CHAR(2)` | Account type code |
| `BALANCE` | `DECIMAL(11,2)` | Current balance |
| `OPEN_DATE` | `DATE` | Account open date |

---

## QMF Objects

### QMF PROC — [`TASK31P.proc`](QMF/PROС/TASK31P.proc)

The QMF PROC is the entry point invoked by `DSQQMFE` at startup via `I=TASK31P`. It runs both queries in sequence and exports their results to PS datasets.

```
RUN QUERY Z73460.Q1TASK31 (FORM=Z73460.Q1TASK31F)
EXP TO 'Z73460.TASK31.QUERY1' (DATAFORMAT = TEXT)
---
RUN QUERY Z73460.Q2TASK31 (FORM=Z73460.Q2TASK31F)
EXP TO 'Z73460.TASK31.QUERY2' (DATAFORMAT = TEXT)
```

### QMF Queries

| Object | File | Description |
|---|---|---|
| `Q1TASK31` | [`Q1TASK31.sql`](QMF/QUERY/Q1TASK31.sql) | Count of active customers by `REGION`, `SEGMENT` |
| `Q2TASK31` | [`Q2TASK31.sql`](QMF/QUERY/Q2TASK31.sql) | Total balance and account count by `ACCT_TYPE`, `REGION` (JOIN) |

**Query 1:**
```sql
SELECT REGION, SEGMENT, COUNT(*) AS CUSTOMET_COUNT
FROM T_CUSTOMER
WHERE STATUS = 'A'
GROUP BY REGION, SEGMENT
ORDER BY REGION, SEGMENT;
```

**Query 2:**
```sql
SELECT A.ACCT_TYPE, C.REGION,
       SUM(A.BALANCE) AS TOTAL_BALANCE,
       COUNT(*)        AS ACCT_COUNT
FROM   T_ACCOUNT A
JOIN   T_CUSTOMER C ON A.CUST_ID = C.CUST_ID
WHERE  C.STATUS = 'A'
GROUP BY A.ACCT_TYPE, C.REGION
ORDER BY A.ACCT_TYPE, C.REGION;
```

### QMF Forms

| Object | File | Description |
|---|---|---|
| `Q1TASK31F` | [`Q1TASK31F.form`](QMF/FORM/Q1TASK31F.form) | Column headers and formatting for Query 1 output |
| `Q2TASK31F` | [`Q2TASK31F.form`](QMF/FORM/Q2TASK31F.form) | Column headers and formatting for Query 2 output |

---

## JCL Pipeline

The job [`DB2PROC.jcl`](JCL/DB2PROC.jcl) runs the full pipeline in four steps:

| Step | PGM | Description |
|---|---|---|
| `STEP005` | `IEFBR14` | Delete work datasets from previous run |
| `STEP010` | `DSQQMFE` | Run QMF batch proc `TASK31P`; exports `QUERY1` and `QUERY2` |
| `STEP015` | `SORT` | Write section header for Query 1 as VB file to GDG `(+1)` via `FTOV` |
| `STEP020` | `SORT` | Write section header for Query 2 as VB file to GDG `(+2)` via `FTOV` |
| `STEP025` | `SORT` | Merge all four parts into `SORTED.REPORT`; convert VB→FB via `VTOF`, strip carriage control, add dated header |

**DSQQMFE startup parameters:**
```
PARM='M=B,S=DBDG,P=QMFD10,I=TASK31P'
```

| Parameter | Value | Meaning |
|---|---|---|
| `M=B` | BATCH | Run QMF in batch mode (no interactive terminal) |
| `S=DBDG` | DBDG | DB2 subsystem name to connect to |
| `P=QMFD10` | QMFD10 | Precompiled DB2 application plan for QMF |
| `I=TASK31P` | TASK31P | Initial QMF PROC to execute on startup |

---

## Output Files

All intermediate and final files are stored in the [`DATA/`](DATA/) folder:

| Dataset | Description |
|---|---|
| [`QUERY1`](DATA/QUERY1) | QMF text export of Query 1 (customer counts by region/segment) |
| [`QUERY2`](DATA/QUERY2) | QMF text export of Query 2 (balances by account type/region) |
| [`QMF.GDG.G0001V00`](DATA/QMF.GDG.G0001V00) | GDG generation `(+1)` — VB separator header for Query 1 |
| [`QMF.GDG.G0002V00`](DATA/QMF.GDG.G0002V00) | GDG generation `(+2)` — VB separator header for Query 2 |
| [`SORTED.REPORT`](DATA/SORTED.REPORT) | Final merged and dated report |
| [`TB.T_ACCOUNT`](DATA/TB.T_ACCOUNT) | INPUT DATA FROM T_ACCOUNT TABLE |
| [`TB.T_CUSTOMER`](DATA/TB.T_CUSTOMER) | INPUT DATA FROM T_CUSTOMER TABLE |


---

## How to Run

1. **Define GDG base** — run [`DEFGDG.jcl`](JCL/DEFGDG.jcl) to allocate the GDG base `Z73460.TASK31.QMF.GDG`
2. **Create DB2 tables and load data** — run SQL from [`SQL/`](SQL/) folder: [`CREATE.T_CUSTOMER.sql`](SQL/CREATE.T_CUSTOMER.sql), [`CREATE.T_ACCOUNT.sql`](CREATE.T_ACCOUNT.sql), then INSERT scripts [`INSERT.T_CUSTOMER.sql`](SQL/INSERT.T_CUSTOMER.sql), [`INSERT.T_ACCOUNT.sql`](INSERT.T_ACCOUNT.sql)
3. **Import QMF objects into QMF catalog** — load `TASK31P.proc`, `Q1TASK31.sql`, `Q2TASK31.sql`, `Q1TASK31F.form`, `Q2TASK31F.form` into QMF using `SAVE` or ISPF QMF panels
4. **Run the pipeline** — submit [`DB2PROC.jcl`](JCL/DB2PROC.jcl)
5. **Review output** — see [`DATA/SORTED.REPORT`](DATA/SORTED.REPORT)

---

## Key QMF + JCL Concepts Used

- **`DSQQMFE` batch executor** — QMF has no COBOL program; the entire report generation is driven by invoking the QMF batch program with `M=B` (batch mode), connecting it to DB2 via plan `QMFD10` and a startup PROC `I=TASK31P`
- **QMF PROC as orchestrator** — `TASK31P.proc` replaces COBOL `PROCEDURE DIVISION`; the `---` separator between `RUN QUERY` commands is the QMF statement delimiter that sequences multiple operations in one PROC
- **`EXP TO ... (DATAFORMAT=TEXT)`** — exports QMF query results to a z/OS PS dataset as formatted text using the layout defined in the associated FORM; this is what bridges QMF output to standard JCL datasets
- **GDG for section headers** — section separator lines (plain text) are written as VB files into GDG generations `(+1)` and `(+2)` using `FTOV` conversion, so they can later be merged in order with the VB query output
- **DFSORT `VTOF` + `REMOVECC`** — the final SORT step converts all VB parts back to fixed-length records with `VTOF`, strips QMF carriage control characters with `REMOVECC`, and injects a dated header line using `HEADER1=(DATE=(MD4/),'@',TIME)`
- **`IEFBR14` cleanup step** — `STEP005` deletes all intermediate work datasets from the previous run before any new data is written; without this, `DISP=(NEW,CATLG)` on subsequent steps would fail with a duplicate dataset error

---

## Notes

- There is no COBOL program in this task — the full pipeline is JCL + QMF PROC + QMF queries + DFSORT; this is a pure QMF batch reporting pattern used in production mainframe environments
- QMF FORM objects (`Q1TASK31F`, `Q2TASK31F`) control column headers, widths, and totals in the exported text; they must be saved in the QMF catalog under the correct owner before the batch job runs
- The GDG base must exist before the job is submitted — `DEFGDG.jcl` creates it; if the base is missing, STEP015 and STEP020 will fail with a JCL error on the `(+1)` / `(+2)` references
- The `---` separator in `TASK31P.proc` is a QMF-specific statement delimiter — it is not a comment and must appear exactly as-is between `RUN QUERY` blocks; omitting it causes the second query to be ignored
- Tested on IBM z/OS with QMF 10 and DB2
