      ******************************************************************
      * TIERED COMMISSION CALCULATOR - IN-MEMORY TABLE LOOKUP          *
      *                                                                *
      * PURPOSE:                                                       *
      * CALCULATES EMPLOYEE COMMISSIONS BASED ON SALARY TIERS LOADED   *
      * INTO MEMORY. TIERED LOOKUP: COMMISSION RATE DEPENDS ON         *
      * SALARY BRACKET.                                                *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - LOAD: READ COMMISSION-TIERS-FILE INTO TIER-TABLE.  *
      *             (MAX 20 TIERS). OVERFLOW RECORDS ARE IGNORED. *
      *   PHASE 2 - PROCESS: FOR EACH EMPLOYEE:                        *
      *     FIND FIRST TIER WHERE TIER-TBL-LIMIT >= SAL-AMOUNT.        *
      *     FOUND:     COMMISSION = SAL-AMOUNT * TIER-TBL-PCT.         *
      *                WRITE OUT-ID, OUT-SAL-AMT, OUT-PCT, OUT-RES.    *
      *     NOT FOUND: LOG NO-TIER-MATCH, SKIP WRITE.                  *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/01                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  COMMDD (COMM.TIERS) - COMMISSION TIERS (PS, 80 B)      *
      * INPUT:  SALDD (EMP.SALARY) - EMPLOYEE SALARIES (PS, 80 B)      *
      * OUTPUT: OUTDD (COMM.OUTPUT) - CALCULATED COMMISSIONS (PS, 80 B)*
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PSTASK15.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT COMMISSION-TIERS-FILE ASSIGN TO COMMDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS COMMISSION-STATUS.

           SELECT EMPLOYEE-SALARY-FILE ASSIGN TO SALDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS SALARY-STATUS.

           SELECT COMMISSION-OUTPUT-FILE ASSIGN TO OUTDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS OUTPUT-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD COMMISSION-TIERS-FILE RECORDING MODE IS F.
       01 COMMISSION-TIER-REC.
          05 COMM-LIMIT PIC 9(6).
          05 COMM-PCT PIC V999.

       FD EMPLOYEE-SALARY-FILE RECORDING MODE IS F.
       01 SALARY-REC.
          05 SAL-ID PIC 9(5).
          05 SAL-AMT PIC 9(6)V99.

       FD COMMISSION-OUTPUT-FILE RECORDING MODE IS F.
       01 COMMISSION-REC.
          05 OUT-ID PIC 9(5).
          05 FILLER PIC X(1).
          05 OUT-SAL-AMT PIC 9(6)V99.
          05 FILLER PIC X(1).
          05 OUT-PCT PIC V999.
          05 FILLER PIC X(1).
          05 OUT-RES PIC 9(6)V99.
          05 FILLER PIC X(53).

       WORKING-STORAGE SECTION.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 COMMISSION-STATUS PIC X(2).
          05 SALARY-STATUS PIC X(2).
          05 OUTPUT-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-COMM-EOF PIC X(1) VALUE 'N'.
          05 WS-SAL-EOF PIC X(1) VALUE 'N'.
          05 WS-FOUND PIC X(1) VALUE 'N'.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 TIERS-LOADED PIC 9(2) VALUE 0.
          05 EMPLOYEES-PROCESSED PIC 9(5) VALUE 0.
          05 RECORDS-WRITTEN PIC 9(5) VALUE 0.
          05 TIER-MATCH-COUNT PIC 9(5) VALUE 0.
          05 NO-TIER-MATCH PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS.
       01 WS-DISP-COUNTERS.
          05 TIERS-LOADED-DISP PIC Z9.
          05 EMPLOYEES-PROCESSED-DISP PIC Z(4)9.
          05 RECORDS-WRITTEN-DISP PIC Z(4)9.
          05 TIER-MATCH-COUNT-DISP PIC Z(4)9.
          05 NO-TIER-MATCH-DISP PIC Z(4)9.

      * IN-MEMORY COMMISSION TIERS TABLE
       01 TIER-TABLE.
          05 TIER-ENTRY OCCURS 20 TIMES INDEXED BY IDX.
             10 WS-LIMIT PIC 9(6).
             10 WS-PCT PIC V999.

      **********************************************
      * OPENS FILES, LOADS TIER TABLE, PROCESSES
      * SALARIES, CLOSES AND DISPLAYS SUMMARY.
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM LOAD-COMMISSION-TABLE.
           PERFORM PROCESS-SALARIES.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT COMMISSION-TIERS-FILE.
           IF COMMISSION-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING COMMISSION TIERS FILE: '
                       COMMISSION-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT EMPLOYEE-SALARY-FILE.
           IF SALARY-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING EMPLOYEE SALARY FILE: '
                       SALARY-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT COMMISSION-OUTPUT-FILE.
           IF OUTPUT-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING COMMISSION OUTPUT FILE: '
                       OUTPUT-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * READS COMMISSION-TIERS-FILE INTO TIER-TABLE.
      * (MAX 20). OVERFLOW IGNORED WITH WARNING.
      * TIERS-LOADED USED AS BOUNDARY IN LOOKUP.
      **********************************************
        LOAD-COMMISSION-TABLE.
           MOVE 'N' TO WS-COMM-EOF.
           PERFORM UNTIL WS-COMM-EOF = 'Y'
              READ COMMISSION-TIERS-FILE
                AT END
                   MOVE 'Y' TO WS-COMM-EOF
                NOT AT END
                   IF COMMISSION-STATUS = '00'
                      IF TIERS-LOADED >= 20
                         DISPLAY 'WARNING: TIER TABLE FULL (20 MAX).'
                                 ' IGNORED: ' COMM-LIMIT
                      ELSE
                         ADD 1 TO TIERS-LOADED
                         SET IDX TO TIERS-LOADED
                         MOVE COMM-LIMIT TO WS-LIMIT(IDX)
                         MOVE COMM-PCT TO WS-PCT(IDX)
                      END-IF
                   ELSE
                      DISPLAY 'ERROR READING COMMISSION TIERS FILE: '
                               COMMISSION-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * READS SALARY RECORDS AND CALLS COMMISSION
      * CALCULATION FOR EACH EMPLOYEE.
      **********************************************
        PROCESS-SALARIES.
           MOVE 'N' TO WS-SAL-EOF.
           PERFORM UNTIL WS-SAL-EOF = 'Y'
              READ EMPLOYEE-SALARY-FILE
                AT END
                   MOVE 'Y' TO WS-SAL-EOF
                NOT AT END
                   IF SALARY-STATUS = '00'
                      ADD 1 TO EMPLOYEES-PROCESSED
                      PERFORM CALCULATE-COMMISSION
                   ELSE
                      DISPLAY 'ERROR READING EMPLOYEE SALARY FILE: '
                               SALARY-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * LINEAR SEARCH: FIRST TIER WHERE LIMIT >= SAL-AMOUNT.
      * FOUND: COMPUTE AND WRITE.
      * NOT FOUND: INCREMENT NO-TIER-COUNT, NO WRITE.
      **********************************************
       CALCULATE-COMMISSION.
           MOVE 'N' TO WS-FOUND.
           PERFORM VARYING IDX FROM 1 BY 1
                   UNTIL IDX > TIERS-LOADED OR WS-FOUND = 'Y'
               IF WS-LIMIT(IDX) >= SAL-AMT
                  MOVE 'Y' TO WS-FOUND
                  MOVE SPACES TO COMMISSION-REC
                  INITIALIZE COMMISSION-REC
                  ADD 1 TO TIER-MATCH-COUNT
                  COMPUTE OUT-RES = SAL-AMT * WS-PCT(IDX)
                  MOVE SAL-ID TO OUT-ID
                  MOVE SAL-AMT TO OUT-SAL-AMT
                  MOVE WS-PCT(IDX) TO OUT-PCT
                  WRITE COMMISSION-REC
                  IF OUTPUT-STATUS = '00'
                     ADD 1 TO RECORDS-WRITTEN
                  ELSE
                     DISPLAY 'ERROR WRITING COMMISSION OUTPUT FILE: '
                              OUTPUT-STATUS
                     DISPLAY 'EMPLOYEE ID: ' SAL-ID
                     STOP RUN
                  END-IF
               END-IF
           END-PERFORM.

           IF WS-FOUND = 'N'
              ADD 1 TO NO-TIER-MATCH
           END-IF.

      **********************************************
      * CLOSE ALL FILES AND CHECK STATUS
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE COMMISSION-TIERS-FILE.
           IF COMMISSION-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING COMMISSION TIERS FILE: '
                       COMMISSION-STATUS
           END-IF.

           CLOSE EMPLOYEE-SALARY-FILE.
           IF SALARY-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING EMPLOYEE SALARY FILE: '
                       SALARY-STATUS
           END-IF.

           CLOSE COMMISSION-OUTPUT-FILE.
           IF OUTPUT-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING COMMISSION OUTPUT FILE: '
                       OUTPUT-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE TIERS-LOADED TO TIERS-LOADED-DISP.
           MOVE EMPLOYEES-PROCESSED TO EMPLOYEES-PROCESSED-DISP.
           MOVE RECORDS-WRITTEN TO RECORDS-WRITTEN-DISP.
           MOVE TIER-MATCH-COUNT TO TIER-MATCH-COUNT-DISP.
           MOVE NO-TIER-MATCH TO NO-TIER-MATCH-DISP.

           DISPLAY '========================================'.
           DISPLAY 'COMMISSION CALCULATION SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'COMMISSION TIERS LOADED:    ' TIERS-LOADED-DISP.
           DISPLAY 'EMPLOYEES PROCESSED:     ' EMPLOYEES-PROCESSED-DISP
           DISPLAY 'RECORDS WRITTEN:         ' RECORDS-WRITTEN-DISP.
           DISPLAY 'TIER MATCHED:            ' TIER-MATCH-COUNT-DISP.
           DISPLAY 'NO TIER MATCH:           ' NO-TIER-MATCH-DISP.
           DISPLAY '========================================'.
