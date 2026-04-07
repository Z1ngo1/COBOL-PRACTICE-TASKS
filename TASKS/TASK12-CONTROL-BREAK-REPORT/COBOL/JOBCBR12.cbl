      ******************************************************************
      * CONTROL BREAK REPORT - SALES BY REGION AND SHOP                *
      *                                                                *
      * PURPOSE:                                                       *
      * GENERATES HIERARCHICAL SALES REPORT WITH SUBTOTALS AT SHOP     *
      * AND REGION LEVELS, PLUS GRAND TOTAL. DEMONSTRATES CLASSIC      *
      * CONTROL BREAK (LEVEL BREAK) ALGORITHM FOR GROUPED DATA.        *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   1. READ PRE-SORTED SALES FILE (BY REGION, THEN SHOP)         *
      *   2. DETECT CONTROL BREAKS WHEN REGION OR SHOP CHANGES         *
      *   3. PRINT SUBTOTALS:                                          *
      *      - SHOP LEVEL: SUM FOR EACH SHOP WITHIN REGION             *
      *      - REGION LEVEL: SUM FOR ENTIRE REGION (ALL SHOPS)         *
      *      - GRAND TOTAL: SUM ACROSS ALL REGIONS                     *
      *   4. TRACK STATISTICS: REGION COUNT, SHOP COUNT, RECORD COUNT  *
      *                                                                *
      * CONTROL BREAK HIERARCHY:                                       *
      *   LEVEL 1 (MAJOR): REGION CHANGE -> PRINT SHOP + REGION TOTAL  *
      *   LEVEL 2 (MINOR): SHOP CHANGE -> PRINT SHOP TOTAL ONLY        *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2025/12/29                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  PSSDD (SALES.DATA) - SORTED SALES DATA (PS, 80 BYTES)  *
      * OUTPUT: REPDD (SALES.REPORT) - FORMATTED REPORT (PS, 80 BYTES) *
      ******************************************************************
                                                                        
       IDENTIFICATION DIVISION.                                         
       PROGRAM-ID. JOBCBR12.                                            
       ENVIRONMENT DIVISION.                                            
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
           SELECT SALES-DATA-FILE ASSIGN TO PSSDD                       
               ORGANIZATION IS SEQUENTIAL                               
               FILE STATUS IS SALES-DATA-STATUS.                        
           SELECT SALES-REPORT-FILE ASSIGN TO REPDD                     
               ORGANIZATION IS SEQUENTIAL                               
               FILE STATUS IS REPORT-STATUS.                            
                                                                        
       DATA DIVISION.                                                   
       FILE SECTION.                                                    
       FD SALES-DATA-FILE RECORDING MODE IS F.                          
       01 SALES-RECORD.                                                 
          05 SALES-REGION PIC X(5).                                     
          05 SALES-SHOP PIC X(5).                                       
          05 SALES-AMOUNT PIC 9(5)V99.                                  
          05 FILLER PIC X(63).                                          
                                                                        
       FD SALES-REPORT-FILE RECORDING MODE IS F.                        
       01 REPORT-LINE PIC X(80).                                        
                                                                        
       WORKING-STORAGE SECTION.                                         
                                                                        
      * FILE STATUS VARIABLES                                           
       01 FILE-STATUSES.                                                
          05 SALES-DATA-STATUS PIC X(2).                                
          05 REPORT-STATUS PIC X(2).                                    
                                                                        
      * CONTROL FLAGS                                                   
       01 FLAGS.                                                        
          05 WS-EOF PIC X(1) VALUE 'N'.                                 
             88 EOF VALUE 'Y'.                                          
                                                                        
      * PREVIOUS VALUE HOLDERS FOR CONTROL BREAK DETECTION              
       01 HOLDERS.                                                      
          05 PREV-REGION PIC X(5) VALUE SPACES.                         
          05 PREV-SHOP PIC X(5) VALUE SPACES.                           
                                                                        
      * COUNTERS FOR REGIONS, SHOPS, AND RECORDS                        
       01 COUNTERS.                                                     
          05 REC-COUNTER PIC 9(5) VALUE 0.                              
          05 REGION-COUNT PIC 9(5) VALUE 0.                             
          05 SHOP-COUNT PIC 9(5) VALUE 0.                               
          05 TOTAL-SHOP-COUNT PIC 9(5) VALUE 0.                         
          05 TOTAL-REGION-COUNT PIC 9(5) VALUE 0.                       
                                                                        
      * ACCUMULATORS FOR SUBTOTALS AND GRAND TOTAL                      
       01 ACCUMULATORS.                                                 
          05 TOTAL-SHOP PIC 9(5)V99 VALUE 0.                            
          05 TOTAL-REGION PIC 9(5)V99 VALUE 0.                          
          05 GRAND-TOTAL PIC 9(7)V99 VALUE 0.                           
                                                                        
      * FORMATTED OUTPUT VARIABLES                                      
       01 OUTPUT-LINE PIC X(80).                                        
       01 DISP-AMOUNT PIC Z(4)9.99.                                     
       01 DISP-GRAND PIC Z(6)9.99.                                      
       01 DISP-SHOPS PIC Z(4)9.                                         
       01 DISP-REGIONS PIC Z(4)9.                                       
       01 DISP-RECORDS PIC Z(4)9.                                       
       01 TEMP-TOTAL-SHOPS PIC Z(4)9.                                   
                                                                        
      **********************************************                    
      * OPENS FILES, SEEDS PREV-KEYS FROM FIRST                         
      * RECORD, PROCESSES ALL RECORDS, CLOSES.                          
      **********************************************                    
       PROCEDURE DIVISION.                                              
       MAIN-LOGIC.                                                      
           PERFORM OPEN-ALL-FILES.                                      
           PERFORM INIT-FIRST-RECORD.                                   
           IF NOT EOF                                                   
              PERFORM PROCESS-FIRST-RECORD                              
              PERFORM PROCESS-SALES                                     
           END-IF.                                                      
           PERFORM CLOSE-ALL-FILES.                                     
           STOP RUN.                                                    
                                                                        
      **********************************************                    
      * OPEN ALL FILES AND CHECK STATUS                                 
      **********************************************                    
       OPEN-ALL-FILES.                                                  
           OPEN INPUT SALES-DATA-FILE.                                  
           IF SALES-DATA-STATUS NOT = '00'                              
              DISPLAY 'ERROR OPENING SALES DATA FILE: '                 
                       SALES-DATA-STATUS                                
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN OUTPUT SALES-REPORT-FILE.                               
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR OPENING REPORT FILE: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * READS FIRST RECORD AND SEEDS PREV-KEYS.                         
      * IF FILE IS EMPTY, SETS EOF.                                     
      **********************************************                    
       INIT-FIRST-RECORD.                                               
           READ SALES-DATA-FILE                                         
             AT END                                                     
                SET EOF TO TRUE                                         
             NOT AT END                                                 
                IF SALES-DATA-STATUS = '00'                             
                   MOVE SALES-REGION TO PREV-REGION                     
                   MOVE SALES-SHOP TO PREV-SHOP                         
                   MOVE 1 TO REGION-COUNT                               
                   MOVE 1 TO SHOP-COUNT                                 
                   ADD 1 TO TOTAL-REGION-COUNT                          
                   ADD 1 TO TOTAL-SHOP-COUNT                            
                ELSE                                                    
                   DISPLAY 'ERROR READING SALES DATA FILE: '            
                            SALES-DATA-STATUS                           
                   STOP RUN                                             
                END-IF                                                  
           END-READ.                                                    
                                                                        
      **********************************************                    
      * ACCUMULATES AND PRINTS DETAIL LINE FOR                          
      * THE FIRST RECORD (PREV-KEYS ALREADY SET).                       
      **********************************************                    
       PROCESS-FIRST-RECORD.                                            
           ADD 1 TO REC-COUNTER.                                        
           ADD SALES-AMOUNT TO TOTAL-SHOP.                              
           ADD SALES-AMOUNT TO TOTAL-REGION.                            
           MOVE SALES-AMOUNT TO DISP-AMOUNT.                            
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'RECORD: ' DELIMITED BY SIZE                          
                  SALES-REGION DELIMITED BY SIZE                        
                  ' ' DELIMITED BY SIZE                                 
                  SALES-SHOP DELIMITED BY SIZE                          
                  ': ' DELIMITED BY SIZE                                
                  FUNCTION TRIM(DISP-AMOUNT) DELIMITED BY SIZE          
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING REPORT: ' REPORT-STATUS            
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * READS LOOP UNTIL EOF. ON EOF FLUSHES                            
      * FINAL TOTALS VIA PRINT-FINAL-TOTALS.                            
      **********************************************                    
       PROCESS-SALES.                                                   
           PERFORM UNTIL EOF                                            
              READ SALES-DATA-FILE                                      
                AT END                                                  
                   SET EOF TO TRUE                                      
                   PERFORM PRINT-FINAL-TOTALS                           
                NOT AT END                                              
                   IF SALES-DATA-STATUS = '00'                          
                      PERFORM PROCESS-SALES-RECORD                      
                   ELSE                                                 
                      DISPLAY 'ERROR READING SALES DATA: '              
                               SALES-DATA-STATUS                        
                      STOP RUN                                          
                   END-IF                                               
              END-READ                                                  
           END-PERFORM.                                                 
                                                                        
      **********************************************                    
      * CHECKS LEVEL 1 (REGION) AND LEVEL 2 (SHOP)                      
      * BREAKS, THEN ACCUMULATES AND PRINTS DETAIL.                     
      **********************************************                    
       PROCESS-SALES-RECORD.                                            
           ADD 1 TO REC-COUNTER.                                        
                                                                        
      * LEVEL 1 BREAK: FLUSH SHOP + REGION, RESET SHOP COUNTER          
           IF SALES-REGION NOT = PREV-REGION                            
              PERFORM PRINT-SHOP-TOTAL                                  
              PERFORM PRINT-REGION-TOTAL                                
              MOVE SALES-REGION TO PREV-REGION                          
              MOVE SPACES TO PREV-SHOP                                  
              ADD 1 TO TOTAL-REGION-COUNT                               
              MOVE 0 TO SHOP-COUNT                                      
           END-IF.                                                      
                                                                        
      * LEVEL 2 BREAK: FLUSH SHOP, PRINT BLANK SEPARATOR                
           IF SALES-SHOP NOT = PREV-SHOP                                
              PERFORM PRINT-SHOP-TOTAL                                  
              MOVE SPACES TO REPORT-LINE                                
              MOVE SPACES TO OUTPUT-LINE                                
              WRITE REPORT-LINE FROM OUTPUT-LINE                        
              IF REPORT-STATUS NOT = '00'                               
                 DISPLAY 'ERROR WRITING SEPARATOR: ' REPORT-STATUS      
                 STOP RUN                                               
              END-IF                                                    
              MOVE SALES-SHOP TO PREV-SHOP                              
              ADD 1 TO TOTAL-SHOP-COUNT                                 
              ADD 1 TO SHOP-COUNT                                       
           END-IF.                                                      
                                                                        
           ADD SALES-AMOUNT TO TOTAL-SHOP.                              
           ADD SALES-AMOUNT TO TOTAL-REGION.                            
                                                                        
           MOVE SALES-AMOUNT TO DISP-AMOUNT.                            
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'RECORD: ' DELIMITED BY SIZE                          
                  SALES-REGION DELIMITED BY SIZE                        
                  ' ' DELIMITED BY SIZE                                 
                  SALES-SHOP DELIMITED BY SIZE                          
                  ': ' DELIMITED BY SIZE                                
                  FUNCTION TRIM(DISP-AMOUNT) DELIMITED BY SIZE          
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING REPORT: ' REPORT-STATUS            
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * PRINTS SHOP SUBTOTAL AND RESETS TOTAL-SHOP.                     
      * SKIPPED IF ACCUM-SHOP = 0 (DOUBLE-FLUSH                         
      * GUARD ON REGION BREAK).                                         
      **********************************************                    
       PRINT-SHOP-TOTAL.                                                
           IF TOTAL-SHOP > 0                                            
              MOVE TOTAL-SHOP TO DISP-AMOUNT                            
              MOVE SPACES TO REPORT-LINE                                
              MOVE SPACES TO OUTPUT-LINE                                
              STRING '   --> SUM FOR SHOP: ' DELIMITED BY SIZE          
                     FUNCTION TRIM(DISP-AMOUNT) DELIMITED BY SIZE       
                     INTO OUTPUT-LINE                                   
              WRITE REPORT-LINE FROM OUTPUT-LINE                        
              IF REPORT-STATUS NOT = '00'                               
                 DISPLAY 'ERROR WRITING SHOP TOTAL: ' REPORT-STATUS     
                 STOP RUN                                               
              END-IF                                                    
              MOVE 0 TO TOTAL-SHOP                                      
           END-IF.                                                      
                                                                        
      **********************************************                    
      * PRINTS REGION SUBTOTAL FOR PREV-REGION.                         
      * ADDS TOTAL-REGION TO GRAND-TOTAL, RESETS IT.                    
      **********************************************                    
       PRINT-REGION-TOTAL.                                              
           MOVE TOTAL-REGION TO DISP-AMOUNT.                            
           MOVE SHOP-COUNT TO DISP-SHOPS.                               
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING '====== TOTAL FOR ' DELIMITED BY SIZE                 
                  PREV-REGION DELIMITED BY SIZE                         
                  ': ' DELIMITED BY SIZE                                
                  FUNCTION TRIM(DISP-AMOUNT) DELIMITED BY SIZE          
                  ' (SHOPS: ' DELIMITED BY SIZE                         
                  FUNCTION TRIM(DISP-SHOPS) DELIMITED BY SIZE           
                  ')' DELIMITED BY SIZE                                 
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING REGION TOTAL: ' REPORT-STATUS      
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           ADD TOTAL-REGION TO GRAND-TOTAL.                             
           MOVE 0 TO TOTAL-REGION.                                      
                                                                        
      * BLANK SEPARATOR AFTER EACH REGION BLOCK                         
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING SEPARATOR: ' REPORT-STATUS         
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CALLED ON EOF. FLUSHES LAST SHOP/REGION,                        
      * THEN PRINTS GRAND TOTAL AND STATISTICS.                         
      **********************************************                    
       PRINT-FINAL-TOTALS.                                              
           IF REC-COUNTER > 0                                           
              PERFORM PRINT-SHOP-TOTAL                                  
              PERFORM PRINT-REGION-TOTAL                                
              MOVE SPACES TO OUTPUT-LINE                                
              MOVE SPACES TO REPORT-LINE                                
              WRITE REPORT-LINE FROM OUTPUT-LINE                        
              IF REPORT-STATUS NOT = '00'                               
                 DISPLAY 'ERROR WRITING SEPARATOR: ' REPORT-STATUS      
                 STOP RUN                                               
              END-IF                                                    
           END-IF.                                                      
                                                                        
           MOVE GRAND-TOTAL TO DISP-GRAND.                              
           MOVE TOTAL-REGION-COUNT TO DISP-REGIONS.                     
           MOVE TOTAL-SHOP-COUNT TO TEMP-TOTAL-SHOPS.                   
           MOVE REC-COUNTER TO DISP-RECORDS.                            
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING '******************************** ' DELIMITED BY SIZE 
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'GRAND TOTAL SALES: ' DELIMITED BY SIZE               
                  FUNCTION TRIM(DISP-GRAND) DELIMITED BY SIZE           
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING '******************************** ' DELIMITED BY SIZE 
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'REGIONS: ' DELIMITED BY SIZE                         
                  FUNCTION TRIM(DISP-REGIONS) DELIMITED BY SIZE         
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'TOTAL SHOPS: ' DELIMITED BY SIZE                     
                  FUNCTION TRIM(TEMP-TOTAL-SHOPS) DELIMITED BY SIZE     
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           MOVE SPACES TO REPORT-LINE.                                  
           MOVE SPACES TO OUTPUT-LINE.                                  
           STRING 'TOTAL RECORDS: ' DELIMITED BY SIZE                   
                  FUNCTION TRIM(DISP-RECORDS) DELIMITED BY SIZE         
                  INTO OUTPUT-LINE                                      
           END-STRING.                                                  
           WRITE REPORT-LINE FROM OUTPUT-LINE.                          
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING GRAND TOTAL: ' REPORT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CLOSE ALL FILES AND CHECK STATUS                                
      **********************************************                    
       CLOSE-ALL-FILES.                                                 
           CLOSE SALES-DATA-FILE.                                       
           IF SALES-DATA-STATUS NOT = '00'                              
              DISPLAY 'WARNING: ERROR CLOSING SALES DATA: '             
                       SALES-DATA-STATUS                                
           END-IF.                                                      
                                                                        
           CLOSE SALES-REPORT-FILE.                                     
           IF REPORT-STATUS NOT = '00'                                  
              DISPLAY 'WARNING: ERROR CLOSING REPORT FILE : '           
                       REPORT-STATUS                                    
           END-IF.                                                      
