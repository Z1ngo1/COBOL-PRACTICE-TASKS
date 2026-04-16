      ******************************************************************
      * ESDS OPERATION LOG - KSDS AND DB2 RECONCILIATION               *
      *                                                                *
      * PURPOSE:                                                       *
      * READS DAILY OPERATION LOG (ESDS), FOR EACH OPERATION:          *
      * VALIDATES INPUT FIELDS, CHECKS ACCOUNT EXISTS IN KSDS,         *
      * FETCHES CURRENT BALANCE FROM DB2, VERIFIES BUSINESS LOGIC.     *
      * LOGS ALL RESULTS (OK / ERROR / SKIPPED) TO PS REPORT FILE.     *
      * NO DATA IS UPDATED - READ-ONLY RECONCILIATION ONLY.            *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - VALIDATE INPUT FIELDS:                             *
      *     OPR-TYPE NOT 'D' OR 'C' -> ERROR: INVALID INPUT DATA.      *
      *     OPR-AMT <= 0            -> ERROR: INVALID INPUT DATA.      *
      *   PHASE 2 - KSDS LOOKUP BY ACCT-ID:                            *
      *     FILE STATUS '23'        -> ERROR: ACCOUNT NOT FOUND.       *
      *     ACCT-STATUS = 'C'       -> SKIPPED: ACCOUNT STATUS CLOSED. *
      *   PHASE 3 - DB2 BALANCE FETCH:                                 *
      *     SQLCODE = 0             -> OK, BALANCE RETRIEVED.          *
      *     SQLCODE = 100           -> ERROR: DB2 ROW MISSING.         *
      *     SQLCODE < 0             -> ERROR: DB2 ERROR <SQLCODE>.     *
      *   PHASE 4 - BUSINESS LOGIC CHECK:                              *
      *     OPR-TYPE 'D' AND DB2-BALANCE < OPR-AMT:                    *
      *       -> ERROR: NEGATIVE BALANCE AFTER OPR.                    *
      *     OPR-TYPE 'D' AND DB2-BALANCE >= OPR-AMT:                   *
      *       -> OK: BALANCE CHECK PASSED.                             *
      *     OPR-TYPE 'C' -> OK: BALANCE CHECK PASSED.                  *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/02/11                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  OPRLOGDD  (OPR.LOG.ESDS)   - ESDS DAILY OPERATION LOG  *
      *         MASTERDD  (ACCT.MASTER)    - VSAM KSDS ACCOUNT MASTER  *
      * OUTPUT: RECONDD   (RECON.LOG)      - PS RECONCILIATION REPORT  *
      * DB2:    TB_ACCOUNT_BAL             - CURRENT ACCOUNT BALANCES  *
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. ESDS29.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

           SELECT OPR-LOG ASSIGN TO AS-OPR
             ORGANIZATION IS SEQUENTIAL
             ACCESS MODE IS SEQUENTIAL
             FILE STATUS IS OPR-STATUS.

           SELECT ACCT-MASTER ASSIGN TO ACCTDD
             ORGANIZATION IS INDEXED
             ACCESS MODE IS RANDOM
             RECORD KEY IS ACCT-MAST-ID
             FILE STATUS IS ACCT-MASTER-STATUS.

           SELECT RECON-LOG ASSIGN TO RECN
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS RECON-LOG-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD OPR-LOG.
       01 OPR-LOG-REC.
          05 OPR-ACCT-ID PIC X(6).
          05 OPR-DATE PIC X(8).
          05 OPR-TYPE PIC X(1).
          05 OPR-AMT PIC 9(7)V99.
          05 OPR-ID PIC X(6).
          05 FILLER PIC X(50).

       FD ACCT-MASTER.
       01 ACCT-MASTER-REC.
          05 ACCT-MAST-ID PIC X(6).
          05 ACCT-CUST-NAME PIC X(25).
          05 ACCT-STATUS PIC X(1).
          05 ACCT-LIMIT PIC 9(7)V99.
          05 FILLER PIC X(39).

       FD RECON-LOG RECORDING MODE IS F.
       01 RECON-LOG-REC PIC X(80).

       WORKING-STORAGE SECTION.

      * DB2 SQL COMMUNICATION AREA
           EXEC SQL
             INCLUDE SQLCA
           END-EXEC.

      * DB2 DCLGEN - GENERATED FROM TB_ACCOUNT_BAL TABLE
           EXEC SQL
             INCLUDE TASK29
           END-EXEC.

      * FILE STATUS VARIABLES
       01 WS-FILE-STATUSES.
          05 OPR-STATUS PIC X(2).
          05 ACCT-MASTER-STATUS PIC X(2).
          05 RECON-LOG-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 EOF-FLAG PIC X(1) VALUE 'N'.
             88 EOF VALUE 'Y'.
          05 VALIDATION-FLAG PIC X(1) VALUE 'Y'.
             88 VALIDATION-OK VALUE 'Y'.
             88 VALIDATION-FAILED VALUE 'N'.

      * REPORT LINE BUFFER AND FIELDS
       01 WS-REPORT-MSG PIC X(80).
       01 WS-DB2-ACCT-ID PIC X(6).
       01 WS-RECON-LOG-VARS.
          05 WS-OPR-ID PIC X(6).
          05 WS-ACCT-ID PIC X(6).
          05 WS-RECON-STATUS PIC X(15).
          05 WS-DETAIL PIC X(30).

      * PROCESSING COUNTERS
       01 WS-COUNTERS.
          05 TOTAL-READ PIC 9(5) VALUE 0.
          05 OK-COUNT PIC 9(5) VALUE 0.
          05 ERR-COUNT PIC 9(5) VALUE 0.
          05 SKIP-COUNT PIC 9(5) VALUE 0.
          05 WRITE-COUNT PIC 9(5) VALUE 0.

      * FORMATTED DISPLAY COUNTERS FOR SUMMARY
       01 WS-DISP-COUNTERS.
          05 TOTAL-READ-DISP PIC Z(4)9.
          05 OK-COUNT-DISP PIC Z(4)9.
          05 ERR-COUNT-DISP PIC Z(4)9.
          05 SKIP-COUNT-DISP PIC Z(4)9.
          05 WRITE-COUNT-DISP PIC Z(4)9.

      * DB2 SQLCODE DISPLAY VARIABLE
       01 WS-SQLCODE PIC -Z(9)9.

      **********************************************
      * OPEN -> PROCESS ALL RECORDS -> CLOSE -> SUMMARY
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM PROCESS-ALL-RECORDS.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * READS OPR-LOG (ESDS) SEQUENTIALLY UNTIL EOF.
      * PER RECORD: INCREMENTS TOTAL-READ,
      * THEN CALLS PROCESS-ONE-RECORD FOR EACH OPERATION.
      * STOPS ON ANY NON-ZERO READ STATUS.
      **********************************************
       PROCESS-ALL-RECORDS.
           PERFORM UNTIL EOF
              READ OPR-LOG
                AT END
                   SET EOF TO TRUE
                NOT AT END
                   IF OPR-STATUS = '00'
                      ADD 1 TO TOTAL-READ
                      PERFORM PROCESS-ONE-RECORD
                   ELSE
                      DISPLAY 'ERROR READING OPR-LOG FILE: ' OPR-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * BUILDS REPORT LINE VIA STRING:
      *   OPR-ID, ACCT-ID, STATUS, DETAIL MESSAGE.
      * WRITES TO RECON-LOG (PS).
      * INCREMENTS WRITE-COUNT.
      * STOPS ON ANY NON-ZERO WRITE STATUS.
      **********************************************
       WRITE-RECON-LOG.
           MOVE SPACES TO WS-REPORT-MSG.
           MOVE OPR-ID TO WS-OPR-ID.
           MOVE OPR-ACCT-ID TO WS-ACCT-ID.
           STRING WS-OPR-ID DELIMITED BY SIZE
                  ' ' DELIMITED BY SIZE
                  WS-ACCT-ID DELIMITED BY SIZE
                  ' ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-RECON-STATUS) DELIMITED BY SIZE
                  ' ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-DETAIL) DELIMITED BY SIZE
                  INTO WS-REPORT-MSG
           END-STRING.
           MOVE WS-REPORT-MSG TO RECON-LOG-REC.
           WRITE RECON-LOG-REC.
           IF RECON-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING RECON-LOG FILE: ' RECON-LOG-STATUS
              DISPLAY 'OPERATION ID: ' WS-OPR-ID
              STOP RUN
           END-IF.
           ADD 1 TO WRITE-COUNT.

      **********************************************
      * VALIDATES OPR-TYPE ('D' OR 'C') AND OPR-AMT > 0.
      * INVALID INPUT -> WRITE ERROR, SET VALIDATION-FAILED.
      * IF VALIDATION-OK -> CALLS READ-ACCT-MASTER.
      **********************************************
       PROCESS-ONE-RECORD.
           SET VALIDATION-OK TO TRUE.
           IF (OPR-TYPE NOT = 'D' AND OPR-TYPE NOT = 'C')
                       OR OPR-AMT <= 0
              ADD 1 TO ERR-COUNT
              MOVE 'ERROR' TO WS-RECON-STATUS
              MOVE 'INVALID INPUT DATA' TO WS-DETAIL
              PERFORM WRITE-RECON-LOG
              SET VALIDATION-FAILED TO TRUE
           END-IF.

           IF VALIDATION-OK
              PERFORM READ-ACCT-MASTER
           END-IF.

      **********************************************
      * RANDOM READ KSDS BY ACCT-MAST-ID.
      * STATUS '23' (NOT FOUND) -> WRITE ERROR, SET VALIDATION-FAILED.
      * ACCT-STATUS = 'C' (CLOSED) -> WRITE SKIPPED, SET VALIDAT-FAILED.
      * OTHER NON-ZERO STATUS -> DISPLAY ERROR, STOP RUN (FATAL).
      * IF VALIDATION-OK -> CALLS CHECK-DB2-BALANCE.
      **********************************************
       READ-ACCT-MASTER.
           MOVE OPR-ACCT-ID TO ACCT-MAST-ID.
           READ ACCT-MASTER RECORD KEY IS ACCT-MAST-ID
             INVALID KEY
                 ADD 1 TO ERR-COUNT
                 MOVE 'ERROR' TO WS-RECON-STATUS
                 MOVE 'ACCOUNT NOT FOUND IN KSDS' TO WS-DETAIL
                 PERFORM WRITE-RECON-LOG
                 SET VALIDATION-FAILED TO TRUE
             NOT INVALID KEY
                 IF ACCT-STATUS = 'C'
                    ADD 1 TO SKIP-COUNT
                    MOVE 'SKIPPED' TO WS-RECON-STATUS
                    MOVE 'ACCOUNT STATUS CLOSED' TO WS-DETAIL
                    PERFORM WRITE-RECON-LOG
                    SET VALIDATION-FAILED TO TRUE
                 END-IF
           END-READ.

           IF ACCT-MASTER-STATUS NOT = '00'
                                 AND ACCT-MASTER-STATUS NOT = '23'
              DISPLAY 'ERROR READ ACCT-MASTER FILE: ' ACCT-MASTER-STATUS
              STOP RUN
           END-IF.

           IF VALIDATION-OK
              PERFORM CHECK-DB2-BALANCE
           END-IF.

      **********************************************
      * FETCHES CURRENT BALANCE FROM DB2 TABLE TB_ACCOUNT_BAL.
      * SQLCODE = 0   -> CALLS CHECK-BALANCE-LOGIC.
      * SQLCODE = 100 -> ERROR: DB2 ROW MISSING, SET VALIDATION-FAILED.
      * SQLCODE < 0   -> ERROR: DB2 ERROR + SQLCODE, SET VALIDAT-FAILED.
      **********************************************
       CHECK-DB2-BALANCE.
           MOVE OPR-ACCT-ID TO WS-DB2-ACCT-ID.
           EXEC SQL
             SELECT BALANCE
               INTO :ACCT-BALANCE
               FROM TB_ACCOUNT_BAL
             WHERE ACCT_ID = :WS-DB2-ACCT-ID
           END-EXEC.

           EVALUATE TRUE
               WHEN SQLCODE = 0
                 PERFORM CHECK-BALANCE-LOGIC
               WHEN SQLCODE = 100
                  ADD 1 TO ERR-COUNT
                  MOVE 'ERROR' TO WS-RECON-STATUS
                  MOVE 'DB2 ROW MISSING' TO WS-DETAIL
                  PERFORM WRITE-RECON-LOG
                  SET VALIDATION-FAILED TO TRUE
               WHEN SQLCODE < 0
                  ADD 1 TO ERR-COUNT
                  MOVE 'ERROR' TO WS-RECON-STATUS
                  MOVE SQLCODE TO WS-SQLCODE
                  STRING 'DB2 ERROR: ' DELIMITED BY SIZE
                          WS-SQLCODE DELIMITED BY SIZE
                          INTO WS-DETAIL
                  END-STRING
                  PERFORM WRITE-RECON-LOG
                  SET VALIDATION-FAILED TO TRUE
           END-EVALUATE.

      **********************************************
      * CHECKS BALANCE LOGIC FOR DEBIT OPERATIONS.
      * OPR-TYPE 'D' AND ACCT-BALANCE < OPR-AMT:
      *   -> ERROR: NEGATIVE BALANCE AFTER OPR.
      * OPR-TYPE 'D' AND ACCT-BALANCE >= OPR-AMT:
      *   -> OK: BALANCE CHECK PASSED.
      * OPR-TYPE 'C':
      *   -> OK: BALANCE CHECK PASSED (NO OVERDRAFT RISK).
      **********************************************
       CHECK-BALANCE-LOGIC.
           IF OPR-TYPE = 'D'
              IF ACCT-BALANCE < OPR-AMT
                 ADD 1 TO ERR-COUNT
                 MOVE 'ERROR' TO WS-RECON-STATUS
                 MOVE 'NEGATIVE BALANCE AFTER OPR' TO WS-DETAIL
                 PERFORM WRITE-RECON-LOG
                 SET VALIDATION-FAILED TO TRUE
              ELSE
                 ADD 1 TO OK-COUNT
                 MOVE 'OK' TO WS-RECON-STATUS
                 MOVE 'BALANCE CHECK PASSED' TO WS-DETAIL
                 PERFORM WRITE-RECON-LOG
              END-IF
           ELSE
              IF OPR-TYPE = 'C'
                 ADD 1 TO OK-COUNT
                 MOVE 'OK' TO WS-RECON-STATUS
                 MOVE 'BALANCE CHECK PASSED' TO WS-DETAIL
                 PERFORM WRITE-RECON-LOG
              END-IF
           END-IF.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT OPR-LOG.
           IF OPR-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING OPR-LOG FILE: ' OPR-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT ACCT-MASTER.
           IF ACCT-MASTER-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING ACCT-MASTER FILE: '
                       ACCT-MASTER-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT RECON-LOG.
           IF RECON-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING RECON-LOG FILE: ' RECON-LOG-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * CLOSE ALL FILES AND CHECK STATUS
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE OPR-LOG.
           IF OPR-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING OPR-LOG FILE: ' OPR-STATUS
           END-IF.

           CLOSE ACCT-MASTER.
           IF ACCT-MASTER-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING ACCT-MASTER FILE: '
                       ACCT-MASTER-STATUS
           END-IF.

           CLOSE RECON-LOG.
           IF RECON-LOG-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING RECON-LOG FILE: '
                       RECON-LOG-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE TOTAL-READ TO TOTAL-READ-DISP.
           MOVE OK-COUNT TO OK-COUNT-DISP.
           MOVE ERR-COUNT TO ERR-COUNT-DISP.
           MOVE SKIP-COUNT TO SKIP-COUNT-DISP.
           MOVE WRITE-COUNT TO WRITE-COUNT-DISP.

           DISPLAY '========================================'.
           DISPLAY 'OPERATION SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'TOTAL OPERATIONS READ: ' TOTAL-READ-DISP.
           DISPLAY 'OPERATIONS OK:         ' OK-COUNT-DISP.
           DISPLAY 'OPERATIONS ERROR:      ' ERR-COUNT-DISP.
           DISPLAY 'OPERATIONS SKIPPED:    ' SKIP-COUNT-DISP.
           DISPLAY 'RECORDS WRITTEN:       ' WRITE-COUNT-DISP.
           DISPLAY '========================================'.
