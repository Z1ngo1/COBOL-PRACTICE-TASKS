//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,             
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID                            
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB                                  
//*=====================================================================
//* DELETE IF EXISTS                                                    
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14                                             
//REPDD1   DD DSN=Z73460.TASK28.ACCT.LIST,                              
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//REPDD2   DD DSN=Z73460.TASK28.ACCT.REPORT,                            
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//*=====================================================================
//* INSERT DATA TO INPUT DATA                                           
//*=====================================================================
//STEP010  EXEC PGM=IEBGENER                                            
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD DUMMY                                                     
//SYSUT1   DD *                                                         
A00001                                                                  
A00002                                                                  
A00003                                                                  
A00004                                                                  
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK28.ACCT.LIST,                              
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80)                          
//*=====================================================================
//* COMPILE AND RUN PROGRAM                                             
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=ESDS28                                  
//RUN.ACCT DD DSN=Z73460.TASK28.ACCT.LIST,DISP=SHR                      
//RUN.TRNS DD DSN=Z73460.TASK28.TRANS.LOG.ESDS,DISP=SHR                 
//RUN.ACCTREP DD DSN=Z73460.TASK28.ACCT.REPORT,                         
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(1,1),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=VB,LRECL=64)                          
