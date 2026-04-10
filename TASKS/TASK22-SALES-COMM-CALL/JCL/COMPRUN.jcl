//COMPRUN  JOB (123),'COMP AND RUN JCL',CLASS=A,MSGCLASS=A,
//             MSGLEVEL=(1,1),NOTIFY=&SYSUID
//SETLIB   JCLLIB ORDER=Z73460.PROCLIB
//*=====================================================================
//* DELETE IF EXISTS
//*=====================================================================
//STEP005  EXEC PGM=IEFBR14
//REPDD1   DD DSN=Z73460.TASK22.COMM.PAYOUT,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//REPDD2   DD DSN=Z73460.TASK22.SALES.DATA,
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
00100NY15000000
00200CA05000000
00300TX00500000
00400FL00800000
00500NY00050000
00600CA00090000
00700TX01200000
/*
//SYSUT2   DD DSN=Z73460.TASK22.SALES.DATA,
//            DISP=(NEW,CATLG,DELETE),
//            SPACE=(TRK,(2,2),RLSE),
//            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)
//*=====================================================================
//* COMPILE AND RUN PROGRAM
//*=====================================================================
//STEP015  EXEC MYCOMPGO,MEMBER=JOBSUB22
//RUN.INDD DD DSN=Z73460.TASK22.SALES.DATA,DISP=SHR
//RUN.OUTDD DD DSN=Z73460.TASK22.COMM.PAYOUT,
//             DISP=(NEW,CATLG,DELETE),
//             SPACE=(TRK,(1,1),RLSE),
//             DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)
