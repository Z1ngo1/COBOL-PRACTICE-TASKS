      ******************************************************************
      * BINARY SEARCH (SEARCH ALL) - PARTS CATALOG LOOKUP              *
      *                                                                *
      * PURPOSE:                                                       *
      * CALCULATES ORDER TOTALS BY FINDING PART PRICES USING BINARY    *
      * SEARCH (SEARCH ALL). CATALOG TABLE MUST BE PRE-SORTED BY       *
      * PART-ID ASCENDING IN THE INPUT FILE.                           *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - LOAD: READ PARTS-CATALOG-FILE INTO CATALOG-TABLE.  *
      *     TABLE USES DEPENDING ON PARTS-LOADED SO SEARCH ALL         *
      *     SCANS ONLY LOADED ENTRIES. MAX 100 PARTS.                  *
      *   PHASE 2 - PROCESS: FOR EACH ORDER RECORD:                    *
      *     SEARCH ALL CATALOG-ENTRY WHERE                             *
      *       CAT-TBL-PART-ID = ORDER-PART-ID.                         *
      *     FOUND:     TOTAL = CAT-TBL-PRICE * ORDER-QUANTITY          *
      *     NOT FOUND: WRITE 'NOT FOUND' LINE, INCREMENT COUNTER.      *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/01                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT: PARTDD (PARTS.CATALOG) - PARTS CATALOG (PS, SORTED,10 B)*
      * INPUT:  ORDRDD (ORDERS.FILE) - CUSTOMER ORDERS (PS, 13 B)      *
      * OUTPUT: INVODD (INVOICE.TXT) - ORDER INVOICES (PS, 80 B)       *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PSTASK16.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT PARTS-CATALOG-FILE ASSIGN TO PARTDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS CATALOG-STATUS.

           SELECT ORDERS-FILE ASSIGN TO ORDRDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS ORDERS-STATUS.

           SELECT INVOICE-FILE ASSIGN TO INVODD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS INVOICE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD PARTS-CATALOG-FILE RECORDING MODE IS F.
       01 CATALOG-REC.
          05 PART-ID PIC 9(5).
          05 PART-PRICE PIC 9(3)V99.

       FD ORDERS-FILE RECORDING MODE IS F.
       01 ORDER-REC.
          05 ORDR-NUM PIC 9(5).
          05 ORDR-ID PIC 9(5).
          05 ORDR-QUANT PIC 9(3).

       FD INVOICE-FILE RECORDING MODE IS F.
       01 INVOICE-REC PIC X(80).

       WORKING-STORAGE SECTION.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 INVOICE-STATUS PIC X(2).
          05 ORDERS-STATUS PIC X(2).
          05 CATALOG-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-FOUND PIC X(1) VALUE 'N'.
             88 FOUND VALUE 'Y'.
             88 NOT-FOUND VALUE 'N'.
          05 WS-PART-EOF PIC X(1) VALUE 'N'.
             88 PART-EOF VALUE 'Y'.
             88 NOT-PART-EOF VALUE 'N'.
          05 WS-ORDR-EOF PIC X(1) VALUE 'N'.
             88 ORDR-EOF VALUE 'Y'.
             88 NOT-ORDR-EOF VALUE 'N'.

      * PARTS LOADED COUNTER
       01 PARTS-LOADED PIC 9(3) VALUE 0.

      * IN-MEMORY PARTS CATALOG TABLE
       01 CATALOG-TABLE.
          05 CATALOG-ENTRY OCCURS 1 TO 100 TIMES
                           DEPENDING ON PARTS-LOADED
                           ASCENDING KEY IS WS-PART-ID
                           INDEXED BY IDX.
             10 WS-PART-ID PIC 9(5).
             10 WS-PRICE PIC 9(3)V99.


      * WORK VARIABLES FOR CALCULATIONS AND DISPLAY
       01 WS-TOTAL-COST PIC 9(5)V99.
       01 WS-TOTAL-COST-DISP PIC Z(4)9.99.
       01 WS-ORDER-NUM-DISP PIC 9(5).

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 ORDERS-PROCESSED PIC 9(5) VALUE 0.
          05 INVOICES-WRITTEN PIC 9(5) VALUE 0.
          05 PARTS-FOUND PIC 9(5) VALUE 0.
          05 PARTS-NOT-FOUND PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS.
       01 WS-DISP-COUNTERS.
          05 PARTS-LOADED-DISP PIC Z(2)9.
          05 ORDERS-PROCESSED-DISP PIC Z(4)9.
          05 INVOICES-WRITTEN-DISP PIC Z(4)9.
          05 PARTS-FOUND-DISP PIC Z(4)9.
          05 PARTS-NOT-FOUND-DISP PIC Z(4)9.

      **********************************************
      * OPENS FILES, LOADS CATALOG TABLE, PROCESSES
      * ORDERS, CLOSES FILES, DISPLAYS SUMMARY.
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM OPEN-ALL-FILES.
           PERFORM LOAD-CATALOG-TABLE.
           PERFORM PROCESS-ORDERS.
           PERFORM CLOSE-ALL-FILES.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * OPEN ALL FILES AND CHECK STATUS
      **********************************************
       OPEN-ALL-FILES.
           OPEN INPUT PARTS-CATALOG-FILE.
           IF CATALOG-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING PARTS CATALOG FILE: '
                       CATALOG-STATUS
              STOP RUN
           END-IF.

           OPEN INPUT ORDERS-FILE.
           IF ORDERS-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING ORDERS FILE: ' ORDERS-STATUS
              STOP RUN
           END-IF.

           OPEN OUTPUT INVOICE-FILE.
           IF INVOICE-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING INVOICE FILE: ' INVOICE-STATUS
              STOP RUN
           END-IF.

      **********************************************
      * TABLE USES DEPENDING ON PARTS-LOADED TO LIMIT
      * SEARCH ALL TO LOADED ENTRIES ONLY.
      * MAX 100 ENTRIES. OVERFLOW IGNORED WITH WARNING.
      **********************************************
       LOAD-CATALOG-TABLE.
           SET NOT-PART-EOF TO TRUE.
           PERFORM UNTIL PART-EOF
              READ PARTS-CATALOG-FILE
                AT END
                   SET PART-EOF TO TRUE
                NOT AT END
                   IF CATALOG-STATUS = '00'
                      IF PARTS-LOADED >= 100
                         DISPLAY 'WARNING: CATALOG TABLE FULL (100 MAX)'
                                 '. IGNORED: ' PART-ID
                      ELSE
                         ADD 1 TO PARTS-LOADED
                         SET IDX TO PARTS-LOADED
                         MOVE PART-ID TO WS-PART-ID(IDX)
                         MOVE PART-PRICE TO WS-PRICE(IDX)
                      END-IF
                   ELSE
                      DISPLAY 'ERROR READING PARTS CATALOG FILE: '
                               CATALOG-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * READS ORDERS FILE AND CALLS SEARCH/WRITE
      * PARAGRAPH FOR EACH RECORD.
      **********************************************
       PROCESS-ORDERS.
           SET NOT-ORDR-EOF TO TRUE.
           PERFORM UNTIL ORDR-EOF
              READ ORDERS-FILE
                AT END
                   SET ORDR-EOF TO TRUE
                NOT AT END
                   IF ORDERS-STATUS = '00'
                      ADD 1 TO ORDERS-PROCESSED
                      PERFORM SEARCH-PART-PRICE
                   ELSE
                      DISPLAY 'ERROR READING ORDERS FILE: '
                               ORDERS-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM.

      **********************************************
      * BINARY SEARCH ON CATALOG-TABLE BY PART-ID.
      * SEARCH ALL REQUIRES ASCENDING KEY CLAUSE AND PRE-SORTED INPUT.
      * CALLS WRITE-INVOICE-RECORD REGARDLESS OF FOUND/NOT-FOUND RESULT.
      **********************************************
       SEARCH-PART-PRICE.
           SET NOT-FOUND TO TRUE.
           MOVE ORDR-NUM TO WS-ORDER-NUM-DISP.
           SEARCH ALL CATALOG-ENTRY
               AT END
                  CONTINUE
               WHEN WS-PART-ID(IDX) = ORDR-ID
                  SET FOUND TO TRUE
                  COMPUTE WS-TOTAL-COST = WS-PRICE(IDX) * ORDR-QUANT
           END-SEARCH.

           PERFORM WRITE-INVOICE-RECORD.

      **********************************************
      * FORMATS AND WRITES ONE INVOICE LINE.
      * FOUND:     ORDER-NUM + TOTAL COST.
      * NOT FOUND: ORDER-NUM + 'NOT FOUND'.
      **********************************************
       WRITE-INVOICE-RECORD.
           MOVE SPACES TO INVOICE-REC.
           IF WS-FOUND = 'Y'
              ADD 1 TO PARTS-FOUND
              MOVE WS-TOTAL-COST TO WS-TOTAL-COST-DISP
              STRING WS-ORDER-NUM-DISP DELIMITED BY SIZE
                     ' ' DELIMITED BY SIZE
                     FUNCTION TRIM(WS-TOTAL-COST-DISP) DELIMITED BY SIZE
                     INTO INVOICE-REC
              END-STRING
           ELSE
              ADD 1 TO PARTS-NOT-FOUND
              STRING WS-ORDER-NUM-DISP DELIMITED BY SIZE
                     ' ' DELIMITED BY SIZE
                     'NOT FOUND' DELIMITED BY SIZE
                     INTO INVOICE-REC
              END-STRING
           END-IF.

           WRITE INVOICE-REC.
           IF INVOICE-STATUS = '00'
              ADD 1 TO INVOICES-WRITTEN
           ELSE
              DISPLAY 'ERROR WRITING INVOICE FILE: ' INVOICE-STATUS
              DISPLAY 'ORDER NUMBER: ' ORDR-NUM
              STOP RUN
           END-IF.

      **********************************************
      * CLOSE ALL FILES AND CHECK STATUS
      **********************************************
       CLOSE-ALL-FILES.
           CLOSE PARTS-CATALOG-FILE.
           IF CATALOG-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING PARTS CATALOG FILE: '
                       CATALOG-STATUS
           END-IF.

           CLOSE ORDERS-FILE.
           IF ORDERS-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING ORDERS FILE: '
                       ORDERS-STATUS
           END-IF.

           CLOSE INVOICE-FILE.
           IF INVOICE-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING INVOICE FILE: '
                       INVOICE-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE PARTS-LOADED TO PARTS-LOADED-DISP.
           MOVE ORDERS-PROCESSED TO ORDERS-PROCESSED-DISP.
           MOVE INVOICES-WRITTEN TO INVOICES-WRITTEN-DISP.
           MOVE PARTS-FOUND TO PARTS-FOUND-DISP.
           MOVE PARTS-NOT-FOUND TO PARTS-NOT-FOUND-DISP.

           DISPLAY '========================================'.
           DISPLAY 'INVOICE GENERATION SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'PARTS LOADED:           ' PARTS-LOADED-DISP.
           DISPLAY 'ORDERS PROCESSED:     ' ORDERS-PROCESSED-DISP.
           DISPLAY 'INVOICES WRITTEN:     ' INVOICES-WRITTEN-DISP.
           DISPLAY 'PARTS FOUND:          ' PARTS-FOUND-DISP.
           DISPLAY 'PARTS NOT FOUND:      ' PARTS-NOT-FOUND-DISP.
           DISPLAY '========================================'.
