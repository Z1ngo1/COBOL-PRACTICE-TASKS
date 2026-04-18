# JCL SAMPLES

Ready-to-use JCL templates for common mainframe tasks: COBOL compilation, program execution, VSAM dataset management, and GDG creation.  
Replace all `YOUR.*` placeholders with your actual dataset, member, and library names before submitting.

---

## COBOL Compilation & Execution

### [JCLCOMP.jcl](./JCLCOMP.jcl)
Compiles a COBOL source member using the **IGYWCL** procedure (IBM COBOL compiler + Link Editor in one step).  
Prints `COMPILATION SUCCESSFUL` if `RC <= 4`.

| Parameter | Description | When to set |
|---|---|---|
| `COBOL.SYSIN DSN` | PDS library with your COBOL source | Always |
| `COBOL.SYSIN (member)` | Member name of your COBOL program | Always |
| `LKED.SYSLMOD DSN` | Load library to store the compiled module | Always |
| `LKED.SYSLIB DSN` | Load library for link-edit references | Always |

---

### [JCLRUN.jcl](./JCLRUN.jcl)
Runs a compiled COBOL program. Deletes old output datasets before execution, then executes the load module with configurable I/O DD statements.

| Parameter | Description | When to set |
|---|---|---|
| `PGM=` | Name of the load module to execute | Always |
| `STEPLIB DSN` | Load library where the module resides | Always |
| `YOURDD DSN` (input) | Input datasets — `DISP=SHR` | For each input file |
| `YOURDD DSN` (output) | Output dataset — `DISP=(NEW,CATLG,DELETE)` | For each output file |
| `DCB=(RECFM,LRECL)` | Record format and length | Match your program's FD |
| `SPACE=(TRK,(2,2),RLSE)` | Primary/secondary space + release | Adjust to expected output size |
| `OUTLIM=15000` | Max output lines to SYSOUT | Increase for large output |
| `*CEEDUMP / *SYSUDUMP` | Dump DD (commented out by default) | Uncomment when debugging ABENDs |

---

### [COMPRUN.jcl](./COMPRUN.jcl)
Combines compile and run in a single job using a **[MYCOMPGO](../JCLPROC/MYCOMPGO.jcl)** catalogued procedure. Deletes old output before compiling, then passes DD statements directly to the RUN step.

| Parameter | Description | When to set |
|---|---|---|
| `JCLLIB ORDER=` | Proclib where MYCOMPGO procedure is stored | Always |
| `MYCOMPGO MEMBER=` | Source member to compile and run | Always |
| `RUN.YOURDD` (input) | Input DD overrides for the RUN step | For each input file |
| `RUN.YOURDD` (output) | Output DD — `DISP=(NEW,CATLG,DELETE)` | For each output file |
| `DCB=(RECFM=VB,LRECL=84)` | Record format; VB = variable blocked | Change if your program uses FB/fixed |

---

### [COBDB2CP.jcl](./COBDB2CP.jcl)
Full COBOL + DB2 compile-and-run pipeline: deletes old output → compiles with DB2 precompile via **DB2CBL** procedure → runs the bound program under IKJEFT01.

| Parameter | Description | When to set |
|---|---|---|
| `DB2CBL MBR=` | Member name of the COBOL+DB2 source | Always |
| `COBOL.SYSIN DSN` | Source library containing the program | Always |
| `COBOL.SYSLIB DSN` | DCLGEN library (DB2 copybooks) | Always when using DB2 host variables |
| `DSN SYSTEM(...)` | DB2 subsystem ID (SSID) | Always |
| `RUN PROGRAM(...)` | Load module name to execute | Always |
| `PLAN(...)` | DB2 application plan name | Always; created during BIND step |
| `LIB(...)` | Load library for the runtime module | Always |
| `YOURDD DSN` (output) | Output dataset with DCB settings | Adjust RECFM/LRECL to match program |
| `COND=(4,LT)` | Skip RUN step if compile RC > 4 | Already set; do not remove |

---

## VSAM Dataset Management

### [DEFKSDS.jcl](./DEFKSDS.jcl)
Defines a **KSDS** (Key-Sequenced Dataset) VSAM cluster using IDCAMS. Records are stored and accessed by a key field.

