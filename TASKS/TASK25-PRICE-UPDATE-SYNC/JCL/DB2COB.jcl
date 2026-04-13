//CBLDBDG  JOB (123),'DB2COB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*=====================================================================
//* STEP 1: DELETE OLD OUTPUT DATASETS IF IT EXISTS                     
//*=====================================================================
//DELREP   EXEC PGM=IEFBR14                                             
//DELDD1   DD  DSN=Z73460.TASK25.PRICE.UPDATE,                          
//             SPACE=(TRK,(1,0),RLSE),                                  
//             DISP=(MOD,DELETE,DELETE)                                 
//DELDD2   DD  DSN=Z73460.TASK25.UPDATE.LOG,                            
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
000010001100                                                            
000020002100                                                            
000030003100                                                            
000040004100                                                            
000050005100                                                            
000060006100                                                            
000070007100                                                            
000080008100                                                            
000090009100                                                            
000100010100                                                            
000110001200                                                            
000120001300                                                            
000130001400                                                            
000140001500                                                            
000150001600                                                            
000160001700                                                            
000170001800                                                            
000180001900                                                            
000190002000                                                            
000200002100                                                            
000210002200                                                            
000220002300                                                            
000230002400                                                            
000240002500                                                            
000250002600                                                            
000260002700                                                            
000270002800                                                            
000280002900                                                            
000290003000                                                            
000300003100                                                            
000310003200                                                            
000320003300                                                            
000330003400                                                            
000340003500                                                            
000350003600                                                            
000360003700                                                            
000370003800                                                            
000380003900                                                            
000390004000                                                            
000400004100                                                            
000410004200                                                            
000420004300                                                            
000430004400                                                            
000440004500                                                            
000450004600                                                            
000460004700                                                            
000470004800                                                            
000480004900                                                            
000490005000                                                            
000500005100                                                            
000510005200                                                            
000520001000                                                            
//SYSUT2   DD DSN=Z73460.TASK25.PRICE.UPDATE,                           
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* STEP 3: COBOL COMPILATION WITH DB2 PRECOMPILE                       
//*=====================================================================
//COMPIL   EXEC DB2CBL,MBR=DB2VSM25                                     
//COBOL.SYSIN  DD DSN=Z73460.COB.PRAC(DB2VSM25),DISP=SHR                
//COBOL.SYSLIB DD DSN=Z73460.DCLGEN,DISP=SHR                            
//*=====================================================================
//* STEP 4: PROGRAM EXECUTION UNDER DB2 CONTROL                         
//*=====================================================================
//RUNPROG  EXEC PGM=IKJEFT01,COND=(4,LT)                                
//STEPLIB  DD DSN=DSND10.SDSNLOAD,DISP=SHR                              
//         DD DSN=Z73460.LOAD,DISP=SHR                                  
//VSAMDD   DD DSN=Z73460.TASK25.PRODUCT.MASTER.VSAM,DISP=SHR            
//INDD     DD DSN=Z73460.TASK25.PRICE.UPDATE,DISP=SHR                   
//OUTDD    DD DSN=Z73460.TASK25.UPDATE.LOG,                             
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                   
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80)                          
//*=====================================================================
//* STEP 5: DB2 EXECUTION CONTROL - RUN PROGRAM UNDER DBDG SUBSYSTEM    
//*=====================================================================
//SYSTSPRT DD SYSOUT=*                                                  
//SYSPRINT DD SYSOUT=*                                                  
//SYSTSIN  DD *                                                         
   DSN SYSTEM(DBDG)                                                     
   RUN PROGRAM(DB2VSM25) PLAN(Z73460) -                                 
       LIB('Z73460.LOAD')                                               
   END                                                                  
/*                                                                      
