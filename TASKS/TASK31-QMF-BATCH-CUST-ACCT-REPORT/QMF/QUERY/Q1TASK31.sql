SELECT REGION,SEGMENT,COUNT(*) AS CUSTOMET_COUNT                               
FROM T_CUSTOMER                                                                
WHERE STATUS = 'A'                                                             
GROUP BY REGION, SEGMENT                                                       
ORDER BY REGION, SEGMENT;                                                      
