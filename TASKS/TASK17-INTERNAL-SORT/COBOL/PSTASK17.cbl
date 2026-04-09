      ******************************************************************
      * INTERNAL SORT WITH FILTERING - HONOR ROLL GENERATOR            *
      *                                                                *
      * PURPOSE:                                                       *
      * GENERATES HONOR ROLL BY FILTERING FAILING STUDENTS AND         *
      * SORTING PASSING STUDENTS BY CLASS AND SCORE.                   *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - INPUT PROCEDURE (FILTER-INPUT-DATA):               *
      *     READ EXAM-FILE. RELEASE RECORDS WHERE STUD-SCORE >= 50.    *
      *     RECORDS WITH SCORE < 50 ARE COUNTED AND DISCARDED.         *
      *                                                                *
      *   PHASE 2 - AUTOMATIC SORT:                                    *
      *     PRIMARY KEY:   SORT-CLASS  ASCENDING.                      *
      *     SECONDARY KEY: SORT-SCORE  DESCENDING (BEST SCORE FIRST).  *
      *                                                                *
      *   PHASE 3 - OUTPUT PROCEDURE (WRITE-SORTED-REPORT):            *
      *     OPEN HONOR-FILE, RETURN SORTED RECORDS, WRITE,             *
      *     CLOSE HONOR-FILE. FILES MANAGED INSIDE PROCEDURES.         *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/01                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  EXDD (EXAM.RAW) - RAW EXAM RESULTS (PS, UNSORTED)      *
      * SORT:   SRTDD (WORK.SORT) - SORT WORK FILE (SD, TEMPORARY)     *
      * OUTPUT: HNRDD (HONOR.ROLL) - SORTED HONOR ROLL (PS, 80 B)      *
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PSTASK17.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT EXAM-FILE ASSIGN TO EXDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS EXAM-STATUS.

           SELECT SORT-FILE ASSIGN TO SRTDD.

           SELECT HONOR-FILE ASSIGN TO HNRDD
              ORGANIZATION IS SEQUENTIAL
              FILE STATUS IS HONOR-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD EXAM-FILE RECORDING MODE IS F.
       01 EXAM-REC.
          05 STUD-ID PIC X(5).
          05 STUD-NAME PIC X(20).
          05 STUD-CLASS PIC X(3).
          05 STUD-SCORE PIC 9(3).

       SD SORT-FILE.
       01 SORT-REC.
          05 SORT-ID PIC X(5).
          05 SORT-NAME PIC X(20).
          05 SORT-CLASS PIC X(3).
          05 SORT-SCORE PIC 9(3).

       FD HONOR-FILE RECORDING MODE IS F.
       01 HONOR-REC.
          05 OUT-ID PIC X(5).
          05 OUT-NAME PIC X(20).
          05 OUT-CLASS PIC X(3).
          05 OUT-SCORE PIC 9(3).

       WORKING-STORAGE SECTION.

      * FILE STATUS VARIABLES
       01 FILE-STATUSES.
          05 EXAM-STATUS PIC X(2).
          05 HONOR-STATUS PIC X(2).

      * CONTROL FLAGS
       01 WS-FLAGS.
          05 WS-EOF PIC X(1) VALUE 'N'.
             88 EOF VALUE 'Y'.
          05 WS-OUT-EOF PIC X(1) VALUE 'N'.
             88 OUT-EOF VALUE 'Y'.

      * STATISTICS COUNTERS
       01 WS-COUNTERS.
          05 RECORDS-READ PIC 9(5) VALUE 0.
          05 RECORDS-FILTERED PIC 9(5) VALUE 0.
          05 RECORDS-PASSED PIC 9(5) VALUE 0.
          05 RECORDS-WRITTEN PIC 9(5) VALUE 0.

      * DISPLAY-FORMATTED COUNTERS
       01 WS-DISP-COUNTERS.
          05 RECORDS-READ-DISP PIC Z(4)9.
          05 RECORDS-FILTERED-DISP PIC Z(4)9.
          05 RECORDS-PASSED-DISP PIC Z(4)9.
          05 RECORDS-WRITTEN-DISP PIC Z(4)9.

      **********************************************
      * SORT STATEMENT DRIVES THE WHOLE PROGRAM.
      * INPUT PROCEDURE FILTERS BEFORE SORT.
      * OUTPUT PROCEDURE WRITES AFTER SORT.
      * DISPLAY-SUMMARY RUNS AFTER SORT COMPLETES.
      **********************************************
       PROCEDURE DIVISION.
       MAIN-LOGIC.
           SORT SORT-FILE
               ON ASCENDING KEY SORT-CLASS
               ON DESCENDING KEY SORT-SCORE
               INPUT PROCEDURE IS FILTER-INPUT-DATA
               OUTPUT PROCEDURE IS WRITE-SORTED-REPORT.
           PERFORM DISPLAY-SUMMARY.
           STOP RUN.

      **********************************************
      * OPENS EXAM-FILE, READS ALL RECORDS.
      * SCORE >= 50: MOVE TO SORT-REC, RELEASE.
      * SCORE < 50: DISCARD, INCREMENT FILTERED.
      **********************************************
       FILTER-INPUT-DATA.
           OPEN INPUT EXAM-FILE
           IF EXAM-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING EXAM FILE: ' EXAM-STATUS
              STOP RUN
           END-IF.

           PERFORM UNTIL EOF
              READ EXAM-FILE
                AT END
                   SET EOF TO TRUE
                NOT AT END
                   IF EXAM-STATUS = '00'
                      ADD 1 TO RECORDS-READ
                      IF STUD-SCORE >= 50
                         ADD 1 TO RECORDS-PASSED
                         MOVE STUD-ID    TO SORT-ID
                         MOVE STUD-NAME  TO SORT-NAME
                         MOVE STUD-CLASS TO SORT-CLASS
                         MOVE STUD-SCORE TO SORT-SCORE
                         RELEASE SORT-REC
                      ELSE
                         ADD 1 TO RECORDS-FILTERED
                      END-IF
                   ELSE
                      DISPLAY 'ERROR READING EXAM FILE: ' EXAM-STATUS
                      STOP RUN
                   END-IF
              END-READ
           END-PERFORM
           CLOSE EXAM-FILE.
           IF EXAM-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING EXAM FILE: ' EXAM-STATUS
           END-IF.

      **********************************************
      * OPENS HONOR-FILE, RETURNS SORTED RECORDS.
      * MOVES SORT-REC FIELDS TO HONOR-REC AND
      * WRITES ONE LINE PER PASSING STUDENT.
      **********************************************
       WRITE-SORTED-REPORT.
           OPEN OUTPUT HONOR-FILE.
           IF HONOR-STATUS NOT = '00'
              DISPLAY 'ERROR OPENING HONOR FILE: ' HONOR-STATUS
              STOP RUN
           END-IF.

           PERFORM UNTIL OUT-EOF
               RETURN SORT-FILE
                   AT END
                       SET OUT-EOF TO TRUE
                   NOT AT END
                       MOVE SORT-ID TO OUT-ID
                       MOVE SORT-NAME TO OUT-NAME
                       MOVE SORT-CLASS TO OUT-CLASS
                       MOVE SORT-SCORE TO OUT-SCORE
                       WRITE HONOR-REC
                       IF HONOR-STATUS = '00'
                          ADD 1 TO RECORDS-WRITTEN
                       ELSE
                          DISPLAY 'ERROR WRITING HONOR FILE: '
                                   HONOR-STATUS
                          STOP RUN
                       END-IF
               END-RETURN
           END-PERFORM
           CLOSE HONOR-FILE.
           IF HONOR-STATUS NOT = '00'
              DISPLAY 'WARNING: ERROR CLOSING HONOR FILE: ' HONOR-STATUS
           END-IF.

      **********************************************
      * DISPLAY SUMMARY STATISTICS TO SYSOUT
      **********************************************
       DISPLAY-SUMMARY.
           MOVE RECORDS-READ TO RECORDS-READ-DISP.
           MOVE RECORDS-FILTERED TO RECORDS-FILTERED-DISP.
           MOVE RECORDS-PASSED TO RECORDS-PASSED-DISP.
           MOVE RECORDS-WRITTEN TO RECORDS-WRITTEN-DISP.

           DISPLAY '========================================'.
           DISPLAY 'HONOR ROLL GENERATION SUMMARY'.
           DISPLAY '========================================'.
           DISPLAY 'RECORDS READ:        ' RECORDS-READ-DISP.
           DISPLAY 'RECORDS FILTERED:    ' RECORDS-FILTERED-DISP.
           DISPLAY 'RECORDS PASSED:      ' RECORDS-PASSED-DISP.
           DISPLAY 'RECORDS WRITTEN:     ' RECORDS-WRITTEN-DISP.
           DISPLAY '========================================'.
