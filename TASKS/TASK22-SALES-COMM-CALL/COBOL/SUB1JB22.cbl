      ******************************************************************
      * SUBPROGRAM: SUB1JB22 - COMMISSION CALCULATOR                   *
      *                                                                *
      * CALLED BY: JOBSUB22                                            *
      * INPUT:  LS-EMP-ID, LS-REGION, LS-SALES-AMT                     *
      * OUTPUT: LS-COMMISSION                                          *
      *                                                                *
      * LOGIC:                                                         *
      *   BASE RATE: NY=5%, CA=7%, TX=3%, OTHER=4%                     *
      *   BONUS: >=100000 +2%, >=50000 +1%                             *
      *   COMMISSION = SALES-AMT * (BASE + BONUS)                      *
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SUB1JB22.
       ENVIRONMENT DIVISION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 WS-BASE-PERCENT PIC V999.
       01 WS-BONUS-PERCENT PIC V999 VALUE 0.
       01 WS-TOTAL-PERCENT PIC V999.

       LINKAGE SECTION.

       01 LS-EMP-ID PIC X(5).
       01 LS-REGION PIC X(2).
       01 LS-SALES-AMT PIC 9(6)V99.
       01 LS-COMMISSION PIC 9(5)V99.

       PROCEDURE DIVISION USING
                          LS-EMP-ID,
                          LS-REGION,
                          LS-SALES-AMT,
                          LS-COMMISSION.

       MAIN-LOGIC.
           MOVE 0 TO WS-BONUS-PERCENT.
           MOVE 0 TO WS-BASE-PERCENT.
           MOVE 0 TO WS-TOTAL-PERCENT.

           EVALUATE LS-REGION
               WHEN 'NY'
                 MOVE 0.05 TO WS-BASE-PERCENT
               WHEN 'CA'
                 MOVE 0.07 TO WS-BASE-PERCENT
               WHEN 'TX'
                 MOVE 0.03 TO WS-BASE-PERCENT
               WHEN OTHER
                 MOVE 0.04 TO WS-BASE-PERCENT
           END-EVALUATE.

           IF LS-SALES-AMT >= 100000
              MOVE 0.02 TO WS-BONUS-PERCENT
           ELSE
             IF LS-SALES-AMT >= 50000
                MOVE 0.01 TO WS-BONUS-PERCENT
             END-IF
           END-IF.

           COMPUTE WS-TOTAL-PERCENT =
                            WS-BASE-PERCENT + WS-BONUS-PERCENT.
           COMPUTE LS-COMMISSION = LS-SALES-AMT * WS-TOTAL-PERCENT.

           GOBACK.
