//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB
//*=====================================================================
//* DELETE IF EXISTS
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14
//REPDD1   DD DSN=Z73460.TASK5.REPORT,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//REPDD2   DD DSN=Z73460.TASK5.TRANS.FILE,
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
10001D0050000                                                           
10002W0060000                                                           
10004D0010000                                                           
10002W0010000                                                           
10003D0030000                                                           
10003W0020000                                                           
10003W0000100                                                           
10001D0000000                                                           
10002W0000000                                                                                                              
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK5.TRANS.FILE,                          
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* COMPILE AND RUN PROGRAM    
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=VSAMJOB5
//RUN.INDD DD DSN=Z73460.TASK5.TRANS.FILE,DISP=SHR
//RUN.EMPDD DD DSN=Z73460.TASK5.ACCT.MASTER.VSAM,DISP=SHR
//RUN.REPDD DD DSN=Z73460.TASK5.REPORT,
//             DISP=(NEW,CATLG,DELETE),
//             SPACE=(TRK,(2,2),RLSE),
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80)
