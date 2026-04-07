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
//* PATH connects an Alternate Index (AIX) to the base KSDS cluster.
//* Without a PATH, the AIX cannot be used to access records.
//*
//*   NAME      - name of the PATH itself (any valid dataset name)
//*   PATHENTRY - must point to an existing AIX (Alternate Index)
//*
//* Before running this JCL, make sure:
//*   1. Base KSDS cluster already exists
//*   2. Alternate Index (AIX) is already defined (use DEFAIX template)
//*   3. After defining PATH - run BLDINDEX to populate the AIX
//*
//* Change all words 'YOUR.CLUSTER.NAME' to your actual dataset name.
//**********************************************************************