| Parameter | Description | When to set |
|---|---|---|
| `NAME` | Fully qualified cluster name | Always |
| `RECORDSIZE(avg max)` | Average and maximum record length in bytes | Match your record layout |
| `TRACKS(primary)` | Primary space allocation | Based on expected data volume |
| `KEYS(length offset)` | Length and offset of the key field | Must match your record structure |
| `CISZ` | Control Interval size (512–32768) | Larger = better for sequential; 4096 is a safe default |
| `FREESPACE(CI CA)` | Free space % per CI and CA | Set higher (e.g. 20 10) if frequent inserts expected |
| `INDEXED` | Declares dataset type as KSDS | Required; use `NONINDEXED` for ESDS, `NUMBERED` for RRDS |
| `REUSE` | Allows cluster to be reloaded with REPRO without redefining | Add when you need to overwrite data repeatedly in testing |

---

### [DEFESDS.jcl](./DEFESDS.jcl)
Defines an **ESDS** (Entry-Sequenced Dataset) VSAM cluster. Records are stored in insertion order — no key, no random access by key. Used for logs, audit trails, sequential output.

| Parameter | Description | When to set |
|---|---|---|
| `NAME` | Fully qualified cluster name | Always |
| `RECORDSIZE(avg max)` | Average and maximum record length in bytes | Match your record layout |
| `TRACKS(primary)` | Primary space allocation | Based on expected data volume |
| `CISZ` | Control Interval size | 4096 is typical |
| `FREESPACE(CI CA)` | Free space percentages | Usually low for ESDS since no inserts by key |
| `NONINDEXED` | Declares dataset type as ESDS | Required for ESDS |
| `REUSE` | Allows re-loading without redefine | Add for test/dev environments |

---

### [DEFAIX.jcl](./DEFAIX.jcl)
Defines an **Alternate Index (AIX)** on an existing KSDS cluster. Allows accessing records by a secondary key (e.g., last name, department) in addition to the primary key.

> **Order of steps:** DEFKSDS → **DEFAIX** → DEFPATH → BLDINDEX

| Parameter | Description | When to set |
|---|---|---|
| `NAME` | Name of the AIX dataset itself | Always |
| `RELATE` | Must point to the base KSDS cluster | Always |
| `CISZ` | CI size — match base cluster if possible | Always |
| `KEYS(length offset)` | Length and offset of the alternate key field in the record | Must match where the alternate key is in your record |
| `NONUNIQUEKEY` | Multiple records can share the same alternate key | When alternate key is not unique (e.g. last name); use `UNIQUEKEY` if it must be unique |
| `UPGRADE` | AIX is automatically updated on every write to base cluster | Preferred for most cases; use `NOUPGRADE` if you want manual control via BLDINDEX |
| `RECORDSIZE(avg max)` | Must be >= base cluster RECORDSIZE | Always |
| `TRACKS(primary secondary)` | Space allocation | Based on number of unique alternate keys |
| `FREESPACE(CI CA)` | Free space percentages | Match or be slightly higher than base cluster |

---

### [DEFPATH.jcl](./DEFPATH.jcl)
Defines a **PATH** that connects an Alternate Index (AIX) to its base KSDS cluster. Without a PATH, the AIX exists but cannot be used to retrieve records.

> **Prerequisites:** base KSDS and AIX must already exist before running this JCL.

| Parameter | Description | When to set |
|---|---|---|
| `NAME` | Name of the PATH (any valid dataset name) | Always |
| `PATHENTRY` | Must point to an existing AIX | Always; run DEFAIX before this |

---

### [BLDINDX.jcl](./BLDINDX.jcl)
Populates an **Alternate Index** with key values and pointers from the base KSDS cluster. Must be run after data has been loaded into the base cluster.

> **Must be re-run manually** if `NOUPGRADE` was set in DEFAIX. If `UPGRADE` was used, this step is only needed for the initial load.

| Parameter | Description | When to set |
|---|---|---|
| `INDATASET` | Base KSDS cluster that contains the source data | Always |
| `OUTDATASET` | AIX to be populated (must already be defined) | Always; run DEFAIX + DEFPATH first |

---

### [DATAVSAM.jcl](./DATAVSAM.jcl)
Three-step job that: (1) deletes and redefines a KSDS cluster, (2) creates a temp PS file from inline data using SORT, (3) loads the data into the KSDS cluster using `REPRO`.

