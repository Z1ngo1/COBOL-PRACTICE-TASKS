//CBLDBDG  JOB (123),'DB2COB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*=====================================================================
//* STEP 1: DELETE OLD OUTPUT DATASETS IF IT EXISTS                     
//*=====================================================================
//DELREP   EXEC PGM=IEFBR14                                             
//DELDD1   DD  DSN=Z73460.TASK26.PAYMENTS,                              
//             SPACE=(TRK,(1,0),RLSE),                                  
//             DISP=(MOD,DELETE,DELETE)                                 
//DELDD2   DD  DSN=Z73460.TASK26.PROCESS.LOG,                           
//             SPACE=(TRK,(1,0),RLSE),                                  
//             DISP=(MOD,DELETE,DELETE)                                 
//*=====================================================================
//* STEP 2: INSERT DATA TO INPUT DATA                                   
//*=====================================================================
//STEPINS  EXEC PGM=IEBGENER                                            
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD DUMMY                                                     
//SYSUT1   DD *                                                         
100001001000100000C                                                     
100002002000200000T                                                     
100003009990050000A                                                     
100004003000300000X                                                     
100005003000800000A                                                     
      003000000000C                                                     
100006003000000000C                                                     
//SYSUT2   DD DSN=Z73460.TASK26.PAYMENTS,                               
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* STEP 3: COBOL COMPILATION WITH DB2 PRECOMPILE                       
//*=====================================================================
//COMPIL   EXEC DB2CBL,MBR=DB2VSM26                                     
//COBOL.SYSIN  DD DSN=Z73460.COB.PRAC(DB2VSM26),DISP=SHR                
//COBOL.SYSLIB DD DSN=Z73460.DCLGEN,DISP=SHR                            
//*=====================================================================
//* STEP 4: PROGRAM EXECUTION UNDER DB2 CONTROL                         
//*=====================================================================
//RUNPROG  EXEC PGM=IKJEFT01,COND=(4,LT)                                
//STEPLIB  DD DSN=DSND10.SDSNLOAD,DISP=SHR                              
//         DD DSN=Z73460.LOAD,DISP=SHR                                  
//VSAMDD   DD DSN=Z73460.TASK26.CUSTOMER.VSAM,DISP=SHR                  
//INPDD    DD DSN=Z73460.TASK26.PAYMENTS,DISP=SHR                       
//LOGDD    DD DSN=Z73460.TASK26.PROCESS.LOG,                            
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=VB,LRECL=84)                          
//*=====================================================================
//* STEP 5: DB2 EXECUTION CONTROL - RUN PROGRAM UNDER DBDG SUBSYSTEM    
//*=====================================================================
//SYSTSPRT DD SYSOUT=*                                                  
//SYSPRINT DD SYSOUT=*                                                  
//SYSTSIN  DD *                                                         
   DSN SYSTEM(DBDG)                                                     
   RUN PROGRAM(DB2VSM26) PLAN(Z73460) -                                 
       LIB('Z73460.LOAD')                                               
   END                                                                  
/*                                                                      
