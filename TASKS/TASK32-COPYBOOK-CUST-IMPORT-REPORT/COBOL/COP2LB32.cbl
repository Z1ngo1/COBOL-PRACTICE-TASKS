      ******************************************************************
      * VSAM CUSTOMER REPORT BY REGION FILTER                          *
      *                                                                *
      * PURPOSE:                                                       *
      * READS FILTER PARAMETER FROM SYSIN (REGION=XX), SCANS VSAM      *
      * KSDS MASTER FILE SEQUENTIALLY, WRITES MATCHING ACTIVE          *
      * CUSTOMERS TO PS OUTPUT FILE WITH FINAL STATISTICS.             *
      *                                                                *
      * BUSINESS LOGIC:                                                *
      *   PHASE 1 - READ REGION FILTER FROM SYSIN:                     *
      *     ACCEPT WS-REGION-FILTER FROM SYSIN.                        *
      *   PHASE 2 - SEQUENTIAL SCAN OF VSAM MASTER FILE:               *
      *     CUST-STATUS NOT = 'A'             -> SKIP RECORD.          *
      *     CUST-REGION NOT = WS-REGION-FILTER -> SKIP RECORD.         *
      *     BOTH CHECKS PASSED:                                        *
      *       WRITE CUST-OUT-REC FROM CUST-MASTER-REC.                 *
      *       ADD 1 TO WS-COUNT.                                       *
      *       ADD CUST-CURRENT-BAL  TO WS-TOTAL-BAL.                   *
      *       ADD CUST-CREDIT-LIMIT TO WS-TOTAL-LIMIT.                 *
      *   PHASE 3 - FINAL STATISTICS:                                  *
      *     DISPLAY TOTAL ACTIVE IN REGION, BALANCE, CREDIT LIMIT.     *
      *                                                                *
      * COPYBOOK: TASK32 - CUSTOMER RECORD LAYOUT (CUST-RECORD)        *
      *                                                                *
      * AUTHOR: STANISLAV                                              *
      * DATE: 2026/02/13                                               *
      *                                                                *
      * FILES:                                                         *
      * INPUT:  MASTDD  (CUST.MASTER.VSAM) - VSAM KSDS MASTER FILE   *  
      * OUTPUT: OUTDD   (CUST.REPORT.PS)   - PS FILTERED REPORT FILE *  
      ******************************************************************
       IDENTIFICATION DIVISION.                                         
       PROGRAM-ID. COP2LB32.                                            
       ENVIRONMENT DIVISION.                                            
       INPUT-OUTPUT SECTION.                                            
       FILE-CONTROL.                                                    
                                                                        
           SELECT CUST-MASTER-FILE ASSIGN TO MASTDD                     
              ORGANIZATION IS INDEXED                                   
              ACCESS MODE IS SEQUENTIAL                                 
              RECORD KEY IS CUST-ID OF CUST-MASTER-REC                  
              FILE STATUS IS CUST-MASTER-STATUS.                        
                                                                        
           SELECT CUST-OUT-FILE ASSIGN TO OUTDD                         
              ORGANIZATION IS SEQUENTIAL                                
              FILE STATUS IS CUST-OUT-STATUS.                           
                                                                        
       DATA DIVISION.                                                   
       FILE SECTION.                                                    
                                                                        
       FD CUST-MASTER-FILE.                                             
       01 CUST-MASTER-REC.                                              
           COPY TASK32.                                                 
                                                                        
       FD CUST-OUT-FILE RECORDING MODE IS F.                            
       01 CUST-OUT-REC.                                                 
           COPY TASK32.                                                 
                                                                        
       WORKING-STORAGE SECTION.                                         
                                                                        
      * FILE STATUS VARIABLES                                           
       01 WS-FILE-STATUSES.                                             
          05 CUST-MASTER-STATUS PIC X(2).                               
          05 CUST-OUT-STATUS PIC X(2).                                  
                                                                        
      * CONTROL FLAGS                                                   
       01 WS-FLAGS.                                                     
          05 WS-EOF PIC X(1) VALUE 'N'.                                 
             88 EOF VALUE 'Y'.                                          
                                                                        
      * SYSIN FILTER PARAMETER                                          
       01 WS-REGION-FILTER PIC X(2).                                    
                                                                        
      * REPORT STATISTICS                                               
       01 WS-COUNT PIC 9(5) VALUE ZEROS.                                
       01 WS-COUNT-DISP PIC Z(4)9.                                      
       01 WS-TOTAL-BAL PIC 9(9)V99 VALUE ZEROS.                         
       01 WS-TOTAL-LIMIT PIC 9(9)V99 VALUE ZEROS.                       
       01 WS-TOTAL-BAL-DISP PIC Z(8)9.99.                               
       01 WS-TOTAL-LIMIT-DISP PIC Z(8)9.99.                             
                                                                        
       PROCEDURE DIVISION.                                              
       MAIN-LOGIC.                                                      
           OPEN INPUT CUST-MASTER-FILE.                                 
           IF CUST-MASTER-STATUS NOT = '00'                             
              DISPLAY 'ERROR OPENING CUST-MASTER FILE: '                
                       CUST-MASTER-STATUS                               
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           OPEN OUTPUT CUST-OUT-FILE.                                   
           IF CUST-OUT-STATUS NOT = '00'                                
              DISPLAY 'ERROR OPENING CUST-OUT FILE: ' CUST-OUT-STATUS   
              STOP RUN                                                  
           END-IF.                                                      
                                                                        
           ACCEPT WS-REGION-FILTER.                                     
                                                                        
           PERFORM UNTIL EOF                                            
              READ CUST-MASTER-FILE                                     
                AT END                                                  
                   SET EOF TO TRUE                                      
                NOT AT END                                              
                   IF CUST-MASTER-STATUS = '00'                         
                      IF CUST-STATUS OF CUST-MASTER-REC = 'A' AND       
                       CUST-REGION OF CUST-MASTER-REC = WS-REGION-FILTER
                         MOVE CUST-MASTER-REC TO CUST-OUT-REC           
                         WRITE CUST-OUT-REC                             
                         IF CUST-OUT-STATUS NOT = '00'                  
                            DISPLAY 'ERROR WRITING CUST-OUT FILE: '     
                                    CUST-OUT-STATUS                     
                            DISPLAY 'CUST-ID: ' CUST-ID OF              
                                CUST-MASTER-REC                         
                            STOP RUN                                    
                         END-IF                                         
                         ADD 1 TO WS-COUNT                              
                         ADD CUST-CURRENT-BAL OF CUST-MASTER-REC        
                             TO WS-TOTAL-BAL                            
                         ADD CUST-CREDIT-LIMIT OF CUST-MASTER-REC       
                             TO WS-TOTAL-LIMIT                          
                      END-IF                                            
                   ELSE                                                 
                      DISPLAY 'ERROR READING CUST-MASTER FILE: '        
                               CUST-MASTER-STATUS                       
                      STOP RUN                                          
                   END-IF                                               
              END-READ                                                  
           END-PERFORM.                                                 
                                                                        
           CLOSE CUST-MASTER-FILE.                                      
           IF CUST-MASTER-STATUS NOT = '00'                             
              DISPLAY 'WARNING: ERROR CLOSING CUST-MASTER FILE: '       
                       CUST-MASTER-STATUS                               
           END-IF.                                                      
                                                                        
           CLOSE CUST-OUT-FILE.                                         
           IF CUST-OUT-STATUS NOT = '00'                                
              DISPLAY 'WARNING: ERROR CLOSING CUST-OUT FILE: '          
                       CUST-OUT-STATUS                                  
           END-IF.                                                      
                                                                        
           MOVE WS-COUNT TO WS-COUNT-DISP.                              
           MOVE WS-TOTAL-BAL   TO WS-TOTAL-BAL-DISP.                    
           MOVE WS-TOTAL-LIMIT TO WS-TOTAL-LIMIT-DISP.                  
                                                                        
           DISPLAY 'TOTAL ACTIVE IN REGION ' WS-REGION-FILTER           
                   ': ' FUNCTION TRIM(WS-COUNT-DISP).                   
           DISPLAY 'TOTAL BALANCE: ' FUNCTION TRIM(WS-TOTAL-BAL-DISP).  
           DISPLAY 'TOTAL CREDIT LIMIT: '                               
               FUNCTION TRIM(WS-TOTAL-LIMIT-DISP).                      
                                                                        
           STOP RUN.                                                    
