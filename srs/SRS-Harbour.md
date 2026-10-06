# Software Requirements Specification (SRS)

## Harbour Console Applications

| Document Information |                          |
| -------------------- | ------------------------ |
| **Document Title**   | Software Requirements Specification – Harbour Console Applications |
| **Version**          | 1.0                      |
| **Status**           | Draft                    |
| **Author**           | Software Architecture Team |
| **Date**             | $(date)                  |
| **Platform**         | Microsoft Windows        |
| **Language**         | Harbour                  |
| **Data Access**      | RDD (Rapid Data Dictionary) |

---

## Revision History

| Version | Date       | Author               | Description           |
| ------- | ---------- | -------------------- | --------------------- |
| 1.0     | $(date)    | Software Architecture Team | Initial Draft        |

---

## Table of Contents

1. [Introduction](#1-introduction)
   1.1 Purpose
   1.2 Document Conventions
   1.3 Intended Audience and Reading Suggestions
   1.4 Project Scope
   1.5 References
   1.6 Overview
2. [Overall Description](#2-overall-description)
   2.1 Product Perspective
   2.2 Product Functions
   2.3 User Characteristics
   2.4 Constraints
   2.5 Assumptions and Dependencies
3. [Specific Requirements](#3-specific-requirements)
   3.1 External Interface Requirements
   3.2 Functional Requirements
   3.3 Non-Functional Requirements
   3.4 Data Access Layer Requirements
   3.5 System Operations
   3.6 Business Rules
4. [Appendices](#4-appendices)
   A. Glossary
   B. Analysis Models

---

## 1. Introduction

### 1.1 Purpose

This Software Requirements Specification (SRS) describes the functional and non-functional requirements for **Harbour-based Windows Console Applications**. This document is intended to serve as the definitive reference for all stakeholders involved in the development, testing, deployment, and maintenance of console applications built using the **Harbour compiler** with **RDD (Rapid Data Dictionary)** as the exclusive data access mechanism.

The purpose of this document is to:

- Define a clear, unambiguous set of requirements that the software must satisfy.
- Establish a common understanding between stakeholders, developers, testers, and project managers.
- Provide a baseline for future changes through a formal change management process.
- Serve as input for test planning and validation activities.

This SRS conforms to the **IEEE Std 830-1998** standard for Software Requirements Specifications.

### 1.2 Document Conventions

The following conventions are used throughout this document:

| Keyword   | Meaning                                                                 |
| --------- | ----------------------------------------------------------------------- |
| **MUST**  | The requirement is mandatory and non-negotiable.                        |
| **SHALL** | Identical in meaning to MUST; indicates an absolute requirement.        |
| **SHOULD** | Recommended but not mandatory; exceptions require documented justification. |
| **MAY**   | Optional; permitted but not required.                                   |

- Requirement IDs follow the format: **REQ-\<Category\>-\<Sequential Number\>** (e.g., `REQ-FUNC-001`).
- All code samples use Harbour syntax.
- Screenshots, diagrams, or sample outputs are included where necessary for clarity.

### 1.3 Intended Audience and Reading Suggestions

| Audience                    | Recommended Sections                          | Rationale                                                    |
| --------------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| **Project Managers**        | Sections 1, 2, 3.5                            | High-level scope, constraints, and operational requirements. |
| **Software Developers**     | All sections                                  | Complete technical and functional specifications.            |
| **QA / Test Engineers**     | Sections 2, 3 (all subsections)               | Functional and non-functional test criteria.                 |
| **System Administrators**   | Sections 1.4, 3.1, 3.5                        | Deployment, configuration, and operational requirements.     |
| **Technical Writers**       | Sections 1, 2, Appendix A                     | Product description and terminology.                         |
| **Stakeholders / Clients**  | Sections 1, 2                                 | Scope, functions, and constraints overview.                  |

### 1.4 Project Scope

This SRS defines requirements for **Windows-based console applications** developed exclusively with the **Harbour programming language** (https://github.com/harbour/core). The scope encompasses:

- Command-line driven user interfaces with structured menus, prompts, and formatted output.
- Data management operations using RDD as the sole data access layer.
- File-based and network-accessible data storage via RDD-supported drivers.
- Modular application architecture supporting reusable components.
- Logging, error handling, and configuration management.

**Out of Scope:**

- Graphical User Interface (GUI) applications (e.g., Windows Forms, WPF, Qt).
- Web-based or cloud-native services.
- Database access via ODBC, ADO.NET, or any mechanism other than RDD.
- Cross-platform development (Linux, macOS).
- Mobile application development.

### 1.5 References

| #   | Reference                                                                                          |
| --- | -------------------------------------------------------------------------------------------------- |
| [1] | IEEE Std 830-1998: *IEEE Recommended Practice for Software Requirements Specifications*            |
| [2] | Harbour Project Documentation: https://github.com/harbour/core                                     |
| [3] | Harbour Compiler User's Guide: https://harbour.github.io/doc/                                      |
| [4] | RDD (Rapid Data Dictionary) Documentation: https://harbour.github.io/doc/                        |
| [5] | xBase Language Specification (Harbour dialect)                                                     |
| [6] | Microsoft Windows Console API Documentation                                                        |

### 1.6 Overview

The remainder of this SRS is organized as follows:

- **Section 2** describes the overall product perspective, including functions, user characteristics, constraints, and assumptions.
- **Section 3** details specific requirements covering interfaces, functionality, non-functional attributes, data access, system operations, and business rules.
- **Appendices** provide a glossary of terms and supplementary analysis models.

---

## 2. Overall Description

### 2.1 Product Perspective

Harbour console applications are self-contained, native Windows executables (`*.exe`) produced by the Harbour compiler linking against the Harbour runtime library. These applications operate within the Windows command-line environment (CMD.EXE or PowerShell) and may also be invoked from scheduled tasks, batch scripts, or other automation frameworks.

The product architecture follows a **layered design**:

```
┌─────────────────────────────────────┐
│         Presentation Layer          │  ← Console I/O, Menus, Validation
├─────────────────────────────────────┤
│         Business Logic Layer        │  ← Domain Rules, Processing
├─────────────────────────────────────┤
│       Data Access Layer (RDD)       │  ← RDD Drivers, Record Operations
├─────────────────────────────────────┤
│          Data Storage               │  ← .DBF, memo files, indexed structures
└─────────────────────────────────────┘
```

The application SHALL communicate with external systems only through:

- Standard file I/O (read/write text, binary, CSV, XML).
- Windows API calls via Harbour's `#include "hbapiwin.ch"` and platform API headers.
- Command-line arguments and environment variables.
- Inter-process communication via named pipes or files (where applicable).

### 2.2 Product Functions

The application SHALL provide the following categories of functionality:

| Function Category       | Description                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------- |
| **Data Entry**          | Structured input of records through console-based forms with validation.                        |
| **Data Retrieval**      | Query, browse, and display records from RDD-managed data sources.                               |
| **Data Modification**   | Update, delete, and append records in RDD tables.                                               |
| **Reporting**           | Generate formatted text reports, summaries, and exports to file formats (CSV, TXT, XML).        |
| **Data Import/Export**  | Bulk data transfer between RDD tables and external file formats.                                |
| **Backup & Restore**    | Create and restore database backups including table structures, records, indexes, and memos.    |
| **User Administration** | Manage user accounts, roles, and permissions (if applicable).                                   |
| **Logging**             | Record application events, errors, and audit trails to log files.                               |
| **Configuration**       | Read/write application settings from configuration files or INI-style storage.                  |

### 2.3 User Characteristics

| User Role              | Technical Proficiency | Expected Responsibilities                                      |
| ---------------------- | --------------------- | -------------------------------------------------------------- |
| **End User**           | Low to Moderate       | Operate the console application, enter data, run reports.      |
| **Data Entry Clerk**   | Low                   | Perform data entry and basic queries; no system administration.|
| **System Operator**    | Moderate              | Manage backups, configure settings, monitor logs.              |
| **Database Administrator** | High              | Maintain RDD structures, manage indexes, optimize performance. |
| **Developer / Maintainer** | High              | Modify source code, extend functionality, debug issues.        |

### 2.4 Constraints

The following constraints SHALL apply to all Harbour console applications covered by this SRS:

#### 2.4.1 Language and Compiler Constraints

| Constraint ID | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| C-CON-001     | All source code SHALL be written in the **Harbour programming language** (xBase dialect).             |
| C-CON-002     | Applications SHALL compile using the **Harbour compiler** (`hbmk2` build system or equivalent).       |
| C-CON-003     | Source code SHALL use UTF-8 encoding for all source files.                                            |
| C-CON-004     | Harbour version SHALL be **3.2.0 or later** (latest stable release preferred).                        |
| C-CON-005     | Third-party Harbour libraries MAY be used only if they are open-source and compatible with the target platform. |

#### 2.4.2 Data Access Constraints

| Constraint ID | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| C-DAL-001     | **RDD (Rapid Data Dictionary)** SHALL be the exclusive data access mechanism.                         |
| C-DAL-002     | Supported RDD drivers include, but are not limited to: `DBFCDX`, `DBFFPT`, `DBFDBase`, `DBFMysql`, `DBFPgsql`, `DBFSQLite`, `DBFODBC` (when configured as an RDD driver). |
| C-DAL-003     | All database operations SHALL be performed through Harbour RDD functions (`USE`, `APPEND BLANK`, `DELETE`, `RECALL`, `FIELDPUT()`, `FIELDGET()`, etc.). |
| C-DAL-004     | Direct file manipulation of `.DBF` files (binary read/write) is **prohibited**.                       |
| C-DAL-005     | Index structures SHALL use `.CDX` (compound index) format via `DBFCDX` RDD driver.                    |
| C-DAL-006     | Memo fields SHALL use `.FPT` format via `DBFFPT` RDD driver.                                          |

#### 2.4.3 Platform Constraints

| Constraint ID | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| C-PLT-001     | Applications SHALL run on **Microsoft Windows** operating systems (Windows 7 SP1 or later).           |
| C-PLT-002     | Applications SHALL be compatible with both 32-bit and 64-bit Windows architectures.                   |
| C-PLT-003     | Console applications SHALL operate within the Windows Console subsystem (`CONSOLE`).                    |

#### 2.4.4 Architectural Constraints

| Constraint ID | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| C-ARC-001     | Applications SHALL follow a **layered architecture** (Presentation → Business Logic → Data Access).   |
| C-ARC-002     | All database access code SHALL be encapsulated within the Data Access Layer.                          |
| C-ARC-003     | Global variables SHALL be minimized; state SHOULD be managed through function parameters and return values. |
| C-ARC-004     | Applications SHALL support modular compilation with separate `.prg` source files organized by functional module. |

### 2.5 Assumptions and Dependencies

#### 2.5.1 Assumptions

| Assumption ID | Description                                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------- |
| A-ASS-001     | The target Windows environment has the necessary runtime DLLs distributed with the Harbour compiler (`hbvm.dll`, `hbrtl.dll`, RDD driver DLLs). |
| A-ASS-002     | Users have appropriate file system permissions to read/write data directories.                     |
| A-ASS-003     | Console code page is set appropriately (e.g., `chcp 65001` for UTF-8) before application execution. |
| A-ASS-004     | Hardware resources meet minimum specifications: ≥2 GB RAM, ≥500 MB disk space.                     |

#### 2.5.2 Dependencies

| Dependency ID | Description                                                                                        |
| ------------- | -------------------------------------------------------------------------------------------------- |
| D-DEP-001     | Application execution depends on the **Harbour runtime environment** being available.              |
| D-DEP-002     | RDD driver availability is a dependency for specific data operations (e.g., `DBFCDX.dll` for CDX indexes). |
| D-DEP-003     | External data import/export depends on the availability and format compatibility of source/destination files. |
| D-DEP-004     | If network-based RDD drivers are used (e.g., `DBFMysql`, `DBFPgsql`), database server connectivity is required. |

---

## 3. Specific Requirements

### 3.1 External Interface Requirements

#### 3.1.1 User Interfaces

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-UI-001     | The application SHALL present a text-based console interface with structured menus and prompts. |
| REQ-UI-002     | All screen output SHALL use monospaced font-compatible characters for alignment.                |
| REQ-UI-003     | Menus SHALL display numbered options with clear labels (e.g., `1. Add Record`, `2. Browse Data`).|
| REQ-UI-004     | User input prompts SHALL clearly indicate expected data type and format (e.g., `[DD/MM/YYYY]`).  |
| REQ-UI-005     | Input validation errors SHALL be displayed in a distinct visual format (e.g., highlighted text).|
| REQ-UI-006     | The application SHALL support screen clearing and cursor positioning for clean display updates.   |
| REQ-UI-007     | Data grids / tabular output SHALL use consistent column widths with header separators.            |
| REQ-UI-008     | Confirmation prompts SHALL require explicit user acknowledgment before destructive operations (e.g., `DELETE`). |

**Example Console Menu:**
```
╔════════════════════════════════════════╗
║       DATA MANAGEMENT SYSTEM           ║
╠════════════════════════════════════════╣
║  1. Add New Record                     ║
║  2. Browse All Records                 ║
║  3. Search Records                     ║
║  4. Update Record                      ║
║  5. Delete Record                      ║
║  6. Generate Report                    ║
║  7. Backup Database                    ║
║  8. Exit                               ║
╠════════════════════════════════════════╣
║  Select option (1-8): _                ║
╚════════════════════════════════════════╝
```

#### 3.1.2 Hardware Interfaces

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-HW-001     | Applications SHALL run on standard x86/x64 hardware with no specialized hardware requirements.  |
| REQ-HW-002     | Console output SHALL be directed to the standard Windows console (stdout).                      |

#### 3.1.3 Software Interfaces

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-SW-001     | Applications SHALL interface with RDD drivers via Harbour's native RDD API.                     |
| REQ-SW-002     | Applications MAY invoke external executables via Harbour's `Run()` or `ShellExecute()` functions.|
| REQ-SW-003     | Configuration files SHALL be readable standard INI/text formats using Harbour's `SysReadIni()` or file I/O. |
| REQ-SW-004     | Log files SHALL be plain text files written via Harbour's file I/O functions (`FWrite()`, `FWriteln()`). |

#### 3.1.4 Communication Interfaces

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-COMM-001   | Applications MAY communicate with remote databases through RDD network drivers (e.g., MySQL, PostgreSQL, SQLite). |
| REQ-COMM-002   | Network connectivity requirements SHALL be documented per application instance.                   |
| REQ-COMM-003   | All network communication SHALL handle connection failures gracefully with user-friendly error messages. |

### 3.2 Functional Requirements

#### 3.2.1 Data Entry Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-001   | The application SHALL provide a form-based interface for entering new records into RDD tables.  |
| REQ-FUNC-002   | Each data field SHALL be validated against its defined type, length, and format constraints.    |
| REQ-FUNC-003   | Required fields SHALL be enforced; the application SHALL reject submission if any required field is empty. |
| REQ-FUNC-004   | Date fields SHALL accept input in a configurable date format (default: `DD/MM/YYYY`) and convert to internal storage format. |
| REQ-FUNC-005   | Numeric fields SHALL validate range constraints (minimum/maximum values).                       |
| REQ-FUNC-006   | The application SHALL support data entry from keyboard input and file-based batch import.       |
| REQ-FUNC-007   | Upon successful record insertion, the application SHALL display a confirmation message with the assigned record identifier (if applicable). |
| REQ-FUNC-008   | The application SHALL prevent duplicate entries based on defined unique key constraints.        |

**Sample Harbour Data Entry Snippet:**
```harbour
FUNCTION EnterRecord()
    LOCAL cName, cDate, nAmount
    LOCAL lValid := .F.

    DO WHILE !lValid
        CLS
        ? "╔══════════════════════════════════╗"
        ? "║       NEW RECORD ENTRY           ║"
        ? "╚══════════════════════════════════╝"
        
        cName := Ask( "Enter Name: ", "", .T. )
        IF Empty( cName )
            Alert( "Name is required!" )
            LOOP
        ENDIF
        
        cDate := Ask( "Enter Date [DD/MM/YYYY]: ", DTOC( Date() ), .F. )
        nAmount := AskN( "Enter Amount: ", 0.00, 2 )
        
        IF ValidateInput( cName, cDate, nAmount )
            USE Customer SHARED NEW
            APPEND BLANK
            FIELDPUT( 1, cName )
            FIELDPUT( 2, CToD( cDate ) )
            FIELDPUT( 3, nAmount )
            REPLACE ALL WITH ;
                UPPER( FieldGet( 1 ) ),;
                DTOC( Date() ) FOR LastModified
            DBCommit()
            USE
            ? "Record saved successfully."
            lValid := .T.
        ELSE
            Alert( "Validation failed. Please correct errors." )
        ENDIF
    ENDDO
    
    RETURN nil
```

#### 3.2.2 Data Retrieval Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-010   | The application SHALL display records from RDD tables in a paginated tabular format.            |
| REQ-FUNC-011   | Users SHALL be able to browse all records or filter by one or more field criteria.              |
| REQ-FUNC-012   | The application SHALL support indexed search using `Seek()`, `Find()`, or `dbGoTo()` functions. |
| REQ-FUNC-013   | Search results SHALL be displayed with record count and navigation controls (Next/Previous).    |
| REQ-FUNC-014   | The application SHALL support sorting of result sets by specified fields using `SetOrder()`.    |
| REQ-FUNC-015   | Memo field contents SHALL be displayed in a scrollable or expanded view when requested.         |
| REQ-FUNC-016   | The application SHALL display a "No records found" message when queries return zero results.    |

**Sample Harbour Browse Snippet:**
```harbour
FUNCTION BrowseRecords()
    LOCAL nPage := 1
    LOCAL nPageSize := 20
    LOCAL nTotal, nPages
    
    USE Customer SHARED NEW ORDER cxCustName
    
    IF RecCount() == 0
        Alert( "No records found." )
        RETURN nil
    ENDIF
    
    nTotal := RecCount()
    nPages := Ceil( nTotal / nPageSize )
    
    DO WHILE .T.
        CLS
        ? "╔══════════════════════════════════════════════════╗"
        ? "║              CUSTOMER RECORDS                    ║"
        ? "╠══════════════════════════════════════════════════╣"
        ? Str( "Page ", nPage, " of ", nPages, " (", nTotal, " records)", -50 )
        ? "╠══════════════════════════════════════════════════╣"
        
        DbGoTop()
        Skip( ( nPage - 1 ) * nPageSize )
        
        FOR nRec := 1 TO Min( nPageSize, nTotal - ( nPage - 1 ) * nPageSize )
            ? Str( RecNo(), 6, " | ", ;
                   PadR( FieldGet( 1 ), 25 ), " | ", ;
                   DTOC( FieldGet( 2 ) ), " | ", ;
                   Str( FieldGet( 3 ), 12, 2 ) )
            Skip()
        NEXT
        
        ? "╠══════════════════════════════════════════════════╣"
        ? "  [N]ext  [P]revious  [Q]uit  [G]o to record"
        
        SWITCH Lower( GetKey() )
            CASE "n"
                IF nPage < nPages, nPage++
            CASE "p"
                IF nPage > 1, nPage--
            CASE "q"
                USE
                RETURN nil
            CASE "g"
                // Go to specific record logic
        ENDSWITCH
    ENDDO
    
    USE
    RETURN nil
```

#### 3.2.3 Data Modification Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-020   | The application SHALL allow users to update existing records with validated input.              |
| REQ-FUNC-021   | Users SHALL be able to select a record for editing by primary key, search criteria, or browse navigation. |
| REQ-FUNC-022   | Updated fields SHALL be validated using the same rules as data entry (see REQ-FUNC-001 through REQ-FUNC-008). |
| REQ-FUNC-023   | The application SHALL support field-level updates using `REPLACE` or `FIELDPUT()` functions.    |
| REQ-FUNC-024   | The application SHALL maintain an audit trail of modifications (old value, new value, timestamp, user). |
| REQ-FUNC-025   | Changes SHALL be committed to the RDD table using `DBCommit()` or automatic commit mode.        |

#### 3.2.4 Data Deletion Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-030   | The application SHALL support logical deletion (soft delete) using RDD `DELETE` mark.           |
| REQ-FUNC-031   | Physically deleted records SHALL be permanently removed from the RDD table.                     |
| REQ-FUNC-032   | Before any deletion, the application SHALL display a confirmation prompt with record details.    |
| REQ-FULK-033   | The application SHALL support bulk deletion based on filter criteria (e.g., `DELETE FOR condition`). |
| REQ-FUNC-034   | After deletion, the application SHALL perform `PACK` operations only with explicit user confirmation. |

#### 3.2.5 Reporting Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-040   | The application SHALL generate formatted text reports from RDD data sources.                    |
| REQ-FUNC-041   | Reports SHALL support standard layouts: list, summary, and cross-tab formats.                   |
| REQ-FUNC-042   | Reports SHALL include header (title, date range), body (data rows), and footer (totals, page numbers). |
| REQ-FUNC-043   | Users SHALL be able to print reports to the console or export them to files (.TXT, .CSV, .XML). |
| REQ-FUNC-044   | The application SHALL support report scheduling via command-line arguments.                     |
| REQ-FUNC-045   | Report data SHALL be retrieved using filtered RDD queries (`SELECT ... FROM ... WHERE`).         |

**Sample Harbour Report Snippet:**
```harbour
FUNCTION GenerateReport( cOutputFile )
    LOCAL hFile, nTotalAmt := 0.0
    
    USE Sales SHARED NEW ORDER cxSaleDate
    
    IF !Empty( cOutputFile )
        hFile := FCreate( cOutputFile )
        IF hFile == -1
            Alert( "Cannot create output file: " + cOutputFile )
            RETURN .F.
        ENDIF
    ENDIF
    
    // Report Header
    PrintReportLine( "SALES REPORT" )
    PrintReportLine( "Generated: " + DTOC( Date() ) )
    PrintReportLine( String( "=", 60 ) )
    PrintReportLine( Str( "Date", 12 ), Str( "Customer", 25 ), Str( "Amount", 12 ) )
    PrintReportLine( String( "-", 60 ) )
    
    // Report Body
    DbGoTop()
    DO WHILE !Eof()
        IF !Deleted()
            PrintReportLine( ;
                Str( DTOC( FieldGet( 1 ) ), 12 ), ;
                Str( FieldGet( 2 ), 25 ), ;
                Str( FieldGet( 3 ), 12, 2 ) )
            nTotalAmt += FieldGet( 3 )
        ENDIF
        Skip()
    ENDDO
    
    // Report Footer
    PrintReportLine( String( "=", 60 ) )
    PrintReportLine( Str( "TOTAL: ", 48 ), Str( nTotalAmt, 12, 2 ) )
    
    IF !Empty( cOutputFile )
        FClose( hFile )
    ENDIF
    
    USE
    RETURN .T.
```

#### 3.2.6 Import/Export Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-050   | The application SHALL import data from CSV, TXT, and XML files into RDD tables.                 |
| REQ-FUNC-051   | The application SHALL export RDD table data to CSV, TXT, and XML file formats.                  |
| REQ-FUNC-052   | Import operations SHALL map source file columns to target RDD table fields by position or header name. |
| REQ-FUNC-053   | Export operations SHALL include field headers for CSV and XML formats.                          |
| REQ-FUNC-054   | Import errors SHALL be logged with row number, field name, and error description.               |
| REQ-FUNC-055   | The application SHALL support incremental imports (append only) and full replacement modes.     |

#### 3.2.7 Backup and Restore Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-060   | The application SHALL create a complete backup of RDD tables, including `.DBF`, `.CDX`, `.FPT` files. |
| REQ-FUNC-061   | Backup operations SHALL ensure data consistency by locking tables during the copy process.      |
| REQ-FUNC-062   | Backups SHALL be stored in a designated backup directory with timestamp-based naming.           |
| REQ-FUNC-063   | The application SHALL support restoration from a previously created backup.                     |
| REQ-FUNC-064   | Before restore, the application SHALL verify backup file integrity (file size, checksum if applicable). |
| REQ-FUNC-065   | The application SHALL log all backup and restore operations with timestamps and user identity.  |

#### 3.2.8 Logging Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-070   | The application SHALL maintain an application log file recording all significant events.        |
| REQ-FUNC-071   | Log entries SHALL include: timestamp, severity level (INFO, WARNING, ERROR), module name, and message. |
| REQ-FUNC-072   | Log files SHALL be rotated based on size (e.g., 5 MB) or date (daily/weekly).                   |
| REQ-FUNC-073   | Error conditions SHALL log full stack traces where available.                                   |
| REQ-FUNC-074   | The application SHALL provide a command-line option to specify the log file path.               |

**Sample Harbour Logging Snippet:**
```harbour
FUNCTION LogEvent( cSeverity, cModule, cMessage )
    LOCAL cLogFile := "app.log"
    LOCAL hFile, cTimestamp
    
    cTimestamp := Time() + " " + DTOC( Date() )
    
    hFile := FOpen( cLogFile, FO_READWRITE + FO_OPENAPP )
    IF hFile >= 0
        FWriteln( hFile, Str( cTimestamp, 20 ) + " [" + PadR( cSeverity, 7 ) + "] " + ;
                  PadR( cModule, 15 ) + " - " + cMessage )
        FClose( hFile )
    ENDIF
    
    RETURN nil
```

#### 3.2.9 Configuration Functions

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-FUNC-080   | The application SHALL read configuration settings from an INI-style configuration file on startup. |
| REQ-FUNC-081   | Configuration SHALL support sections for: database paths, logging, display preferences, and security. |
| REQ-FUNC-082   | Default values SHALL be embedded in the application code when configuration entries are missing. |
| REQ-FUNC-083   | The application SHALL write updated settings back to the configuration file when modified by the user. |
| REQ-FUNC-084   | Configuration changes SHALL take effect on next application start (or immediately if hot-reload is supported). |

### 3.3 Non-Functional Requirements

#### 3.3.1 Performance Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-001     | Record retrieval from RDD tables SHALL complete within **2 seconds** for up to 10,000 records with proper indexing. |
| REQ-NF-002     | Data entry form submission SHALL complete within **1 second**.                                  |
| REQ-NF-003     | Report generation SHALL complete within **5 seconds** for datasets up to 50,000 records.        |
| REQ-NF-004     | The application SHALL support concurrent access by multiple users through RDD's shared table locking mechanism. |
| REQ-NF-005     | Application startup time SHALL not exceed **3 seconds** on standard hardware.                   |

#### 3.3.2 Reliability Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-010     | The application SHALL maintain **99.5% uptime** during scheduled operational hours.             |
| REQ-NF-011     | Data corruption due to unexpected termination SHALL be prevented through transactional RDD operations where supported. |
| REQ-NF-012     | The application SHALL recover gracefully from RDD lock contention by implementing retry logic (up to 5 attempts). |
| REQ-NF-013     | Database integrity checks SHALL be available as a maintenance function (`DBReindex()`, `DbVerify()`). |

#### 3.3.3 Security Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-020     | The application SHALL support user authentication via username/password stored in an encrypted RDD table. |
| REQ-NF-021     | Sensitive data (passwords, financial data) SHALL be encrypted at rest using Harbour's cryptographic functions (`CryptEncrypt()`). |
| REQ-NF-022     | File system permissions SHALL restrict access to data directories based on operating system security policies. |
| REQ-NF-023     | The application SHALL log all authentication attempts (successful and failed).                  |
| REQ-NF-024     | Session timeout SHALL be configurable; idle sessions SHALL be terminated after a defined period. |

#### 3.3.4 Usability Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-030     | The application SHALL be operable by users with basic computer literacy without formal training.|
| REQ-NF-031     | All user-facing messages SHALL be in clear, non-technical language (configurable for localization). |
| REQ-NF-032     | Keyboard shortcuts SHALL be provided for common operations (e.g., `Ctrl+C` to cancel, `Esc` to go back). |
| REQ-NF-033     | The application SHALL provide online help accessible via the `?` or `F1` key.                   |
| REQ-NF-034     | Console window size SHALL adapt to available terminal dimensions where possible.                |

#### 3.3.5 Maintainability Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-040     | Source code SHALL include inline comments for all functions, complex logic blocks, and non-obvious algorithms. |
| REQ-NF-041     | Functions SHALL not exceed **100 lines** of code to promote readability and testability.        |
| REQ-NF-042     | The application SHALL support modular compilation; each functional module SHALL be a separate `.prg` file. |
| REQ-NF-043     | Version information SHALL be embedded in the compiled executable (via `#pragma startup` or resource compilation). |

#### 3.3.6 Portability Requirements

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-NF-050     | Applications SHALL compile and run on both **Windows 32-bit** and **Windows 64-bit** architectures without code changes. |
| REQ-NF-051     | Source code SHALL be compatible with multiple Harbour compiler backends (GCC, MSVC, MinGW).      |

### 3.4 Data Access Layer Requirements

#### 3.4.1 RDD Driver Selection and Configuration

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-DAL-001    | The application SHALL initialize the required RDD driver at startup using `SetRDDType()` or equivalent Harbour function. |
| REQ-DAL-002    | The default RDD driver SHALL be `DBFCDX` for local table operations unless otherwise specified in configuration. |
| REQ-DAL-003    | Multiple RDD drivers MAY be active simultaneously if required (e.g., `DBFCDX` for local tables, `DBFMysql` for remote data). |
| REQ-DAL-004    | RDD driver initialization SHALL be performed before any database operations and SHALL include error handling. |

**Sample Harbour RDD Initialization:**
```harbour
FUNCTION InitDataAccess()
    LOCAL nRDDType
    
    // Initialize CDX/FPT RDD driver (default)
    SetRDDType( RDD_CDX )
    
    IF !RddSetDefault( "DBFCDX" )
        LogEvent( "ERROR", "DAL", "Failed to initialize DBFCDX RDD driver." )
        RETURN .F.
    ENDIF
    
    // Register FPT for memo support
    RddRegister( "DBFFPT" )
    
    LogEvent( "INFO", "DAL", "RDD drivers initialized successfully." )
    RETURN .T.
```

#### 3.4.2 Table Operations

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-DAL-005    | All table openings SHALL use the `USE` statement with appropriate scope (`SHARED`, `EXCLUSIVE`).|
| REQ-DAL-006    | Tables SHALL be opened with explicit index specification using `ORDER` clause when indexed access is required. |
| REQ-DAL-007    | Table closures SHALL be performed explicitly using `USE` (without arguments) to release file handles. |
| REQ-DAL-008    | The application SHALL handle "Table in use by another user" errors with appropriate retry or notification logic. |

#### 3.4.3 Index Management

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-DAL-010    | All compound index files (`.CDX`) SHALL be maintained and rebuilt when table structures change. |
| REQ-DAL-011    | Index tags SHALL follow naming conventions: `cx<FieldNames>` for composite indexes, `x<FieldNames>` for single-field indexes. |
| REQ-DAL-012    | Index creation/rebuilding SHALL use the `CREATE INDEX` or `INDEX ON` statements with appropriate expression and filter. |
| REQ-DAL-013    | The application SHALL verify index integrity periodically using `DbReindex()` during maintenance windows. |

#### 3.4.4 Transaction Management

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-DAL-015    | Multi-record operations SHALL be wrapped in RDD transaction blocks (`DBBegin()`, `DBCommit()`, `DBRollback()`). |
| REQ-DAL-016    | In the event of an error during a transaction, the application SHALL execute `DBRollback()` to restore data consistency. |
| REQ-DAL-017    | Auto-commit mode SHALL be disabled for batch operations; explicit commit SHALL be used.          |

**Sample Harbour Transaction Snippet:**
```harbour
FUNCTION TransferRecords( cFromTable, cToTable, nCount )
    LOCAL nSuccess := 0
    LOCAL nError := 0
    
    USE (cFromTable) SHARED NEW
    USE (cToTable) SHARED NEW
    
    DBBegin()
    
    TRY
        DbGoTop()
        WHILE !Eof() .AND. nSuccess < nCount
            IF !Deleted()
                // Copy record
                AppendFrom( cFromTable, cToTable )
                Delete()  // Logical delete from source
                nSuccess++
            ENDIF
            Skip()
        ENDDO
        
        DBCommit()
        LogEvent( "INFO", "DAL", ;
            Format( "Transfer complete: %d records moved.", nSuccess ) )
        
    CATCH oError
        DBRollback()
        LogEvent( "ERROR", "DAL", ;
            Format( "Transfer failed at record %d: %s", RecNo(), oError:description ) )
        nError++
    FINALLY
        USE IN (cFromTable)
        USE IN (cToTable)
    END
    
    RETURN IIF( nError > 0, .F., .T. )
```

#### 3.4.5 Data Integrity

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-DAL-020    | The application SHALL enforce referential integrity through application-level validation (unless the RDD driver supports foreign key constraints). |
| REQ-DAL-021    | Field-level data types SHALL be enforced by Harbour's type system and validated at input.        |
| REQ-DAL-022    | NULL/empty value handling SHALL follow consistent rules per field type (numeric: 0, character: empty string, date: nil). |
| REQ-DAL-023    | Auto-increment fields (if used) SHALL be managed through sequence tables or application-level counters. |

### 3.5 System Operations

#### 3.5.1 Startup and Shutdown

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-SYS-001    | The application SHALL read command-line arguments at startup using `CmdLine()` or Harbour's argument parsing functions. |
| REQ-SYS-002    | Startup sequence: (1) Load configuration, (2) Initialize RDD drivers, (3) Validate data directory, (4) Display main menu. |
| REQ-SYS-003    | Shutdown sequence: (1) Close all open tables (`USE ALL`), (2) Flush logs, (3) Release resources, (4) Exit with appropriate return code. |
| REQ-SYS-004    | The application SHALL return exit code `0` for successful execution and non-zero for errors.     |

#### 3.5.2 Monitoring and Maintenance

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-SYS-010    | The application SHALL provide a maintenance mode accessible via command-line flag (`/MAINTENANCE`) for offline operations. |
| REQ-SYS-011    | Database integrity checks (`DBVerify()`, `DBReindex()`) SHALL be available as scheduled or on-demand operations. |
| REQ-SYS-012    | Disk space monitoring SHALL warn users when the data directory exceeds a configurable threshold. |

#### 3.5.3 Backup Procedures

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-SYS-020    | Automated backups MAY be scheduled via Windows Task Scheduler invoking the application with backup parameters. |
| REQ-SYS-021    | Backup verification SHALL compare source and destination file counts and sizes.                 |

### 3.6 Business Rules

| Requirement ID | Description                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------- |
| REQ-BR-001     | **Record Uniqueness**: No two records SHALL share the same value in fields designated as unique keys. |
| REQ-BR-002     | **Data Retention**: Records marked for deletion SHALL be retained for a configurable period (default: 90 days) before permanent removal. |
| REQ-BR-003     | **Audit Trail**: All create, update, and delete operations SHALL be logged with user identity, timestamp, and field-level changes. |
| REQ-BR-004     | **Access Control**: Users SHALL only perform operations authorized by their assigned role.        |
| REQ-BR-005     | **Data Validation**: All input data SHALL conform to predefined format, range, and type rules before acceptance. |
| REQ-BR-006     | **Transaction Atomicity**: Multi-step data operations SHALL succeed completely or rollback entirely (no partial updates). |

---

## 4. Appendices

### Appendix A: Glossary

| Term                        | Definition                                                                                                                           |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| ** Harbour**                | An open-source compiler and runtime environment for the xBase programming language, compatible with dBASE and FoxPro source code.   |
| **RDD (Rapid Data Dictionary)** | Harbour's data access abstraction layer that provides a unified interface to various database formats through pluggable drivers.  |
| **.DBF**                    | dBASE table file format; the primary data storage format used by RDD.                                                                |
| **.CDX**                    | Compound index file format used by Harbour's `DBFCDX` RDD driver for efficient record retrieval.                                    |
| **.FPT**                    | FoxPro memo file format used to store memo/memo-type field contents in RDD tables.                                                   |
| **xBase**                   | A family of programming languages derived from dBASE, including Clipper, FoxPro, and Harbour.                                        |
| **DBE (Database Engine)**   | Harbour's newer database engine abstraction; this SRS does NOT cover DBE—only RDD-based access.                                      |
| **Soft Delete**             | Logical deletion of a record using RDD's `DELETE` mark without physically removing the record from the table.                       |
| **Hard Delete**             | Physical removal of a record from the table, typically via `PACK` operation after `DELETE` marking.                                  |
| **HBMK2**                   | Harbour's build system/compiler driver for compiling `.prg` source files into executables.                                           |
| **DBFCDX**                  | The compound index RDD driver for Harbour; provides fast indexed access to `.DBF` tables with `.CDX` indexes.                        |
| **DBFFPT**                  | The FoxPro memo RDD driver for Harbour; provides memo field support for `.DBF` tables with `.FPT` files.                             |

### Appendix B: Analysis Models

#### B.1 High-Level Data Flow Diagram

```
                    ┌──────────────┐
                    │   External    │
                    │   Files       │
                    │  (CSV/XML)    │
                    └──────┬────────┘
                           │ Import/Export
                           ▼
┌─────────┐    ┌──────────────────────┐    ┌─────────┐
│  User   │───▶│   Harbour Console     │───▶│ RDD     │
│  Input  │    │   Application         │    │ Tables  │
└─────────┘    │                       │    │ (.DBF)  │
               │  ┌─────────────────┐  │    └─────────┘
               │  │ Presentation    │  │
               │  │ Layer           │  │
               │  └─────────────────┘  │
               │  ┌─────────────────┐  │
               │  │ Business Logic  │  │
               │  │ Layer           │  │
               │  └─────────────────┘  │
               │  ┌─────────────────┐  │
               │  │ Data Access     │  │
               │  │ Layer (RDD)     │  │
               │  └─────────────────┘  │
               └──────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │   Log    │ │ Config   │ │  Backup  │
        │  Files   │ │  Files   │ │  Files   │
        └──────────┘ └──────────┘ └──────────┘
```

#### B.2 Typical Application Structure

```
MyApp/
├── src/
│   ├── main.prg           ← Application entry point
│   ├── config.prg         ← Configuration management
│   ├── dal/
│   │   ├── dbinit.prg     ← RDD initialization
│   │   ├── customer.prg   ← Customer table operations
│   │   ├── sales.prg      ← Sales table operations
│   │   └── utils.prg      ← Common data access utilities
│   ├── logic/
│   │   ├── auth.prg       ← Authentication logic
│   │   ├── reports.prg    ← Report generation logic
│   │   └── import.prg     ← Import/export logic
│   └── ui/
│       ├── menu.prg       ← Main menu
│       ├── forms.prg      ← Data entry forms
│       ├── browse.prg     ← Browse/display functions
│       └── console.prg    ← Console I/O utilities
├── data/
│   ├── customers.dbf      ← Customer table
│   ├── customers.cdx      ← Customer indexes
│   ├── sales.dbf          ← Sales table
│   └── sales.cdx          ← Sales indexes
├── config/
│   └── app.ini            ← Application configuration
├── logs/
│   └── app.log            ← Application log file
├── backups/               ← Backup storage directory
├── include/
│   └── defines.ch         ← Constant and type definitions
├── Makefile (hbmk2)       ← Build script
└── README.md              ← Project documentation
```

#### B.3 Harbour Command Reference for RDD Operations

| Category       | Harbour/RDD Functions Used                                              |
| -------------- | ----------------------------------------------------------------------- |
| **Table Mgmt** | `USE`, `USE IN`, `USE ALL`, `CLOSE ALL`, `DBCreate()`, `DbAlter()`     |
| **Record Ops** | `APPEND BLANK`, `INSERT INTO`, `DELETE`, `RECALL`, `PACK`, `GO TOP`, `SKIP`, `GO TO` |
| **Field Ops**  | `FIELDGET()`, `FIELDPUT()`, `REPLACE`, `DBEval()`                       |
| **Search**     | `SEEK()`, `FIND()`, `DbGoTo()`, `DBSeek()`, `LOCATE FOR`, `CONTINUE`   |
| **Indexing**   | `INDEX ON`, `CREATE INDEX`, `SET ORDER TO`, `DbReindex()`, `TagCount()`|
| **Transactions**| `DBBegin()`, `DBCommit()`, `DBRollback()`, `DBInTransaction()`          |
| **Info**       | `RecCount()`, `Eof()`, `Bof()`, `RecNo()`, `DbUseArea()`, `DbCloseArea()` |
| **Validation** | `DbEval()`, `DbSetFilter()`, `DbSetOrder()`, `DbGotop()`               |

---

## End of Document

*This Software Requirements Specification is a living document. All changes SHALL be tracked through the revision history and approved by the project's change control board.*
