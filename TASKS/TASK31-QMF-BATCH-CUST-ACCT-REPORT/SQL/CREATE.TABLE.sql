-- TASK 31: Batch customer account report
-- CREATE T_CUSTOMER

CREATE TABLE T_CUSTOMER (          
   CUST_ID CHAR(6) NOT NULL,       
   CUST_NAME VARCHAR(40),          
   REGION CHAR(2),                 
   SEGMENT CHAR(1),                
   STATUS CHAR(1),                 
   PRIMARY KEY(CUST_ID)            
) IN DATABASE Z73460;              
