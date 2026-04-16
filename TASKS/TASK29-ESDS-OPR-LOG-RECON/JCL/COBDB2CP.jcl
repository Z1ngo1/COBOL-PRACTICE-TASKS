//CBLDBDG  JOB (123),'DB2COB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*=====================================================================
//* STEP 1: DELETE DATASETS IF IT EXISTS                                
//*=====================================================================
//STEPDEL  EXEC PGM=IEFBR14                                             
//REPDD1   DD DSN=Z73460.TASK29.RECON.LOG,                              
//            SPACE=(TRK,(1,0),RLSE),                                   
//            DISP=(MOD,DELETE,DELETE)                                  
//*=====================================================================
//* STEP 2: INSERT DATA TO KSDS                                         
//*=====================================================================
//STEPINS  EXEC PGM=IDCAMS                                              
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//INDD     DD *                                                         
000100IVAN PETROV              A00070000000                             
000200MARIA SIDOROVA           A00020000000                             
000300ALEXEY KOZLOV            A00080000000                             
000400CLOSED ACCOUNT           C00050000000                             
000500FOUND NO DB2             A00100000000                             
/*                                                                      
//OUTDD    DD DSN=Z73460.TASK29.ACCT.MSTER.KSDS,DISP=SHR                
//SYSIN    DD *                                                         
  REPRO INFILE(INDD) OUTFILE(OUTDD)                                     
/*                                                                      
//*=====================================================================
//* STEP 3: INSERT DATA TO ESDS                                         
//*=====================================================================
//STEPINS2 EXEC PGM=IDCAMS                                              
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//INDD     DD *                                                         
00010020260416D000100000OP0001                                          
00020020260416D000200000OP0002                                          
00030020260416C000050000OP0003                                          
00040020260416D000100000OP0004                                          
00050020260416D000100000OP0005                                          
00060020260416D000200000OP0006                                          
00070020260416X000100000OP0007                                          
00010020260416D000000000OP0008                                          
00010020260417C000500000OP0009                                          
/*                                                                      
//OUTDD    DD DSN=Z73460.TASK29.OPR.LOG.ESDS,DISP=SHR                   
//SYSIN    DD *                                                         
  REPRO INFILE(INDD) OUTFILE(OUTDD)                                     
/*                                                                      
//*=====================================================================
//* STEP 4: COBOL COMPILATION WITH DB2 PRECOMPILE                       
//*=====================================================================
//COMPIL   EXEC DB2CBL,MBR=ESDS29                                       
//COBOL.SYSIN  DD DSN=Z73460.COB.PRAC(ESDS29),DISP=SHR                  
//COBOL.SYSLIB DD DSN=Z73460.DCLGEN,DISP=SHR                            
//*=====================================================================
//* STEP 5: PROGRAM EXECUTION UNDER DB2 CONTROL                         
//*=====================================================================
//RUNPROG  EXEC PGM=IKJEFT01,COND=(4,LT)                                
//STEPLIB  DD DSN=DSND10.SDSNLOAD,DISP=SHR                              
//         DD DSN=Z73460.LOAD,DISP=SHR                                  
//OPR      DD DSN=Z73460.TASK29.OPR.LOG.ESDS,DISP=SHR                   
//ACCTDD   DD DSN=Z73460.TASK29.ACCT.MSTER.KSDS,DISP=SHR                
//RECN     DD DSN=Z73460.TASK29.RECON.LOG,                              
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80)                          
//*=====================================================================
//* STEP 6: DB2 EXECUTION CONTROL - RUN PROGRAM UNDER DBDG SUBSYSTEM    
//*=====================================================================
//SYSTSPRT DD SYSOUT=*                                                  
//SYSPRINT DD SYSOUT=*                                                  
//SYSTSIN  DD *                                                         
   DSN SYSTEM(DBDG)                                                     
   RUN PROGRAM(ESDS29) PLAN(Z73460) -                                   
       LIB('Z73460.LOAD')                                               
   END                                                                  
/*                                                                      
