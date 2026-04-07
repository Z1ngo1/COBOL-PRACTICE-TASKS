//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB
//*=====================================================================
//* DELETE IF EXISTS
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14                    
//REPDD1   DD DSN=Z73460.TASK11.APPROVED.FILE, 
//            SPACE=(TRK,(1,0),RLSE),   
//            DISP=(MOD,DELETE,DELETE)         
//REPDD2   DD DSN=Z73460.TASK11.DECLINED.FILE, 
//            SPACE=(TRK,(1,0),RLSE),        
//            DISP=(MOD,DELETE,DELETE)        
//REPDD3   DD DSN=Z73460.TASK11.TRANS.DAILY, 
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
0000111112222333344440010000                                            
0000222223333444455550050000                                            
0000333334444555566660025000                                            
0000444445555666677770100000                                            
0000555556666777788880075000                                            
0000699998888777766660015000                                            
0000766667777888899990030000                                            
0000888889999000011110020000                                            
0000912345678901234560005000                                            
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK11.TRANS.DAILY,                          
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* COMPILE AND RUN PROGRAM
//*=====================================================================
//STEP010  EXEC MYCOMPGO,MEMBER=VSMJOB11                   
//RUN.VSAMDD DD DSN=Z73460.TASK11.CARD.MASTER.VSAM,DISP=SHR
//RUN.TRNSDD DD DSN=Z73460.TASK11.TRANS.DAILY,DISP=SHR     
//RUN.APRVDD DD DSN=Z73460.TASK11.APPROVED.FILE,           
//             DISP=(NEW,CATLG,DELETE),                    
//             SPACE=(TRK,(2,2),RLSE),                     
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80)            
//RUN.DECLDD DD DSN=Z73460.TASK11.DECLINED.FILE,           
//             DISP=(NEW,CATLG,DELETE),                    
//             SPACE=(TRK,(2,2),RLSE),                     
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80)            
