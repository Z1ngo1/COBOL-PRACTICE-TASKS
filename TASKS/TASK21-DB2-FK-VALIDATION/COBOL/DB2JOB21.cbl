      ******************************************************************
      * DB2 ORDER LOADER - ORDERS WITH PRODUCT VALIDATION              *
      *                                                                *
      * PURPOSE:                                                       *
      * READS ORDER RECORDS FROM INPUT FILE, VALIDATES EACH RECORD,    *
      * CHECKS WHETHER THE PRODUCT EXISTS IN TB_PRODUCTS, AND INSERTS  *
      * VALID ORDERS INTO TB_ORDERS. REJECTED ORDERS ARE LOGGED.       *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - VALIDATE:                                          *
      *     ORD-ID NOT SPACES AND NOT IN WS-SEEN-ORDERS ARRAY.         *
      *     ORD-DATE MONTH IN '01'-'12'.                               *
      *     ORD-QUANTITY >= 1.                                         *
      *     ANY FAILURE: SET VALID-ERROR, LOG, SKIP DB2 WORK.          *
      *   PHASE 2 - PRODUCT LOOKUP:                                    *
      *     SELECT PROD_NAME, UNIT_PRICE FROM TB_PRODUCTS.             *
      *     SQLCODE   0  : FOUND -> PERFORM INSERT-ORDER.              *
      *     SQLCODE 100  : NOT FOUND -> LOG REJECT, SKIP.              *
      *     OTHER        : LOG SELECT ERROR, SKIP.                     *
      *   PHASE 3 - INSERT:                                            *
      *     INSERT INTO TB_ORDERS.                                     *
      *     SQLCODE   0   : LOG SUCCESS, ADD ID TO WS-SEEN-ORDERS.     *
      *     SQLCODE -803  : DUPLICATE ORDER_ID -> LOG REJECT.          *
      *     CRITICAL CODES: ROLLBACK AND STOP RUN.                     *
      *   PHASE 4 - COMMIT EVERY 100 SUCCESSFUL INSERTS.               *
      *     FINAL COMMIT IN CLOSE-ALL-FILES FOR REMAINDER.             *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/17                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  INDD (ORDERS.LOAD) - INPUT FILE (PS, 80 BYTE)          *
      * OUTPUT: OUTDD (ORDER.LOG) - PROCESSING LOG FILE (PS, 80 BYTE)  *
      * DB2 TABLE: TB_PRODUCTS - PRODUCT MASTER TABLE (SELECT)         *
      * DB2 TABLE: TB_ORDERS - ORDERS TABLE (INSERT)                   *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. DB2JOB21.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.

           SELECT ORDER-FILE ASSIGN TO INDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS ORDER-STATUS.

           SELECT LOG-FILE ASSIGN TO OUTDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS OUT-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD ORDER-FILE RECORDING MODE IS F.
       01 ORDER-REC.
          05 IN-ORDER-ID PIC X(6).
          05 IN-ORDER-DATE PIC 9(8).
          05 IN-PROD-ID PIC X(5).
          05 IN-QUANTITY PIC 9(4).
          05 FILLER PIC X(57).

       FD LOG-FILE RECORDING MODE IS V.
       01 LOG-REC PIC X(80).

       WORKING-STORAGE SECTION.

      * SQL COMMUNICATION AREA
          EXEC SQL
            INCLUDE SQLCA
          END-EXEC.

      * DB2 HOST VARIABLES
       01 HV-ORDER-ID PIC X(6).
       01 HV-ORDER-DATE PIC X(10).
       01 HV-PROD-ID PIC X(5).
       01 HV-QUANTITY PIC S9(4) COMP-3.
       01 HV-PROD-NAME PIC X(30).
       01 HV-UNIT-PRICE PIC S9(5)V99 COMP-3.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 ORDER-STATUS PIC X(2).
          05 OUT-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-EOF PIC X(1) VALUE 'N'.
          05 WS-ERROR-FIND PIC X(1) VALUE 'N'.
          05 WS-FOUND-FLAG PIC X(1) VALUE 'N'.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 RECORDS-PROCESSED PIC 9(5) VALUE 0.
          05 RECORDS-INSERTED PIC 9(5) VALUE 0.
          05 RECORDS-ERRORS PIC 9(5) VALUE 0.
          05 COMMIT-COUNTER PIC 9(5) VALUE 0.
          05 COMMIT-BATCHES PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS
       01 WS-DISP-COUNTERS.
          05 RECORDS-PROCESSED-DISP PIC Z(4)9.
          05 RECORDS-INSERTED-DISP PIC Z(4)9.
          05 RECORDS-ERRORS-DISP PIC Z(4)9.
          05 COMMIT-COUNTER-DISP PIC Z(4)9.
          05 COMMIT-BATCHES-DISP PIC Z(4)9.

      * FORMATTED SQLCODE FOR DISPLAY
       77 WS-SQLCODE-DISP PIC -Z(9)9.

      * FORMATTED UNIT PRICE FOR LOG MESSAGE
       01 WS-PRICE-DISP PIC Z(4)9.99.

      * MESSAGE FOR LOG
       01 WS-MSG PIC X(80).

      * ORDER DATE PARTS
       01 WS-ORDER-DATE.
          05 WS-YEAR PIC X(4).
          05 WS-MONTH PIC X(2).
          05 WS-DAY PIC X(2).

      * ARRAY TO TRACK ALREADY PROCESSED ORDER-ID
       01 PROCESSED-ORDERS.
          05 PROCESSED-ORDER PIC X(6) OCCURS 100 TIMES.
       01 PROCESSED-COUNT PIC 9(3) VALUE 0.
       01 IDX PIC 9(3).

      *******************************
      * OPENS FILES, PROCESSES ALL RECORDS, WRITES
      * SUMMARY TO LOG FILE, CLOSES FILES AND
      * DISPLAYS SYSOUT SUMMARY.
      *******************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM PROCESS-ALL-RECORDS.
           PERFORM WRITE-SUMMARY.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      *******************************
      * OPEN ALL FILES AND CHECK STATUS
      *******************************
       OPEN-ALL-FILES.
           OPEN INPUT ORDER-FILE.
           IF ORDER-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING INP STATUS: ' ORDER-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT LOG-FILE.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING OUT STATUS: ' OUT-STATUS
              STOP RUN
           END-IF.

      *******************************
      * READS ORDER-FILE UNTIL EOF.
      * RESETS VALID-ERROR FLAG PER RECORD.
      * RUNS ALL 3 VALIDATIONS (EACH LOGS ITS OWN ERROR).
      * IF VALID: PROCESS-ORDER + COMMIT CHECK.
      * COMMIT EVERY 100 SUCCESSFUL INSERTS.
      *******************************
       PROCESS-ALL-RECORDS.
           PERFORM UNTIL WS-EOF = 'Y'
              MOVE 'N' TO WS-ERROR-FIND
              MOVE SPACES TO WS-MSG
              MOVE ALL SPACES TO LOG-REC
              READ ORDER-FILE
                AT END
                   MOVE 'Y' TO WS-EOF
                NOT AT END
                   IF ORDER-STATUS NOT = '00'
                      DISPLAY 'ERROR READING INPUT FILE: ' ORDER-STATUS
                      EXEC SQL
                        ROLLBACK WORK
                      END-EXEC
                      STOP RUN
                   END-IF
                   ADD 1 TO RECORDS-PROCESSED
                   PERFORM VALIDATE-ORDER-ID
                   PERFORM VALIDATE-ORDER-DATE
                   PERFORM VALIDATE-QUANTITY
                   IF WS-ERROR-FIND = 'N'
                      PERFORM CHECK-PRODUCT-AND-INSERT
                      IF WS-ERROR-FIND = 'N'
                         ADD 1 TO COMMIT-COUNTER
                         IF COMMIT-COUNTER >= 100
                            EXEC SQL
                              COMMIT WORK
                            END-EXEC
                            IF SQLCODE NOT = 0
                               MOVE SQLCODE TO WS-SQLCODE-DISP
                               DISPLAY 'BATCH COMMIT ERROR: '
                                       WS-SQLCODE-DISP
                               EXEC SQL
                                 ROLLBACK WORK
                               END-EXEC
                               STOP RUN
                            END-IF
                            ADD 1 TO COMMIT-BATCHES
                            MOVE 0 TO COMMIT-COUNTER
                         END-IF
                      END-IF
                   END-IF
              END-READ
           END-PERFORM.

      *******************************
      * VALIDATES ORD-ID NOT SPACES.
      * THEN SCANS WS-SEEN-ORDERS FOR DUPLICATE.
      * SETS VALID-ERROR AND LOGS IF EMPTY OR DUP.
      *******************************
       VALIDATE-ORDER-ID.
           IF IN-ORDER-ID = SPACES
              MOVE 'Y' TO WS-ERROR-FIND
              MOVE 'REJECTED (VALIDATION ERROR: ORDER-ID IS EMPTY)'
                    TO WS-MSG
              ADD 1 TO RECORDS-ERRORS
              PERFORM WRITE-LOG-MESSAGE
           ELSE
              MOVE 'N' TO WS-FOUND-FLAG
              PERFORM VARYING IDX FROM 1 BY 1
                 UNTIL IDX > PROCESSED-COUNT
                 IF PROCESSED-ORDER(IDX) = IN-ORDER-ID
                    MOVE 'Y' TO WS-FOUND-FLAG
                    EXIT PERFORM
                 END-IF
              END-PERFORM
              IF WS-FOUND-FLAG = 'Y'
                 MOVE 'Y' TO WS-ERROR-FIND
                 STRING 'REJECTED (VALIDATION ERROR: DUPLICATE ORDERID '
                             DELIMITED BY SIZE
                        IN-ORDER-ID DELIMITED BY SIZE
                        ')' DELIMITED BY SIZE
                        INTO WS-MSG
                 END-STRING
                 ADD 1 TO RECORDS-ERRORS
                 PERFORM WRITE-LOG-MESSAGE
              ELSE
                 CONTINUE
              END-IF
           END-IF.

      *******************************
      * VALIDATES ORD-DATE MONTH IN '01'-'12'.
      * SKIPS CHECK IF VALID-ERROR ALREADY SET.
      * SETS HV-ORDER-DATE (YYYY-MM-DD) IF VALID.
      *******************************
       VALIDATE-ORDER-DATE.
           IF WS-ERROR-FIND = 'Y'
              CONTINUE
           ELSE
             MOVE IN-ORDER-DATE(1:4) TO WS-YEAR
             MOVE IN-ORDER-DATE(5:2) TO WS-MONTH
             MOVE IN-ORDER-DATE(7:2) TO WS-DAY
             IF WS-MONTH < '01' OR WS-MONTH > '12'
                MOVE 'Y' TO WS-ERROR-FIND
                STRING 'REJECTED (INVALID DATE: ' DELIMITED BY SIZE
                        IN-ORDER-DATE DELIMITED BY SIZE
                        ')' DELIMITED BY SIZE
                        INTO WS-MSG
                END-STRING
                ADD 1 TO RECORDS-ERRORS
                PERFORM WRITE-LOG-MESSAGE
             ELSE
                STRING WS-YEAR DELIMITED BY SIZE
                       '-' DELIMITED BY SIZE
                       WS-MONTH DELIMITED BY SIZE
                       '-' DELIMITED BY SIZE
                       WS-DAY DELIMITED BY SIZE
                       INTO HV-ORDER-DATE
                END-STRING
             END-IF
           END-IF.

      *******************************
      * VALIDATES ORD-QUANTITY >= 1.
      * SKIPS CHECK IF VALID-ERROR ALREADY SET.
      * SETS VALID-ERROR AND LOGS IF ZERO.
      *******************************
       VALIDATE-QUANTITY.
             IF WS-ERROR-FIND = 'Y'
                CONTINUE
             ELSE
               IF IN-QUANTITY < 1
                  MOVE 'Y' TO WS-ERROR-FIND
                  STRING 'REJECTED (PRODUCT ' DELIMITED BY SIZE
                         IN-PROD-ID DELIMITED BY SIZE
                         ' QUANTITY MUST BE > 0' DELIMITED BY SIZE
                         INTO WS-MSG
                  END-STRING
                  ADD 1 TO RECORDS-ERRORS
                  PERFORM WRITE-LOG-MESSAGE
               END-IF
             END-IF.

      *******************************
      * MOVES RECORD FIELDS TO HOST VARIABLES.
      * SELECTS PROD_NAME, UNIT_PRICE FROM TB_PRODUCTS.
      *   SQLCODE   0  : PRODUCT FOUND -> INSERT-ORDER.
      *   SQLCODE 100  : NOT FOUND -> LOG REJECT.
      *   CRITICAL CODE: ROLLBACK AND STOP RUN.
      *   OTHER ERROR  : LOG SELECT ERROR.
      *******************************
       CHECK-PRODUCT-AND-INSERT.
           MOVE IN-PROD-ID TO HV-PROD-ID.
           MOVE IN-ORDER-ID TO HV-ORDER-ID.
           MOVE IN-QUANTITY TO HV-QUANTITY.

           EXEC SQL
             SELECT PROD_NAME,UNIT_PRICE
               INTO :HV-PROD-NAME, :HV-UNIT-PRICE
               FROM TB_PRODUCTS
             WHERE PROD_ID = :HV-PROD-ID
           END-EXEC.

           EVALUATE SQLCODE
               WHEN 0
                   PERFORM INSERT-ORDER
               WHEN 100
                   MOVE 'Y' TO WS-ERROR-FIND
                   STRING 'REJECTED (PRODUCT ' DELIMITED BY SIZE
                          HV-PROD-ID DELIMITED BY SIZE
                          ' NOT FOUND IN TB_PRODUCTS)' DELIMITED BY SIZE
                          INTO WS-MSG
                   END-STRING
                   ADD 1 TO RECORDS-ERRORS
                   PERFORM WRITE-LOG-MESSAGE
               WHEN OTHER
                   MOVE 'Y' TO WS-ERROR-FIND
                   MOVE SQLCODE TO WS-SQLCODE-DISP
                   IF SQLCODE < -900
                      DISPLAY 'CRITICAL SELECT ERROR: ' WS-SQLCODE-DISP
                      DISPLAY 'ORDER ID: ' HV-ORDER-ID
                      EXEC SQL
                        ROLLBACK WORK
                      END-EXEC
                      STOP RUN
                   END-IF
                   STRING 'REJECTED (SELECT ERROR: SQLCODE= ' DELIMITED
                              BY SIZE
                          WS-SQLCODE-DISP DELIMITED BY SIZE
                          ')' DELIMITED BY SIZE
                          INTO WS-MSG
                   END-STRING
                   ADD 1 TO RECORDS-ERRORS
                   PERFORM WRITE-LOG-MESSAGE
           END-EVALUATE.

      *******************************
      * INSERTS VALIDATED ORDER INTO TB_ORDERS.
      * SQLCODE 0: ADD TO WS-SEEN-ORDERS, LOG OK.
      * SQLCODE -803: DUPLICATE KEY -> LOG REJECT.
      * CRITICAL CODE: ROLLBACK AND STOP RUN.
      * OTHER ERROR : LOG INSERT ERROR.
      *******************************
       INSERT-ORDER.
           EXEC SQL
             INSERT INTO TB_ORDERS
                (ORDER_ID, ORDER_DATE, PROD_ID, QUANTITY)
             VALUES
                (:HV-ORDER-ID,
                 :HV-ORDER-DATE,
                 :HV-PROD-ID,
                 :HV-QUANTITY)
           END-EXEC.

           EVALUATE SQLCODE
               WHEN 0
                 IF PROCESSED-COUNT < 100
                    ADD 1 TO PROCESSED-COUNT
                    MOVE IN-ORDER-ID TO PROCESSED-ORDER(PROCESSED-COUNT)
                 ELSE
                    DISPLAY 'WARNING: SEEN-ORDERS ARRAY FULL'
                            ', DUPE CHECK DISABLED'
                 END-IF
                 MOVE HV-UNIT-PRICE TO WS-PRICE-DISP
                 STRING 'INSERTED (PRODUCT: ' DELIMITED BY SIZE
                        HV-PROD-ID DELIMITED BY SIZE
                        ' FOUND, PRICE: ' DELIMITED BY SIZE
                        FUNCTION TRIM(WS-PRICE-DISP) DELIMITED BY SIZE
                        ')' DELIMITED BY SIZE
                        INTO WS-MSG
                 END-STRING
                 ADD 1 TO RECORDS-INSERTED
                 PERFORM WRITE-LOG-MESSAGE
               WHEN -803
                 MOVE 'Y' TO WS-ERROR-FIND
                 STRING 'REJECTED (DUPLIC ORDER ID: ' DELIMITED BY SIZE
                        HV-ORDER-ID DELIMITED BY SIZE
                        ')' DELIMITED BY SIZE
                        INTO WS-MSG
                 END-STRING
                 ADD 1 TO RECORDS-ERRORS
                 PERFORM WRITE-LOG-MESSAGE
               WHEN OTHER
                 MOVE 'Y' TO WS-ERROR-FIND
                 MOVE SQLCODE TO WS-SQLCODE-DISP
                 IF SQLCODE < -900
                    DISPLAY 'CRITICAL INSERT ERROR: ' WS-SQLCODE-DISP
                    DISPLAY 'ORDER ID: ' HV-ORDER-ID
                    EXEC SQL
                      ROLLBACK WORK
                    END-EXEC
                    STOP RUN
                 END-IF
                 STRING 'REJECTED (DB2 ERROR: SQLCODE=' DELIMITED BY
                          SIZE
                        WS-SQLCODE-DISP DELIMITED BY SIZE
                        ')' DELIMITED BY SIZE
                        INTO WS-MSG
                 END-STRING
                 ADD 1 TO RECORDS-ERRORS
                 PERFORM WRITE-LOG-MESSAGE
           END-EVALUATE.

      *******************************
      * WRITES WS-LOG-MSG TO LOG-FILE PREFIXED WITH ORD-ID.
      * CLEARS BOTH BUFFERS AFTER WRITE.
      * ROLLBACK AND STOP ON WRITE FAILURE.
      *******************************
       WRITE-LOG-MESSAGE.
           STRING IN-ORDER-ID DELIMITED BY SIZE
                  ' ' DELIMITED BY SIZE
                  WS-MSG DELIMITED BY SIZE
                  INTO LOG-REC
           END-STRING.
           WRITE LOG-REC.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING OUTPUT FILE: ' OUT-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.
           MOVE SPACES TO WS-MSG.
           MOVE ALL SPACES TO LOG-REC.

      *******************************
      * WRITE STATISTICS TO OUTPUT FILE
      *******************************
       WRITE-SUMMARY.
           MOVE RECORDS-PROCESSED TO RECORDS-PROCESSED-DISP.
           MOVE RECORDS-INSERTED TO RECORDS-INSERTED-DISP.
           MOVE RECORDS-ERRORS TO RECORDS-ERRORS-DISP.

           MOVE ALL SPACES TO LOG-REC.
           STRING 'TOTAL PROCESSED: ' DELIMITED BY SIZE
                 FUNCTION TRIM(RECORDS-PROCESSED-DISP) DELIMITED BY SIZE
                 INTO LOG-REC
           END-STRING
           WRITE LOG-REC.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING SUMMARY: ' OUT-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO LOG-REC.
           STRING 'TOTAL INSERTED: ' DELIMITED BY SIZE
                  FUNCTION TRIM(RECORDS-INSERTED-DISP) DELIMITED BY SIZE
                  INTO LOG-REC
           END-STRING
           WRITE LOG-REC.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING SUMMARY: ' OUT-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.

           MOVE ALL SPACES TO LOG-REC.
           STRING 'TOTAL REJECTED: ' DELIMITED BY SIZE
                  FUNCTION TRIM(RECORDS-ERRORS-DISP) DELIMITED BY SIZE
                  INTO LOG-REC
           END-STRING
           WRITE LOG-REC.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING SUMMARY: ' OUT-STATUS
              EXEC SQL
                ROLLBACK WORK
              END-EXEC
              STOP RUN
           END-IF.

      *******************************
      * FINAL COMMIT AND CLOSE ALL FILES
      *******************************
       CLOSE-ALL-FILES.
           IF COMMIT-COUNTER > 0
              EXEC SQL
                COMMIT WORK
              END-EXEC
              IF SQLCODE NOT = 0
                 MOVE SQLCODE TO WS-SQLCODE-DISP
                 DISPLAY 'FINAL COMMIT ERROR: ' WS-SQLCODE-DISP
                 EXEC SQL
                   ROLLBACK WORK
                 END-EXEC
                 STOP RUN
              END-IF
              ADD 1 TO COMMIT-BATCHES
              MOVE 0 TO COMMIT-COUNTER
           END-IF.

           CLOSE ORDER-FILE.
           IF ORDER-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING INPUT FILE: ' ORDER-STATUS
           END-IF.

           CLOSE LOG-FILE.
           IF OUT-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING OUTPUT FILE: ' OUT-STATUS
           END-IF.

       DISPLAY-SUMMARY.
           MOVE RECORDS-PROCESSED TO RECORDS-PROCESSED-DISP.
           MOVE RECORDS-INSERTED TO RECORDS-INSERTED-DISP.
           MOVE RECORDS-ERRORS TO RECORDS-ERRORS-DISP.
           MOVE COMMIT-BATCHES TO COMMIT-BATCHES-DISP.

           DISPLAY '========================================'.
           DISPLAY 'ORDER LOAD SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'RECORDS PROCESSED: '
                   FUNCTION TRIM(RECORDS-PROCESSED-DISP).
           DISPLAY 'RECORDS INSERTED: '
                   FUNCTION TRIM(RECORDS-INSERTED-DISP).
           DISPLAY 'RECORDS ERRORS: '
                   FUNCTION TRIM(RECORDS-ERRORS-DISP).
           DISPLAY 'COMMIT BATCHES: '
                   FUNCTION TRIM(COMMIT-BATCHES-DISP).
           DISPLAY '========================================'.
