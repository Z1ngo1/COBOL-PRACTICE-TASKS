//JCLRUN   JOB (123),'JOB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*=====================================================================
//* DELETE OLD OUTPUT DATASETS IF EXISTS
//*=====================================================================
//DELREP   EXEC PGM=IEFBR14
//REPDD    DD DSN=YOUR.DATASET,
//            SPACE=(TRK,(1,0),RLSE),
//            DISP=(MOD,DELETE,DELETE)
//*=====================================================================
//* PROGRAM EXECUTION STEP
//* LOAD LIBRARY - WHERE EXECUTABLE PROGRAMS ARE STORED
//*=====================================================================
//RUN     EXEC PGM=YOUR.MEMBER.NAME
//STEPLIB   DD DSN=YOUR.LOADLIB,DISP=SHR
//*=====================================================================
//* INPUT/OUTPUT FILE DEFINITIONS
//*=====================================================================
//YOURDD    DD DSN=YOUR.DATASET,DISP=SHR
//YOURDD    DD DSN=YOUR.DATASET,DISP=SHR
//YOURDD    DD DSN=YOUR.DATASET,DISP=SHR
//YOURDD    DD DSN=YOUR.DATASET,
//             DISP=(NEW,CATLG,DELETE),
//             SPACE=(TRK,(2,2),RLSE),
//             DCB=(DSORG=PS,RECFM=VB,LRECL=84)
//*=====================================================================
//* CONSOLE OUTPUT
//*=====================================================================
//SYSOUT   DD SYSOUT=*,OUTLIM=15000
//*=====================================================================
//* FOR DUMP (OPTIONAL)
//*=====================================================================
//*CEEDUMP  DD DUMMY
//*SYSUDUMP DD DUMMY
//*=====================================================================
//**********************************************************************
//* DEPENDING ON THE SIZE AND FORMAT OF THE DATASET YOU WANT TO CREATE,
//* CHANGE THE DCB SETTINGS!!!
//* CHANGE ALL THE WORDS FROM 'YOUR' TO YOUR DATA, NAMELY:
//* DD NAMES AND DATA SETS NAMES
//**********************************************************************
