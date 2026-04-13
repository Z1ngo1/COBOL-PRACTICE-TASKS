      ******************************************************************
      * BALANCE RECONCILIATION SYSTEM - DB2 + VSAM + PS                *
      *                                                                *
      * PURPOSE:                                                       *
      * RECONCILES END-OF-DAY ACCOUNT BALANCES ACROSS THREE SOURCES:   *
      * VSAM (YESTERDAY BALANCES), PS (TODAY TRANSACTIONS), DB2        *
      * (CURRENT MASTER). FLAGS ACCOUNTS WHERE DB2 BALANCE DOES NOT    *
      * MATCH VSAM YESTERDAY + TODAY TRANSACTIONS.                     *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - LOAD VSAM INTO MEMORY TABLE:                       *
      *     READ ALL VSAM RECORDS INTO ACCOUNT-TABLE (MAX 100)         *
      *   PHASE 2 - PROCESS TRANSACTION LOG (PS):                      *
      *     FOR EACH TRANSACTION FIND ACCOUNT IN TABLE                 *
      *     C (CREDIT) -> ADD TO ACCT-TODAYS-TRANS                     *
      *     D (DEBIT)  -> SUBTRACT FROM ACCT-TODAYS-TRANS              *
      *   PHASE 3 - RECONCILE AGAINST DB2:                             *
      *     FOR EACH ACCOUNT IN TABLE SELECT BALANCE FROM TB_ACCOUNTS  *
      *     EXPECTED = YESTERDAY + TODAY-TRANS                         *
      *     IF ACTUAL = EXPECTED -> OK                                 *
      *     IF ACTUAL != EXPECTED -> FAIL + LOG DIFF                   *
      *     SQLCODE 100 -> ACCOUNT NOT IN DB2                          *
      *     SQLCODE < -900 -> CRITICAL, STOP RUN.                      *
      *   PHASE 4 - FIND ACCOUNTS IN DB2 BUT NOT IN VSAM:              *
      *     CURSOR SCAN TB_ACCOUNTS, CHECK EACH ID IN MEMORY TABLE     *
      *     IF NOT FOUND IN TABLE -> LOG NOT IN VSAM                   *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/21                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  VSAMDD (ACCT.BACKUP)  - VSAM KSDS YESTERDAY BALANCES   *
      *         TRNSDD (TRANS.LOG)    - PS SEQUENTIAL TRANSACTION LOG  *
      * OUTPUT: REPDD  (RECON.REPORT) - PS RECONCILIATION REPORT       *
      *                                                                *
      * DB2 OBJECTS:                                                   *
      * TB_ACCOUNTS - ACCOUNT MASTER TABLE (ACCOUNT_ID, BALANCE)       *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. DB2VSM24.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

      * VSAM KSDS OPENED SEQUENTIAL TO LOAD ALL RECORDS INTO TABLE.
           SELECT VSAM-FILE ASSIGN TO VSAMDD
              ORGANIZATION IS INDEXED
              ACCESS MODE IS SEQUENTIAL
              RECORD KEY IS VSAM-ACCT-ID
              FILE STATUS IS VSAM-STATUS.

           SELECT TRNS-FILE ASSIGN TO TRNSDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS TRNS-STATUS.

           SELECT REP-FILE ASSIGN TO REPDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS REP-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD VSAM-FILE.
       01 VSAM-REC.
          05 VSAM-ACCT-ID PIC X(6).
          05 VSAM-YBAL PIC 9(9)V99.
          05 VSAM-BDATE PIC 9(8).
          05 FILLER PIC X(55).

       FD TRNS-FILE RECORDING MODE IS F.
       01 TRNS-REC.
          05 TRANS-ACCT-ID PIC X(6).
          05 TRANS-TYPE PIC X(1).
          05 TRANS-AMT PIC 9(7)V99.
          05 FILLER PIC X(64).

       FD REP-FILE RECORDING MODE IS V.
       01 REP-REC PIC X(120).

       WORKING-STORAGE SECTION.

      * SQL COMMUNICATION AREA
           EXEC SQL
             INCLUDE SQLCA
           END-EXEC.

      * CURSOR DEFINITION FOR ACCOUNT MASTER TABLE
           EXEC SQL
             DECLARE DB2-CURSOR CURSOR FOR
                 SELECT ACCOUNT_ID, BALANCE
                   FROM TB_ACCOUNTS
                  ORDER BY ACCOUNT_ID
           END-EXEC.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 VSAM-STATUS PIC X(2).
          05 TRNS-STATUS PIC X(2).
          05 REP-STATUS  PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-VSAM-EOF PIC X(1) VALUE 'N'.
             88 VSAM-EOF VALUE 'Y'.
             88 VSAM-NOT-EOF VALUE 'N'.
          05 WS-TRNS-EOF PIC X(1) VALUE 'N'.
             88 TRNS-EOF VALUE 'Y'.
             88 TRNS-NOT-EOF VALUE 'N'.
          05 WS-FOUND PIC X(1) VALUE 'N'.
             88 FOUND VALUE 'Y'.
             88 NOT-FOUND VALUE 'N'.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 TOTAL-ACCOUNTS PIC 9(5) VALUE 0.
          05 RECONCILED-OK PIC 9(5) VALUE 0.
          05 DISCREPANCIES-CNT PIC 9(5) VALUE 0.
          05 ERRORS-DATA PIC 9(5) VALUE 0.
          05 NOT-IN-DB2-CNT PIC 9(5) VALUE 0.
          05 NOT-IN-VSAM-CNT PIC 9(5) VALUE 0.
          05 VSAM-ONLY-CNT PIC 9(5) VALUE 0.

      * FORMATTED COUNTERS
       01 WS-TOTALS-EDIT.
          05 WS-TOTAL-EDIT PIC ZZZZ9.
          05 WS-OK-EDIT PIC ZZZZ9.
          05 WS-DISC-EDIT PIC ZZZZ9.
          05 WS-ERRORS-EDIT PIC ZZZZ9.

      * IN-MEMORY TABLE
       01 ACCOUNT-TABLE.
          05 ACCT-ENTRY OCCURS 100 TIMES INDEXED BY ACCT-IDX.
             10 ACCT-ID PIC X(6).
             10 ACCT-YBAL PIC S9(11)V99 COMP-3.
             10 ACCT-TODAYS-TRANS PIC S9(11)V99 COMP-3.
             10 ACCT-PROCESSED PIC X(1) VALUE 'N'.

      * REPORT OUTPUT LINE
       01 REPORT-LINE.
          05 ACCOUNT PIC X(6).
          05 FILLER PIC X(3) VALUE SPACES.
          05 YESTERDAY PIC Z(8)9.99.
          05 FILLER PIC X(3) VALUE SPACES.
          05 TODAY-TRNS PIC ++++++9.99.
          05 FILLER PIC X(3) VALUE SPACES.
          05 EXPECTED PIC Z(8)9.99.
          05 FILLER PIC X(3) VALUE SPACES.
          05 ACTUAL PIC ZZZZZZZZ9.99.
          05 FILLER PIC X(3) VALUE SPACES.
          05 WS-STATUS PIC X(10).
          05 FILLER PIC X(3) VALUE SPACES.
          05 DIFF PIC ++++++9.99.

      * WORK VARIABLES
       01 WORK-VARS.
          05 WS-TABLE-COUNT PIC 9(5) VALUE 0.
          05 WS-IDX PIC 9(5) VALUE 0.
          05 WS-EXPECTED PIC S9(11)V99 COMP-3.
          05 WS-ACTUAL PIC S9(11)V99 COMP-3.
          05 WS-DIFF PIC S9(11)V99 COMP-3.

      * DB2 HOST VARIABLES
       01 DB2-VARS.
          05 HV-ACCT-ID PIC X(6).
          05 HV-ACTUAL-BALANCE PIC S9(11)V99 COMP-3.

      * BUFFER
       01 MESSAGE-LINE PIC X(120).

      **********************************************
      * OPEN -> LOAD VSAM -> PROCESS TRNS -> RECONCILE
      * FIND NOT-IN-VSAM -> LOG NOT-IN-DB2 -> FOOTER -> CLOSE.
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM READ-VSAM.
           PERFORM READ-TRNS.
           PERFORM RECONCILE.
           PERFORM FIND-NOT-IN-VSAM.
           PERFORM WRITE-FOOTER.
           PERFORM CLOSE-ALL-FILES.
           STOP RUN.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT VSAM-FILE.
           IF VSAM-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING VSAM FILE: ' VSAM-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT TRNS-FILE.
           IF TRNS-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING TRNS FILE: ' TRNS-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT REP-FILE.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO REP-REC.
           STRING 'ACCOUNT     YESTERDAY   TODAY-TRNS       EXPECTED '
                  '        ACTUAL   STATUS           '
                  '  DIFF' DELIMITED BY SIZE
                  INTO REP-REC
           END-STRING.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO REP-REC.

      **********************************************
      * READS ALL VSAM-FILE RECORDS INTO TABLE.
      * INITIALIZES TODAYS-TRANS=0, PROCESSED='N'.
      **********************************************
       READ-VSAM.
           MOVE 0 TO WS-TABLE-COUNT.
           SET VSAM-NOT-EOF TO TRUE.
           PERFORM UNTIL VSAM-EOF
              READ VSAM-FILE
                AT END
                   SET VSAM-EOF TO TRUE
                NOT AT END
                   IF VSAM-STATUS NOT = '00' AND VSAM-STATUS NOT = '10'
                      DISPLAY 'ERROR READING VSAM FILE: ' VSAM-STATUS
                      STOP RUN
                   END-IF
                   IF WS-TABLE-COUNT >= 100
                      DISPLAY 'FATAL: ACCOUNT TABLE OVERFLOW, MAX=100'
                      STOP RUN
                   END-IF
                   ADD 1 TO WS-TABLE-COUNT
                   SET ACCT-IDX TO WS-TABLE-COUNT
                   MOVE VSAM-ACCT-ID TO ACCT-ID(ACCT-IDX)
                   MOVE VSAM-YBAL TO ACCT-YBAL(ACCT-IDX)
                   MOVE ZEROS TO ACCT-TODAYS-TRANS(ACCT-IDX)
                   MOVE 'N' TO ACCT-PROCESSED(ACCT-IDX)
              END-READ
           END-PERFORM.

      **********************************************
      * READS TRNS-FILE TO EOF.
      * PER RECORD CALLS PROCESS-TRANS TO APPLY CREDIT/DEBIT TO TABLE.
      **********************************************
       READ-TRNS.
           SET TRNS-NOT-EOF TO TRUE.
           PERFORM UNTIL TRNS-EOF
              READ TRNS-FILE
                AT END
                   SET TRNS-EOF TO TRUE
                NOT AT END
                   IF TRNS-STATUS NOT = '00'
                      DISPLAY 'ERROR READING TRANS FILE: ' TRNS-STATUS
                      STOP RUN
                   END-IF
                   PERFORM PROCESS-TRANS
              END-READ
           END-PERFORM.

      **********************************************
      * FINDS TRANS-ACCT-ID IN TABLE. APPLIES:
      * C (CREDIT) -> ADD. D (DEBIT) -> SUBTRACT.
      * UNKNOWN TYPE -> LOGGED TO SYSOUT, SKIPPED.
      **********************************************
       PROCESS-TRANS.
           SET NOT-FOUND TO TRUE.
           PERFORM VARYING WS-IDX FROM 1 BY 1
               UNTIL WS-IDX > WS-TABLE-COUNT OR FOUND
              IF ACCT-ID(WS-IDX) = TRANS-ACCT-ID
                 SET FOUND TO TRUE
                 SET ACCT-IDX TO WS-IDX
                 EVALUATE TRANS-TYPE
                     WHEN 'C'
                       COMPUTE ACCT-TODAYS-TRANS(ACCT-IDX) =
                          ACCT-TODAYS-TRANS(ACCT-IDX) + TRANS-AMT
                     WHEN 'D'
                       COMPUTE ACCT-TODAYS-TRANS(ACCT-IDX) =
                          ACCT-TODAYS-TRANS(ACCT-IDX) - TRANS-AMT
                     WHEN OTHER
                       DISPLAY 'ERROR: INCORRECT TYPE'
                 END-EVALUATE
              END-IF
           END-PERFORM.

      **********************************************
      * LOOPS ALL TABLE ENTRIES.
      * CALLS COMPARE-DB2-PARA FOR EACH ACCOUNT.
      **********************************************
       RECONCILE.
           PERFORM VARYING WS-IDX FROM 1 BY 1
               UNTIL WS-IDX > WS-TABLE-COUNT
              PERFORM COMPARE-DB2
           END-PERFORM.

      **********************************************
      * SELECTS BALANCE FROM DB2.
      * COMPARES ACTUAL VS EXPECTED (YBAL + TODAYS-TRANS).
      * DIFF=0 -> OK. DIFF!=0 -> FAIL.
      * SQLCODE 100 -> NOT IN DB2, DATA ERROR.
      * CRITICAL SQLCODES -> STOP RUN.
      **********************************************
       COMPARE-DB2.
           SET ACCT-IDX TO WS-IDX.
           MOVE ACCT-ID(ACCT-IDX) TO HV-ACCT-ID.
           ADD 1 TO TOTAL-ACCOUNTS.
           COMPUTE WS-EXPECTED =
              ACCT-YBAL(ACCT-IDX) + ACCT-TODAYS-TRANS(ACCT-IDX).

           EXEC SQL
             SELECT BALANCE
               INTO :HV-ACTUAL-BALANCE
               FROM TB_ACCOUNTS
             WHERE ACCOUNT_ID = :HV-ACCT-ID
           END-EXEC.

           EVALUATE TRUE
               WHEN SQLCODE = 0
                 COMPUTE WS-DIFF = HV-ACTUAL-BALANCE - WS-EXPECTED
                 IF WS-DIFF = 0
                    MOVE 'OK' TO WS-STATUS
                    ADD 1 TO RECONCILED-OK
                 ELSE
                    MOVE 'FAIL' TO WS-STATUS
                    ADD 1 TO DISCREPANCIES-CNT
                 END-IF
                 MOVE 'Y' TO ACCT-PROCESSED(ACCT-IDX)
                 MOVE ACCT-ID(ACCT-IDX) TO ACCOUNT
                 MOVE ACCT-YBAL(ACCT-IDX) TO YESTERDAY
                 MOVE ACCT-TODAYS-TRANS(ACCT-IDX) TO TODAY-TRNS
                 MOVE WS-EXPECTED TO EXPECTED
                 MOVE HV-ACTUAL-BALANCE TO ACTUAL
                 MOVE WS-DIFF TO DIFF
                 MOVE ALL SPACES TO REP-REC
                 MOVE REPORT-LINE TO REP-REC
                 WRITE REP-REC
                 IF REP-STATUS NOT = '00'
                    DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
                    STOP RUN
                 END-IF
                 MOVE ALL SPACES TO REP-REC
               WHEN SQLCODE = 100
                 ADD 1 TO NOT-IN-DB2-CNT
                 ADD 1 TO VSAM-ONLY-CNT
                 ADD 1 TO ERRORS-DATA
                 MOVE 'N' TO ACCT-PROCESSED(ACCT-IDX)
               WHEN OTHER
                 IF SQLCODE < -900
                    DISPLAY 'CRITICAL DB2 ERROR: ' SQLCODE
                    STOP RUN
                 END-IF
                 ADD 1 TO ERRORS-DATA
                 MOVE 'E' TO ACCT-PROCESSED(ACCT-IDX)
                 MOVE SPACES TO REPORT-LINE
                 MOVE 'ERROR' TO WS-STATUS
                 MOVE ACCT-ID(ACCT-IDX) TO ACCOUNT
                 MOVE ALL SPACES TO REP-REC
                 MOVE REPORT-LINE TO REP-REC
                 WRITE REP-REC
                 IF REP-STATUS NOT = '00'
                    DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
                    STOP RUN
                 END-IF
           END-EVALUATE.

      **********************************************
      * OPENS DB2-CURSOR, FETCHES ALL DB2 ACCOUNTS.
      * PER ROW CALLS CHECK-IN-VSAM-PARA.
      * SQLCODE 100 = EOF. OTHER NON-ZERO = FATAL.
      **********************************************
       FIND-NOT-IN-VSAM.
           EXEC SQL
             OPEN DB2-CURSOR
           END-EXEC.

           IF SQLCODE NOT = 0
              DISPLAY 'ERROR OPENING CURSOR: ' SQLCODE
              STOP RUN
           END-IF.

           PERFORM UNTIL SQLCODE NOT = 0
              EXEC SQL
                FETCH DB2-CURSOR INTO :HV-ACCT-ID,:HV-ACTUAL-BALANCE
              END-EXEC

              EVALUATE TRUE
                  WHEN SQLCODE = 0
                       PERFORM CHECK-IN-VSAM
                  WHEN SQLCODE = 100
                       EXIT PERFORM
                  WHEN OTHER
                       DISPLAY 'FETCH ERROR: ' SQLCODE
                       EXEC SQL
                         CLOSE DB2-CURSOR
                       END-EXEC
                       STOP RUN
              END-EVALUATE
           END-PERFORM.

           EXEC SQL
             CLOSE DB2-CURSOR
           END-EXEC.

      **********************************************
      * SEARCHES ACCOUNT-TABLE FOR HV-ACCT-ID.
      * NOT FOUND -> LOG TO REPORT, INCREMENT COUNTER.
      **********************************************
       CHECK-IN-VSAM.
           IF HV-ACCT-ID = LOW-VALUES OR SPACES
              EXIT PARAGRAPH
           END-IF.
           SET NOT-FOUND TO TRUE.
           PERFORM VARYING WS-IDX FROM 1 BY 1
               UNTIL WS-IDX > WS-TABLE-COUNT OR FOUND
              IF ACCT-ID(WS-IDX) = HV-ACCT-ID
                 SET FOUND TO TRUE
              END-IF
           END-PERFORM.

           IF NOT-FOUND
              ADD 1 TO NOT-IN-VSAM-CNT
              ADD 1 TO ERRORS-DATA
              MOVE ALL SPACES TO MESSAGE-LINE
              MOVE ALL SPACES TO REP-REC
              STRING 'NOT IN VSAM(BUT IN DB2): ' DELIMITED BY SIZE
                     HV-ACCT-ID DELIMITED BY SIZE
                     INTO MESSAGE-LINE
              END-STRING
              MOVE MESSAGE-LINE TO REP-REC
              WRITE REP-REC
              IF REP-STATUS NOT = '00'
                 DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
                 STOP RUN
              END-IF
              MOVE SPACES TO HV-ACCT-ID
              MOVE ALL SPACES TO MESSAGE-LINE
           END-IF.

      **********************************************
      * LOGS ACCOUNTS WITH PROCESSED='N' (NOT IN DB2)
      * THEN WRITES STATISTICS FOOTER TO REPORT.
      **********************************************
       WRITE-FOOTER.
           PERFORM VARYING WS-IDX FROM 1 BY 1
               UNTIL WS-IDX > WS-TABLE-COUNT
              IF ACCT-PROCESSED(WS-IDX) = 'N'
                 MOVE ALL SPACES TO MESSAGE-LINE
                 STRING 'NOT IN DB2 (BUT IN VSAM/PS): '
                    DELIMITED BY SIZE
                    ACCT-ID(WS-IDX) DELIMITED BY SIZE
                    INTO MESSAGE-LINE
                 END-STRING
                 MOVE ALL SPACES TO REP-REC
                 MOVE MESSAGE-LINE TO REP-REC
                 WRITE REP-REC
                 IF REP-STATUS NOT = '00'
                    DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
                    STOP RUN
                 END-IF
                 MOVE ALL SPACES TO MESSAGE-LINE
                 MOVE ALL SPACES TO REP-REC
              END-IF
           END-PERFORM.

           MOVE ALL SPACES TO REP-REC.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

           MOVE TOTAL-ACCOUNTS TO WS-TOTAL-EDIT.
           MOVE RECONCILED-OK TO WS-OK-EDIT.
           MOVE DISCREPANCIES-CNT TO WS-DISC-EDIT.
           MOVE ERRORS-DATA TO WS-ERRORS-EDIT.

           MOVE ALL SPACES TO REP-REC.
           STRING 'TOTAL ACCOUNTS CHECKED: ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-TOTAL-EDIT) DELIMITED BY SIZE
                  INTO REP-REC
           END-STRING.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO REP-REC.
           STRING 'RECONCILED OK: ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-OK-EDIT) DELIMITED BY SIZE
                  INTO REP-REC
           END-STRING.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO REP-REC.
           STRING 'DISCREPANCIES: ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-DISC-EDIT) DELIMITED BY SIZE
                  INTO REP-REC
           END-STRING.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO REP-REC.
           STRING 'ERRORS DATA: ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-ERRORS-EDIT) DELIMITED BY SIZE
                  INTO REP-REC
           END-STRING.
           WRITE REP-REC.
           IF REP-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING REPORT FILE: ' REP-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * CLOSE ALL FILES
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE VSAM-FILE.
           IF VSAM-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING VSAM FILE: ' VSAM-STATUS
           END-IF.
           CLOSE TRNS-FILE.
           IF TRNS-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING TRANS FILE: ' TRNS-STATUS
           END-IF.
           CLOSE REP-FILE.
           IF REP-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING REPORT FILE: ' REP-STATUS
           END-IF.
