# Software Requirements Specification
## For HIX-Harbour Web Application System

Version 1.0  
Prepared by Jack (Software Architect)  
HIX-Harbour Project  

## Table of Contents
<!-- TOC -->
* [1. Introduction](#1-introduction)
    * [1.1 Document Purpose](#11-document-purpose)
    * [1.2 Product Scope](#12-product-scope)
    * [1.3 Definitions, Acronyms, and Abbreviations](#13-definitions-acronyms-and-abbreviations)
    * [1.4 References](#14-references)
    * [1.5 Document Overview](#15-document-overview)
* [2. Product Overview](#2-product-overview)
    * [2.1 Product Perspective](#21-product-perspective)
    * [2.2 Product Functions](#22-product-functions)
    * [2.3 Product Constraints](#23-product-constraints)
    * [2.4 User Characteristics](#24-user-characteristics)
    * [2.5 Assumptions and Dependencies](#25-assumptions-and-dependencies)
    * [2.6 Apportioning of Requirements](#26-apportioning-of-requirements)
* [3. Requirements](#3-requirements)
    * [3.1 External Interfaces](#31-external-interfaces)
        * [3.1.1 User Interfaces](#311-user-interfaces)
        * [3.1.2 Hardware Interfaces](#312-hardware-interfaces)
        * [3.1.3 Software Interfaces](#313-software-interfaces)
    * [3.2 Functional](#32-functional)
    * [3.3 Quality of Service](#33-quality-of-service)
        * [3.3.1 Performance](#331-performance)
        * [3.3.2 Security](#332-security)
        * [3.3.3 Reliability](#333-reliability)
        * [3.3.4 Availability](#334-availability)
        * [3.3.5 Observability](#335-observability)
    * [3.4 Compliance](#34-compliance)
    * [3.5 Design and Implementation](#35-design-and-implementation)
        * [3.5.1 Installation](#351-installation)
        * [3.5.2 Build and Delivery](#352-build-and-delivery)
        * [3.5.3 Distribution](#353-distribution)
        * [3.5.4 Maintainability](#354-maintainability)
        * [3.5.5 Reusability](#355-reusability)
        * [3.5.6 Portability](#356-portability)
* [4. Verification](#4-verification)
* [5. Appendixes](#5-appendixes)
<!-- TOC -->

## Revision History

| Name | Date | Reason For Changes | Version |
|------|------|--------------------|---------|
| Jack | 2025-01-01 | Initial SRS draft | 1.0 |

---

## 1. Introduction
💬 _Provides an overview of the document and orients the reader to the system being specified._

This SRS defines the complete set of requirements for a web application system built exclusively on the **HIX Web Server** framework (v2.2 Audit Edition) with **Harbour RDD** (`DBFCDX` / `DBFNTX`) as the sole data access layer. The system provides a production-grade, MVC-structured web platform using xBase/Clipper heritage technologies for record-oriented data management — no SQL databases are used or permitted.

➥ This document specifies what the system shall do, not how it will be implemented in detail. It is intended for product managers, engineers, QA testers, and operations staff who need a complete understanding of the system's capabilities, constraints, and verification criteria. Related documents include the HIX official documentation (https://carles9000.github.io/hix/) and the Harbour Project reference (https://harbour.github.io).

### 1.1 Document Purpose
💬 _Clarifies why this SRS exists, what it contains, and who should use it._

This Software Requirements Specification exists to define the complete functional, non-functional, and implementation requirements for a web application built on the HIX framework with Harbour RDD data access. The primary audiences are:

- **Product Managers**: To understand the system's capabilities and constraints defined by the HIX/Harbour technology stack.
- **Engineering Teams**: To implement controllers, models (UDbf), views (Mambo), and middlewares within the established architecture.
- **QA/Test Engineers**: To derive test cases from verifiable requirements with unique identifiers.
- **Security Auditors**: To verify compliance with HIX's built-in security mechanisms (JWT, CSRF, CORS, firewall).
- **Operations Staff**: To understand deployment topology, monitoring via metrics, and log rotation capabilities.

💡 The SRS defines what the system must do; implementation details are governed by the HixStyle MVC conventions and Harbour RDD mechanics described herein.

### 1.2 Product Scope
💬 _Defines the software product's purpose, boundaries, and relationship to business goals._

The product is a **HIX-Harbour Web Application System** — a full-stack web application that serves both traditional HTML pages (via the Mambo view engine) and RESTful JSON APIs from a single codebase. The system manages record-oriented data stored exclusively in DBF files with CDX/NTX structural indexes, accessed through Harbour's RDD mechanism.

**Inclusions:**
- MVC architecture via HixStyle mode (`hixstyle.enabled = true`)
- DBF table management (CRUD) via the UDbf wrapper over `DBFCDX` RDD
- Session-based authentication and/or JWT-based stateless API authentication
- CSRF protection, CORS handling, rate limiting, and IP firewall
- Real-time communication via WebSocket, Server-Sent Events (SSE), and Long Polling
- Centralized logging with rotation and CLF access log
- In-memory metrics exposed at `/hix-status`
- Template rendering via the Mambo view engine with caching
- Harbour Core ONLY for RDDCDX database management

**Exclusions:**
- SQL database access (no `RDDSQL`, no ODBC, no JDBC)
- External ORM frameworks
- Non-Harbour backends for data persistence
- Microservice mesh or service discovery protocols

### 1.3 Definitions, Acronyms, and Abbreviations

| Term | Definition |
|------|------------|
| **CDX** | Clipper/DBase multi-tag index file format used by Harbour RDD |
| **DBF** | dBASE table file format — the core data storage format |
| **HIX** | HIX Web Server — a lightweight web server built on Harbour/xBase |
| **Harbour** | Portable, xBase-compatible programming language and development environment |
| **Mambo** | HIX's internal template/view engine for HTML rendering |
| **MVC** | Model-View-Controller architectural pattern implemented by HixStyle |
| **RDD** | Runtime Data Driver — Harbour's mechanism for data source abstraction (DBFCDX, DBFNTX, etc.) |
| **UDbf** | HIX-style wrapper class over the `HIX_DBF` class providing hash-oriented DBF access |
| **xBase** | The family of programming languages and file formats originating from dBASE |
| **API** | Application Programming Interface — a set of definitions for software integration |
| **SRS** | Software Requirements Specification |
| **UI** | User Interface — the visual part through which users interact with software |
| **JWT** | JSON Web Token — stateless authentication mechanism (HMAC-SHA256) |
| **CSRF** | Cross-Site Request Forgery protection mechanism |
| **SSE** | Server-Sent Events — unidirectional server-to-client streaming |
| **CLF** | Common Log Format — Apache-style access log format |

### 1.4 References

| Reference | Author/Owner | Version | Date | Location | Status |
|-----------|-------------|---------|------|----------|--------|
| HIX Web Server Documentation | carles9000 | v2.2 | 2026 | https://carles9000.github.io/hix/ | Normative |
| HIX Source Repository | carles9000 | main | 2026 | https://github.com/carles9000/hix | Normative |
| Harbour Project Documentation | The Harbour Project | 3.4+ | 2025 | https://harbour.github.io | Normative |
| Harbour Core Repository | harbour/core | main | 2025 | https://github.com/harbour/core | Informative |
| SRS Template | jam01 | master | — | https://github.com/jam01/SRS-Template | Informative |
| DBFCDX RDD Source | harbour/core (src/rdd/dbfcdx) | — | — | Local: `$HB_ROOT/src/rdd/dbfcdx` | Normative |

### 1.5 Document Overview
💬 _Brief guide to the structure of the SRS so readers can quickly find what they need._

Section 2 (Product Overview) provides context about the HIX-Harbour system, its place within the web application ecosystem, and the constraints imposed by the technology stack. Section 3 (Requirements) specifies all verifiable requirements organized by external interfaces, functional behavior, quality of service, compliance, and design constraints. Section 4 (Verification) maps each requirement to a verification method. Appendixes in Section 5 provide supporting material including data dictionaries and architectural diagrams.

---

## 2. Product Overview
💬 _Provides background and context influencing the product's requirements._

### 2.1 Product Perspective
💬 _Places the product within a larger ecosystem or lineage._

The HIX-Harbour system is a self-contained web application server that combines:

1. **HIX Web Server** as the HTTP engine, request dispatcher, and MVC framework.
2. **Harbour RDD (DBFCDX/DBFNTX)** as the exclusive data persistence layer for record-oriented storage.

The product replaces traditional SQL-based web applications with a file-based, xBase heritage architecture. It is designed for mid-tier business applications — inventory management, order processing, customer relationship systems, and internal dashboards — where data volumes fit comfortably within DBF file constraints (multi-gigabyte tables with structural indexes).

**Relationship to external systems:**
- The system may sit behind an Apache/Nginx reverse proxy for TLS termination and load balancing.
- Static assets are served directly from the `public/` directory.
- No external database servers, message queues, or cache services are required.

### 2.2 Product Functions
💬 _High-level summary of what the product enables users or systems to do._

The system provides the following major functional areas:

1. **Web Application Serving** — Render HTML pages via the Mambo view engine with template inheritance, conditional directives (`@if`, `@foreach`), and automatic XSS escaping.
2. **REST API Delivery** — Return JSON responses for mobile apps and single-page applications, sharing the same models and middleware as HTML routes.
3. **DBF Data Management** — Full CRUD operations on DBF tables with CDX indexes via the UDbf wrapper: `Insert()`, `GetRecno()`, `GetId()`, `Update()`, `Delete()`, `LoadAll()`, `Page()`, with field-level visibility control and UTF-8 conversion.
4. **User Authentication** — Dual authentication model: session-based (with CSRF) for traditional web flows, and JWT (HMAC-SHA256) for stateless API access. Role-based authorization via `HIX_MwHasRole` and scope-based authorization via `HIX_MwJwtScope`.
5. **Request Validation** — Declarative validation rules (`required`, `string`, `number`, `date`, `max:`, `min:`) with the validator middleware, supporting both form POST and JSON body input.
6. **Real-Time Communication** — WebSocket (bidirectional), Server-Sent Events (unidirectional streaming), and Long Polling via dedicated worker pools (`pool_ws`, `pool_rest`).
7. **Security Middleware Chain** — CSRF tokens (`HIX_MwCsrf` / `HIX_MwCsrfCheck`), CORS headers, rate limiting per IP, IP firewall (blacklist/whitelist by CIDR), body size limits, and HTTP security hardening headers.
8. **Observability** — Centralized logging with severity levels and rotation, CLF access log, in-memory metrics counters, boot log for startup diagnostics, and a `/hix-status` admin endpoint.

### 2.3 Product Constraints
💬 _Defines contextual limitations or conditions shaping design and implementation._

The system is bound by the following mandatory constraints:

1. **C-001**: The application server shall be HIX Web Server (v2.2 Audit Edition) exclusively. No other web server framework shall be used.
2. **C-002**: Data access shall use Harbour RDD exclusively — specifically `DBFCDX` or `DBFNTX`. SQL-based data access (`RDDSQL`, ODBC, JDBC) is strictly prohibited.
3. **C-003**: The application shall follow the HixStyle MVC architecture with `hixstyle.enabled = true` in `hix.json`, enforcing the folder structure: `routes/`, `controllers/`, `models/`, `views/`, `middlewares/`, `loaders/`, `public/`, and `errors/`.
4. **C-004**: All data shall be stored in `.dbf` files with associated `.cdx` (or `.ntx`) index files on the local filesystem. No external database servers shall be deployed or connected to.
5. **C-005**: Template rendering shall use HIX's built-in Mambo view engine exclusively. No third-party template engines are permitted.
6. **C-006**: Route definitions in HixStyle mode shall be declared as JSON files in the `routes/` directory, following the schema: `{ "name", "url", "method", "action", "middleware", "scope" }`.
7. **C-007**: Authentication shall use either session-based (with `HIX_MwSession`, `HIX_MwCsrf`) or JWT-based (`HIX_MwJwt`, `HIX_JwtEncode`/`HIX_JwtValidate`) mechanisms provided by HIX. No custom authentication schemes are permitted.
8. **C-008**: The system shall be written in Harbour programming language (`.prg` source files), compiled via `hbmk2` or the HIX on-the-fly compiler for `.prg` route files.
9. **C-009**: SSL/TLS termination shall either be handled directly by HIX (`server.ssl = true`) or by a reverse proxy in `mode = "proxied"` with `X-Forwarded-*` header support.
10. **C-010**: The application must be compatible with both Linux (GCC) and Windows (MSVC/MINGW64) as supported by the HIX build system.

### 2.4 User Characteristics
💬 _Defines the user groups and the attributes that affect requirements._

| User Class | Expertise | Access Level | Goals | Frequency of Use |
|------------|-----------|-------------|-------|-----------------|
| **End User** | Basic computer literacy | Standard session-authenticated web UI | View and edit records, submit forms, navigate pages | Daily / multiple times per day |
| **API Consumer** | Software developer | JWT or API key authenticated | Consume REST JSON endpoints for mobile/web clients | Continuous (automated) |
| **Administrator** | System administration knowledge | Admin panel (`/hix-*` routes), server config access | Monitor metrics, review logs, manage configuration, deploy updates | Weekly / as needed |
| **Developer** | Harbour/HIX programming | Full source code and build environment access | Implement controllers, models, views, middlewares; debug and extend | Daily |

**Accessibility considerations:** Mambo templates shall produce semantic HTML5. Form inputs shall use proper `label` elements. Error messages from the validator shall be human-readable with field labels defined in the validation rules.

### 2.5 Assumptions and Dependencies
💬 _External assumed factors or conditions, as opposed to known facts, that the project relies on._

| # | Assumption / Dependency | Impact if False |
|---|------------------------|-----------------|
| A-01 | DBF file system operations remain fast for tables up to ~10 million records with CDX indexes. | Performance degrades; pagination and search become unusably slow. |
| A-02 | The server runs on a machine with sufficient disk I/O bandwidth for concurrent DBF reads/writes. | Record locking contention increases; `Rlock()` timeout failures rise. |
| A-03 | Harbour RDD `DBFCDX` supports the required field types: Character (C), Numeric (N), Logical (L), Date (D), and Memo (M). | New data types cannot be persisted without custom RDD extensions. |
| A-04 | The HIX server runs as a single process with thread-based worker pools (`pool_http`, `pool_ws`). | Multi-process deployment requires file-based sessions (`storage = "file"`) and session affinity via load balancer stickysession. |
| A-05 | SSL certificates are available (Let's Encrypt, self-signed for dev) and renewed automatically. | HTTPS cannot be enabled; data travels in plaintext. |
| A-06 | The `hbmk2` compiler is available in the build environment for compiling `.prg` files into `.hrb` libraries. | Build pipeline fails; on-the-fly compilation by HIX becomes the only option (slower startup). |

### 2.6 Apportioning of Requirements
💬 _Allocation of requirements across components or increments._

| Requirement Area | Component / Layer | Section Reference |
|-----------------|-------------------|-------------------|
| HTTP Serving & Routing | HIX Server (`THixServer`) | REQ-FUNC-001 through REQ-FUNC-004 |
| MVC Architecture | HixStyle Engine | REQ-FUNC-005 through REQ-FUNC-007 |
| Data Access (DBF/CDX) | Harbour RDD + UDbf wrapper | REQ-FUNC-010 through REQ-FUNC-016 |
| Authentication & Authorization | HIX Middleware Chain | REQ-FUNC-020 through REQ-FUNC-025 |
| View Rendering | Mambo Engine | REQ-FUNC-030 through REQ-FUNC-032 |
| Validation | HIX Validator | REQ-FUNC-035 through REQ-FUNC-037 |
| Real-Time (WS/SSE/LP) | HIX Worker Pools | REQ-FUNC-040 through REQ-FUNC-042 |
| Security Headers & Firewall | HIX Middleware Chain | REQ-SEC-001 through REQ-SEC-008 |
| Logging & Metrics | HIX Logger + Monitor | REQ-OBS-001 through REQ-OBS-005 |
| Performance | Thread Pools + RDD Optimizations | REQ-PERF-001 through REQ-PERF-004 |

---

## 3. Requirements
💬 _This section specifies **verifiable** requirements of the software product to enable design and testing._

### 3.1 External Interfaces

#### 3.1.1 User Interfaces

- **ID**: REQ-INT-UI-001
- **Title**: Mambo Template Rendering
- **Statement**: The system shall render all HTML user interfaces using the HIX Mambo view engine, which supports `{{ var }}` macro substitution with automatic XSS escaping, `@if`/`@else`/`@endif` conditional directives, `@foreach ... @endforeach` loop directives, template inheritance via layout files, and explicit `@args` parameter declarations.
- **Rationale**: Mambo provides the only view rendering mechanism available within the HIX framework, ensuring consistent HTML generation with built-in security against XSS attacks.
- **Acceptance Criteria**:
  - A `.view.html` file in the `views/` directory containing `{{ variable }}` expressions renders interpolated values from the controller.
  - Variables rendered via `{{ }}` are automatically HTML-escaped (e.g., `<` becomes `&lt;`).
  - Raw HTML injection is possible only via `{!! !!}` syntax.
  - Template inheritance works: a base layout file extends child views via Mambo's inclusion mechanism.
  - Views compile to cached `.hrb` files on first render and are recompiled only when the source `.view.html` is modified (when `hixstyle.cache_disk = true`).
- **Verification Method**: Test
- **More Information**: See HIX documentation: Mambo View Engine (https://carles9000.github.io/hix/hixstyle/views/mambo.html).

- **ID**: REQ-INT-UI-002
- **Title**: Form Input and Validation Feedback
- **Statement**: The system shall render HTML form inputs populated from validated data hashes, display validation error messages per field with human-readable labels, and support flash message display (success/danger types) across POST/Redirect/GET cycles.
- **Rationale**: xBase heritage applications require robust form handling with immediate user feedback on data entry errors.
- **Acceptance Criteria**:
  - Form `<input>` elements are populated from `oVal:Resume()` hash values returned via flash storage.
  - Validation error messages reference the human label defined in the extended rule format `{ "rules", "Label", "default" }`.
  - Flash messages set via `UFlash("formId"):Set({...})` persist across a single redirect and are consumed on the next GET request.
  - Form fields marked with `|field` suffix in validation rules are included in `oVal:DataFields()` for direct feeding into `UDbf:Update()`.
- **Verification Method**: Test
- **More Information**: See HIX documentation: Validator (https://carles9000.github.io/hix/hixstyle/controllers/validator.html).

- **ID**: REQ-INT-UI-003
- **Title**: Signed Resource IDs in Forms
- **Statement**: The system shall embed signed resource identifiers in edit/delete form action URLs using `UGetResource()` to prevent manual HTML modification of record IDs by end users.
- **Rationale**: Prevents IDOR (Insecure Direct Object Reference) attacks where users manipulate URL parameters to access unauthorized records.
- **Acceptance Criteria**:
  - Edit and delete forms use `UGetResource()` to obtain a signed identifier for the target record.
  - The controller reads the signed resource via `UGetResource()` in the POST handler and verifies its integrity.
  - Tampered URLs produce a validation failure that triggers a redirect with an error flash message.
- **Verification Method**: Test

#### 3.1.2 Hardware Interfaces

- **ID**: REQ-INT-HW-001
- **Statement**: The system shall run on standard x86_64 or ARM64 hardware with no specialized hardware requirements beyond those needed to run the Harbour runtime and the HIX server process.
- **Rationale**: HIX is a pure software HTTP server; it has no dependency on GPUs, TPMs, or custom I/O devices.
- **Acceptance Criteria**: The system boots and serves requests on any machine meeting the minimum OS requirements (Linux with glibc 2.17+, Windows 10+).
- **Verification Method**: Demonstration

#### 3.1.3 Software Interfaces

- **ID**: REQ-INT-SW-001
- **Statement**: The system shall use Harbour `DBFCDX` or `DBFNTX` RDD exclusively for all data persistence operations. No SQL, ODBC, JDBC, or external database drivers shall be linked or loaded.
- **Rationale**: Constraint C-002 mandates RDD-only data access; this requirement enforces it at the implementation level.
- **Acceptance Criteria**:
  - The application calls `RDDSETDEFAULT( "DBFCDX" )` (or `DBFNTX`) during initialization.
  - All table operations use Harbour xBase commands: `USE`, `APPEND`, `EDIT`, `DELETE`, `RECALL`, `PACK`, `ZAP`, `DbGoTop`, `DbGoBottom`, `DbSkip`, `DbSeek`, `DbGoTo`, `Rlock()`, `FieldGet()`, `FieldPut()`.
  - The UDbf wrapper class (`www/models/txxx.prg`) configures `cRdd := "DBFCDX"` and calls `oDbf:Open()` which internally invokes Harbour's RDD layer.
  - No reference to `RDDSQL`, `hb_fbird`, `hb_mssql`, or any SQL-related Harbour library exists in the application source code.
- **Verification Method**: Inspection
- **More Information**: See HIX documentation: UDbf (https://carles9000.github.io/hix/hixstyle/models/udbf.html).

- **ID**: REQ-INT-SW-002
- **Statement**: The system shall expose an in-memory metrics API at the `/hix-status` endpoint returning a JSON object with atomic counters for requests, errors, active connections, bytes transferred, latency percentiles, memory usage, uptime, and view cache statistics.
- **Rationale**: The HIX framework provides built-in metrics via `HIX_Metric*` helpers and a monitor thread; the system shall leverage this for operational visibility.
- **Acceptance Criteria**:
  - A GET request to `/hix-status` returns HTTP 200 with a JSON body containing at minimum: `requests`, `errors`, `activehttp`, `bytesin`, `bytesout`, `uptimesec`, `memused`, `mempeak`, `req_ms_max`, `req_ms_avg`.
  - The response includes `req_slowest_dyn` (top-N slowest dynamic routes) and `req_slowest_stat` (top-N slowest static assets).
  - In production mode (`env = "prod"`), the endpoint requires admin authentication via signed `hix_admin` cookie.
- **Verification Method**: Test

- **ID**: REQ-INT-SW-003
- **Statement**: The system shall support WebSocket connections for bidirectional real-time communication, SSE for unidirectional server-to-client streaming, and Long Polling as a fallback mechanism, each served by dedicated worker pools defined in `hix.json`.
- **Rationale**: HIX provides built-in WebSocket (`pool_ws`), SSE, and Long Polling (`pool_rest`) support; the system shall utilize these for real-time features.
- **Acceptance Criteria**:
  - WebSocket connections are handled via `oSrv:bOnWsConnect`, `oSrv:bOnWsMessage`, and `oSrv:bOnWsClose` callbacks with message opcodes: 1 (text), 2 (binary), 8 (close), 9 (ping), 10 (pong).
  - Ping/pong keepalive operates per `pool_ws.ping_interval_s` and `pool_ws.ping_timeout_s` configuration.
  - SSE streams are initiated via `USendStreamStart( "text/event-stream" )` with chunked delivery via `USendChunk()`.
  - Maximum concurrent connections are bounded by `pool_ws.workers` (WebSocket) and `pool_rest.workers_sse` / `pool_rest.workers_longpoll` (SSE/Long Poll).
- **Verification Method**: Test

### 3.2 Functional

- **ID**: REQ-FUNC-001
- **Title**: HTTP Request Routing
- **Statement**: The system shall route incoming HTTP requests to the appropriate controller action by matching the URL pattern and HTTP method against routes defined in JSON files under the `routes/` directory, evaluating routes in order of specificity (literal segments score 10, variable parameters score 1).
- **Rationale**: HIX's router evaluates routes by specificity; this requirement formalizes that behavior as a system obligation.
- **Acceptance Criteria**:
  - A GET request to `/users/profile` is matched before `/users/:id`.
  - Variable parameters (`:id`) are accessible via `UParam("id")` in the controller.
  - Regex-constrained parameters (`:id([0-9]+)`) reject non-matching values (e.g., `/users/abc` does not match).
  - Optional parameters (`:section!`) default to empty string when absent.
  - Wildcard routes (`/static/*`) match any path prefix.
  - Route groups apply a common URL prefix and middleware to all contained routes.
- **Verification Method**: Test

- **ID**: REQ-FUNC-002
- **Title**: Controller Execution Lifecycle
- **Statement**: The system shall execute the controller lifecycle in the following order for each request: (1) Router matches URL + method, (2) Middleware chain executes sequentially and may reject the request, (3) Controller collects data via `U*` helpers, validates input, processes business logic through models, and produces output, (4) HTTP response is sent.
- **Rationale**: HixStyle enforces a strict MVC flow; this requirement ensures controllers follow the prescribed pattern.
- **Acceptance Criteria**:
  - Middleware that returns `.F.` prevents controller execution; the request is terminated at that middleware level.
  - Controllers use `UParam()`, `UGet()`, `UPost()`, `UJson()`, `UHeader()`, `UCookie()`, `UFiles()`, and `USession()` helpers — never direct access to an `oReq` object in codeblocks.
  - POST actions that modify data always end with `URedirect( URoute(...) )` (PRG pattern), never returning HTML directly.
  - JSON API endpoints return responses via `USendJson()` or `USendError()`.
- **Verification Method**: Test | Demonstration

- **ID**: REQ-FUNC-003
- **Title**: Data-Driven Route Configuration
- **Statement**: The system shall load all `.json` files from the `routes/` directory at server startup, parsing each as an array of route objects with fields: `name` (required), `url` (required), `method` (optional, default `"*"`), `action` (required), `middleware` (optional), and `scope` (optional).
- **Rationale**: HixStyle's data-driven configuration enables hot-reloading of routes in development mode without recompiling the server.
- **Acceptance Criteria**:
  - A file `routes/users.json` containing route definitions is automatically loaded on `THixServer:Start()`.
  - Route names are globally unique; duplicate names cause a startup error and prevent the server from starting.
  - The `action` field may reference: a `.prg` file, an `.hrb` precompiled file, a class method (`method@class.prg`), or an `.html` view template.
  - In development mode, routes can be reloaded via `GET /hix-routes/reload` without server restart.
- **Verification Method**: Test

- **ID**: REQ-FUNC-004
- **Title**: Middleware Chain Execution
- **Statement**: The system shall execute middleware functions in the order specified (comma-separated) before the route action. Each middleware receives a context object (`oCtx`) and returns `.T.` to continue or `.F.` to terminate the request with an appropriate HTTP status code.
- **Rationale**: HIX's middleware architecture is the primary mechanism for cross-cutting concerns (auth, CSRF, CORS, rate limiting).
- **Acceptance Criteria**:
  - Multiple middlewares are specified as `"HIX_MwSession,HIX_MwCsrfCheck,HIX_MwIsAuth"` and execute sequentially.
  - A middleware that rejects the request sets `oCtx:lHandled = .T.` and returns `.F.`; subsequent middlewares and the action do not execute.
  - The system includes all built-in HIX middlewares: `HIX_MwSecHeaders`, `HIX_MwCors`, `HIX_MwBodyLimit`, `HIX_MwRateLimit`, `HIX_MwSession`, `HIX_MwJwt`, `HIX_MwRequireAuth`, `HIX_MwCsrf`, `HIX_MwCsrfCheck`, `HIX_MwMaintenance`.
- **Verification Method**: Test | Inspection

- **ID**: REQ-FUNC-010
- **Title**: DBF Table Open and Structure Discovery
- **Statement**: The system shall open DBF tables via the UDbf wrapper, which internally calls Harbour's RDD layer to load the table structure into `hFields` (a hash mapping field names to `{name, type, len, dec}` descriptors) and set the connection flag `lConnect = .T.`.
- **Rationale**: The UDbf class encapsulates all xBase mechanics behind a modern hash-oriented API; this requirement ensures proper table initialization.
- **Acceptance Criteria**:
  - Calling `oDbf:Open()` returns `.T.` on success and sets `oDbf:lConnect = .T.`.
  - The `hFields` hash is populated with structure information for each visible field.
  - If the `.dbf` file is missing or the specified index tag does not exist, `SetError()` is called and `.F.` is returned.
  - The model function returns a configured UDbf instance: `oDbf:cPath`, `oDbf:cDbf`, `oDbf:cCdx`, `oDbf:cTag` are set before `Open()`.
- **Verification Method**: Test

- **ID**: REQ-FUNC-011
- **Title**: Record Insertion
- **Statement**: The system shall insert new records into a DBF table via `UDbf:Insert(hFields, @cError, @nNewRecno)`, which performs an `APPEND BLANK` followed by `FieldPut()` for each key-value pair in the hash, then commits the record.
- **Rationale**: UDbf's `Insert()` method provides a single-call atomic insert operation returning the new record number.
- **Acceptance Criteria**:
  - `Insert()` returns `.T.` on success; the hash `hFields` keys become field values in the new record.
  - On failure, `@cError` is populated with the error description and `.F.` is returned.
  - On success, `@nNewRecno` contains the physical record number of the newly inserted record.
  - Fields not present in the hash retain their default values (empty string for Character, 0 for Numeric, etc.).
- **Verification Method**: Test

- **ID**: REQ-FUNC-012
- **Title**: Record Retrieval by Recno or Index Key
- **Statement**: The system shall retrieve records from a DBF table via `UDbf:GetRecno(nRecno, @hRow)` for physical record number lookup and `UDbf:GetId(cKey, @hRow)` for index-key-based lookup, both returning `.T.` on success and populating the output hash.
- **Rationale**: Both recno-based and index-based lookups are essential for different access patterns (primary key vs. alternate key searches).
- **Acceptance Criteria**:
  - `GetRecno()` positions the record pointer at the specified physical record number and returns all visible fields as a hash in `@hRow`.
  - `GetId()` performs a `DbSeek()` on the active index (or a specified tag) and returns the matching record.
  - The returned hash always includes `_recno` (physical record number) and `_deleted` (deletion mark status).
  - When `lToStringWeb = .T.` is passed, Date fields serialize to `"YYYY-MM-DD"`, Logical fields return `"checked"` or `""`, and Numeric fields are formatted with proper decimal places.
- **Verification Method**: Test

- **ID**: REQ-FUNC-013
- **Title**: Record Update with Record Locking
- **Statement**: The system shall update existing records via `UDbf:Update(nRecno, hChanges, @cError)`, which acquires a record lock (`Rlock()`), applies `FieldPut()` for each key in the changes hash, commits the change, and releases the lock.
- **Rationale**: Concurrent access to DBF tables requires explicit record-level locking to prevent data corruption.
- **Acceptance Criteria**:
  - `Update()` internally calls `Rlock()` which retries up to `oDbf:nTime` seconds (default 3s) before failing.
  - On lock failure, `@cError` contains `"DBF_ERR_LOCK"` and `.F.` is returned.
  - On success, only the fields specified in `hChanges` are modified; all other fields retain their existing values.
  - The record is automatically unlocked via `DbUnlock()` after the update commits.
- **Verification Method**: Test

- **ID**: REQ-FUNC-014
- **Title**: Record Deletion and Recovery
- **Statement**: The system shall support soft deletion (`UDbf:Delete(nRecno)`), record recovery (`UDbf:Delete(nRecno, .T.)` to toggle), permanent removal via `Pack()`, and table truncation via `Zap()` (exclusive mode only).
- **Rationale**: Business applications often require soft-delete semantics for audit trails while supporting full purge operations.
- **Acceptance Criteria**:
  - `Delete(nRecno)` marks the record with a deletion mark (`_deleted = .T.`); the record is excluded from `LoadAll()` and `Page()` results.
  - `Delete(nRecno, .T.)` toggles the deletion state (recalls if deleted, deletes if not).
  - `Recall()` removes the deletion mark from the current record pointer position.
  - `Pack(@cError)` physically removes all deleted records; requires exclusive table access.
  - `Zap()` empties the entire table; requires exclusive access and produces no undo capability.
- **Verification Method**: Test

- **ID**: REQ-FUNC-015
- **Title**: Record Listing with Pagination
- **Statement**: The system shall retrieve record sets via `UDbf:LoadAll([aFields], [cScopeTop], [cScopeBottom], [bCondition])` for full listing and `UDbf:Page(nPage, nRows, aFields, @nTotalPages)` for paginated results with total page count returned by reference.
- **Rationale**: Web applications require both complete data listings (with optional scope filtering) and paginated views for large datasets.
- **Acceptance Criteria**:
  - `LoadAll()` returns an array of hashes, one per record, with field selection via the optional `aFields` parameter.
  - Scope filtering via `cScopeTop` and `cScopeBottom` limits results to records whose key values fall within the specified range.
  - A codeblock condition (`bCondition`) filters records at the RDD level (e.g., `{|a| !Deleted() }`).
  - `Page()` calculates `nTotalPages` by rounding up `RecCount() / nRows`, relocates to the correct record position using `OrdKeyGoto()` when an index is active, and returns the page's records.
  - If `nPage > nTotalPages`, the function relocates to the last available page.
- **Verification Method**: Test

- **ID**: REQ-FUNC-016
- **Title**: Field Visibility Control
- **Statement**: The system shall restrict which fields are exposed in record hashes via `UDbf:Hide(aFields)` (blacklist) and `UDbf:Visible(aFields)` (whitelist), applied before `Open()` to trim the `hFields` structure.
- **Rationale**: Sensitive fields (passwords, salaries, internal keys) must never reach templates or JSON responses; field visibility is a security requirement.
- **Acceptance Criteria**:
  - `Hide("salary")` excludes the `salary` field from all subsequent `Row()`, `LoadAll()`, and `Page()` results.
  - `Visible({"id", "name"})` includes only those fields; all others are excluded.
  - Field visibility settings must be applied before `Open()` takes effect on `hFields`.
  - The `_recno` and `_deleted` control fields are always present regardless of visibility settings.
- **Verification Method**: Test

- **ID**: REQ-FUNC-020
- **Title**: Session-Based Authentication
- **Statement**: The system shall manage user sessions using `HIX_MwSession`, storing session data in memory (`storage = "memory"`) or on disk (`storage = "file"`), with configurable lifetime, garbage collection, and optional encryption via a seed key.
- **Rationale**: Session-based authentication is the canonical pattern for traditional web applications with login forms and CSRF protection.
- **Acceptance Criteria**:
  - The session cookie name is configurable (default `"HIXSID"`); the cookie carries `HttpOnly; SameSite=Lax` flags.
  - Session data is accessible via `USession("key")` for reads and `USession():Set("key", value)` / `USession():Save()` for writes.
  - `storage = "file"` persists sessions to disk in the configured directory with file prefix; sessions survive server restarts.
  - `storage = "memory"` stores sessions in process RAM; sessions are lost on restart.
  - `crypt = true` encrypts session files using the provided seed key via `HIX_MwSessionSetup`.
  - `USession():Destroy()` erases all session data and expires the cookie.
- **Verification Method**: Test

- **ID**: REQ-FUNC-021
- **Title**: JWT-Based Stateless Authentication
- **Statement**: The system shall issue and validate JSON Web Tokens using HMAC-SHA256 signing via `HIX_JwtEncode()` and `HIX_JwtValidate()`, with configurable secret key and expiration time, for stateless API authentication.
- **Rationale**: REST APIs and mobile clients require stateless authentication that scales horizontally without shared session storage.
- **Acceptance Criteria**:
  - `HIX_JwtEncode(hPayload)` produces a base64url-encoded token with standard claims: `iss` ("HIX"), `iat` (issue timestamp), `exp` (expiration), plus any custom claims in the input hash.
  - `HIX_JwtValidate(cToken)` returns the decoded payload hash on success or `NIL` if the signature is invalid or the token has expired.
  - The middleware `HIX_MwJwt` extracts the `Authorization: Bearer <token>` header, validates the token, and stores the payload in `oCtx:hData["jwt"]`.
  - Invalid or missing tokens result in HTTP 401 responses.
  - Multiple signing keys are supported via `HIX_MwJwtFactory(cKey)`.
- **Verification Method**: Test

- **ID**: REQ-FUNC-022
- **Title**: JWT Scope-Based Authorization
- **Statement**: The system shall enforce OAuth 2.0-style scope authorization via `HIX_MwJwtScope`, comparing the required scope from the route's `cScope` parameter against the `scope` claim in the JWT payload.
- **Rationale**: API endpoints need fine-grained access control beyond simple authentication; scopes provide operation-level granularity.
- **Acceptance Criteria**:
  - A route declared with `"scope": "read:products"` requires a JWT whose `scope` claim contains the token `read:products`.
  - Space-separated scope tokens in the JWT (e.g., `"read:products write:orders"`) grant access to both scopes.
  - Missing required scopes result in HTTP 403 responses.
  - Empty `cScope` on a route bypasses scope checking entirely.
  - `HIX_MwJwtScope` must appear after `HIX_MwJwt` in the middleware chain (order matters).
- **Verification Method**: Test

- **ID**: REQ-FUNC-023
- **Title**: Role-Based Authorization
- **Statement**: The system shall enforce role-based access control via `HIX_MwHasRole`, comparing the route's `cScope` parameter against user roles stored in the session or JWT payload.
- **Rationale**: Web applications need hierarchical role-based permissions (admin, editor, viewer) with operation-level granularity.
- **Acceptance Criteria**:
  - A route with `"scope": "admin:delete"` requires the authenticated user to have role `admin` with operation `delete`.
  - Full access is granted if the role value in `cScope` is empty (e.g., `"admin"`).
  - Granular operations are separated by semicolons in the scope string.
  - Missing or insufficient roles result in HTTP 403 responses.
  - Roles are read from `oCtx:hData["session"][_auth_user][roles_key]` or from the JWT payload, using the configurable `roles_key` (default `"roles"`).
- **Verification Method**: Test

- **ID**: REQ-FUNC-024
- **Title**: CSRF Protection for State-Mutating Requests
- **Statement**: The system shall protect all state-mutating HTTP methods (POST, PUT, DELETE, PATCH) against Cross-Site Request Forgery attacks using either session-based tokens (`HIX_MwCsrf`) or HMAC-signed stateless tokens (`HIX_MwCsrfCheck`).
- **Rationale**: CSRF protection is mandatory for any application that accepts state-mutating requests from browser contexts with automatic cookie transmission.
- **Acceptance Criteria**:
  - Safe methods (GET, HEAD, OPTIONS) always pass without token validation.
  - `HIX_MwCsrf` generates a random token per session on the first GET and validates it on unsafe methods against the session-stored `_csrf_token`.
  - `HIX_MwCsrfCheck` validates HMAC-signed tokens generated by `HIX_CsrfMakeToken()` or embedded via `UCsrfToHtml()` in templates, using the application key (`app_key`) as the HMAC secret.
  - Token validation checks both the `_csrf` form field and the `X-CSRF-Token` header.
  - Invalid or missing tokens result in HTTP 403 responses (JSON) or a redirect to a configured URL with a flash error message.
- **Verification Method**: Test

- **ID**: REQ-FUNC-025
- **Title**: API Key Authentication for Machine-to-Machine Communication
- **Statement**: The system shall authenticate machine-to-machine requests using static API keys via `HIX_MwApiKey`, validating the `X-Api-Key` header against a configured hash of allowed keys with O(1) lookup.
- **Rationale**: Internal services and partner integrations need simple, stateless authentication without the overhead of JWT signing/verification.
- **Acceptance Criteria**:
  - `HIX_MwApiKeySetup(aKeys)` configures the set of accepted API key strings.
  - A request with `X-Api-Key: svc-key-1` is authenticated if the key exists in the configured set.
  - Missing or invalid keys result in HTTP 401 responses.
  - The accepted key is exposed in `oCtx:hData["api_key"]` for downstream logging and auditing.
  - `HIX_MwApiKeyFactory(aKeys)` provides route-specific key sets.
- **Verification Method**: Test

- **ID**: REQ-FUNC-030
- **Title**: HTML Template Rendering
- **Statement**: The system shall render HTML templates using the Mambo view engine, supporting macro substitution (`{{ var }}`), control directives (`@if`, `@foreach`, `@for`), template inheritance, and automatic compilation with caching.
- **Rationale**: Mambo is HIX's built-in view engine; all HTML output must flow through it for consistency and security.
- **Acceptance Criteria**:
  - Controllers call `UView("path/view.html", arg1, arg2, ...)` to render templates.
  - Positional arguments are passed directly to the template's `@args` declaration.
  - Template files reside in the `views/` directory and use `.view.html` extension by convention.
  - Views are compiled to native code on first execution and cached in `.cached/views/` (disk cache) or shared RAM (RAM cache).
  - Cache invalidation occurs automatically when the source `.view.html` file is modified (detected by file timestamp).
- **Verification Method**: Test

- **ID**: REQ-FUNC-031
- **Title**: JSON API Response
- **Statement**: The system shall return JSON responses for REST API endpoints via `USendJson(hash, [nStatus])`, supporting standard HTTP status codes (200, 201, 204, 400, 401, 403, 404, 422, 500).
- **Rationale**: REST APIs require structured JSON responses with appropriate HTTP status semantics.
- **Acceptance Criteria**:
  - `USendJson({"id": 42, "name": "Carles"})` returns HTTP 200 with `Content-Type: application/json`.
  - `USendJson(hash, 201)` returns the specified status code (e.g., Created).
  - `USendEmpty()` returns HTTP 204 No Content (appropriate for successful DELETE operations).
  - `USendError(nStatus, cDetail)` returns an error JSON body with the specified status.
- **Verification Method**: Test

- **ID**: REQ-FUNC-035
- **Title**: Declarative Input Validation
- **Statement**: The system shall validate user input using declarative rule strings separated by `|`, supporting rules: `required`, `string`, `number`, `numeric`, `date`, `logic`, `email`, `min:N`, `max:N`, with field modifiers `|field`, `|escapedfield`, and `|resume`.
- **Rationale**: Input validation is a security prerequisite; declarative rules provide a concise, maintainable specification.
- **Acceptance Criteria**:
  - `UValidatePost(rules)` validates POST body data (form-encoded or JSON).
  - `UValidateParams(rules)` validates URL query string and route parameter data.
  - The extended rule format `{ "rules", "Label", "default" }` provides human-readable error messages and default values.
  - `oVal:Make()` runs all validation rules and returns `.T.` on success, `.F.` on failure.
  - `oVal:GetErrors()` returns a hash of field names to error message strings.
  - Fields marked with `|field` are collected in `oVal:DataFields()` for direct database update.
  - Fields marked with `|resume` are collected in `oVal:Resume()` for form repopulation on validation failure.
- **Verification Method**: Test

### 3.3 Quality of Service

#### 3.3.1 Performance

- **ID**: REQ-PERF-001
- **Title**: Request Latency
- **Statement**: The system shall process standard CRUD requests (single DBF read or write with index lookup) within 50ms under normal load, as measured by the HIX metrics `req_ms_avg` and `req_ms_max`.
- **Rationale**: xBase RDD operations on indexed DBF files are fast; 50ms provides a realistic target including network overhead.
- **Acceptance Criteria**:
  - Under steady-state conditions (up to 80% of `pool_http.workers` utilization), the average request latency (`req_ms_avg`) does not exceed 50ms for simple GET and POST operations.
  - The maximum recorded latency (`req_ms_max`) does not exceed 500ms for any single request under normal conditions.
  - Slowest requests are reported in `/hix-status` under `req_slowest_dyn` and can be investigated by route path.
- **Verification Method**: Test
- **More Information**: Performance measurement via HIX metrics system.

- **ID**: REQ-PERF-002
- **Title**: Concurrent Connection Handling
- **Statement**: The system shall handle up to `pool_http.workers` (default 64) concurrent HTTP requests, with a queue capacity of `pool_http.queue_size` (default 256) for pending connections.
- **Rationale**: HIX's thread pool architecture defines the concurrency boundary; this requirement formalizes those parameters as system obligations.
- **Acceptance Criteria**:
  - The system accepts and processes up to 64 simultaneous HTTP requests without dropping connections.
  - Requests beyond the worker capacity are queued (up to 256); excess connections are rejected with an appropriate HTTP status.
  - The monitor thread reports queue saturation via the `saturated` counter when utilization exceeds `monitor.alert_pct` (default 75%).
- **Verification Method**: Test

- **ID**: REQ-PERF-003
- **Title**: View Cache Hit Rate
- **Statement**: The system shall achieve a view cache hit rate of at least 95% for served views after an initial warm-up period, as reported by `vcache_hits` and `vcache_misses` in the metrics.
- **Rationale**: Mambo's compiled view caching is critical for rendering performance; high hit rates indicate stable templates.
- **Acceptance Criteria**:
  - After the first request to each unique view (cold start), subsequent requests serve from cache (`vcache_hits`).
  - The ratio `vcache_hits / (vcache_hits + vcache_misses)` is ≥ 0.95 during steady-state operation.
  - Cache misses occur only when a `.view.html` source file has been modified since the last compilation.
- **Verification Method**: Analysis

- **ID**: REQ-PERF-004
- **Title**: Record Lock Timeout
- **Statement**: The system shall acquire record locks via `UDbf:Rlock()` within 3 seconds by default, configurable per model instance via `oDbf:nTime`, before failing with a lock timeout error.
- **Rationale**: Concurrent update operations require bounded waiting; unbounded lock waits cause request timeouts and degraded user experience.
- **Acceptance Criteria**:
  - `Rlock()` retries internally for up to `nTime` seconds (default 3s) before returning `.F.`.
  - On timeout, the error description is set via `SetError(DBF_ERR_LOCK)` and propagated to the controller.
  - High-concurrency scenarios may increase `nTime` per model instance or implement retry logic at the controller level.
- **Verification Method**: Test

#### 3.3.2 Security

- **ID**: REQ-SEC-001
- **Title**: HTTPS Enforcement
- **Statement**: The system shall support SSL/TLS termination either directly via HIX (`server.ssl = true` with `cert_private` and `cert_public` configuration) or through a reverse proxy in `mode = "proxied"` with `X-Forwarded-Proto` header recognition.
- **Rationale**: Data in transit must be encrypted; HTTPS is mandatory for any system handling authentication, sessions, or sensitive data.
- **Acceptance Criteria**:
  - In direct TLS mode, HIX loads the private key and certificate from `paths.certs/` on startup and negotiates TLS connections on the configured port (conventionally 443).
  - In proxied mode, `server.ssl = false` and `server.mode = "proxied"` enable reading of `X-Forwarded-Proto`, `X-Forwarded-For`, and `X-Forwarded-Host` headers from the proxy.
  - The `UIsHttps()` helper returns `.T.` in both modes when the original request used HTTPS.
  - Self-signed certificates are acceptable for development; production must use certificates from a trusted CA (e.g., Let's Encrypt).
- **Verification Method**: Test | Inspection

- **ID**: REQ-SEC-002
- **Title**: HTTP Security Headers
- **Statement**: The system shall inject security hardening headers on every response via `HIX_MwSecHeaders`, including `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security` (HSTS), and a configurable `Content-Security-Policy`.
- **Rationale**: These headers mitigate clickjacking, MIME-type sniffing, protocol downgrade attacks, and cross-site scripting.
- **Acceptance Criteria**:
  - Every HTTP response includes `X-Frame-Options: DENY` (or `SAMEORIGIN` if configured).
  - Every HTTP response includes `X-Content-Type-Options: nosniff`.
  - HTTPS responses include `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
  - The CSP header is configurable via `HIX_MwSecHeadersSetup(cCSP)`.
- **Verification Method**: Test

- **ID**: REQ-SEC-003
- **Title**: CORS Policy Enforcement
- **Statement**: The system shall enforce Cross-Origin Resource Sharing policies via `HIX_MwCors`, configuring allowed origins, HTTP methods, and request headers for cross-domain API consumption.
- **Rationale**: Public APIs consumed from browsers require explicit CORS configuration; the default is to deny all cross-origin requests.
- **Acceptance Criteria**:
  - `HIX_MwCorsSetup(cOrigin, cMethods, cHeaders)` configures the allowed origin (e.g., `"https://app.example.com"`), methods (`"GET,POST,PUT"`), and headers (`"Content-Type,Authorization"`).
  - Preflight `OPTIONS` requests receive an immediate `204 No Content` response with appropriate CORS headers.
  - Actual cross-origin requests include `Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`, and `Access-Control-Allow-Headers` in the response.
- **Verification Method**: Test

- **ID**: REQ-SEC-004
- **Title**: Rate Limiting
- **Statement**: The system shall limit request rates per client IP using fixed-window counters via `HIX_MwRateLimit`, returning HTTP 429 (Too Many Requests) when the threshold is exceeded.
- **Rationale**: Rate limiting protects against brute-force authentication attacks and denial-of-service attempts.
- **Acceptance Criteria**:
  - `HIX_MwRateLimitSetup(nMax, nWindowSecs)` configures the maximum requests per IP within the time window (e.g., 100 requests per 60 seconds).
  - Exceeded limits return HTTP 429 with a JSON error body.
  - The current request count is exposed in `oCtx:hData["rate_count"]` for logging and monitoring.
  - Per-route rate limits are supported via `HIX_MwRateLimitFactory(nMax, nWindowSecs)` (e.g., 5 requests per 60 seconds for login endpoints).
- **Verification Method**: Test

- **ID**: REQ-SEC-005
- **Title**: IP Firewall
- **Statement**: The system shall filter incoming connections by client IP address using a configurable blacklist or whitelist mode via the `firewall` section in `hix.json`, supporting both individual IPs and CIDR notation.
- **Rationale**: Network-level access control provides an additional defense layer before requests reach application middleware.
- **Acceptance Criteria**:
  - `firewall.mode = "blacklist"` blocks all connections from IPs listed in `firewall.filter`; all other IPs are permitted.
  - `firewall.mode = "whitelist"` permits only IPs listed in `firewall.filter`; all others are blocked.
  - The `filter` field accepts comma-separated IP addresses and CIDR ranges (e.g., `"192.168.1.0/24, 10.0.0.5"`).
  - IPv4 and IPv6 addresses are both supported (the audit confirmed IPv6 bypass was fixed in v2.2).
- **Verification Method**: Test

- **ID**: REQ-SEC-006
- **Title**: Body Size Limitation
- **Statement**: The system shall reject HTTP requests with a body exceeding a configurable maximum size via `HIX_MwBodyLimit`, returning HTTP 413 (Payload Too Large).
- **Rationale**: Unbounded request bodies enable denial-of-service attacks through resource exhaustion.
- **Acceptance Criteria**:
  - `HIX_MwBodyLimitSetup(nMax)` sets the maximum body size in bytes (default: 1 MB).
  - The limit is checked against the `Content-Length` header before the body is fully read.
  - Exceeding the limit returns HTTP 413 with JSON error body `{ "error": "payload_too_large" }`.
  - Per-route limits are supported via `HIX_MwBodyLimitFactory(nMax)`.
- **Verification Method**: Test

- **ID**: REQ-SEC-007
- **Title**: Session Cookie Security Flags
- **Statement**: The system shall set session cookies with `HttpOnly` and `SameSite=Lax` attributes to prevent JavaScript access and cross-site request forgery via cookie theft.
- **Rationale**: These cookie attributes are fundamental security controls that HIX provides by default for session cookies.
- **Acceptance Criteria**:
  - The session cookie (default name `HIXSID`) includes the `HttpOnly` flag, preventing client-side JavaScript from reading it.
  - The session cookie includes `SameSite=Lax`, preventing the browser from sending it on cross-site top-level navigation requests.
  - When HTTPS is enabled, the `Secure` flag should be set (either by HIX directly or via the reverse proxy configuration).
- **Verification Method**: Inspection

- **ID**: REQ-SEC-008
- **Title**: JWT Signature Integrity
- **Statement**: The system shall validate JWT tokens using HMAC-SHA256 with a configurable secret key of minimum 32 random bytes, rejecting any token with an invalid signature or expired `exp` claim.
- **Rationale**: JWT integrity is the foundation of stateless authentication; weak keys or missing validation undermine the entire mechanism.
- **Acceptance Criteria**:
  - The default key (`"hix-secret-key"`) must be replaced in production; the system shall document this requirement.
  - Tokens with tampered payloads (even a single byte change) are rejected because the HMAC-SHA256 signature no longer matches.
  - Expired tokens (where current time > `exp` claim) are rejected regardless of signature validity.
  - Timing-attack resistance is implemented: the audit confirmed timing attack fixes in v2.2 for JWT validation.
  - The payload is base64-encoded, not encrypted; sensitive data must not be placed in JWT claims.
- **Verification Method**: Test | Analysis

#### 3.3.3 Reliability

- **ID**: REQ-REL-001
- **Title**: Record Locking Integrity
- **Statement**: The system shall ensure that concurrent update operations on the same DBF record are serialized through `Rlock()`/`Unlock()`, preventing lost updates and data corruption.
- **Rationale**: DBF files use record-level locking; without proper serialization, concurrent writes can corrupt data.
- **Acceptance Criteria**:
  - `UDbf:Update()` internally acquires a record lock before modifying fields and releases it after the commit.
  - Concurrent requests attempting to update the same record are queued; the first acquires the lock, subsequent requests wait (up to `nTime` seconds) or fail with a lock error.
  - The system never writes to a DBF record without holding an exclusive lock on that record.
- **Verification Method**: Test

- **ID**: REQ-REL-002
- **Title**: Error Recovery
- **Statement**: The system shall capture Harbour/xBase runtime errors within UDbf operations using `TRY/CATCH` blocks and route them to the HIX error dispatcher (`HIX_Throw`), which generates appropriate HTTP error responses based on the application environment (`env = "dev"` or `"prod"`).
- **Rationale**: Unhandled xBase errors would crash worker threads; proper error routing ensures graceful degradation.
- **Acceptance Criteria**:
  - UDbf operations wrapped in `TRY/CATCH` convert Harbour errors to HIX exceptions via `HIX_Throw`.
  - In development mode (`env = "dev"`), detailed error information (stack trace, file, line number) is returned in the response.
  - In production mode (`env = "prod"`), a generic error message is returned; details are logged to `hix.log`.
  - Custom error pages can be configured via `<paths.root>/errors/` directory or the `app.errorsys` setting.
- **Verification Method**: Test

#### 3.3.4 Availability

- **ID**: REQ-AVAIL-001
- **Title**: Server Self-Recovery
- **Statement**: The system shall maintain continuous operation under normal conditions, with worker threads independently handling requests without affecting other workers. A single request failure shall not crash the server process.
- **Rationale**: HIX's multi-threaded architecture isolates failures to individual worker threads; this requirement formalizes that isolation as an availability obligation.
- **Acceptance Criteria**:
  - Worker thread crashes are detected by the monitor thread (`oServer:lRunning` check), and the main server process continues running.
  - The `uptimesec` metric increases monotonically during normal operation.
  - A `.prg` route file that throws an unhandled error terminates only that worker's request processing; other workers continue serving requests.
- **Verification Method**: Test

- **ID**: REQ-AVAIL-002
- **Title**: Session Persistence (File Storage Mode)
- **Statement**: When configured with `session.storage = "file"`, the system shall persist session data to disk so that sessions survive server restarts and are shareable across multiple HIX instances.
- **Rationale**: File-based sessions enable multi-instance deployments behind a load balancer with stickysession support.
- **Acceptance Criteria**:
  - Session files are stored in the configured directory with prefix `sess_` (configurable).
  - Sessions survive server restarts and are immediately available to any HIX instance with access to the same session storage directory.
  - Garbage collection removes orphaned session files after `session.gc_days` (default 3 days) of expiration.
- **Verification Method**: Test

#### 3.3.5 Observability

- **ID**: REQ-OBS-001
- **Title**: Centralized Logging with Rotation
- **Statement**: The system shall maintain a centralized, thread-safe logger that writes application and server events to `hix.log` with automatic rotation based on file size (`max_size_mb`) and maximum file count (`max_files`).
- **Rationale**: Observability is essential for diagnosing production issues; HIX provides built-in logging with severity levels and rotation.
- **Acceptance Criteria**:
  - Log levels are configurable: `debug`, `info`, `warn`, `error`, `fatal`; only messages at or above the configured level are written.
  - Log rotation occurs when `hix.log` reaches `max_size_mb`; rotated files are named `hix_YYYYMMDDHHMMSS_NNNNNN.log`.
  - Up to `max_files` backup files are retained; `max_files = 0` means unlimited backups.
  - The logger is thread-safe: concurrent writes from multiple worker threads are synchronized via mutex.
- **Verification Method**: Test

- **ID**: REQ-OBS-002
- **Title**: CLF Access Logging
- **Statement**: The system shall maintain an Apache-style Common Log Format access log (`access.log`) with one line per HTTP request, recording client IP, timestamp, request method and path, and HTTP status code.
- **Rationale**: Access logs are compatible with standard analysis tools (awstats, goaccess, lnav) and provide a complete audit trail of HTTP traffic.
- **Acceptance Criteria**:
  - Each HTTP request generates one line in `access.log` in the format: `<IP> - - [<timestamp>] "<METHOD> <PATH> HTTP/1.1" <STATUS>`.
  - The access log is enabled by default (`access_log.enabled = true`) and can be disabled via configuration.
  - Access logs do not rotate automatically; external tools (logrotate) must be used for high-traffic deployments.
- **Verification Method**: Test

- **ID**: REQ-OBS-003
- **Title**: Boot Log Diagnostics
- **Statement**: The system shall record all server initialization events (loaded configuration files, initialized subsystems, compiled loaders, loaded middlewares, registered routes) in a boot log accessible at runtime via `HIX_BootLog()`.
- **Rationale**: The boot log provides startup diagnostics and is exposed to the admin panel for operational visibility.
- **Acceptance Criteria**:
  - Each boot event is recorded as `{ cAction, lStatus, cValue, xCargo }` in sections: `config`, `server`, `loaders`, `middlewares`, `routes`.
  - Failed operations are marked with `lStatus = .F.` and include an error description in `xCargo`.
  - The complete boot log is accessible via JSON at `/hix-boot` (protected by admin authentication) or programmatically via `HIX_BootLog()`.
  - A callback mechanism (`HIX_BootLogAction`) forwards each event to the logger in real time during startup.
- **Verification Method**: Test

- **ID**: REQ-OBS-004
- **Title**: Metrics Dashboard
- **Statement**: The system shall maintain in-memory atomic counters for requests, errors, active connections, bytes transferred, latency, memory usage, uptime, and view cache statistics, exposed as JSON at `/hix-status` and queryable programmatically via `HIX_Metric*` helpers.
- **Rationale**: Real-time metrics enable operational monitoring, alerting, and capacity planning without external tooling.
- **Acceptance Criteria**:
  - The monitor thread updates system metrics (memory, uptime, queue saturation) every `monitor.interval_s` seconds (default 5s).
  - Application-specific counters can be incremented via `HIX_Metric("myapp.counter")` and decremented via `HIX_MetricDec("myapp.counter")`.
  - Request timing is tracked per route with moving average (`req_ms_avg`) and top-N slowest requests (`req_slowest_dyn`, `req_slowest_stat`).
  - All metric operations are thread-safe; counters can be updated from any worker without external synchronization.
- **Verification Method**: Test

- **ID**: REQ-OBS-005
- **Title**: Per-Module Trace Filtering
- **Statement**: The system shall support fine-grained trace filtering by module name via `HIX_TraceSet(module, .T./`.F.)`, enabling debug-level logging for specific subsystems without increasing the global log level.
- **Rationale**: Production diagnosis requires targeted visibility; lowering the global level to `debug` generates excessive noise.
- **Acceptance Criteria**:
  - `HIX_TraceSet("router", .T.)` activates `DEBUG` and `INFO` messages from the router module only.
  - Trace settings are hot-toggled via `GET /hix-trace?mod=<module>&on=1` without server restart.
  - `WARN`, `ERROR`, and `FATAL` messages always pass through regardless of trace filter settings.
  - Trace configuration is available per module: `app`, `server`, `worker_http`, `worker_ws`, `worker_otros`, `pool`, `metrics`, `config`, `socket`, `monitor`, `response`, `logger`, `error`.
- **Verification Method**: Test

### 3.4 Compliance

- **ID**: REQ-COMP-001
- **Title**: Harbour License Compliance
- **Statement**: The system shall comply with the Harbour Project's dual licensing model (LGPL for the runtime library, plus the special linking exception that permits linking with proprietary code without triggering copyleft obligations).
- **Rationale**: Harbour is distributed under the LGPL with a special exception; understanding these terms is essential for commercial deployment.
- **Acceptance Criteria**:
  - The application links against Harbour libraries (`libhbvm.a`, `libhbrtl.a`, `libhbcxx.a`) and HIX server binary.
  - The linking exception in the Harbour license permits distribution of the compiled application without requiring the application source to be open-sourced.
  - Modifications to the Harbour core itself are subject to LGPL requirements; application code (`.prg` files) is not.
- **Verification Method**: Inspection

- **ID**: REQ-COMP-002
- **Title**: Data Format Standards Compliance
- **Statement**: The system shall store data in standard DBF formats compatible with xBase/Clipper/Harbour ecosystems, using CDX structural index files for multi-tag indexing.
- **Rationale**: DBF/CDX is the universal interchange format for xBase applications; compliance ensures interoperability and data portability.
- **Acceptance Criteria**:
  - DBF files use standard field type codes: C (Character), N (Numeric), L (Logical), D (Date), M (Memo).
  - CDX index files are structural (named identically to the DBF file, e.g., `customers.cdx` for `customers.dbf`).
  - Memo fields use FPT (FoxPro) memo format when the `DBFFPT` RDD extension is used.
  - Files can be opened by any standard xBase/Harbour application without conversion.
- **Verification Method**: Inspection

### 3.5 Design and Implementation

#### 3.5.1 Installation

- **ID**: REQ-INST-001
- **Title**: Server Deployment
- **Statement**: The system shall be deployed as a single HIX server binary (`hix_server`) alongside a `hix.json` configuration file, a `www/` application directory (with subdirectories: `routes/`, `controllers/`, `models/`, `views/`, `middlewares/`, `loaders/`, `public/`, `errors/`), and optionally a `certs/` directory for SSL certificates.
- **Rationale**: HIX's self-contained architecture requires minimal deployment artifacts; this requirement defines the canonical deployment layout.
- **Acceptance Criteria**:
  - The server binary is placed in a directory alongside `hix.json`.
  - Running `./hix_server` from that directory starts the server, loading configuration and application structure automatically.
  - The `www/` root directory (configurable via `paths.root`) contains all application code and static assets.
  - SSL certificates are placed in `certs/` (configurable via `paths.certs`).
- **Verification Method**: Demonstration

- **ID**: REQ-INST-002
- **Title**: Configuration Management
- **Statement**: The system shall be configured entirely through the `hix.json` file, with no command-line arguments or environment variables required for basic operation. Application-specific configuration is stored in `www/config.json`.
- **Rationale**: HIX's single-file configuration simplifies deployment and version control; application settings are separated into a secondary config file.
- **Acceptance Criteria**:
  - All server-level settings (network, pools, logging, sessions, firewall, SSL) are defined in `hix.json`.
  - Application-specific settings (session parameters, auth keys, redirect URLs) are defined in `www/config.json` and accessed via `UMwConfig()`.
  - The `hix.json` structure includes sections: `server`, `paths`, `app`, `admin`, `detector`, `pool_http`, `pool_ws`, `pool_rest`, `pool_hix`, `session`, `monitor`, `log`, `access_log`, `firewall`, `hixstyle`, `trace`.
- **Verification Method**: Inspection

#### 3.5.2 Build and Delivery

- **ID**: REQ-BUILD-001
- **Title**: Source Compilation via hbmk2
- **Statement**: The system's application code (`.prg` files in `models/`, `controllers/`, `middlewares/`, `loaders/`) shall be compiled using the Harbour build tool `hbmk2` to produce `.hrb` libraries for production deployment, or compiled on-the-fly by HIX during development.
- **Rationale**: Pre-compiling application code improves startup performance and enables dependency checking before deployment; on-the-fly compilation provides rapid iteration during development.
- **Acceptance Criteria**:
  - `hbmk2` compiles `.prg` source files into `.hrb` object libraries that are linked into the HIX server or loaded dynamically.
  - In development mode, HIX compiles `.prg` route files on-the-fly when first requested, caching the compiled output.
  - Compilation errors (syntax errors, missing includes) prevent the affected module from loading and produce a boot log entry with `lStatus = .F.`.
  - The build process is reproducible: the same source code produces identical `.hrb` artifacts across builds on the same platform.
- **Verification Method**: Test | Analysis

#### 3.5.3 Distribution

- **ID**: REQ-DIST-001
- **Title**: Multi-Instance Deployment with Session Affinity
- **Statement**: The system shall support multiple HIX server instances behind a load balancer, using file-based session storage (`session.storage = "file"`) and Apache stickysession routing via `HIX_MwSessionSetRoute()` for session consistency.
- **Rationale**: Production deployments may require horizontal scaling; file-based sessions with stickysession routing provide session consistency without shared memory.
- **Acceptance Criteria**:
  - Each HIX instance writes session files to a shared directory (network-mounted or local with synchronized storage).
  - Apache load balancer is configured with `stickysession=HIXSID` and `BalancerMember` routes (`route=i1`, `route=i2`).
  - `HIX_MwSessionSetRoute("i1")` appends the instance suffix to the session ID cookie, enabling sticky routing.
  - Session files are named `sess_<prefix><SID>.dat` and include a `.lock` file for concurrent access protection.
- **Verification Method**: Demonstration

#### 3.5.4 Maintainability

- **ID**: REQ-MAINT-001
- **Title**: HixStyle Folder Structure Enforcement
- **Statement**: The system shall enforce the HixStyle MVC folder structure, where the browser can only access files in the `public/` directory and all other directories (`controllers/`, `models/`, `views/`, `routes/`, `middlewares/`, `loaders/`) are private by default.
- **Rationale**: Folder privacy prevents accidental code disclosure; a fixed structure ensures any developer can navigate any HixStyle project immediately.
- **Acceptance Criteria**:
  - Direct URL access to `/controllers/auth.prg` or `/models/tcustomers.prg` returns 403 or 404, never the source file contents.
  - Only files in `public/` are served directly to the browser as static assets (CSS, JS, images).
  - Route definitions must explicitly declare which `.prg`, `.hrb`, or `.html` files are accessible via HTTP.
- **Verification Method**: Test | Inspection

- **ID**: REQ-MAINT-002
- **Title**: Model Encapsulation Pattern
- **Statement**: The system shall follow the Fenix model pattern: one `TXxx()` function per DBF table in `www/models/`, returning a configured UDbf instance with path, file names, tag, field visibility, and connection settings encapsulated.
- **Rationale**: Model encapsulation centralizes data access configuration, making schema changes and field visibility updates single-point modifications.
- **Acceptance Criteria**:
  - Each table has exactly one model function: `TCustomers()`, `TOrders()`, `TStates()`, etc.
  - The model function configures `cPath`, `cDbf`, `cCdx`, `cTag`, `Hide()`/`Visible()`, and calls `Open()` before returning the instance.
  - Controllers never directly open DBF files; they always obtain table access through the model function.
  - Model functions are included in controllers via `#include 'models/tcustomers.prg'` at the end of the controller file.
- **Verification Method**: Inspection

#### 3.5.5 Reusability

- **ID**: REQ-REUSE-001
- **Title**: Middleware Reusability
- **Statement**: The system shall package cross-cutting concerns as reusable middleware functions (`HIX_MwXxx`) that can be combined in any route's middleware chain via comma-separated declaration in route JSON files.
- **Rationale**: Middleware reusability enables consistent security, logging, and validation policies across all routes without duplicating logic.
- **Acceptance Criteria**:
  - Built-in middlewares (`HIX_MwSession`, `HIX_MwJwt`, `HIX_MwCsrfCheck`, `HIX_MwRateLimit`, etc.) are available for use in any route.
  - Custom middleware can be created as a function `MyMiddleware(oCtx)` following the standard pattern and placed in the `middlewares/` directory.
  - Middleware groups (e.g., `MyAppAuth` combining session + auth) are defined in `.prg` files under `middlewares/` with a `config.json` declaration.
  - The middleware loader (`mw_loader`) compiles all `.prg` files in the middlewares directory on startup.
- **Verification Method**: Inspection

#### 3.5.6 Portability

- **ID**: REQ-PORT-001
- **Title**: Cross-Platform Compilation
- **Statement**: The system shall compile and run on Linux (GCC) and Windows (MSVC, MINGW64) platforms using the HIX build scripts provided in the repository.
- **Rationale**: Harbour is a cross-platform language; HIX provides build automation for the major target platforms to ensure broad deployment options.
- **Acceptance Criteria**:
  - The GCC build script (`go_lib_gcc.sh`) compiles the server on Linux with GCC.
  - The MSVC64 build script (`go_lib_msvc64.bat`) compiles the server on Windows with Visual Studio.
  - The MINGW64 build script (`go_lib_mingw64.bat`) compiles a Windows binary on Linux via MinGW-w64 cross-compiler.
  - Application code (`.prg` files) is platform-independent; no platform-specific code paths are required for standard operation.
- **Verification Method**: Test
