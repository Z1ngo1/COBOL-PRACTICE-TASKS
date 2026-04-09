//JOB18    JOB (123),'ALL STEPS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//            NOTIFY=&SYSUID
//*=====================================================================
//* IF EXISTS DELETE VSAM CLUSTER AND DEFINE NEW ONE
//*=====================================================================
//STEP005  EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DELETE Z73460.TASK18.LIBRARY.MASTER.VSAM -
      PURGE
  SET MAXCC=0

  DEFINE CLUSTER (NAME(Z73460.TASK18.LIBRARY.MASTER.VSAM) -
      RECORDSIZE(64,64)               -
      TRACKS(1 1)                     -
      KEYS(10 0)                      -
      CISZ(4096)                      -
      FREESPACE(10,20)                -
      INDEXED)                        -
  DATA (NAME(Z73460.TASK18.LIBRARY.MASTER.VSAM.DATA)) -
  INDEX (NAME(Z73460.TASK18.LIBRARY.MASTER.VSAM.INDEX))
/*
//*
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN LOAD DATA TO LIBRARY MASTER
//*=====================================================================
//STEP010  EXEC PGM=IDCAMS,COND=(04,LT)
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//INDD     DD *
0001112222KING STEPHEN        IT                            1986
0001234567ASIMOV ISAAC        FOUNDATION                    1951
0002345678CHRISTIE AGATHA     MURDER ON ORIENT              1934
0003334444TOLKIEN J.R.R.      THE HOBBIT                    1937
0004445555ROWLING J.K.        HARRY POTTER 1                1997
0005556666KING STEPHEN        THE SHINING                   1977
0006667777ASIMOV ISAAC        I ROBOT                       1950
0007778888ROWLING J.K.        HARRY POTTER 2                1998
0008889999TOLKIEN J.R.R.      LORD OF RINGS 1               1954
0009990000KING STEPHEN        MISERY                        1987
0010101010ROWLING J.K.        HARRY POTTER 3                1999
0011111111ASIMOV ISAAC        CAVES OF STEEL                1954
0013131313CHRISTIE AGATHA     TEN LITTLE INDIANS            1939
0014141414TOLKIEN J.R.R.      LORD OF RINGS 2               1954
/*
//SYSIN    DD *
  REPRO INFILE(INDD) -
        OUTDATASET(Z73460.TASK18.LIBRARY.MASTER.VSAM)
/*
//*
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN DEFINE ALTERNATE INDEX
//*=====================================================================
//STEP015  EXEC PGM=IDCAMS,COND=(04,LT)
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE AIX                        -
  (NAME(Z73460.TASK18.LIBRARY.MASTER.VSAM.AIX) -
  RELATE (Z73460.TASK18.LIBRARY.MASTER.VSAM) -
     CISZ(4096)                            -
     KEYS(20 10)                            -
     NONUNIQUEKEY                          -
     UPGRADE                               -
     RECORDSIZE(64,64)                     -
     TRACKS(2,2)                            -
     FREESPACE(10,20))
/*
//*
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN DEFINE PATH FOR AIX
//*=====================================================================
//STEP020  EXEC PGM=IDCAMS,COND=(04,LT)
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  DEFINE PATH ( -
     NAME (Z73460.TASK18.LIBRARY.MASTER.VSAM.PATH) -
     PATHENTRY(Z73460.TASK18.LIBRARY.MASTER.VSAM.AIX))
/*
//*
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN BUILD ALTERNATE INDEX
//*=====================================================================
//STEP025  EXEC PGM=IDCAMS,COND=(04,LT)
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSIN    DD *
  BLDINDEX -
   INDATASET(Z73460.TASK18.LIBRARY.MASTER.VSAM) -
   OUTDATASET(Z73460.TASK18.LIBRARY.MASTER.VSAM.AIX)
/*
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 DELETE SEARCH REQUEST FILE IF EXISTS
//*=====================================================================
//STEP030  EXEC PGM=IEFBR14,COND=(04,LT)
//REPDD    DD DSN=Z73460.TASK18.SEARCH.REQ,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 CREATE SEARCH REQUEST FILE AND LOADDATA
//*=====================================================================
//STEP035  EXEC PGM=IEBGENER,COND=(04,LT)
//SYSPRINT DD SYSOUT=*
//SYSOUT   DD SYSOUT=*
//SYSUT1   DD *
KING STEPHEN
ROWLING J.K.
PUSHKIN A.S.
ASIMOV ISAAC
TOLKIEN J.R.R.
HEMINGWAY ERNEST
CHRISTIE AGATHA

/*
//SYSUT2   DD DSN=Z73460.TASK18.SEARCH.REQ,
//           DISP=(NEW,CATLG,DELETE),
//           SPACE=(TRK,(2,2),RLSE),
//           DCB=(DSORG=PS,RECFM=FB,LRECL=80)
//SYSIN    DD DUMMY
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN DELETE RESULT FILE IF EXISTS
//*=====================================================================
//STEP040  EXEC PGM=IEFBR14,COND=(04,LT)
//REPDD    DD DSN=Z73460.TASK18.RESULT.RPT,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN COMPILE AND LINK COBOL PROGRAM
//*=====================================================================
//STEP045  EXEC IGYWCL,COND=(04,LT)
//COBOL.SYSIN  DD DSN=Z73460.COB.PRAC(VSAM18),DISP=SHR
//COBOL.SYSLIB DD DSN=Z73460.COPYLIB,DISP=SHR
//LKED.SYSLMOD DD DSN=Z73460.LOAD(VSAM18),DISP=SHR
//LKED.SYSLIB  DD DSN=Z73460.LOAD,DISP=SHR
//*=====================================================================
//* IF RC OF PREVIOUS STEP <= 4 THEN RUN SEARCH PROGRAM
//*=====================================================================
//STEP050  EXEC PGM=VSAM18,COND=(04,LT)
//STEPLIB  DD DSN=Z73460.LOAD,DISP=SHR
//VSAMDD DD DSN=Z73460.TASK18.LIBRARY.MASTER.VSAM,DISP=SHR
//VSAMDD1 DD DSN=Z73460.TASK18.LIBRARY.MASTER.VSAM.PATH,DISP=SHR
//SRCHDD DD DSN=Z73460.TASK18.SEARCH.REQ,DISP=SHR
//RSLTDD DD DSN=Z73460.TASK18.RESULT.RPT,
//            DISP=(NEW,CATLG,DELETE),
//            SPACE=(TRK,(2,2),RLSE),
//            DCB=(RECFM=VB,LRECL=84)
//SYSOUT   DD SYSOUT=*
