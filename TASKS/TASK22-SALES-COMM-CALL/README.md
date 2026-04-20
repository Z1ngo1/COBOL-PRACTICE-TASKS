# Task 22: Sales Commission with Subprogram Calls

## Overview
This task demonstrates the modularity of COBOL by implementing a Sales Commission Payout System. The system consists of a main program that coordinates the processing and two specialized subprograms for calculation logic.
1.  **Main Program (`JOBSUB22`)**: Reads employee sales records, calls subprograms, and generates the final payout report.
2.  **Commission Subprogram (`SUB1JB22`)**: Calculates commission rates based on geographical region and total sales volume.
3.  **Tax Subprogram (`SUB2JB22`)**: Calculates the tax amount based on the calculated commission brackets.

## Files
- `COBOL/JOBSUB22.cbl`: Main driver program.
- `COBOL/SUB1JB22.cbl`: Subprogram 1 - Commission Calculator (COMMCALC logic).
- `COBOL/SUB2JB22.cbl`: Subprogram 2 - Tax Calculator (TAXCALC logic).
- `JCL/COMPRUN.jcl`: Job to create input data, compile all components, and execute the system.
- `DATA/SALES.txt`: (Defined in JCL) Sequential input file with sales data.
- `OUTPUT/COMM.PAYOUT`: Generated report showing commission, tax, and net payout.

## Record Layouts
### Input Sales Record (`SALES.DATA`) — LRECL=80
| Field | Position | Format | Description |
| :--- | :--- | :--- | :--- |
| `EMP-ID` | 1-5 | `X(5)` | Employee Identifier |
| `REGION` | 6-7 | `X(2)` | Sales Region (NY, CA, TX, etc.) |
| `SALES-AMT`| 8-15 | `9(6)V99`| Total Sales Amount |
| `FILLER` | 16-80 | `X(65)` | Reserved |

## Processing Logic
### 1. Commission Calculation (`SUB1JB22`)
Calculates the commission amount based on the following rules:
- **Base Rate by Region**:
    - `NY`: 5%
    - `CA`: 7%
    - `TX`: 3%
    - Others: 4%
- **Volume Bonus**:
    - Sales >= $100,000: +2% bonus rate
    - Sales >= $50,000: +1% bonus rate
- **Formula**: `Commission = Sales * (Base Rate + Bonus Rate)`

### 2. Tax Calculation (`SUB2JB22`)
Calculates the tax to be deducted from the commission:
- Commission < $1,000: 15% tax
- $1,000 <= Commission < $5,000: 20% tax
- Commission >= $5,000: 25% tax

### 3. Output Generation
The main program computes the Net Payout (`Commission - Tax`) and writes a formatted line to the output file.

## JCL Steps
- **`STEP005`**: Deletes previous output and input datasets.
- **`STEP010`**: Uses `IEBGENER` to populate the `SALES.DATA` file with sample records.
- **`STEP015`**: Compiles the main program and subprograms, links them, and executes the final module.

## Key COBOL Concepts Used
- **Inter-Program Communication**: Using `CALL ... USING` to pass data between programs via the `LINKAGE SECTION`.
- **Modular Design**: Separating business rules (commission/tax) from I/O processing.
- **`EVALUATE` Statement**: Handling multiple conditions for regions and tax brackets efficiently.
- **`STRING` with `FUNCTION TRIM`**: Building formatted output lines dynamically.

## How to Run
1.  Verify the dataset names in `JCL/COMPRUN.jcl` match your environment.
2.  Submit the JCL to compile and run the entire suite.
3.  Check `Z73460.TASK22.COMM.PAYOUT` for the results.

## Notes
- Ensure all subprograms are compiled and accessible to the main program's load module at runtime.
- The system handles invalid regions by applying a default 4% base rate.
- Tested on IBM z/OS.
