//DEFESDS  JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*
//************************************************************
//* STEP 1: DEFINE VSAM ESDS CLUSTER
//************************************************************
//STEP10   EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE CLUSTER (NAME(YOUR.CLUSTER.NAME) -
           RECORDSIZE(80,80)               -
           TRACKS(15)                      -
           CISZ(4096)                      -
           FREESPACE(10,20)                -
           NONINDEXED)
/*
//**********************************************************************
//* ESDS (ENTRY SEQUENCED DATASET) - RECORDS ARE STORED AND ACCESSED
//* IN THE ORDER THEY WERE WRITTEN. NO KEY FIELD, NO REUSE BY KEY.
//* TYPICALLY USED FOR TRANSACTION LOGS, AUDIT TRAILS, SEQUENTIAL OUTPUT.
//*
//*   NAME        - FULLY QUALIFIED NAME OF THE ESDS CLUSTER
//*   RECORDSIZE  - (AVERAGE MAXIMUM) RECORD LENGTH IN BYTES
//*   TRACKS      - PRIMARY SPACE ALLOCATION
//*   CISZ        - CONTROL INTERVAL SIZE (512-32768)
//*   FREESPACE   - (CI CA) FREE SPACE PERCENTAGES
//*   NONINDEXED  - DEFINES DATASET AS ESDS (NO INDEX COMPONENT)
//*                 USE INDEXED FOR KSDS, NUMBERED FOR RRDS
//*
//* CHANGE ALL WORDS 'YOUR' TO YOUR ACTUAL NAME.
//**********************************************************************
