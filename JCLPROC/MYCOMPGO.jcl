//MYCOMPGO PROC MEMBER=,
//             SRCLIB='Z73460.COB.PRAC',
//             COPYLIB='Z73460.COPYLIB',
//             LOADLIB='Z73460.LOAD'
//*=====================================================================
//* STEP 1: COMPILE AND LINK EDIT
//*=====================================================================
//COMP    EXEC IGYWCL
//COBOL.SYSIN  DD DSN=&SRCLIB(&MEMBER),DISP=SHR
//COBOL.SYSLIB DD DSN=&COPYLIB,DISP=SHR
//LKED.SYSLMOD DD DSN=&LOADLIB(&MEMBER),DISP=SHR
//LKED.SYSLIB  DD DSN=&LOADLIB,DISP=SHR
//*=====================================================================
//* STEP 2: EXECUTE PROGRAM
//*=====================================================================
//RUN     EXEC PGM=&MEMBER,COND=(4,LT,COMP.COBOL)
//STEPLIB   DD DSN=&LOADLIB,DISP=SHR
//SYSOUT    DD SYSOUT=*
//**********************************************************************
//* TO OVERRIDE THESE VALUES, SPECIFY THEM IN YOUR JCL WHEN CALLING
//*
//*   //STEP1   EXEC YOURPROCNAME,
//*   //             MEMBER=YOUR.MEMBER,
//*   //             SRCLIB='YOUR.COBOL.SRC',
//*   //             COPYLIB='YOUR.COPYBOOKS',
//*   //             LOADLIB='YOUR.LOADLIB'
//*
//* ADDITIONAL DD STATEMENTS CAN BE ADDED TO THE RUN STEP BY CODING
//* THEM AFTER THE EXEC STATEMENT IN YOUR CALLING JCL:
//*
//*   //STEP1   EXEC YOURPROCNAME,MEMBER=YOUR MEMBER
//*   //RUN.YOURDD DD DSN=YOUR.DATA.SET,DISP=SHR
//*   //RUN.YOURDD DD DSN=YOUR.DATA.SET,
//*   //             DISP=(NEW,CATLG,DELETE),
//*   //              SPACE=(TRK,(10,5),RLSE)
//**********************************************************************
