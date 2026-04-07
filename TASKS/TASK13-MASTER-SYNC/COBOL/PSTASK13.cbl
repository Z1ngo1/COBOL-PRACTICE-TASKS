      ******************************************************************
      * MATCH-MERGE ALGORITHM - MASTER FILE UPDATE                     *
      *                                                                *
      * PURPOSE:                                                       *
      * APPLIES DAILY TRANSACTIONS TO OLD MASTER FILE TO CREATE NEW    *
      * MASTER FILE. CLASSIC MATCH-MERGE (BALANCE LINE) ALGORITHM      *
      * USING TWO SORTED SEQUENTIAL FILES.                             *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   COMPARE WS-OLD-ID VS WS-TRNS-ID:                             *
      *     TRNS > OLD : COPY OLD TO NEW, READ NEXT OLD                *
      *     TRNS < OLD : ADD NEW RECORD (A) OR LOG ERROR, READ TRANS   *
      *     TRNS = OLD : APPLY U/D/A, READ NEXT TRANS                  *
      *   TRANSACTION TYPES:                                           *
      *     'A' ADD    - NEW CUSTOMER (ERROR IF ALREADY EXISTS)        *
      *     'U' UPDATE - ADD AMOUNT TO BALANCE (ERROR IF NOT EXISTS)   *
      *     'D' DELETE - SKIP RECORD IN OUTPUT (ERROR IF NOT EXISTS)   *
      *   HIGH-VALUES USED AS EOF SENTINEL ON BOTH FILES.              *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2025/12/30                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  OLDDD (OLD.MASTER) - CURRENT MASTER FILE (PS, 80 B)    *
      * INPUT:  TRNSDD (TRANS.FILE) - DAILY TRANSACTIONS (PS, 80 B)    *
      * OUTPUT: NEWDD (NEW.MASTER) - UPDATED MASTER FILE (PS, 80 B)    *
      * OUTPUT: REPDD (ERROR.REPORT) - ERROR LOG (PS, 80 B)            *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PSTASK13.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT OLD-MASTER-FILE ASSIGN TO OLDDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS OLD-MASTER-STATUS.

           SELECT TRANSACTIONS-FILE ASSIGN TO TRNSDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS TRANS-STATUS.

           SELECT NEW-MASTER-FILE ASSIGN TO NEWDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS NEW-MASTER-STATUS.

           SELECT ERROR-REPORT-FILE ASSIGN TO REPDD
             ORGANIZATION IS SEQUENTIAL
             FILE STATUS IS ERROR-REPORT-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD OLD-MASTER-FILE RECORDING MODE IS F.
       01 OLD-MASTER-REC.
          05 OLD-ID PIC X(5).
          05 OLD-NAME PIC X(20).
          05 OLD-BAL PIC 9(5)V99.
          05 FILLER PIC X(48).

       FD TRANSACTIONS-FILE RECORDING MODE IS F.
       01 TRANSACTION-REC.
          05 TRNS-ID PIC X(5).
          05 TRNS-ACT PIC X(1).
          05 TRNS-DATA PIC X(20).
          05 TRNS-AMOUNT PIC 9(5)V99.
          05 FILLER PIC X(47).

       FD NEW-MASTER-FILE RECORDING MODE IS F.
       01 NEW-MASTER-REC.
          05 NEW-ID PIC X(5).
          05 NEW-NAME PIC X(20).
          05 NEW-BAL PIC 9(5)V99.
          05 FILLER PIC X(48).

       FD ERROR-REPORT-FILE RECORDING MODE IS F.
       01 ERROR-REPORT-REC.
          05 REP-ID PIC X(5).
          05 REP-ACT PIC X(1).
          05 REP-NAME PIC X(20).
          05 REP-BAL PIC 9(5)V99.
          05 FILLER PIC X(47).

       WORKING-STORAGE SECTION.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 OLD-MASTER-STATUS PIC X(2).
          05 TRANS-STATUS PIC X(2).
          05 NEW-MASTER-STATUS PIC X(2).
          05 ERROR-REPORT-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-DEL-FLAG PIC X(1) VALUE 'N'.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 OLD-MASTER-READ PIC 9(5) VALUE 0.
          05 TRANS-READ PIC 9(5) VALUE 0.
          05 NEW-MASTER-WRITTEN PIC 9(5) VALUE 0.
          05 RECORDS-ADDED PIC 9(5) VALUE 0.
          05 RECORDS-UPDATED PIC 9(5) VALUE 0.
          05 RECORDS-DELETED PIC 9(5) VALUE 0.
          05 ERRORS-LOGGED PIC 9(5) VALUE 0.

      * KEY HOLDERS FOR MATCH-MERGE COMPARISON
       01 WS-OLD-ID PIC X(5).
       01 WS-TRNS-ID PIC X(5).

      * CURRENT WORKING RECORD (ACCUMULATES UPDATES)
       01 WS-CUR-REC.
          05 WS-CUR-ID PIC X(5).
          05 WS-CUR-NAME PIC X(20).
          05 WS-CUR-BAL PIC 9(5)V99.

      * DISPLAY-FORMATTED COUNTERS
       01 WS-DISP-VAR.
          05 OLD-MASTER-READ-DISP PIC Z(4)9.
          05 TRANS-READ-DISP PIC Z(4)9.
          05 NEW-MASTER-WRITTEN-DISP PIC Z(4)9.
          05 RECORDS-ADDED-DISP PIC Z(4)9.
          05 RECORDS-UPDATED-DISP PIC Z(4)9.
          05 RECORDS-DELETED-DISP PIC Z(4)9.
          05 ERRORS-LOGGED-DISP PIC Z(4)9.

      **********************************************
      * OPENS FILES, PRIMES BOTH READS, RUNS MERGE
      * LOOP UNTIL BOTH KEYS = HIGH-VALUES (EOF).
      **********************************************
       PROCEDURE DIVISION.

       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM READ-OLD-MASTER.
           PERFORM READ-TRANSACTION.
           PERFORM PROCESS-MERGE-LOGIC UNTIL WS-OLD-ID = HIGH-VALUES AND
                   WS-TRNS-ID = HIGH-VALUES.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT OLD-MASTER-FILE.
           IF OLD-MASTER-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING OLD MASTER FILE: '
                       OLD-MASTER-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT TRANSACTIONS-FILE.
           IF TRANS-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING TRANSACTIONS FILE: ' TRANS-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT NEW-MASTER-FILE.
           IF NEW-MASTER-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING NEW MASTER FILE: '
                       NEW-MASTER-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT ERROR-REPORT-FILE.
           IF ERROR-REPORT-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING REPORT FILE: ' ERROR-REPORT-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * READS NEXT OLD MASTER RECORD INTO WS-CUR-REC.
      * AT EOF SETS WS-OLD-ID = HIGH-VALUES.
      **********************************************
       READ-OLD-MASTER.
           READ OLD-MASTER-FILE
             AT END
                MOVE HIGH-VALUES TO WS-OLD-ID
             NOT AT END
                IF OLD-MASTER-STATUS = '00'
                   MOVE OLD-ID TO WS-OLD-ID
                   MOVE OLD-ID TO WS-CUR-ID
                   MOVE OLD-NAME TO WS-CUR-NAME
                   MOVE OLD-BAL TO WS-CUR-BAL
                   ADD 1 TO OLD-MASTER-READ
                ELSE
                   DISPLAY 'ERROR READING OLD MASTER FILE: '
                            OLD-MASTER-STATUS
                   STOP RUN
                END-IF
           END-READ.

      **********************************************
      * READS NEXT TRANSACTION RECORD.
      * AT EOF SETS WS-TRNS-ID = HIGH-VALUES.
      **********************************************
       READ-TRANSACTION.
           READ TRANSACTIONS-FILE
             AT END
                MOVE HIGH-VALUES TO WS-TRNS-ID
             NOT AT END
                IF TRANS-STATUS = '00'
                   MOVE TRNS-ID TO WS-TRNS-ID
                   ADD 1 TO TRANS-READ
                ELSE
                   DISPLAY 'ERROR READING TRANSACTIONS FILE: '
                            TRANS-STATUS
                   STOP RUN
                END-IF
           END-READ.

      **********************************************
      * CORE MERGE: COMPARES KEYS AND ROUTES TO
      * APPROPRIATE PROCESSING PARAGRAPH.
      *   TRNS > OLD : COPY OLD -> READ NEXT OLD
      *   TRNS < OLD : UNMATCHED TRANS -> READ NEXT TRANS
      *   TRNS = OLD : APPLY TRANS -> READ NEXT TRANS
      **********************************************
       PROCESS-MERGE-LOGIC.
           EVALUATE TRUE
               WHEN WS-TRNS-ID > WS-OLD-ID
                   PERFORM WRITE-NEW-MASTER-REC
                   PERFORM READ-OLD-MASTER

               WHEN WS-TRNS-ID < WS-OLD-ID
                   PERFORM PROCESS-UNMATCHED
                   PERFORM READ-TRANSACTION

               WHEN WS-TRNS-ID = WS-OLD-ID
                   PERFORM APPLY-TRANSACTION
                   PERFORM READ-TRANSACTION
           END-EVALUATE.

      **********************************************
      * WRITES WS-CUR-REC TO NEW MASTER UNLESS
      * WS-DEL-FLAG = 'Y' (DELETED) OR AT SENTINEL.
      * RESETS WS-DEL-FLAG TO 'N' AFTER EACH CALL.
      * EVEN IF RECORD WAS SKIPPED, SO THAT THE NEXT
      * MASTER RECORD STARTS WITH A CLEAN FLAG.
      **********************************************
       WRITE-NEW-MASTER-REC.
           IF WS-DEL-FLAG = 'N' AND WS-OLD-ID NOT = HIGH-VALUES
              MOVE SPACES TO NEW-MASTER-REC
              INITIALIZE NEW-MASTER-REC
              MOVE WS-CUR-ID TO NEW-ID
              MOVE WS-CUR-NAME TO NEW-NAME
              MOVE WS-CUR-BAL TO NEW-BAL
              WRITE NEW-MASTER-REC
              IF NEW-MASTER-STATUS NOT = '00'
                 DISPLAY 'ERROR WRITING NEW MASTER: ' NEW-MASTER-STATUS
                 DISPLAY 'CUSTOMER ID: ' WS-CUR-ID
                 STOP RUN
              END-IF
              ADD 1 TO NEW-MASTER-WRITTEN
           END-IF.
           MOVE 'N' TO WS-DEL-FLAG.

      **********************************************
      * TRANSACTION HAS NO MATCHING MASTER RECORD.
      * 'A': VALID - WRITE AS NEW RECORD.
      * OTHER: ERROR - LOG AND CONTINUE.
      **********************************************
       PROCESS-UNMATCHED.
           IF WS-TRNS-ID NOT = HIGH-VALUES
              IF TRNS-ACT = 'A'
                 MOVE SPACES TO NEW-MASTER-REC
                 MOVE TRNS-ID TO NEW-ID
                 MOVE TRNS-DATA TO NEW-NAME
                 MOVE TRNS-AMOUNT TO NEW-BAL
                 WRITE NEW-MASTER-REC
                 IF NEW-MASTER-STATUS NOT = '00'
                    DISPLAY 'ERROR WRITING NEW MASTER: '
                             NEW-MASTER-STATUS
                    DISPLAY 'TRANS ID: ' TRNS-ID
                    STOP RUN
                 END-IF
                 ADD 1 TO NEW-MASTER-WRITTEN
                 ADD 1 TO RECORDS-ADDED
              ELSE
      *            U OR D WITHOUT MATCHING MASTER = ERROR
                 PERFORM LOG-ERROR-TRANSACTION
              END-IF
           END-IF.

      **********************************************
      * MATCHED RECORD: APPLIES TRANSACTION TYPE.
      * 'U': ADD AMOUNT TO WS-CUR-BAL.
      * 'D': SET DEL-FLAG, WRITE-NEW-MASTER-REC SKIPS IT.
      * 'A': DUPLICATE ADD = ERROR.
      * IF DEL-FLAG = 'Y' AND ANOTHER TRANS ARRIVES
      * FOR SAME ID - IT IS LOGGED AS ERROR.
      *     (CANNOT UPDATE/DELETE ALREADY DELETED RECORD)
      **********************************************
       APPLY-TRANSACTION.
           IF WS-DEL-FLAG = 'Y'
              PERFORM LOG-ERROR-TRANSACTION
           ELSE
              EVALUATE TRUE
                  WHEN TRNS-ACT = 'U'
                      ADD TRNS-AMOUNT TO WS-CUR-BAL
                      ADD 1 TO RECORDS-UPDATED
                  WHEN TRNS-ACT = 'D'
                      MOVE 'Y' TO WS-DEL-FLAG
                      ADD 1 TO RECORDS-DELETED
                  WHEN TRNS-ACT = 'A'
      * ADD ON EXISTING CUSTOMER = ERROR
                      PERFORM LOG-ERROR-TRANSACTION
              END-EVALUATE
           END-IF.

      **********************************************
      * WRITES FAILED TRANSACTION TO ERROR REPORT.
      **********************************************
       LOG-ERROR-TRANSACTION.
           MOVE SPACES TO ERROR-REPORT-REC.
           INITIALIZE ERROR-REPORT-REC.
           MOVE TRNS-ID TO REP-ID.
           MOVE TRNS-ACT TO REP-ACT.
           MOVE TRNS-DATA TO REP-NAME.
           MOVE TRNS-AMOUNT TO REP-BAL.
           WRITE ERROR-REPORT-REC.
           IF ERROR-REPORT-STATUS NOT = '00'
              DISPLAY 'ERROR WRITING ERROR REPORT: '
                       ERROR-REPORT-STATUS
              DISPLAY 'TRANSACTION ID: ' TRNS-ID
              STOP RUN
           END-IF.
           ADD 1 TO ERRORS-LOGGED.

      **********************************************
      * CLOSE ALL FILES AND CHECK STATUS
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE OLD-MASTER-FILE.
           IF OLD-MASTER-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING OLD MASTER: '
                       OLD-MASTER-STATUS
           END-IF.

           CLOSE TRANSACTIONS-FILE.
           IF TRANS-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING TRANSACTIONS: '
                       TRANS-STATUS
           END-IF.

           CLOSE NEW-MASTER-FILE.
           IF NEW-MASTER-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING NEW MASTER: '
                       NEW-MASTER-STATUS
           END-IF.

           CLOSE ERROR-REPORT-FILE.
           IF ERROR-REPORT-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING ERROR REPORT: '
                       ERROR-REPORT-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE OLD-MASTER-READ TO OLD-MASTER-READ-DISP.
           MOVE TRANS-READ TO TRANS-READ-DISP.
           MOVE NEW-MASTER-WRITTEN TO NEW-MASTER-WRITTEN-DISP.
           MOVE RECORDS-ADDED TO RECORDS-ADDED-DISP.
           MOVE RECORDS-UPDATED TO RECORDS-UPDATED-DISP.
           MOVE RECORDS-DELETED TO RECORDS-DELETED-DISP.
           MOVE ERRORS-LOGGED TO ERRORS-LOGGED-DISP.

           DISPLAY '========================================'.
           DISPLAY 'MASTER FILE UPDATE SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'OLD MASTER RECORDS READ:  ' OLD-MASTER-READ-DISP.
           DISPLAY 'TRANSACTIONS PROCESSED:   ' TRANS-READ-DISP.
           DISPLAY 'NEW MASTER RECORDS:       ' NEW-MASTER-WRITTEN-DISP.
           DISPLAY 'ADDED:                    ' RECORDS-ADDED-DISP.
           DISPLAY 'UPDATED:                  ' RECORDS-UPDATED-DISP.
           DISPLAY 'DELETED:                  ' RECORDS-DELETED-DISP.
           DISPLAY 'ERRORS LOGGED:            ' ERRORS-LOGGED-DISP.
           DISPLAY '========================================'.
