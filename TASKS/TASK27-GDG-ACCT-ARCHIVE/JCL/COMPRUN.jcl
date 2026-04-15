//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,             
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID                            
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB                                  
//*=====================================================================
//* DELETE IF EXISTS                                                    
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14                                             
//REPDD1   DD DSN=Z73460.TASK27.ACCT.DATA,                              
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//REPDD2   DD DSN=Z73460.TASK27.PROCESS.REPORT,                         
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//*=====================================================================
//* INSERT DATA TO INPUT DATA                                           
//*=====================================================================
//STEP010  EXEC PGM=IEBGENER                                            
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD *                                                         
  GENERATE MAXFLDS=1                                                    
  RECORD FIELD=(58,1,,1)                                                
//SYSUT1   DD *                                                         
A00001JOHN SMITH               20260101010000000                        
A00002JANE DOE                 20250101005000000                        
A00003BOB MARLEY               20260115020000000                        
A00004ALICE COOPER             20260101003000000                        
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK27.ACCT.DATA,                              
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=58)                          
//*=====================================================================
//* COMPILE AND RUN PROGRAM                                             
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=GDGJOB27                                
//RUN.INPSDD DD DSN=Z73460.TASK27.ACCT.DATA,DISP=SHR                    
//RUN.VSAMDD DD DSN=Z73460.TASK27.ACCT.HISTORY.VSAM,DISP=SHR            
//RUN.GDGDD1 DD DSN=Z73460.TASK27.ACCT.ACTIVE.GDG(+1),                  
//           DISP=(NEW,CATLG,DELETE),                                   
//           SPACE=(TRK,(1,1),RLSE),                                    
//           DCB=(DSORG=PS,RECFM=FB,LRECL=48)                           
//RUN.GDGDD2 DD DSN=Z73460.TASK27.ARCHIVE.OLD.GDG(+1),                  
//           DISP=(NEW,CATLG,DELETE),                                   
//           SPACE=(TRK,(1,1),RLSE),                                    
//           DCB=(DSORG=PS,RECFM=FB,LRECL=48)                           
//RUN.GDGDD3 DD DSN=Z73460.TASK27.UNMATCH.GDG(+1),                      
//           DISP=(NEW,CATLG,DELETE),                                   
//           SPACE=(TRK,(1,1),RLSE),                                    
//           DCB=(DSORG=PS,RECFM=FB,LRECL=48)                           
//RUN.REPPSDD DD DSN=Z73460.TASK27.PROCESS.REPORT,                      
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=VB,LRECL=54)                          
