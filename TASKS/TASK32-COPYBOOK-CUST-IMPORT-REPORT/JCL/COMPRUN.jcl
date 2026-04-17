//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,             
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID                            
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB                                  
//*=====================================================================
//* DELETE IF EXISTS                                                    
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14                                             
//REPDD1   DD DSN=Z73460.TASK32.CUST.IN.PS,                             
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//REPDD2   DD DSN=Z73460.TASK32.CUST.OUT.PS,                            
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//*=====================================================================
//* INSERT DATA INTO INPUT FILE                                         
//*=====================================================================
//STEP010  EXEC PGM=IEBGENER                                            
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD *                                                         
  GENERATE MAXFLDS=1                                                    
  RECORD FIELD=(65,1,,1)                                                
//SYSUT1   DD *                                                         
000001IVAN PETROV                   RUA00050000000010000020260101       
000002MARIA SIDOROVA                RUA00030000000005000020260115       
000003JOHN SMITH                    USA00080000000020000020260110       
000004ANNA VOLKOVA                  RUI00020000000000000020260201       
000005ALEX LEE                      EUA00060000000015000020260120       
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK32.CUST.IN.PS,                             
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(1,1),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=65)                          
//*=====================================================================
//* COMPILE AND RUN PROGRAM                                             
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=COP1LB32                                
//RUN.INDD DD DSN=Z73460.TASK32.CUST.IN.PS,DISP=SHR                     
//RUN.MASTDD DD DSN=Z73460.TASK32.CUST.MSTER.VSAM,DISP=SHR              
//*=====================================================================
//* COMPILE AND RUN SECOND PROGRAM                                      
//*=====================================================================
//STEP020  EXEC MYCOMPGO,MEMBER=COP2LB32                                
//RUN.SYSIN DD *                                                        
RU                                                                      
/*                                                                      
//RUN.MASTDD DD DSN=Z73460.TASK32.CUST.MSTER.VSAM,DISP=SHR              
//RUN.OUTDD DD DSN=Z73460.TASK32.CUST.OUT.PS,                           
//          DISP=(NEW,CATLG,DELETE),                                    
//          SPACE=(TRK,(1,1),RLSE),                                     
//          DCB=(DSORG=PS,RECFM=FB,LRECL=65)                            
