 SELECT A.ACCT_TYPE,                                                            
        C.REGION,                                                               
        SUM(A.BALANCE) AS TOTAL_BALANCE,                                        
        COUNT(*)        AS ACCT_COUNT                                           
 FROM   T_ACCOUNT A                                                             
 JOIN   T_CUSTOMER C                                                            
   ON   A.CUST_ID = C.CUST_ID                                                   
 WHERE  C.STATUS = 'A'                                                          
 GROUP BY A.ACCT_TYPE, C.REGION                                                 
 ORDER BY A.ACCT_TYPE, C.REGION;                                                
