//DEFAIX   JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*
//*==================================================================
//* STEP10: DEFINE ALTERNATE INDEX (AIX) FOR KSDS CLUSTER
//*==================================================================
//STEP10   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE AIX                                        -
     (NAME(YOUR.CLUSTER.NAME.AIX)                   -
     RELATE(YOUR.CLUSTER.NAME)                      -
     CISZ(4096)                                     -
     KEYS(20 10)                                    -
     NONUNIQUEKEY                                   -
     UPGRADE                                        -
     RECORDSIZE(80,80)                              -
     TRACKS(2,1)                                    -
     FREESPACE(10,20))
/*
//**********************************************************************
//* AIX (ALTERNATE INDEX) ALLOWS ACCESS TO A KSDS CLUSTER BY A FIELD
//* OTHER THAN THE PRIMARY KEY (E.G. BY LAST NAME, DEPARTMENT, ETC.)
//*
//*   NAME     - NAME OF THE AIX DATASET ITSELF
//*   RELATE   - MUST POINT TO THE BASE KSDS CLUSTER
//*   CISZ     - CONTROL INTERVAL SIZE (MATCH BASE CLUSTER IF POSSIBLE)
//*   KEYS     - (LENGTH OFFSET) OF THE ALTERNATE KEY FIELD IN RECORD
//*   NONUNIQUEKEY - MULTIPLE RECORDS CAN SHARE THE SAME ALTERNATE KEY
//*                - USE UNIQUEKEY IF ALTERNATE KEY MUST BE UNIQUE
//*   UPGRADE - AIX IS AUTOMATICALLY UPDATED WHEN BASE CLUSTER CHANGES
//*         - USE NOUPGRADE IF MANUAL REBUILD VIA BLDINDEX IS PREFERRED
//*   RECORDSIZE - (AVERAGE MAXIMUM) MUST BE >= BASE CLUSTER RECORDSIZE
//*   TRACKS      - PRIMARY AND SECONDARY SPACE ALLOCATION
//*   FREESPACE   - (CI CA) FREE SPACE PERCENTAGES
//*
//* ORDER OF STEPS TO USE AIX:
//*   1. DEFKSDS  - DEFINE BASE KSDS CLUSTER
//*   2. DEFAIX   - DEFINE ALTERNATE INDEX (THIS JCL)
//*   3. DEFPATH  - DEFINE PATH TO CONNECT AIX TO BASE CLUSTER
//*   4. BLDINDEX - POPULATE THE AIX WITH DATA FROM BASE CLUSTER
//*
//* CHANGE ALL WORDS 'YOUR.CLUSTER.NAME' TO YOUR ACTUAL DATASET NAME.
//**********************************************************************
