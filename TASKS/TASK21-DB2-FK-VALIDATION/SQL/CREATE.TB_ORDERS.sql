-- TASK 21: ORDERS WITH PRODUCT VALIDATION
-- CREATE TABLE TB_ORDERS

CREATE TABLE TB_ORDERS (                                
   ORDER_ID      CHAR(6) NOT NULL,                      
   ORDER_DATE    DATE,                                  
   PROD_ID       CHAR(5),                               
   QUANTITY      INTEGER,                               
   PRIMARY KEY (ORDER_ID),                              
   FOREIGN KEY (PROD_ID) REFERENCES TB_PRODUCTS(PROD_ID)
) IN DATABASE Z73460;                                   
