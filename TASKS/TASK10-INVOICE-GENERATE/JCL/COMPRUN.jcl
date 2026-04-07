//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB
//*=====================================================================
//* DELETE IF EXISTS
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14
//REPDD1   DD DSN=Z73460.TASK10.INVOICE.FILE,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//REPDD2   DD DSN=Z73460.TASK10.ORDERS.DAILY,
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
1000100100010                                                           
1000200200005                                                           
1000300300001                                                           
1000400400025                                                           
1000500500050                                                           
1000699999001                                                           
1000700600002                                                           
1000800700001                                                           
1000900800010                                                           
1001088888003                                                           
1001100900015                                                           
1012001000020                                                           
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK10.ORDERS.DAILY,                          
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* COMPILE AND RUN PROGRAM
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=VSMJOB10
//RUN.VSAMDD DD DSN=Z73460.TASK10.PROD.MASTER.VSAM,DISP=SHR
//RUN.ORDD DD DSN=Z73460.TASK10.ORDERS.DAILY,DISP=SHR
//RUN.OUTDD DD DSN=Z73460.TASK10.INVOICE.FILE,
//             DISP=(NEW,CATLG,DELETE),
//             SPACE=(TRK,(2,2),RLSE),
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80)
