//DEFKSDS  JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*
//*==================================================================
//* STEP 1: DEFINE VSAM KSDS CLUSTER
//*==================================================================
//STEP10   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE CLUSTER (NAME(YOUR.CLUSTER.NAME) -
           RECORDSIZE(80,80)               -
           TRACKS(2)                       -
           KEYS(5 0)                       -
           CISZ(4096)                      -
           FREESPACE(10,20)                -
           INDEXED)
/*
//**********************************************************************
//* DEPENDING ON THE SIZE AND FORMAT OF THE DATASET YOU WANT TO CREATE,
//* CHANGE THE FOLLOWING SETTINGS:
//*
//*   RECORDSIZE - SET (AVERAGE MAXIMUM) RECORD LENGTH IN BYTES
//*   TRACKS     - SET PRIMARY SPACE ALLOCATION
//*   KEYS       - SET (LENGTH OFFSET) OF THE KEY FIELD
//*   CISZ       - SET CONTROL INTERVAL SIZE (MUST BE 512-32768)
//*   FREESPACE  - SET (CI CA) FREE SPACE PERCENTAGES
//*
//* CHANGE ALL THE WORDS FROM 'YOUR' TO YOUR ACTUAL DATASET NAME.
//**********************************************************************
