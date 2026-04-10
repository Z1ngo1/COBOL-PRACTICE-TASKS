      ******************************************************************
      * COMMISSION PAYOUT SYSTEM - SALES COMMISSION WITH TAX CALC      *
      *                                                                *
      * PURPOSE:                                                       *
      * READS SALES RECORDS FROM INPUT FILE AND CALCULATES COMMISSION  *
      * AND TAX FOR EACH EMPLOYEE BY CALLING TWO SUBPROGRAMS.          *
      * WRITES PAYOUT DETAILS TO OUTPUT FILE.                          *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - READ: READ EMPLOYEE SALES RECORD FROM SALES-FILE.  *
      *   PHASE 2 - COMMISSION: CALL SUB1JB22 WITH EMP-ID, REGION,     *
      *     SALES-AMT. RECEIVE WS-COMMISSION.                          *
      *   PHASE 3 - TAX: CALL SUB2JB22 WITH WS-COMMISSION.             *
      *     RECEIVE WS-TAX-AMOUNT.                                     *
      *   PHASE 4 - OUTPUT: NET = COMMISSION - TAX. WRITE PAYOUT LINE. *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/01/19                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  INDD (SALES.DATA) - EMPLOYEE SALES RECORDS (PS, 80 B)  *
      * OUTPUT: OUTDD (COMM.PAYOUT) - COMMISSION PAYOUT REPORT (PS, F) *
      *                                                                *
      * SUBPROGRAMS CALLED:                                            *
      * SUB1JB22 - COMMISSION RATE BY REGION + SALES VOLUME BONUS      *
      * SUB2JB22 - TAX RATE BY COMMISSION BRACKET                      *
      ******************************************************************
       IDENTIFICATION DIVISION.                                         
       PROGRAM-ID. JOBSUB22.                                            
       ENVIRONMENT DIVISION.                                            
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
                                                                        
           SELECT SALES-FILE ASSIGN TO INDD                             
              ORGANIZATION IS SEQUENTIAL                                
              FILE STATUS IS SALES-STATUS.                              
                                                                        
           SELECT PAYOUT-FILE ASSIGN TO OUTDD                           
              ORGANIZATION IS SEQUENTIAL                                
              FILE STATUS IS PAYOUT-STATUS.                             
                                                                        
       DATA DIVISION.                                                   
       FILE SECTION.                                                    
       FD SALES-FILE RECORDING MODE IS F.                               
       01 SALES-REC.                                                    
          05 EMP-ID PIC X(5).                                           
          05 REGION PIC X(2).                                           
          05 SALES-AMT PIC 9(6)V99.                                     
          05 FILLER PIC X(65).                                          
                                                                        
       FD PAYOUT-FILE RECORDING MODE IS F.                              
       01 PAYOUT-REC PIC X(80).                                         
                                                                        
       WORKING-STORAGE SECTION.                                         
                                                                        
      * FILE STATUS VARIABLES                                           
       01 F-STATUS.                                                     
          05 SALES-STATUS PIC X(2).                                     
          05 PAYOUT-STATUS PIC X(2).                                    
                                                                        
      * CONTROL FLAGS                                                   
       01 WS-FLAGS.                                                     
          05 WS-EOF PIC X(1) VALUE 'N'.                                 
             88 EOF VALUE 'Y'.                                          
                                                                        
      * CALCULATED RESULTS FROM SUBPROGRAMS                             
       01 WS-COMMISSION    PIC 9(5)V99.                                 
       01 WS-TAX-AMOUNT    PIC 9(5)V99.                                 
       01 WS-NET-COMM      PIC 9(5)V99.                                 
                                                                        
      * DISPLAY-FORMATTED CALCULATED VALUES FOR OUTPUT LINE             
       01 WS-COMM-STR      PIC Z(5).99.                                 
       01 WS-TAX-STR       PIC Z(5).99.                                 
       01 WS-NET-STR       PIC Z(5).99.                                 
                                                                        
      **********************************************                    
      * OPENS FILES, PROCESSES ALL RECORDS, CLOSES.                     
      **********************************************                    
       PROCEDURE DIVISION.                                              
       MAIN-LOGIC.                                                      
           PERFORM OPEN-ALL-FILES.                                      
           PERFORM PROCESS-ALL-RECORDS.                                 
           PERFORM CLOSE-ALL-FILES.                                     
           STOP RUN.                                                    
                                                                        
      **********************************************                    
      * OPEN ALL FILES AND CHECK STATUS                                 
      **********************************************                    
       OPEN-ALL-FILES.                                                  
           OPEN INPUT SALES-FILE.                                       
           IF SALES-STATUS NOT = '00'                                   
              DISPLAY 'ERROR OPENING INPUT FILE: ' SALES-STATUS         
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN OUTPUT PAYOUT-FILE.                                     
           IF PAYOUT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR OPENING OUTPUT FILE: ' PAYOUT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * READS SALES-FILE UNTIL EOF.                                     
      * PER RECORD: CALLS SUB1JB22 (COMMISSION),                        
      * SUB2JB22 (TAX), THEN WRITE-PAYOUT-LINE.                         
      **********************************************                    
       PROCESS-ALL-RECORDS.                                             
           PERFORM UNTIL WS-EOF = 'Y'                                   
              READ SALES-FILE                                           
                AT END                                                  
                   MOVE 'Y' TO WS-EOF                                   
                NOT AT END                                              
                   IF SALES-STATUS NOT = '00'                           
                      DISPLAY 'ERROR READING FILE: ' SALES-STATUS       
                      STOP RUN                                          
                   END-IF                                               
      * PHASE 2 - COMMISSION: BASE RATE BY REGION + BONUS BY VOLUME     
                   CALL 'SUB1JB22' USING                                
                        EMP-ID,                                         
                        REGION,                                         
                        SALES-AMT,                                      
                        WS-COMMISSION                                   
                   END-CALL                                             
      * PHASE 3 - TAX: RATE BY COMMISSION BRACKET                       
                   CALL 'SUB2JB22' USING                                
                        WS-COMMISSION,                                  
                        WS-TAX-AMOUNT                                   
                   END-CALL                                             
                   PERFORM COMPUTE-AND-WRITE                            
              END-READ                                                  
           END-PERFORM.                                                 
                                                                        
      **********************************************                    
      * COMPUTES NET-COMMISSION = COMMISSION - TAX.                     
      * FORMATS ALL THREE AMOUNTS AND WRITES ONE                        
      * PAYOUT LINE PER EMPLOYEE TO PAYOUT-FILE.                        
      **********************************************                    
       COMPUTE-AND-WRITE.                                               
           COMPUTE WS-NET-COMM = WS-COMMISSION - WS-TAX-AMOUNT.         
                                                                        
           MOVE SPACES TO PAYOUT-REC.                                   
           MOVE WS-COMMISSION TO WS-COMM-STR.                           
           MOVE WS-TAX-AMOUNT TO WS-TAX-STR.                            
           MOVE WS-NET-COMM TO WS-NET-STR.                              
           STRING EMP-ID DELIMITED BY SIZE                              
                  ' COMMISSION: ' DELIMITED BY SIZE                     
                  FUNCTION TRIM(WS-COMM-STR) DELIMITED BY SIZE          
                  ', TAX: ' DELIMITED BY SIZE                           
                  FUNCTION TRIM(WS-TAX-STR) DELIMITED BY SIZE           
                  ', NET: ' DELIMITED BY SIZE                           
                  FUNCTION TRIM(WS-NET-STR) DELIMITED BY SIZE           
                  INTO PAYOUT-REC                                       
           END-STRING.                                                  
           WRITE PAYOUT-REC.                                            
           IF PAYOUT-STATUS NOT = '00'                                  
              DISPLAY 'ERROR WRITING OUTPUT FILE: ' PAYOUT-STATUS       
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
      **********************************************                    
      * CLOSE ALL FILES                                                 
      **********************************************                    
       CLOSE-ALL-FILES.                                                 
           CLOSE SALES-FILE.                                            
           IF SALES-STATUS NOT = '00'                                   
              DISPLAY 'WARNING: ERROR CLOSING INPUT FILE: ' SALES-STATUS
           END-IF.                                                      
           CLOSE PAYOUT-FILE.                                           
           IF PAYOUT-STATUS NOT = '00'                                  
              DISPLAY 'WARNING: ERROR CLOSING OUTPUT FILE: '            
                       PAYOUT-STATUS                                    
           END-IF.                                                      