| Parameter | Description | When to set |
|---|---|---|
| `DELETE ... PURGE` | Deletes existing cluster regardless of expiry date | Remove or comment out if cluster should not be deleted |
| `SET MAXCC = 0` | Resets return code after DELETE (in case cluster didn't exist) | Keep — prevents job failure when cluster is new |
| `RECORDSIZE / KEYS / CISZ` | Cluster definition parameters | Adjust to your record layout |
| `SORTIN DD *` (inline data) | Your raw data records | Replace with your actual records |
| `OUTREC BUILD=(1,32)` | Trims/pads each record to exactly 32 bytes | Change `32` to match your `LRECL` |
| `REPRO INFILE / OUTFILE` | Source PS temp file → target VSAM cluster | Always |
| `COND=(0,NE)` on STEP2/STEP3 | Skips step if previous step had any error | Keep — prevents loading to broken cluster |

> **Simplified variant** — if your records are already the correct length, skip the SORT step entirely. Load inline data directly into the KSDS using IDCAMS REPRO with inline DD:
> ```jcl
> //STEPINS  EXEC PGM=IDCAMS
> //SYSPRINT DD SYSOUT=*
> //SYSOUT   DD SYSOUT=*
> //INDD     DD *
> 000100IVAN PETROV              A00070000000
> 000200MARIA SIDOROVA           A00020000000
> /*
> //OUTDD    DD DSN=YOUR.VSAM.CLUSTER,DISP=SHR
> //SYSIN    DD *
>   REPRO INFILE(INDD) OUTFILE(OUTDD)
> /*
> ```
> The SORT step with `OUTREC BUILD` is only needed when records must be **padded or trimmed** to an exact length. If the data already matches the cluster `RECORDSIZE` — use REPRO with inline DD directly, no temp dataset needed.

---

### [DATA2PS.jcl](./DATA2PS.jcl)
Loads inline data records into a **PS (Physical Sequential)** dataset using IEBGENER. Useful for creating small test datasets quickly.

| Parameter | Description | When to set |
|---|---|---|
| `SYSUT1 DD *` (inline data) | Your raw data records | Replace with your actual test records |
| `RECORD FIELD=(32,1,,1)` | Copy field: length 32, from pos 1, to pos 1 | Change `32` to match your record length |
| `DCB=(RECFM=FB,LRECL=32)` | Output dataset record format and length | Match your data record length |
| `SPACE=(TRK,(1,1),RLSE)` | Primary/secondary space + auto-release | Increase for larger datasets |
| `DISP=(MOD,DELETE,DELETE)` in STEP1 | Deletes existing dataset before re-creating | Keep — prevents DISP conflict on re-run |

> **Simplified variant** — if your records are already the correct length (e.g. 80 bytes) and no field transformation is needed, remove the `SYSIN GENERATE/RECORD` step and use `SYSIN DD DUMMY`. IEBGENER will copy records as-is:
> ```jcl
> //STEP2    EXEC PGM=IEBGENER
> //SYSPRINT DD SYSOUT=*
> //SYSOUT   DD SYSOUT=*
> //SYSIN    DD DUMMY
> //SYSUT1   DD *
> 00100NY15000000
> 00200CA05000000
> /*
> //SYSUT2   DD DSN=YOUR.DATA.SET,
> //            DISP=(NEW,CATLG,DELETE),
> //            SPACE=(TRK,(2,2),RLSE),
> //            DCB=(DSORG=PS,RECFM=FB,LRECL=80,BLKSIZE=800)
> ```
> `SYSIN DD DUMMY` tells IEBGENER to apply no transformations — just copy records from SYSUT1 to SYSUT2 unchanged. `RECORD FIELD` is only needed when you want to extract a specific byte range from each record.

---

## GDG Management

### [DEFGDG.jcl](./DEFGDG.jcl)
Defines a **GDG (Generation Data Group)** base entry in the catalog. The base itself is not a physical dataset — each generation (GDS) is allocated separately at job time.

| Parameter | Description | When to set |
|---|---|---|
| `NAME` | Fully qualified GDG base name | Always |
| `LIMIT` | Max number of generations retained (1–255) | Set based on how many historical copies you need |
| `NOEMPTY` | Only the oldest generation is removed when limit is exceeded | Default choice; use `EMPTY` to delete **all** generations at once when limit is hit |
| `SCRATCH` | Physically deletes the removed generation from disk | Use when disk space matters; use `NOSCRATCH` to only uncatalog it (file stays on volume) |
