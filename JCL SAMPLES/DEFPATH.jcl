//DEFPATH  JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*
//*==================================================================
//* STEP10: DEFINE PATH FOR ALTERNATE INDEX
//*==================================================================
//STEP10   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE PATH (                          -
     NAME(YOUR.CLUSTER.NAME.PATH)        -
     PATHENTRY(YOUR.CLUSTER.NAME.AIX)    -
     )
/*
//**********************************************************************
//* PATH CONNECTS AN ALTERNATE INDEX (AIX) TO THE BASE KSDS CLUSTER.
//* WITHOUT A PATH, THE AIX CANNOT BE USED TO ACCESS RECORDS.
//*
//*   NAME      - NAME OF THE PATH ITSELF (ANY VALID DATASET NAME)
//*   PATHENTRY - MUST POINT TO AN EXISTING AIX (ALTERNATE INDEX)
//*
//* BEFORE RUNNING THIS JCL, MAKE SURE:
//*   1. BASE KSDS CLUSTER ALREADY EXISTS
//*   2. ALTERNATE INDEX (AIX) IS ALREADY DEFINED (USE DEFAIX TEMPLATE)
//*   3. AFTER DEFINING PATH - RUN BLDINDEX TO POPULATE THE AIX
//*
//* CHANGE ALL WORDS 'YOUR.CLUSTER.NAME' TO YOUR ACTUAL DATASET NAME.
//**********************************************************************
