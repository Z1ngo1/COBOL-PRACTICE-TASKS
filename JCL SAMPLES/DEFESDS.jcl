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
//* ESDS (Entry Sequenced Dataset) - records are stored and accessed
//* in the order they were written. No key field, no reuse by key.
//* Typically used for transaction logs, audit trails, sequential output.
//*
//*   NAME        - fully qualified name of the ESDS cluster
//*   RECORDSIZE  - (average maximum) record length in bytes
//*   TRACKS      - primary space allocation
//*   CISZ        - Control Interval size (512-32768)
//*   FREESPACE   - (CI CA) free space percentages
//*   NONINDEXED  - defines dataset as ESDS (no index component)
//*                 use INDEXED for KSDS, NUMBERED for RRDS
//*
//* Change all words 'YOUR' to your actual name.
//**********************************************************************
