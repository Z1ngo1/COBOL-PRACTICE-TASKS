//CBLDBDG  JOB (123),'DB2COB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*=====================================================================
//*STEP 1: DELETE OLD OUTPUT DATASETS IF IT EXISTS
//*=====================================================================
//DELREP   EXEC PGM=IEFBR14
//DELDD1   DD  DSN=Z73460.TASK24.RECON.REPORT,
//             SPACE=(TRK,(1,0),RLSE),
//             DISP=(MOD,DELETE,DELETE)
//DELDD2   DD  DSN=Z73460.TASK24.TRANS.LOG,
//             SPACE=(TRK,(1,0),RLSE),
//             DISP=(MOD,DELETE,DELETE)
//*=====================================================================
//* STEP 2: CREATE AND INSERT DATA INTO INPUT FILE
//*=====================================================================
//STEPCRT  EXEC PGM=IEBGENER
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD DUMMY
//SYSUT1   DD *
000100C000050000
000100D000020000
000200C000010000
000300D000050000
000500C000010000
000300X000010000
/*
//SYSUT2   DD DSN=Z73460.TASK24.TRANS.LOG,
//            DISP=(NEW,CATLG,DELETE),
//            SPACE=(TRK,(2,2),RLSE),
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)
//*=====================================================================
//* STEP 3: COBOL COMPILATION WITH DB2 PRECOMPILE
//*=====================================================================
//COMPIL   EXEC DB2CBL,MBR=DB2VSM24
//COBOL.SYSIN  DD DSN=Z73460.COB.PRAC(DB2VSM24),DISP=SHR
//COBOL.SYSLIB DD DSN=Z73460.DCLGEN,DISP=SHR
//*=====================================================================
//* STEP 4: PROGRAM EXECUTION UNDER DB2 CONTROL
//*=====================================================================
//RUNPROG  EXEC PGM=IKJEFT01,COND=(4,LT)
//STEPLIB  DD DSN=DSND10.SDSNLOAD,DISP=SHR
//         DD DSN=Z73460.LOAD,DISP=SHR
//VSAMDD   DD DSN=Z73460.TASK24.ACCT.BACKUP.VSAM,DISP=SHR
//TRNSDD   DD DSN=Z73460.TASK24.TRANS.LOG,DISP=SHR
//REPDD    DD DSN=Z73460.TASK24.RECON.REPORT,
//            DISP=(NEW,CATLG,DELETE),
//            SPACE=(TRK,(2,2),RLSE),
//            DCB=(DSORG=PS,RECFM=VB,LRECL=124)
//*=====================================================================
//* STEP 4: DB2 EXECUTION CONTROL - RUN PROGRAM UNDER DBDG SUBSYSTEM
//*=====================================================================
//SYSTSPRT DD SYSOUT=*
//SYSPRINT DD SYSOUT=*
//SYSTSIN  DD *
  DSN SYSTEM(DBDG)
  RUN PROGRAM(DB2VSM24) PLAN(Z73460) -
      LIB('Z73460.LOAD')
  END
/*
