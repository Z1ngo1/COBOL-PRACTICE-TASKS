//BLDINDEX JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*                                                
//*==================================================================          
//* STEP10: BUILD ALTERNATE INDEX USING BLDINDEX COMMAND                                            
//*==================================================================          
//STEP10   EXEC PGM=IDCAMS                                              
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD *                                                         
  BLDINDEX                                          -                                                            
   INDATASET(YOUR.CLUSTER.NAME)                     -                       
   OUTDATASET(YOUR.CLUSTER.NAME.AIX)                    
/*                                                                      
//**********************************************************************
//* BLDINDEX reads the base KSDS cluster and populates the AIX
//* with alternate key values and pointers to base cluster records.
//* Must be run AFTER DEFAIX and DEFPATH, and AFTER data is loaded
//* into the base KSDS cluster.
//*
//*   INDATASET  - base KSDS cluster that contains the source data
//*   OUTDATASET - AIX to be populated (must already be defined)
//*
//* BLDINDEX must be re-run manually if UPGRADE was set to NOUPGRADE
//* in DEFAIX. If UPGRADE(YES) was used, AIX is updated automatically
//* on every write to the base cluster - no need to re-run BLDINDEX.
//*
//* Full order of steps to set up AIX:
//*   1. DEFKSDS  - define base KSDS cluster
//*   2. DEFAIX   - define Alternate Index
//*   3. DEFPATH  - define PATH to connect AIX to base cluster
//*   4. BLDINDEX - populate AIX with data (this JCL)
//*
//* Change all words 'YOUR.CLUSTER.NAME' to your actual dataset name.
//**********************************************************************
