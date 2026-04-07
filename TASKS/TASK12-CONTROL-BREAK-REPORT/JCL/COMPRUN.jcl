//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB
//*=====================================================================
//* DELETE IF EXISTS
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14                                             
//REPDD1   DD DSN=Z73460.TASK12.SALES.DATA,                             
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//REPDD2   DD DSN=Z73460.TASK12.SALES.REPORT,                           
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
NORTHSHOP10010000                                                       
NORTHSHOP10005000                                                       
NORTHSHOP20020000                                                       
SOUTHSHOP10030000                                                       
SOUTHSHOP10010000                                                       
SOUTHSHOP20015000                                                       
SOUTHSHOP20010000                                                       
EAST SHOP10025000                                                       
EAST SHOP20035000                                                       
EAST SHOP20015000                                                       
WEST SHOP10020000                                                       
WEST SHOP20030000                                                       
/*                                                                      
//SYSUT2   DD DSN=Z73460.TASK12.SALES.DATA,                             
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* COMPILE AND RUN PROGRAM
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=JOBCBR12                                
//RUN.PSSDD DD DSN=Z73460.TASK12.SALES.DATA,DISP=SHR                    
//RUN.REPDD DD DSN=Z73460.TASK12.SALES.REPORT,                          
//             DISP=(NEW,CATLG,DELETE),                                 
//             SPACE=(TRK,(1,1),RLSE),                                  
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)             
