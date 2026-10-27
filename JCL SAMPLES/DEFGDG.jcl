//DEFGDG   JOB (123),'MYJOB',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),
//            NOTIFY=&SYSUID
//**************************************************************
//* JCL TO CREATE GDG
//**************************************************************
//STEP1    EXEC PGM=IDCAMS
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  DEFINE GDG(NAME(YOUR.GDG.NAME) -
         LIMIT(5) -
         NOEMPTY -
         SCRATCH)
/*
//**********************************************************************
//* GDG BASE IS A CATALOG ENTRY ONLY - NO PHYSICAL DATASET IS CREATED.
//* EACH GENERATION (GDS) IS ALLOCATED SEPARATELY AS G0001V00, ETC.
//*
//*   NAME    - FULLY QUALIFIED GDG BASE NAME IN THE CATALOG
//*   LIMIT   - MAX NUMBER OF GENERATIONS KEPT (1-255)
//*             OLDEST IS REMOVED WHEN NEW ONE EXCEEDS THE LIMIT
//*   NOEMPTY - ONLY THE OLDEST GENERATION IS REMOVED WHEN LIMIT HIT
//*             USE EMPTY TO REMOVE ALL GENERATIONS AT ONCE
//*   SCRATCH - PHYSICALLY DELETES REMOVED GENERATION FROM THE VOLUME
//*             USE NOSCRATCH TO ONLY UNCATALOG IT (KEEP ON DISK)
//*
//* CHANGE ALL WORDS 'YOUR' TO YOUR ACTUAL GDG BASE NAME.
//**********************************************************************
