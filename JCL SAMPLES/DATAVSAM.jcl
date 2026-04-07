//LOADDATA JOB (123),'DATA TO KSDS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1), 
//             NOTIFY=&SYSUID                                          
//*----------------------------------------------------
//* STEP1: DELETE IF EXIST AND DEFINE NEW CLUSTER
//*----------------------------------------------------
//STEP1    EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DELETE YOUR.VSAM.CLUSTER PURGE
      SET MAXCC = 0

  DEFINE CLUSTER (NAME(YOUR.VSAM.CLUSTER) -
      RECORDSIZE(32 32)         -
      TRACKS(1 1)               -
      KEYS(10 0)                -
      CISZ(4096)                -
      FREESPACE(10 20)          -
      INDEXED)                  -
  DATA (NAME(YOUR.VSAM.DATA)) -
  INDEX (NAME(YOUR.VSAM.INDEX))
/*
//*----------------------------------------------------
//* STEP2: CREATE TEMP PS FILE WITH CORRECT LRECL
//*----------------------------------------------------
//STEP2    EXEC PGM=SORT,COND=(0,NE)
//SYSOUT   DD SYSOUT=*
//SORTIN   DD *
YOUR DATA                                       
/*                                                                     
//SORTOUT  DD DSN=&&TEMP,
//            DISP=(NEW,PASS,DELETE),
//            SPACE=(TRK,(1,1),RLSE),
//            DCB=(DSORG=PS,RECFM=FB,LRECL=32)
//SYSIN    DD *
  SORT FIELDS=COPY
  OUTREC BUILD=(1,32)
/*
//*----------------------------------------------------
//* STEP3: LOAD INTO VSAM KSDS
//*----------------------------------------------------
//STEP3    EXEC PGM=IDCAMS,COND=(0,NE)
//SYSPRINT DD SYSOUT=*
//INDD     DD DSN=&&TEMP,DISP=(OLD,DELETE)
//OUTDD    DD DSN=YOUR.VSAM.CLUSTER,DISP=SHR                            
//SYSIN    DD *                                                        
  REPRO INFILE(INDD) -                                                 
        OUTFILE(OUTDD)                                                 
/*                                                                     
//**********************************************************************
//* USE THIS EXAMPLE IF YOU WANT TO LOAD EXACT LENGHT OF RECORD
//* Depending on the size and format of the dataset you want to create,
//* change the DCB settings!!! 
//* Change all the words from 'YOUR' to your data 
//* Change the data in SYSUT1 and RECORD FIELD in SYSIN
//**********************************************************************
