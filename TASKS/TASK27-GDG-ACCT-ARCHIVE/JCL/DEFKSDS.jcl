//DEFVSAM  JOB (123),'VSAM KSDS BUILD',CLASS=A,MSGCLASS=A
//             NOTIFY=&SYSUID
//*=====================================================================
//* STEP 1: DELETE OLD VSAM CLUSTER (IF EXISTS)
//*=====================================================================
//DELETE   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  DELETE Z73460.TASK27.ACCT.HISTORY.VSAM PURGE CLUSTER
  SET MAXCC=0
/*
//*=====================================================================
//* STEP 2: DEFINE NEW VSAM KSDS CLUSTER
//*=====================================================================
//DEFINE   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  DEFINE CLUSTER (NAME(Z73460.TASK27.ACCT.HISTORY.VSAM) -
           RECORDSIZE(18,18)               -
           TRACKS(15)                      -
           KEYS(6 0)                       -
           CISZ(4096)                      -
           FREESPACE(10,20)                -
           INDEXED)
/*
