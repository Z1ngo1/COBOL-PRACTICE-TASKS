      ******************************************************************
      * DCLGEN TABLE(TB_EMP_SALARY)                                    *
      *        LIBRARY(Z73460.DCLGEN.COBOL(TASK7))                     *
      *        LANGUAGE(COBOL)                                         *
      *        QUOTE                                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
           EXEC SQL DECLARE TB_EMP_SALARY TABLE
           ( EMP_ID                         CHAR(5) NOT NULL,
             EMP_NAME                       VARCHAR(30),
             DEPT_CODE                      CHAR(3),
             SALARY                         DECIMAL(9, 2)
           ) END-EXEC.
      ******************************************************************
      * COBOL DECLARATION FOR TABLE TB_EMP_SALARY                      *
      ******************************************************************
       01  DCLTB-EMP-SALARY.
           10 EMP-ID               PIC X(5).
           10 EMP-NAME.
              49 EMP-NAME-LEN      PIC S9(4) USAGE COMP-5.
              49 EMP-NAME-TEXT     PIC X(30).
           10 DEPT-CODE            PIC X(3).
           10 SALARY               PIC S9(7)V9(2) USAGE COMP-3.
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 4       *
      ******************************************************************
