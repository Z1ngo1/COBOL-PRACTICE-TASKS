      ******************************************************************
      * SUBPROGRAM: SUB2JB22 - TAX CALCULATOR                          *
      * CALLED BY:  JOBSUB22                                           *
      *                                                                *
      * INPUT:  LS-COMMISSION                                          *
      * OUTPUT: LS-TAX-AMOUNT                                          *
      *                                                                *
      * LOGIC:                                                         *
      *   COMMISSION < 1000 -> 15%                                     *
      *   1000 <= COMMISSION < 5000 -> 20%                             *
      *   COMMISSION >= 5000 -> 25%                                    *
      *   TAX-AMOUNT = COMMISSION * TAX-RATE                           *
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SUB2JB22.
       ENVIRONMENT DIVISION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 WS-TAX-RATE PIC V999.

       LINKAGE SECTION.

       01 LS-COMMISSION PIC 9(5)V99.
       01 LS-TAX-AMOUNT PIC 9(5)V99.

       PROCEDURE DIVISION USING LS-COMMISSION, LS-TAX-AMOUNT.
       MAIN-LOGIC.
           MOVE 0 TO WS-TAX-RATE.

           EVALUATE TRUE
               WHEN LS-COMMISSION < 1000
                 MOVE 0.15 TO WS-TAX-RATE
               WHEN LS-COMMISSION < 5000
                 MOVE 0.20 TO WS-TAX-RATE
               WHEN OTHER
                 MOVE 0.25 TO WS-TAX-RATE
           END-EVALUATE.

           COMPUTE LS-TAX-AMOUNT = LS-COMMISSION * WS-TAX-RATE.

           GOBACK.
