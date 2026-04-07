//CBLDBDG  JOB (123),'DB2COB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*=====================================================================
//*STEP 1: DELETE OLD OUTPUT DATASETS IF IT EXISTS                      
//*=====================================================================
//DELREP   EXEC PGM=IEFBR14                                             
//DELDD    DD  DSN=YOUR.DATASET,                          
//             SPACE=(TRK,(1,0),RLSE),                                
//             DISP=(MOD,DELETE,DELETE)                                 
//*=====================================================================
//* STEP 2: COBOL COMPILATION WITH DB2 PRECOMPILE                       
//*=====================================================================
//COMPIL   EXEC DB2CBL,MBR=YOUR.MEMBER                                   
//COBOL.SYSIN  DD DSN=YOUR.COBOL.SOURCE(YOUR.MEMBER.NAME),DISP=SHR                
//COBOL.SYSLIB DD DSN=YOUR.DCLGEN,DISP=SHR                            
//*=====================================================================
//* STEP 3: PROGRAM EXECUTION UNDER DB2 CONTROL                         
//*=====================================================================
//RUNPROG  EXEC PGM=IKJEFT01,COND=(4,LT)                                
//STEPLIB  DD DSN=DSND10.SDSNLOAD,DISP=SHR                              
//         DD DSN=YOUR.LOAD.LIBRARY,DISP=SHR                                  
//YOURDD   DD DSN=YOUR.DATASET,                           
//            DISP=(NEW,CATLG,DELETE),                                  
//            SPACE=(TRK,(2,2),RLSE),                                        
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)              
//*=====================================================================
//* STEP 4: DB2 EXECUTION CONTROL - RUN PROGRAM UNDER DBDG SUBSYSTEM    
//*=====================================================================
//SYSTSPRT DD SYSOUT=*                                                  
//SYSPRINT DD SYSOUT=*                                                  
//SYSTSIN  DD *                                                         
  DSN SYSTEM(YOUR.DB2.SSID)                                                      
  RUN PROGRAM(YOUR.MEMBER.NAME) PLAN(YOUR.PLAN.NAME) -                                  
      LIB('YOUR.LOAD.LIBRARY')                                                
  END                                                                   
/*                    
//**********************************************************************
//* Depending on the size and format of the dataset you want to create,
//* change the DCB settings!!! 
//* Change all the words from 'YOUR' to your data, namely:
//* DD NAMES AND DATA SETS NAMES
//**********************************************************************
