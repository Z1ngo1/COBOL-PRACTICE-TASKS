      ******************************************************************
      * ROBUST PAYMENT BATCH                                           *
      *                                                                *
      * PURPOSE:                                                       *
      * READS PAYMENT FILE (PS), FINDS CUSTOMER IN VSAM, UPDATES       *
      * BALANCE IN DB2, LOGS ALL RESULTS AND SETS RETURN-CODE          *
      * BASED ON ERROR SEVERITY.                                       *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - VALIDATE INPUT PAYMENT RECORD:                     *
      *     PAYMENT-ID = SPACES OR AMOUNT <= 0 OR                      *
      *     TYPE NOT IN (C,T,A) -> LOG ERROR, INCREMENT SKIP-COUNT.    *
      *   PHASE 2 - RANDOM READ VSAM BY CUST-ID:                       *
      *     STATUS '23': LOG NOT FOUND, INCREMENT SKIP-COUNT.          *
      *     OTHER NON-ZERO: LOG ERROR, ROLLBACK, RC=12, STOP LOOP.     *
      *   PHASE 3 - CHECK ACCOUNT STATUS:                              *
      *     'S' (SUSPENDED): LOG REJECTED, INCREMENT SKIP-COUNT.       *
      *     OTHER (ACTIVE): PROCEED TO DB2 UPDATE.                     *
      *   PHASE 4 - UPDATE TB_CUSTOMER_BALANCE IN DB2:                 *
      *     SQLCODE  0:    LOG SUCCESS, INCREMENT SUCCESS-COUNT.       *
      *     SQLCODE -911:  DEADLOCK, ROLLBACK, RC=12, STOP LOOP.       *
      *     SQLCODE < 0:   DB2 ERROR, ROLLBACK, RC=8, STOP LOOP.       *
      *   POST-LOOP - FINAL RETURN-CODE (IF RC STILL 0):               *
      *     ERROR-COUNT > 10: RC=16.                                   *
      *     ERROR-COUNT >  0: RC=4.                                    *
      *     ERROR-COUNT =  0: RC=0.                                    *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE:   2026/01/28                                             *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  INPDD  (PAYMENTS)      - PS PAYMENT INPUT              *
      *         VSAMDD (CUSTOMER.MST)  - VSAM KSDS CUSTOMER MASTER     *
      * OUTPUT: LOGDD  (PAYMENT.LOG)   - PS LOG OF RESULTS/ERRORS      *
      *                                                                *
      * DB2 OBJECTS:                                                   *
      * TB_CUSTOMER_BALANCE - CUSTOMER BALANCE AND LAST PAYMENT        *
      * DCLGEN: TASK26         - HOST VARIABLES FOR DB2 UPDATE         *
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. DB2VSM26.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

           SELECT PAYMENT-FILE ASSIGN TO INPDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS PAYMENT-STATUS.

      * VSAM KSDS OPENED INPUT FOR RANDOM READ ONLY.
           SELECT VSAM-FILE ASSIGN TO VSAMDD
              ORGANIZATION IS INDEXED
              ACCESS MODE IS RANDOM
              RECORD KEY IS VSAM-ID
              FILE STATUS IS VSAM-STATUS.

           SELECT PAYMENT-LOG-FILE ASSIGN TO LOGDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS PAYMENT-LOG-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD PAYMENT-FILE RECORDING MODE IS F.
       01 PAYMENT-REC.
          05 PAYMENT-ID PIC X(6).
          05 PMT-CUST-ID PIC X(5).
          05 PMT-AMOUNT PIC 9(5)V99.
          05 PAYMENT-TYPE PIC X(1).
          05 FILLER PIC X(61).

       FD VSAM-FILE.
       01 VSAM-REC.
          05 VSAM-ID PIC X(5).
          05 VSAM-CUST-NAME PIC X(25).
          05 VSAM-ACCT-STATUS PIC X(1).

       FD PAYMENT-LOG-FILE RECORDING MODE V.
       01 PAYMENT-LOG-REC PIC X(80).

       WORKING-STORAGE SECTION.

      * SQL COMMUNICATION AREA
           EXEC SQL
             INCLUDE SQLCA
           END-EXEC.

      * DCLGEN FOR TB_CUSTOMER_BALANCE
           EXEC SQL
             INCLUDE TASK26
           END-EXEC.

      * FILE STATUS VARIABLES
       01 WS-FILE-STATUSES.
          05 PAYMENT-STATUS PIC X(2).
          05 VSAM-STATUS PIC X(2).
          05 PAYMENT-LOG-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-EOF PIC X(1) VALUE 'N'.
             88 EOF VALUE 'Y'.
          05 ERROR-FLAG PIC X(1) VALUE 'N'.
             88 WS-ERROR VALUE 'Y'.

      * PROCESSING COUNTERS
       01 WS-COUNTERS.
          05 TOTAL-COUNT PIC 9(5) VALUE 0.
          05 SUCCESS-COUNT PIC 9(5) VALUE 0.
          05 ERROR-COUNT PIC 9(5) VALUE 0.
          05 SKIP-COUNT PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS
       01 WS-DISP-COUNTERS.
          05 TOTAL-COUNT-DISP PIC Z(4)9.
          05 SUCCESS-COUNT-DISP PIC Z(4)9.
          05 ERROR-COUNT-DISP PIC Z(4)9.
          05 SKIP-COUNT-DISP PIC Z(4)9.

      * LOG MESSAGE BUFFER
       01 WS-MSG PIC X(80).

      * DB2 HOST VARIABLES FOR AMOUNT AND CUSTOMER ID
       01 PMT-DB2-AMOUNT PIC S9(7)V99 COMP-3.
       01 CUST-DB2-ID PIC X(5).

      * DISPLAY FIELDS FOR SQLCODE AND RETURN-CODE
       77 WS-SQLCODE-DISP  PIC -Z(9)9.
       77 WS-RC-DISP       PIC -Z9.

      **********************************************
      * MAIN FLOW: OPEN -> INIT -> PROCESS -> FINAL
      * -> FINAL-LOG -> CLOSE
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-PARA.
           PERFORM INITIALIZE-PARA.
           PERFORM READ-PS-PARA.
           PERFORM FINAL-PARA.
           PERFORM FINAL-LOG.
           PERFORM CLOSE-PARA.
           STOP RUN.

      **********************************************
      * ZEROES COUNTERS, RETURN-CODE AND BUFFERS
      * BEFORE PROCESSING BEGINS.
      **********************************************
       INITIALIZE-PARA.
           MOVE ZERO TO WS-COUNTERS.
           MOVE 0 TO RETURN-CODE.
           MOVE SPACES TO WS-MSG.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-PARA.
           OPEN INPUT PAYMENT-FILE.
           IF PAYMENT-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING INPUT FILE: ' PAYMENT-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT VSAM-FILE.
           IF VSAM-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING VSAM FILE: ' VSAM-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT PAYMENT-LOG-FILE.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING LOG FILE: ' PAYMENT-LOG-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * READS PAYMENT-FILE TO EOF OR UNTIL FATAL ERROR (WS-ERROR).
      * PER RECORD: VALIDATES INPUT FIELDS (PHASE 1).
      * VALID RECORDS CALL READ-VSAM-PARA (PHASES 2-4).
      * INCREMENTS TOTAL-COUNT FOR EACH RECORD READ.
      **********************************************
       READ-PS-PARA.
           PERFORM UNTIL EOF OR WS-ERROR
              READ PAYMENT-FILE
                AT END
                   SET EOF TO TRUE
                NOT AT END
                   IF PAYMENT-STATUS NOT = '00'
                      DISPLAY 'ERROR READING INPUT FILE: '
                          PAYMENT-STATUS
                      EXEC SQL
                        ROLLBACK WORK
                      END-EXEC
                      STOP RUN
                   END-IF
                   ADD 1 TO TOTAL-COUNT
      * LEVEL 1: BASIC INPUT VALIDATION
                   IF PAYMENT-ID = SPACES OR
                      PMT-AMOUNT <= 0 OR
                      (PAYMENT-TYPE NOT = 'C' AND
                      PAYMENT-TYPE NOT = 'T' AND
                      PAYMENT-TYPE NOT = 'A')
                      MOVE 'VALIDATION ERROR: INVALID PAYMENT RECORD'
                        TO WS-MSG
                      PERFORM WRITE-MSG-LOG
                      ADD 1 TO SKIP-COUNT
                   ELSE
      * LEVEL 2/3/4: VSAM READ, STATUS CHECK, DB2 UPDATE
                      PERFORM READ-VSAM-PARA
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * RANDOM READ VSAM BY PMT-CUST-ID.
      * STATUS '23': LOG NOT FOUND, SKIP.
      * OTHER NON-ZERO: LOG ERROR, ROLLBACK,
      *   RC=12, SET WS-ERROR TO STOP LOOP.
      * FOUND: CALL CHECK-ACCT-STATUS (PHASE 3).
      **********************************************
       READ-VSAM-PARA.
           MOVE PMT-CUST-ID TO VSAM-ID.
           READ VSAM-FILE
             INVALID KEY
               IF VSAM-STATUS = '23'
                  STRING 'NOT FOUND: CUSTOMER ID ' DELIMITED BY SIZE
                         VSAM-ID DELIMITED  BY SIZE
                         INTO WS-MSG
                  END-STRING
                  PERFORM WRITE-MSG-LOG
                  ADD 1 TO SKIP-COUNT
               ELSE
                  STRING 'VSAM ERROR: ' DELIMITED BY SIZE
                         VSAM-STATUS DELIMITED  BY SIZE
                         INTO WS-MSG
                  END-STRING
                  PERFORM WRITE-MSG-LOG
                  ADD 1 TO ERROR-COUNT
                  EXEC SQL
                    ROLLBACK WORK
                  END-EXEC
                  MOVE 12 TO RETURN-CODE
                  SET WS-ERROR TO TRUE
               END-IF
      * LEVEL 3: CHECK ACCOUNT STATUS BEFORE DB2 UPDATE
             NOT INVALID KEY
               PERFORM CHECK-ACCT-STATUS
           END-READ.

      **********************************************
      * CHECKS VSAM-ACCT-STATUS.
      * 'S' (SUSPENDED): LOG REJECTED, SKIP.
      * OTHER (ACTIVE): CALL UPDATE-DB2-PARA (PHASE 4).
      **********************************************
       CHECK-ACCT-STATUS.
           IF VSAM-ACCT-STATUS = 'S'
              MOVE 'ACCOUNT SUSPENDED: PAYMENT REJECTED' TO WS-MSG
              PERFORM WRITE-MSG-LOG
              ADD 1 TO SKIP-COUNT
           ELSE
      * LEVEL 4: ACTIVE ACCOUNT - PERFORM DB2 BALANCE UPDATE
              PERFORM UPDATE-DB2-PARA
           END-IF.

      **********************************************
      * MOVES AMOUNT AND CUST-ID TO DB2 HOST VARS, THEN
      * UPDATES CUST_BALANCE AND LAST_PAYMENT IN TB_CUSTOMER_BALANCE.
      * SQLCODE 0: LOG SUCCESS, INCREMENT SUCCESS-COUNT.
      * SQLCODE -911: DEADLOCK, ROLLBACK, RC=12, SET WS-ERROR.
      * SQLCODE < 0: DB2 ERROR, LOG CODE, ROLLBACK, RC=8, SET WS-ERROR.
      **********************************************
       UPDATE-DB2-PARA.
           MOVE PMT-AMOUNT TO PMT-DB2-AMOUNT.
           MOVE VSAM-ID TO CUST-DB2-ID.

           EXEC SQL
             UPDATE TB_CUSTOMER_BALANCE
                SET CUST_BALANCE = CUST_BALANCE + :PMT-DB2-AMOUNT,
                    LAST_PAYMENT = CURRENT TIMESTAMP
                WHERE CUST_ID = :CUST-DB2-ID
           END-EXEC.

           EVALUATE TRUE
               WHEN SQLCODE = 0
                 MOVE 'SUCCESS: PAYMENT PROCESSED' TO WS-MSG
                 ADD 1 TO SUCCESS-COUNT
                 PERFORM WRITE-MSG-LOG
               WHEN SQLCODE = -911
                 MOVE 'DEADLOCK: RETRY MECHANISM NEEDED' TO WS-MSG
                 ADD 1 TO ERROR-COUNT
                 PERFORM WRITE-MSG-LOG
                 EXEC SQL
                   ROLLBACK WORK
                 END-EXEC
                 MOVE 12 TO RETURN-CODE
                 SET WS-ERROR TO TRUE
               WHEN SQLCODE < 0
                 MOVE SQLCODE TO WS-SQLCODE-DISP
                 STRING 'DB2 ERROR: ' DELIMITED BY SIZE
                        WS-SQLCODE-DISP DELIMITED BY SIZE
                        INTO WS-MSG
                 END-STRING
                 ADD 1 TO ERROR-COUNT
                 PERFORM WRITE-MSG-LOG
                 EXEC SQL
                   ROLLBACK WORK
                 END-EXEC
                 MOVE 8 TO RETURN-CODE
                 SET WS-ERROR TO TRUE
           END-EVALUATE.

      **********************************************
      * SETS FINAL RETURN-CODE BASED ON ERROR-COUNT
      * ONLY IF RC IS STILL 0 (NO FATAL DB2/VSAM ERROR OCCURRED).
      * ERROR-COUNT > 10: RC=16 (HIGH SEVERITY)
      * ERROR-COUNT > 0: RC=4 (WARNINGS EXIST)
      * ERROR-COUNT = 0: RC=0 (CLEAN RUN)
      **********************************************
       FINAL-PARA.
           IF RETURN-CODE = 0
              EVALUATE TRUE
                  WHEN ERROR-COUNT > 10
                    MOVE 16 TO RETURN-CODE
                  WHEN ERROR-COUNT > 0
                    MOVE 4 TO RETURN-CODE
                  WHEN OTHER
                    MOVE 0 TO RETURN-CODE
              END-EVALUATE
           END-IF.

      **********************************************
      * MOVES COUNTERS TO EDITED FIELDS AND WRITES
      * SUMMARY SECTION TO PAYMENT-LOG-FILE.
      * STOPS ON ANY NON-ZERO PAYMENT-LOG-STATUS.
      **********************************************
       FINAL-LOG.
           MOVE TOTAL-COUNT TO TOTAL-COUNT-DISP.
           MOVE SUCCESS-COUNT TO SUCCESS-COUNT-DISP.
           MOVE ERROR-COUNT TO ERROR-COUNT-DISP.
           MOVE SKIP-COUNT TO SKIP-COUNT-DISP.

           MOVE '-------------------------------------' TO
                 PAYMENT-LOG-REC
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING LOG HEADER: ' PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

           STRING 'TOTAL PROCESSED: ' DELIMITED BY SIZE
                  FUNCTION TRIM(TOTAL-COUNT-DISP) DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING TOTAL PROCESSED LINE: '
                  PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

           STRING 'SUCCESSFUL: ' DELIMITED BY SIZE
                  FUNCTION TRIM(SUCCESS-COUNT-DISP) DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING SUCCESSFUL LINE: '
                  PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

           STRING 'ERRORS: ' DELIMITED BY SIZE
                  FUNCTION TRIM(ERROR-COUNT-DISP) DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING ERROR LINE: ' PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

           STRING 'SKIPPED: ' DELIMITED BY SIZE
                  FUNCTION TRIM(SKIP-COUNT-DISP) DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING SKIPPED LINE: ' PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

           MOVE RETURN-CODE TO WS-RC-DISP
           STRING 'RETURN CODE: ' DELIMITED BY SIZE
                  FUNCTION TRIM(WS-RC-DISP) DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING RETURN CODE LINE: '
                  PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

      **********************************************
      * BUILDS ONE LOG LINE, WRITES TO PAYMENT-LOG-FILE.
      * ON WRITE FAILURE: ROLLBACK, STOP RUN.
      * CLEARS WS-MSG AND LOG BUFFER AFTER WRITE.
      **********************************************
       WRITE-MSG-LOG.
           STRING PAYMENT-ID DELIMITED BY SIZE
                  ' ' DELIMITED BY SIZE
                  WS-MSG DELIMITED BY SIZE
                  INTO PAYMENT-LOG-REC
           END-STRING.
           WRITE PAYMENT-LOG-REC.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING MESSAGE LOG: ' PAYMENT-LOG-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE SPACES TO WS-MSG.
           MOVE ALL SPACES TO PAYMENT-LOG-REC.

      **********************************************
      * FINAL COMMIT (ONLY IF NO FATAL ERROR OCCURRED),
      * CLOSE ALL FILES AND CHECK STATUS.
      **********************************************
       CLOSE-PARA.
           IF NOT WS-ERROR
              EXEC SQL
                COMMIT WORK
              END-EXEC
              IF SQLCODE NOT = 0
                 DISPLAY 'FINAL COMMIT ERROR: ' SQLCODE
                 EXEC SQL
                   ROLLBACK WORK
                 END-EXEC
                 STOP RUN
              END-IF
           END-IF.

           CLOSE PAYMENT-FILE.
           IF PAYMENT-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING INPUT FILE: '
                  PAYMENT-STATUS
           END-IF.
           CLOSE VSAM-FILE.
           IF VSAM-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING VSAM FILE: ' VSAM-STATUS
           END-IF.
           CLOSE PAYMENT-LOG-FILE.
           IF PAYMENT-LOG-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING LOG FILE: '
                  PAYMENT-LOG-STATUS
           END-IF.
