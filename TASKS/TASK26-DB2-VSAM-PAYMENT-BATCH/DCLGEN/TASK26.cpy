      ******************************************************************
      * DCLGEN TABLE(TB_CUSTOMER_BALANCE)                              *
      *        LIBRARY(Z73460.DCLGEN.COBOL(TASK26))                    *
      *        LANGUAGE(COBOL)                                         *
      *        QUOTE                                                   *
      * ... IS THE DCLGEN COMMAND THAT MADE THE FOLLOWING STATEMENTS   *
      ******************************************************************
           EXEC SQL DECLARE TB_CUSTOMER_BALANCE TABLE                   
           ( CUST_ID                        CHAR(5) NOT NULL,           
             CUST_BALANCE                   DECIMAL(9, 2),              
             LAST_PAYMENT                   TIMESTAMP                   
           ) END-EXEC.                                                  
      ******************************************************************
      * COBOL DECLARATION FOR TABLE TB_CUSTOMER_BALANCE                *
      ******************************************************************
       01  DCLTB-CUSTOMER-BALANCE.                                      
           10 CUST-ID              PIC X(5).                            
           10 CUST-BALANCE         PIC S9(7)V9(2) USAGE COMP-3.         
           10 LAST-PAYMENT         PIC X(26).                           
      ******************************************************************
      * THE NUMBER OF COLUMNS DESCRIBED BY THIS DECLARATION IS 3       *
      ******************************************************************
