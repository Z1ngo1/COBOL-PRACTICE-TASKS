//JOB18   JOB (123),'COB COMPILE',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//             NOTIFY=&SYSUID
//*==================================================================
//* COMPILE AND LINK EDIT STEP - IGYWCL PROCEDURE COMBINES BOTH
//* IGYWCL = IBM COBOL COMPILER WITH INTEGRATED LINK EDITOR
//* PERFORMS: PRECOMPILE (IF NEEDED) -> COMPILE -> LINK -> BIND
//*==================================================================
//COMP1   EXEC IGYWCL
//COBOL.SYSIN  DD DSN=YOUR.DATASET(YOUR MEMBER),DISP=SHR
//LKED.SYSLMOD DD DSN=YOUR.LOADLIB(YOUR MEMBER),DISP=SHR
//LKED.SYSLIB  DD DSN=YOUR.LOADLIB,DISP=SHR
//*==================================================================
//* SUCCESS NOTIFICATION IF RC <= 4
//* IF COMPILATION/LINK RC (RETURN CODE) <= 4, PRINT SUCCESS MESSAGE
//* RC=0 = SUCCESSFUL, RC=4 = WARNINGS ONLY
//*==================================================================
// IF RC <= 4 THEN
//SUCCESS  EXEC PGM=IEBGENER
//SYSPRINT DD SYSOUT=*
//SYSIN    DD DUMMY
//SYSUT1   DD *
COMPILATION SUCCESSFUL
/*
//SYSUT2   DD SYSOUT=*
// ENDIF
//*==================================================================
//**********************************************************************
//* In COBOL.SYSIN, enter the name of the library 
//* where your COBOL code is located, and in the parentheses, 
//* enter the MEMBER name
//* In LKED.SYSLMOD, enter the name of your LOAD library, 
//* and in the parentheses, enter the member name
//* In LKED.SYSLIB again enter the name of your LOAD library
//**********************************************************************
