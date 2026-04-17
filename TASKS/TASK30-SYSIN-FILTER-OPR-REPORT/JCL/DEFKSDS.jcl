//DEFKSDS  JOB (123),'IDCAMS',CLASS=A,MSGCLASS=A,MSGLEVEL=(1,1),        
//             NOTIFY=&SYSUID                                           
//*                                                                     
//************************************************************          
//* DEFINE VSAM KSDS CLUSTER                                            
//************************************************************          
//STEP10   EXEC PGM=IDCAMS                                              
//SYSPRINT DD SYSOUT=*                                                  
//SYSOUT   DD SYSOUT=*                                                  
//SYSIN    DD *                                                         
  DEFINE CLUSTER (NAME(Z73460.TASK30.OPR.LOG.KSDS) -                    
           RECORDSIZE(80,80) -                                          
           TRACKS(15)                      -                            
           KEYS(20 0)                       -                           
           CISZ(4096)                      -                            
           FREESPACE(10,20)                -                            
           INDEXED)                                                     
/*                                                                      
