      ******************************************************************
      * SUBPROGRAM: SUB1JB23 - CREDIT ELIGIBILITY CHECKER              *
      * CALLED BY:  JOBSUB23                                           *
      *                                                                *
      * INPUT:  LS-CREDIT-SCORE, LS-LATE-PAYMENTS,                     *
      *         LS-CURRENT-DEBT, LS-LOAN-AMOUNT                        *
      * OUTPUT: LS-DECISION, LS-REASON,                                *
      *         LS-SUCCESS-COUNTER, LS-ERROR-COUNTER                   *
      *                                                                *
      * LOGIC (CHECKED IN ORDER):                                      *
      *   1. CREDIT-SCORE < 600              -> REJECTED               *
      *      REASON: POOR CREDIT SCORE                                 *
      *   2. LATE-PAYMENTS >= 3              -> REJECTED               *
      *      REASON: TOO MANY LATE PAYMENTS                            *
      *   3. CURRENT-DEBT + LOAN > SCORE*200 -> REJECTED               *
      *      REASON: DEBT EXCEEDS LIMIT                                *
      *   4. ALL CHECKS PASS                 -> APPROVED               *
      *      REASON: CLIENT QUALIFIES                                  *
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SUB1JB23.
       ENVIRONMENT DIVISION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 WS-DEBT-LIMIT PIC 9(9)V99.
       01 WS-TOTAL-DEBT PIC 9(9)V99.

       LINKAGE SECTION.

       01 LS-CREDIT-SCORE PIC 9(3).
       01 LS-LATE-PAYMENTS PIC 9(2).
       01 LS-CURRENT-DEBT PIC 9(5)V99.
       01 LS-LOAN-AMOUNT PIC 9(5)V99.
       01 LS-DECISION PIC X(10).
       01 LS-REASON PIC X(25).

       PROCEDURE DIVISION USING
                          LS-CREDIT-SCORE,
                          LS-LATE-PAYMENTS,
                          LS-CURRENT-DEBT,
                          LS-LOAN-AMOUNT,
                          LS-DECISION,
                          LS-REASON.

      **********************************************
      * EVALUATES CREDIT CONDITIONS IN ORDER.
      * FIRST FAILING CHECK SETS DECISION AND EXITS.
      * ALL CHECKS PASS -> APPROVED.
      **********************************************
       MAIN-LOGIC.
           IF LS-CREDIT-SCORE < 600
              MOVE 'REJECTED' TO LS-DECISION
              MOVE 'POOR CREDIT SCORE' TO LS-REASON
           ELSE
             IF LS-LATE-PAYMENTS >= 3
                MOVE 'REJECTED' TO LS-DECISION
                MOVE 'TOO MANY LATE PAYMENTS' TO LS-REASON
             ELSE
               COMPUTE WS-DEBT-LIMIT = LS-CREDIT-SCORE * 200
               COMPUTE WS-TOTAL-DEBT =
                       LS-CURRENT-DEBT + LS-LOAN-AMOUNT
               IF WS-TOTAL-DEBT > WS-DEBT-LIMIT
                  MOVE 'REJECTED' TO LS-DECISION
                  MOVE 'DEBT EXCEEDS LIMIT' TO LS-REASON
               ELSE
                  MOVE 'APPROVED' TO LS-DECISION
                  MOVE 'CLIENT QUALIFIES' TO LS-REASON
               END-IF
             END-IF
           END-IF.

           GOBACK.
