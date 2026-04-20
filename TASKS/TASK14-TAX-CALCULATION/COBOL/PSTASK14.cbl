      ******************************************************************
      * TABLE LOOKUP ALGORITHM - TAX CALCULATION WITH IN-MEMORY TABLE  *
      *                                                                *
      * PURPOSE:                                                       *
      * CALCULATES EMPLOYEE TAXES USING REGION-BASED TAX RATES LOADED  *
      * INTO MEMORY. DEMONSTRATES IN-MEMORY TABLE LOOKUP (OCCURS       *
      * CLAUSE) FOR EFFICIENT PROCESSING OF LARGE FILES.               *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - LOAD: READ TAX-RATES-FILE INTO TAX-TABLE (MAX 50). *
      *   PHASE 2 - PROCESS: FOR EACH EMPLOYEE RECORD:                 *
      *     LOOKUP EMP-REGION-CODE IN TAX-TABLE (LINEAR SEARCH).       *
      *     FOUND:     TAX = EMP-SALARY * TAX-TBL-RATE                 *
      *     NOT FOUND: TAX = EMP-SALARY * DEF-TAX-RATE (20%)           *
      *     WRITE PAYROLL-REC WITH OUT-ID, OUT-REGION, OUT-TAX.        *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2025/12/31                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  TAXDD (TAX.RATES) - TAX RATES BY REGION (PS, 80 B)     *
      * INPUT:  EMPDD (EMP.SALARY) - EMPLOYEE SALARIES (PS, 80 B)      *
      * OUTPUT: OUTDD (PAYROLL.TXT) - CALCULATED TAXES (PS, 80 B)      *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PSTASK14.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TAX-RATES-FILE ASSIGN TO TAXDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS TAX-RATES-STATUS.

           SELECT EMPLOYEE-SALARY-FILE ASSIGN TO EMPDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS EMPLOYEE-STATUS.

           SELECT PAYROLL-OUTPUT-FILE ASSIGN TO OUTDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS PAYROLL-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD TAX-RATES-FILE RECORDING MODE IS F.
       01 TAX-RATE-REC.
          05 TAX-REGION-CODE PIC X(2).
          05 RATE PIC V999.
          05 FILLER PIC X(75).

       FD EMPLOYEE-SALARY-FILE RECORDING MODE IS F.
       01 EMPLOYEE-REC.
          05 EMP-ID PIC X(5).
          05 EMP-NAME PIC X(20).
          05 EMP-REGION-CODE PIC X(2).
          05 EMP-SALARY PIC 9(5)V99.
          05 FILLER PIC X(46).

       FD PAYROLL-OUTPUT-FILE RECORDING MODE IS F.
       01 PAYROLL-REC.
          05 OUT-ID PIC X(5).
          05 OUT-REGION PIC X(2).
          05 OUT-TAX PIC 9(5)V99.
          05 FILLER PIC X(66).

       WORKING-STORAGE SECTION.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 TAX-RATES-STATUS PIC X(2).
          05 EMPLOYEE-STATUS PIC X(2).
          05 PAYROLL-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-FOUND PIC X(1) VALUE 'N'.
             88 FOUND VALUE 'Y'.
          05 WS-TAX-EOF PIC X(1) VALUE 'N'.
             88 TAX-EOF VALUE 'Y'.
          05 WS-EMP-EOF PIC X(1) VALUE 'N'.
             88 EMP-EOF VALUE 'Y'.

      * IN-MEMORY TAX RATE TABLE
       01 TAX-TABLE.
          05 TAX-ENTRY OCCURS 50 TIMES INDEXED BY IDX.
             10 WS-REGION PIC X(2).
             10 WS-RATE PIC V999.

      * DEFAULT TAX RATE
       01 DEF-TAX-RATE PIC V999 VALUE .200.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 TAX-RATES-LOADED PIC 9(2) VALUE 0.
          05 EMPLOYEES-PROCESSED PIC 9(5) VALUE 0.
          05 TAXES-CALCULATED PIC 9(5) VALUE 0.
          05 RATE-FOUND-COUNT PIC 9(5) VALUE 0.
          05 DEFAULT-RATE-COUNT PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS
       01 WS-DISP-COUNTERS.
          05 TAX-RATES-LOADED-DISP PIC Z9.
          05 EMPLOYEES-PROCESSED-DISP PIC Z(4)9.
          05 TAXES-CALCULATED-DISP PIC Z(4)9.
          05 RATE-FOUND-COUNT-DISP PIC Z(4)9.
          05 DEFAULT-RATE-COUNT-DISP PIC Z(4)9.

      **********************************************
      * OPENS FILES, LOADS TAX TABLE, PROCESSES
      * EMPLOYEES, CLOSES AND DISPLAYS SUMMARY.
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM LOAD-TAX-TABLE.
           PERFORM PROCESS-EMPLOYEES.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT TAX-RATES-FILE.
           IF TAX-RATES-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING TAX RATES FILE: ' TAX-RATES-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT EMPLOYEE-SALARY-FILE.
           IF EMPLOYEE-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING EMPLOYEE FILE: ' EMPLOYEE-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT PAYROLL-OUTPUT-FILE.
           IF PAYROLL-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING PAYROLL FILE: ' PAYROLL-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * READS TAX-RATES-FILE INTO TAX-TABLE (MAX 50).
      * TAX-RATES-LOADED USED AS TABLE BOUNDARY
      * IN LOOKUP-TAX-RATE.
      **********************************************
       LOAD-TAX-TABLE.
           MOVE 'N' TO WS-TAX-EOF.
           PERFORM UNTIL TAX-EOF
              READ TAX-RATES-FILE
                AT END
                   MOVE 'Y' TO WS-TAX-EOF
                NOT AT END
                   IF TAX-RATES-STATUS = '00'
                      IF TAX-RATES-LOADED >= 50
                         DISPLAY 'WARNING: TAX TABLE FULL (50 MAX). '
                                  'IGNORED: ' TAX-REGION-CODE
                      ELSE
                         ADD 1 TO TAX-RATES-LOADED
                         SET IDX TO TAX-RATES-LOADED
                         MOVE TAX-REGION-CODE TO WS-REGION(IDX)
                         MOVE RATE TO WS-RATE(IDX)
                      END-IF
                   ELSE
                      DISPLAY 'ERROR READING TAX RATES FILE: '
                               TAX-RATES-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * READS EMPLOYEE RECORDS AND WRITES PAYROLL.
      * CALLS LOOKUP THEN EITHER APPLIES FOUND RATE
      * OR DEFAULT RATE (20%) FOR UNKNOWN REGIONS.
      **********************************************
       PROCESS-EMPLOYEES.
           MOVE 'N' TO WS-EMP-EOF.
           PERFORM UNTIL EMP-EOF
              READ EMPLOYEE-SALARY-FILE
                AT END
                   MOVE 'Y' TO WS-EMP-EOF
                NOT AT END
                   IF EMPLOYEE-STATUS = '00'
                      ADD 1 TO EMPLOYEES-PROCESSED
                      MOVE SPACES TO PAYROLL-REC
                      PERFORM LOOKUP-TAX-RATE
                      IF WS-FOUND = 'Y'
                         WRITE PAYROLL-REC
                         IF PAYROLL-STATUS = '00'
                            ADD 1 TO TAXES-CALCULATED
                         ELSE
                            DISPLAY 'ERROR WRITING PAYROLL: '
                                     PAYROLL-STATUS
                            DISPLAY 'EMPLOYEE ID: ' EMP-ID
                            STOP RUN
                         END-IF
                      ELSE
                         PERFORM APPLY-DEFAULT-RATE
                         WRITE PAYROLL-REC
                         IF PAYROLL-STATUS = '00'
                            ADD 1 TO TAXES-CALCULATED
                         ELSE
                            DISPLAY 'ERROR WRITING PAYROLL: '
                                     PAYROLL-STATUS
                            DISPLAY 'EMPLOYEE ID: ' EMP-ID
                            STOP RUN
                         END-IF
                      END-IF
                   ELSE
                      DISPLAY 'ERROR READING EMPLOYEE FILE: '
                               EMPLOYEE-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * LINEAR SEARCH THROUGH TAX-TABLE BY REGION.
      * IF FOUND: POPULATES OUT-* FIELDS AND SETS
      * WS-FOUND = 'Y'. CALLER CHECKS WS-FOUND.
      **********************************************
       LOOKUP-TAX-RATE.
           MOVE 'N' TO WS-FOUND.
           PERFORM VARYING IDX FROM 1 BY 1
             UNTIL IDX > TAX-RATES-LOADED OR WS-FOUND = 'Y'
               IF EMP-REGION-CODE = WS-REGION(IDX)
                  MOVE 'Y' TO WS-FOUND
                  COMPUTE OUT-TAX = EMP-SALARY * WS-RATE(IDX)
                  MOVE EMP-ID TO OUT-ID
                  MOVE WS-REGION(IDX) TO OUT-REGION
                  ADD 1 TO RATE-FOUND-COUNT
               END-IF
           END-PERFORM.

      **********************************************
      * FALLBACK: REGION NOT IN TABLE.
      * APPLIES DEF-TAX-RATE AND MARKS REGION 'XX'.
      **********************************************
       APPLY-DEFAULT-RATE.
           COMPUTE OUT-TAX = EMP-SALARY * DEF-TAX-RATE.
           MOVE EMP-ID TO OUT-ID.
           MOVE EMP-REGION-CODE TO OUT-REGION.
           ADD 1 TO DEFAULT-RATE-COUNT.

      **********************************************
      * CLOSE ALL FILES AND CHECK STATUS
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE TAX-RATES-FILE.
           IF TAX-RATES-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING TAX RATES FILE: '
                       TAX-RATES-STATUS
           END-IF.

           CLOSE EMPLOYEE-SALARY-FILE.
           IF EMPLOYEE-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING EMPLOYEE FILE: '
                       EMPLOYEE-STATUS
           END-IF.

           CLOSE PAYROLL-OUTPUT-FILE.
           IF PAYROLL-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING PAYROLL FILE: '
                       PAYROLL-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE TAX-RATES-LOADED TO TAX-RATES-LOADED-DISP.
           MOVE EMPLOYEES-PROCESSED TO EMPLOYEES-PROCESSED-DISP.
           MOVE TAXES-CALCULATED TO TAXES-CALCULATED-DISP.
           MOVE RATE-FOUND-COUNT TO RATE-FOUND-COUNT-DISP.
           MOVE DEFAULT-RATE-COUNT TO DEFAULT-RATE-COUNT-DISP.

           DISPLAY '========================================'.
           DISPLAY 'TAX CALCULATION SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'TAX RATES LOADED:           ' TAX-RATES-LOADED-DISP.
           DISPLAY 'EMPLOYEES PROCESSED:     ' EMPLOYEES-PROCESSED-DISP.
           DISPLAY 'PAYROLL RECORDS WRITTEN: ' TAXES-CALCULATED-DISP.
           DISPLAY 'RATE FOUND:              ' RATE-FOUND-COUNT-DISP.
           DISPLAY 'DEFAULT RATE USED:       ' DEFAULT-RATE-COUNT-DISP.
           DISPLAY '========================================'.
