      ******************************************************************
      * CREDIT CARD TRANSACTION VALIDATION SYSTEM                      *
      *                                                                *
      * PURPOSE:                                                       *
      * VALIDATES DAILY CARD TRANSACTIONS AGAINST CARD MASTER FILE.    *
      * CHECKS CARD EXISTENCE, STATUS (ACTIVE/BLOCKED), AND EXPIRY.    *
      * SPLITS TRANSACTIONS INTO APPROVED AND DECLINED FILES.          *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   READ TRANSACTION (TRANS-ID, CARD-NUM, AMOUNT)                *
      *   RANDOM READ VSAM BY CARD-NUM:                                *
      *     STATUS '23' -> DECLINE: NOT FOUND                          *
      *     STATUS '00' -> CHECK CARD-STATUS:                          *
      *       'B' -> DECLINE: BLOCKED                                  *
      *       OTHER -> CHECK EXPIRY (MMYY FORMAT):                     *
      *         YY = CUR-YY AND                                        *
      *         MM < CUR-MM          -> DECLINE: EXPIRED               *
      *         YY = CUR-YY AND                                        *
      *         MM = CUR-MM          -> APPROVE (VALID THRU MONTH END) *
      *         OTHERWISE            -> APPROVE                        *
      *     OTHER STATUS -> STOP RUN                                   *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2025/12/27                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  VSAMDD (CARD.MASTER) - CARD MASTER FILE (KSDS)         *
      * INPUT:  TRNSDD (TRANS.DAILY) - DAILY TRANSACTIONS (PS, 80 B)   *
      * OUTPUT: APRVDD (APPROVED.FILE) - APPROVED TRANS (PS, 80 B)     *
      * OUTPUT: DECLDD (DECLINED.FILE) - DECLINED TRANS (PS, 80 B)     *
      ******************************************************************
                                                                        
       IDENTIFICATION DIVISION.                                         
       PROGRAM-ID. VSMJOB11.                                            
       ENVIRONMENT DIVISION.                                            
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
           SELECT CARD-MASTER-FILE ASSIGN TO VSAMDD                     
               ORGANIZATION IS INDEXED                                  
               ACCESS MODE IS RANDOM                                    
               RECORD KEY IS CARD-NUMBER                                
               FILE STATUS IS CARD-FILE-STATUS.                         
                                                                        
           SELECT DAILY-TRANS-FILE ASSIGN TO TRNSDD                     
               ORGANIZATION IS SEQUENTIAL                               
               FILE STATUS IS TRANS-STATUS.                             
                                                                        
           SELECT APPROVED-TRANS-FILE ASSIGN TO APRVDD                  
               ORGANIZATION IS SEQUENTIAL                               
               FILE STATUS IS APPROVED-STATUS.                          
                                                                        
           SELECT DECLINED-TRANS-FILE ASSIGN TO DECLDD                  
               ORGANIZATION IS SEQUENTIAL                               
               FILE STATUS IS DECLINED-STATUS.                          
                                                                        
       DATA DIVISION.                                                   
       FILE SECTION.                                                    
       FD CARD-MASTER-FILE.                                             
       01 CARD-MASTER-REC.                                              
          05 CARD-NUMBER PIC 9(16).                                     
          05 CARD-OWNER-NAME PIC X(20).                                 
          05 CARD-EXPIRY-DATE PIC X(4).                                 
          05 CARD-STATUS PIC X(1).                                      
                                                                        
       FD DAILY-TRANS-FILE RECORDING MODE IS F.                         
       01 TRANSACTION-REC.                                              
          05 TRANS-ID PIC X(5).                                         
          05 TRANS-CARD-NUM PIC 9(16).                                  
          05 TRANS-AMOUNT PIC 9(5)V99.                                  
          05 FILLER PIC X(52).                                          
                                                                        
       FD APPROVED-TRANS-FILE RECORDING MODE IS F.                      
       01 APPROVED-REC.                                                 
          05 APPROVED-TRANS-ID PIC X(5).                                
          05 FILLER PIC X(1).                                           
          05 APPROVED-CARD-NUM PIC 9(16).                               
          05 FILLER PIC X(1).                                           
          05 APPROVED-AMOUNT PIC $$$$9.99.                              
          05 FILLER PIC X(49).                                          
                                                                        
       FD DECLINED-TRANS-FILE RECORDING MODE IS F.                      
       01 DECLINED-REC.                                                 
          05 DECLINED-TRANS-ID PIC X(5).                                
          05 FILLER PIC X(1).                                           
          05 DECLINED-CARD-NUM PIC 9(16).                               
          05 FILLER PIC X(1).                                           
          05 DECLINED-AMOUNT PIC $$$$9.99.                              
          05 FILLER PIC X(1).                                           
          05 DECLINE-REASON PIC X(10).                                  
          05 FILLER PIC X(38).                                          
                                                                        
       WORKING-STORAGE SECTION.                                         
                                                                        
      * FILE-STATUS VARIABLES                                           
       01 FILE-STATUSES.                                                
          05 CARD-FILE-STATUS PIC X(2).                                 
          05 TRANS-STATUS PIC X(2).                                     
          05 APPROVED-STATUS PIC X(2).                                  
          05 DECLINED-STATUS PIC X(2).                                  
                                                                        
      * CONTROL FLAGS                                                   
       01 WS-FLAGS.                                                     
          05 WS-EOF PIC X(1) VALUE 'N'.                                 
             88 EOF VALUE 'Y'.                                          
                                                                        
      * CURRENT DATE (YYYYMMDD FROM SYSTEM)                             
       01 WS-CUR-DATE-GROUP.                                            
          05 WS-CUR-YYYY PIC 9(4).                                      
          05 WS-CUR-MM PIC 9(2).                                        
          05 WS-CUR-DD PIC 9(2).                                        
                                                                        
      * DATE COMPARISON VARIABLES (YY FORMAT)                           
       01 WS-DATE-COMPARE.                                              
          05 WS-CUR-YY PIC 9(2).                                        
          05 WS-CARD-MM PIC 9(2).                                       
          05 WS-CARD-YY PIC 9(2).                                       
                                                                        
      * DECLINE REASON CODE                                             
       01 WS-DECLINE-REASON PIC X(10).                                  
                                                                        
      * STATISTICS COUNTERS                                             
       01 WS-COUNTERS.                                                  
          05 TOTAL-TRANSACTIONS PIC 9(5) VALUE 0.                       
          05 TOTAL-APPROVED PIC 9(5) VALUE 0.                           
          05 TOTAL-DECLINED PIC 9(5) VALUE 0.                           
          05 TOTAL-NOT-FOUND PIC 9(5) VALUE 0.                          
          05 TOTAL-BLOCKED PIC 9(5) VALUE 0.                            
          05 TOTAL-EXPIRED PIC 9(5) VALUE 0.                            
                                                                        
      * DISPLAY-FORMATTED COUNTERS                                      
       01 WS-DISP-COUNTERS.                                             
          05 TOTAL-TRANSACTIONS-DISP PIC Z(4)9.                         
          05 TOTAL-APPROVED-DISP PIC Z(4)9.                             
          05 TOTAL-DECLINED-DISP PIC Z(4)9.                             
          05 TOTAL-NOT-FOUND-DISP PIC Z(4)9.                            
          05 TOTAL-BLOCKED-DISP PIC Z(4)9.                              
          05 TOTAL-EXPIRED-DISP PIC Z(4)9.                              
                                                                        
      **********************************************                    
      * GETS SYSTEM DATE, OPENS ALL FILES,                              
      * PROCESSES TRANSACTIONS, CLOSES FILES                            
      * AND DISPLAYS FINAL SUMMARY.                                     
      **********************************************                    
       PROCEDURE DIVISION.                                              
       MAIN-LOGIC.                                                      
           PERFORM INIT-PROCESS.                                        
           PERFORM OPEN-ALL-FILES.                                      
           PERFORM READ-TRANS-LOOP.                                     
           PERFORM CLOSE-ALL-FILES.                                     
           PERFORM DISPLAY-SUMMARY.                                     
           STOP RUN.                                                    
                                                                        
      **********************************************                    
      * ACCEPTS CURRENT DATE FROM SYSTEM (YYYYMMDD)                     
      * AND EXTRACTS 2-DIGIT YEAR FOR EXPIRY COMPARE.                   
      **********************************************                    
       INIT-PROCESS.                                                    
           ACCEPT WS-CUR-DATE-GROUP FROM DATE YYYYMMDD.                 
           MOVE WS-CUR-YYYY(3:2) TO WS-CUR-YY.                          
           DISPLAY 'CURRENT DATE: ' WS-CUR-YYYY '/' WS-CUR-MM '/'       
                    WS-CUR-DD.                                          
           DISPLAY 'COMPARE YEAR: ' WS-CUR-YY.                          
           DISPLAY 'COMPARE MONTH: ' WS-CUR-MM.                         
                                                                        
      **********************************************                    
      * OPEN ALL FILES AND CHECK STATUS                                 
      **********************************************                    
       OPEN-ALL-FILES.                                                  
           OPEN INPUT CARD-MASTER-FILE.                                 
           IF CARD-FILE-STATUS NOT = '00'                               
              DISPLAY 'ERROR OPENING CARD MASTER FILE: '                
                       CARD-FILE-STATUS                                 
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN INPUT DAILY-TRANS-FILE.                                 
           IF TRANS-STATUS NOT = '00'                                   
              DISPLAY 'ERROR OPENING TRANSACTIONS FILE: ' TRANS-STATUS  
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN OUTPUT APPROVED-TRANS-FILE.                             
           IF APPROVED-STATUS NOT = '00'                                
              DISPLAY 'ERROR OPENING APPROVED FILE: ' APPROVED-STATUS   
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN OUTPUT DECLINED-TRANS-FILE.                             
           IF DECLINED-STATUS NOT = '00'                                
              DISPLAY 'ERROR OPENING DECLINED FILE: ' DECLINED-STATUS   
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * READS TRANSACTIONS SEQUENTIALLY UNTIL EOF.                      
      * INITIALIZES OUTPUT RECORDS BEFORE EACH                          
      * ITERATION AND CALLS PROCESS-TRANSACTION.                        
      **********************************************                    
       READ-TRANS-LOOP.                                                 
           PERFORM UNTIL EOF                                            
              MOVE SPACES TO APPROVED-REC                               
              MOVE SPACES TO DECLINED-REC                               
              READ DAILY-TRANS-FILE                                     
                AT END                                                  
                   SET EOF TO TRUE                                      
                NOT AT END                                              
                   IF TRANS-STATUS = '00'                               
                      ADD 1 TO TOTAL-TRANSACTIONS                       
                      PERFORM PROCESS-TRANSACTION                       
                   ELSE                                                 
                      DISPLAY 'ERROR READING TRANS FILE: ' TRANS-STATUS 
                      STOP RUN                                          
                   END-IF                                               
              END-READ                                                  
           END-PERFORM.                                                 
                                                                        
      **********************************************                    
      * RANDOM READ VSAM BY CARD-NUM AND ROUTES                         
      * TO VALIDATE-CARD-STATUS OR DECLINE.                             
      * STATUS '23' -> DECLINE NOT FOUND.                               
      * STATUS '00' -> VALIDATE-CARD-STATUS.                            
      * OTHER       -> STOP RUN.                                        
      **********************************************                    
       PROCESS-TRANSACTION.                                             
           MOVE SPACES TO WS-DECLINE-REASON.                            
           MOVE TRANS-CARD-NUM TO CARD-NUMBER.                          
           READ CARD-MASTER-FILE                                        
           IF CARD-FILE-STATUS = '23'                                   
              MOVE 'NOT FOUND' TO WS-DECLINE-REASON                     
              PERFORM WRITE-DECLINED-TRANS                              
           ELSE                                                         
             IF CARD-FILE-STATUS = '00'                                 
                PERFORM VALIDATE-STATUS                                 
             ELSE                                                       
                DISPLAY 'CRITICAL VSAM READ ERROR: ' CARD-FILE-STATUS   
                DISPLAY 'TRANSACTION ID: ' TRANS-ID                     
                DISPLAY 'CARD NUMBER: ' TRANS-CARD-NUM                  
                STOP RUN                                                
             END-IF                                                     
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CHECK CARD-STATUS FIELD:                                        
      * 'B' (BLOCKED) -> DECLINE.                                       
      * OTHER         -> VALIDATE-EXPIRY.                               
      **********************************************                    
       VALIDATE-STATUS.                                                 
           IF CARD-STATUS = 'B'                                         
              MOVE 'BLOCKED' TO WS-DECLINE-REASON                       
              PERFORM WRITE-DECLINED-TRANS                              
           ELSE                                                         
              PERFORM VALIDATE-EXPIRY                                   
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CHECKS CARD EXPIRY DATE (MMYY FORMAT).                          
      * COMPARES WS-CARD-YY VS WS-CUR-YY FIRST,                         
      * THEN MONTH IF YEARS ARE EQUAL.                                  
      * EXPIRED -> DECLINE. OTHERWISE -> APPROVE.                       
      **********************************************                    
       VALIDATE-EXPIRY.                                                 
           MOVE CARD-EXPIRY-DATE(1:2) TO WS-CARD-MM.                    
           MOVE CARD-EXPIRY-DATE(3:2) TO WS-CARD-YY.                    
           IF WS-CARD-YY < WS-CUR-YY                                    
              MOVE 'EXPIRED' TO WS-DECLINE-REASON                       
              PERFORM WRITE-DECLINED-TRANS                              
           ELSE                                                         
              IF WS-CARD-YY = WS-CUR-YY                                 
                 IF WS-CARD-MM < WS-CUR-MM                              
                    MOVE 'EXPIRED' TO WS-DECLINE-REASON                 
                    PERFORM WRITE-DECLINED-TRANS                        
                 ELSE                                                   
                    PERFORM WRITE-APPROVED-TRANS                        
                 END-IF                                                 
              ELSE                                                      
                 PERFORM WRITE-APPROVED-TRANS                           
              END-IF                                                    
           END-IF.                                                      
                                                                        
      **********************************************                    
      * WRITE APPROVED TRANSACTION TO OUTPUT FILE                       
      **********************************************                    
       WRITE-APPROVED-TRANS.                                            
           MOVE TRANS-ID TO APPROVED-TRANS-ID.                          
           MOVE TRANS-CARD-NUM TO APPROVED-CARD-NUM.                    
           MOVE TRANS-AMOUNT TO APPROVED-AMOUNT.                        
           WRITE APPROVED-REC.                                          
           IF APPROVED-STATUS NOT = '00'                                
              DISPLAY 'ERROR WRITING APPROVED FILE: ' APPROVED-STATUS   
              DISPLAY 'TRANSACTION ID: ' TRANS-ID                       
              STOP RUN                                                  
           ELSE                                                         
              ADD 1 TO TOTAL-APPROVED                                   
           END-IF.                                                      
                                                                        
      **********************************************                    
      * WRITES DECLINED TRANSACTION WITH REASON.                        
      * ALSO INCREMENTS BREAKDOWN COUNTER FOR THE                       
      * SPECIFIC DECLINE REASON.                                        
      **********************************************                    
       WRITE-DECLINED-TRANS.                                            
           MOVE TRANS-ID TO DECLINED-TRANS-ID.                          
           MOVE TRANS-CARD-NUM TO DECLINED-CARD-NUM.                    
           MOVE TRANS-AMOUNT TO DECLINED-AMOUNT.                        
           MOVE WS-DECLINE-REASON TO DECLINE-REASON.                    
           WRITE DECLINED-REC.                                          
           IF DECLINED-STATUS NOT = '00'                                
              DISPLAY 'ERROR WRITING DECLINED FILE: ' DECLINED-STATUS   
              DISPLAY 'TRANSACTION ID: ' TRANS-ID                       
              STOP RUN                                                  
           ELSE                                                         
              ADD 1 TO TOTAL-DECLINED                                   
                                                                        
              EVALUATE WS-DECLINE-REASON                                
                  WHEN 'NOT FOUND'                                      
                    ADD 1 TO TOTAL-NOT-FOUND                            
                  WHEN 'BLOCKED'                                        
                    ADD 1 TO TOTAL-BLOCKED                              
                  WHEN 'EXPIRED'                                        
                    ADD 1 TO TOTAL-EXPIRED                              
              END-EVALUATE                                              
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CLOSE ALL FILES AND CHECK STATUS                                
      **********************************************                    
       CLOSE-ALL-FILES.                                                 
           CLOSE CARD-MASTER-FILE.                                      
           IF CARD-FILE-STATUS NOT = '00'                               
              DISPLAY 'WARNING: ERROR CLOSING CARD MASTER: '            
                       CARD-FILE-STATUS                                 
           END-IF.                                                      
                                                                        
           CLOSE DAILY-TRANS-FILE.                                      
           IF TRANS-STATUS NOT = '00'                                   
              DISPLAY 'WARNING: ERROR CLOSING TRANSACTIONS: '           
                       TRANS-STATUS                                     
           END-IF.                                                      
                                                                        
           CLOSE APPROVED-TRANS-FILE.                                   
           IF APPROVED-STATUS NOT = '00'                                
              DISPLAY 'WARNING: ERROR CLOSING APPROVED: '               
                       APPROVED-STATUS                                  
           END-IF.                                                      
                                                                        
           CLOSE DECLINED-TRANS-FILE.                                   
           IF DECLINED-STATUS NOT = '00'                                
              DISPLAY 'WARNING: ERROR CLOSING DECLINED: '               
                      DECLINED-STATUS                                   
           END-IF.                                                      
                                                                        
      **********************************************                    
      * DISPLAY SUMMARY STATISTICS TO SYSOUT                            
      **********************************************                    
       DISPLAY-SUMMARY.                                                 
           MOVE TOTAL-TRANSACTIONS TO TOTAL-TRANSACTIONS-DISP.          
           MOVE TOTAL-APPROVED TO TOTAL-APPROVED-DISP.                  
           MOVE TOTAL-DECLINED TO TOTAL-DECLINED-DISP.                  
           MOVE TOTAL-NOT-FOUND TO TOTAL-NOT-FOUND-DISP.                
           MOVE TOTAL-BLOCKED TO TOTAL-BLOCKED-DISP.                    
           MOVE TOTAL-EXPIRED TO TOTAL-EXPIRED-DISP.                    
                                                                        
           DISPLAY '========================================'.          
           DISPLAY 'CARD VALIDATION SUMMARY'.                           
           DISPLAY '========================================'.          
           DISPLAY 'TOTAL TRANSACTIONS: ' TOTAL-TRANSACTIONS-DISP.      
           DISPLAY 'APPROVED:           ' TOTAL-APPROVED-DISP.          
           DISPLAY 'DECLINED:           ' TOTAL-DECLINED-DISP.          
           DISPLAY '  NOT FOUND:        ' TOTAL-NOT-FOUND-DISP.         
           DISPLAY '  BLOCKED:          ' TOTAL-BLOCKED-DISP.           
           DISPLAY '  EXPIRED:          ' TOTAL-EXPIRED-DISP.           
           DISPLAY '========================================'.          
