-- TASK 31: Batch customer account report
-- CREATE T_ACCOUNT

CREATE TABLE T_ACCOUNT (       
   ACCT_ID CHAR(8) NOT NULL,   
   CUST_ID CHAR(6) NOT NULL,   
   ACCT_TYPE CHAR(2),          
   BALANCE DECIMAL(11,2),      
   OPEN_DATE DATE,             
   PRIMARY KEY(ACCT_ID)        
) IN DATABASE Z73460;           
