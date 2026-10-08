# SME-Ops on HIX + RDDCDX — research and project plan

> **Report only.** No code was changed, no `.dbf`/`.cdx` created, no branch added, no build run.
> **Date:** 2026-10-08
> **Question:** what does it take to build a **new web service** on **HIX** (`@hix-unified/`, framework at the
> repository root) whose storage layer is the **RDDCDX** RDD (Harbour's Range Data Definition for
> DBF + CDX), with the **database schema taken from `@sme-ops-system-builder/`** (100 operational
> modules, each one table)?
> **Constraint baseline:** `01-requirements/DEV-compliance.md` (HIX style only, **no SQL**, no 3rd-party
> web UI, `hbmk2 app.hbp` build only, port 9090) and `01-requirements/SRS-Harbour-HIX.md` (C-001…C-010).

---

## 0. Naming reconciliation (read first)

The request says "RDDCDX". Three names are in play in this checkout and they are not interchangeable:

| Name | Where it appears | What it is |
|---|---|---|
| **RDD** | Harbour API (`hbapirdd.h`, `rddSetDefault()`) | Range Data Definition — Harbour's pluggable record-store driver interface |
| **DBFCDX** | `www/config.json` → `"dbf": { "rddname": "DBFCDX" }`; `HIX_Dbf:cRdd INIT 'DBFCDX'`; `src/rdd/dbfcdx/` | **the driver name that is actually registered** in this Harbour build |
| **RDDCDX** | prose in this corpus (`02-design/AUTH-migrate.md`, `03-implementation/P4-8-USERS-RESULTS…`, `www/models/modeluser.prg:8`) | the project's shorthand for the same store: DBF + CDX index |

**This plan targets the driver `DBFCDX`** and uses "RDDCDX" only as the corpus's prose name for it.
Everything below that says "the store" means: one `.dbf` per table + one or more `.cdx` index tags,
opened through `UDbf()` → `HIX_Dbf` (`src/dbf/hix_dbf.prg`).

---

## 1. Verdict

| | |
|---|---|
| **Load the SME schema as-is** | **Not achievable.** 51.5 % of the schema's field names are illegal in a DBF, `SERIAL` does not exist, `NULL` does not exist, `TIMESTAMP` has no native type, and 31 `CHECK` clauses have no DBF representation. |
| **Load the SME schema *translated*** | **Achievable, and it is the honest target.** 87 modules → 87–89 `.dbf` + `.cdx` pairs, one 9-route module each, on the proven `webapp/` DAL pattern. |
| **Cover all 87 modules at once** | **Not advisable.** 36 modules carry > 20 fields and 20 of the 87 are Scale-tier; the router in `@sme-ops-system-builder/` exists precisely to pick two or three. Recommended envelope: **12–18 modules**. |
| **Cover the Analyze layer (aggregation) with DBFCDX alone** | **Not covered by the store.** No aggregation engine; needs hand-maintained counter DBFs or `HIX_Pool*` counters. |
| **Recommended shape** | **A new HIX application, `smeapp/`, DBFCDX-backed, Starter-tier shortlist, with the SME Field Reference table as the single schema source** and a generated rename table. SQL DDL is a **spec**, never executed — which keeps the "No SQL" clause true without the MySQL exception. |

The envelope is strong exactly where the SME corpus is strong — one process = one table, named
columns, fixed types, a status field, CRUD forms, an approval state — and absent where the corpus
assumes a relational engine: joins, `NULL`, `CHECK`, aggregation, schema migration.

---

## 2. Measured inputs

### 2.1 `@hix-unified/` (this checkout, branch `enhance`)

| Fact | Value |
|---|---|
| Framework | **38 131 LOC Harbour**, 58 `.prg` in `src/`, **19 middlewares** in `src/mw/`, `src/dbf/hix_dbf.prg`, `src/wdo/` (WDO pool + `src/wdo/mysql/`) |
| Version | HIX v2.2 Audit Edition — 87 audit points closed, 2 105 tests (Windows + Linux) |
| Audited app | `webapp/` — **137 routes** in `www/routes/web.json`: **14 modules × 9 routes** (`grid search show create edit store update delete_confirm delete`) + 11 `sys` routes |
| RDDCDX proof-of-concept | `www/models/tcustomers.prg` (`cDbf 'customers.dbf'`, `cCdx 'customers.cdx'`, `cTag 'first'`); `www/models/modeluser.prg` keeps its RDDCDX store "on purpose, as the proof-of-concept" |
| Store on disk | `webapp/data/customers.dbf` 100 rec × 304 B, 8 fields — `ID N(10,0)`, `FIRST C(20)`, `LAST C(20)`, `ADDRESS C(120)`, `ZIP C(10)`, `COUNTRY C(50)`, `NOTES C(70)`, `AGE N(3)`; `states.dbf` 51 rec, 2 fields; `users.dbf` 6 rec — `PASS C(128)`, `SALT C(32)`, `ROLES C(255)` |
| Store on disk, absent | **no `.fpt`** in `webapp/data/` → **no MEMO field is in use today**; **no `D` and no `L` field is in use today** — both are unproven on this app |
| Server config | `hix.json`: port **9090**, `ssl: true`, `paths.root = www`, `auto_close_dbf: true`, `exec_timeout_ms 30000` |
| DBF/CDX constants | `CDX_MAXKEY 240`, `CDX_MAXTAGNAMELEN 10`, `CDX_MAX_REC_NUM 0xFFFFFFFF` (`include/hbrddcdx.h:57,59,77`); `uiMaxFieldNameLength = 10` (`src/rdd/dbf1.c:4106`); char field width clamped to **255** (`src/rdd/dbf1.c:3409`) |
| `HIX_DBF` verbs | `Open/Close/Count/CountDeleted/FieldPos/FieldName/FieldGet/FieldPut/Next/Prev/First/Last/Focus/Seek/SoftSeek/Rlock/Unlock/Zap/Pack/Append/Delete/Recall/Insert/Update/Blank/Row/Normalize/RecCount/Recno/Bof/Eof/Skip/Goto/SetFields/Hide/Visible`, `nTime` default 3 s |
| `UDbf` verbs | `cPath/cDbf/cCdx/cTag/cRdd/lExclusive/lToUtf8`, `Open/Close`, `First/Last/Next/Prev/Skip/Goto`, `Seek/Focus`, `Row/Blank`, `Insert/GetRecno/GetId/Update/Delete/Recall/Pack/Zap`, `LoadAll(OrdScope + codeblock)`, `Page(nPage,nRows,aFields,@nTotal)` |
| Request/response helpers | `UParam/UJson/UGet/UPost/UFiles/USendJson/USendView/USetStatus/USetHeader/UFlush` … |
| Validator rule kinds | `optional required numeric integer positive min max minlen maxlen between in notin email url ip regex mindate maxdate confirmed` — **19 kinds** (`src/validator/hix_val_rules.prg`) |
| RDD drivers in this Harbour build | `src/rdd/`: `dbf1.c` (DBF), `dbfcdx/` (DBFCDX), `dbffpt/` (MEMO/FPT), `dbfnsx/`, `dbfntx/`, `hbsix/` (SIX), `nulsys`, `usrrdd` (user RDD). **No R-Tree driver** |
| Multi-key CDX | supported — `pTag->MultiKey`, `DBOI_MULTIKEY`, `RDDI_MULTIKEY` (`src/rdd/dbfcdx/dbfcdx1.c:8514,8565,8883`) |
| Compliance clauses | `01-requirements/DEV-compliance.md`: HIX style only, **No SQL** (scoped exception for the MySQL WDO plan only), no 3rd-party web UI, `hbmk2 app.hbp`, port 9090, tools inside the project folder |

### 2.2 `@sme-ops-system-builder/` (this checkout)

| Fact | Value |
|---|---|
| Modules | **100** claimed; on disk **93 skill dirs** = 87 modules with a table + 4 helpers + 2 pack routers |
| Tables | **89** `CREATE TABLE` blocks (87 modules, 2 carry two tables) |
| Fields | **1 794** field lines in the DDL; **1 566** rows in the `## Field Reference` tables (the canonical per-module list) |
| Type vocabulary (Field Reference) | `text 571`, `select 270`, `date 159`, `currency 150`, `number 128`, `id 87`, `long_text 76`, `checkbox 53`, `relation 46`, `url 16`, `email 7`, `datetime 3` |
| SQL widths (DDL) | `VARCHAR(255) 628`, `VARCHAR(100) 275`, `TIMESTAMP 181`, `DATE 165`, `NUMERIC(14,2) 155`, `NUMERIC 133`, `TEXT 94`, `SERIAL PRIMARY KEY 89`, `BOOLEAN 53` |
| **Field names > 10 chars** | **924 of 1 794 = 51.5 %** — illegal in DBF, a rename table is mandatory |
| `CHECK` clauses | **31** lines: enum membership (`status IN (...)`), ranges (`>= 0`), cross-field implications (`(status IN ('Closed',…)) = (access_removed_date IS NOT NULL)`) |
| Structure | **10 layers** (Foundation, Acquire, Onboard, Manage, Develop, Engage, Protect, Operate, Analyze, Exit); catalog tiers **Starter 24 / Growth 37 / Scale 20** |
| Artifacts per module | CSV, SQL DDL, JSON Schema (draft 2020-12), Notion mapping, Excel workbook — all from **one field list**, "cannot drift apart" |
| Contract | context-first intake, one question per message, build only on request, never invent a value |

---

## 3. The translation: SME schema → DBF + CDX

The SME `## Field Reference` table (`| # | Field | Type | SQL | JSON Schema | Notion | CSV example |`)
is the **single source**. The SQL column is read as a *spec*, never executed — the "No SQL" clause
stays true without the scoped exception, because nothing here parses or runs SQL.

| SME type | Count | DBF rendering | Cost / trap |
|---|---:|---|---|
| `id` → `SERIAL PRIMARY KEY` | 87 | `N(10,0)` + a persisted counter + a CDX tag on a character `pkid` field | **mandatory, not free.** `Pack()`/deletion renumbers recnos — recno is **not** a public id. Tag names ≤ 10 chars (`CDX_MAXTAGNAMELEN`) |
| `text` → `VARCHAR(255)` | 628 | `C(255)` | free, but **fixed width, blank-padded**: every read needs `AllTrim`; 255 is the clamp, so a longer value is silently truncated — validator `maxlen 255` closes it |
| `select` → `VARCHAR(100)` | 270 | `C(100)` + validator `in` rule from the module's **Select Options** section | free; the enum is enforced at the request boundary, **not** in the store |
| `number` → `NUMERIC` | 128 | `N(w,d)` | free; `NUMERIC` unqualified has no width in SQL — the generator must choose one (recommend `N(12,2)`) |
| `currency` → `NUMERIC(14,2)` | 150 | `N(16,2)` + a `C(3)` currency code where the module implies one | small |
| `date` → `DATE` | 159 | `D(8)` | free — **but unproven on this app**: no `D` field exists in `webapp/data/` |
| `datetime` → `TIMESTAMP` | 181 | **no native type.** `D(8)` + `C(9)` time, or `C(20)` ISO-8601 | small, pervasive; sorting on a `C(20)` ISO string is correct by construction |
| `checkbox` → `BOOLEAN` | 53 | `L(1)` | free — also unproven on this app |
| `long_text` → `TEXT` | 76 | `M` (MEMO) + `.FPT` sidecar | **unproven here** — no `.fpt` in `webapp/data/`; `dbffpt` GC path is untested by this app. Fallback: `C(255)` + a companion `M` |
| `relation` → `VARCHAR(255)` | 46 | `N(10,0)` holding the target's `pk`, resolved with `Seek()` on the target's CDX; keep the human label as a separate `C(255)` | **medium** — no join, no `FOREIGN`; a dangling value is invisible unless `Orphans()` reports it |
| `email` / `url` → `VARCHAR(255)` | 23 | `C(255)` + validator `email` / `url` | free |
| `NULL` | pervasive | **does not exist** — DBF has typed blanks (`""`, `0`, `.F.`, date-blank) | **pervasive rewrite**: every "is not set" test becomes `IS EMPTY` / typed-blank |
| `CHECK` | 31 | **no DBF equivalent** | validator (`in notin min max between mindate maxdate regex`) at the boundary + a DAL probe for cross-field implications |
| field **names** | 924 (51.5 %) | DBF names are **≤ 10 chars**, `[A-Za-z_][A-Za-z0-9_]*`, case-insensitive, unique | **tedious, error-prone** — one generated rename table, applied identically in models, views, routes and JSON output |
| `CREATE INDEX … (status)` | several | a second CDX tag per indexed column | free; `CDX_MAXKEY 240` bounds the key expression |

---

## 4. What the envelope covers — and what it does not

### 4.1 Covered by HIX + RDDCDX, at no extra cost

| SME need | Envelope |
|---|---|
| One row per process, CRUD, form pages | `UDbf` `Insert/Update/Delete/Recall` + the 9-route module pattern (proven 14× in `webapp/`) |
| Paginated data grid, column sort, filter params | `UDbf:Page(nPage,nRows,aFields,@nTotal)`, `LoadAll(OrdScope, codeblock)`, `UParam()` fallback fix in `src/hix_helpers.prg` |
| Status field + transitions | `C(100)` + CDX tag on status + validator `in` |
| Money, dates, booleans | `N(16,2)`, `D(8)`, `L(1)` |
| Who-can-see-what (the `access-matrix` module) | HIX middleware stack: `HIX_MwAuth`, `HIX_MwHasRole`, `HIX_MwIsAuth`, `HIX_MwRequireAuth`, `HIX_MwJwt(+Scope)`, per-route `scope` in `routes/*.json` |
| CSRF, sessions, rate limit, body limit, security headers, TLS | `HIX_MwCsrf` (session-bound, enhanced), `HIX_MwSession`, `HIX_MwRateLimit`, `HIX_MwBodyLimit`, `HIX_MwSecHeaders`, `hix.json` `ssl` + `H-05a/H-05c` session store modes |
| Audit trail / `audit-log` module | `HIX_MwReqLog`, CLF access log, logger w/ rotation, `/hix-trace`, `/hix-status` metrics |
| Reminders / `notification-reminder-hub` | SSE (`hix_sse`), long-poll (`hix_longpoll`), WS worker pools |
| JSON API output | `USendJson`, `Row()`, `hix_jsonEncode` |
| Static assets, gzip, ETag | dispatcher over `public/` (**no `Range` support**) |
| Extensibility | `controllers/*.prg` compiled on the fly; `/hix-routes/add\|delete\|reload` |

### 4.2 Partially covered — needs a named mechanism, not a workaround

| SME construct | Count | Gap | Mechanism this plan chooses |
|---|---:|---|---|
| `relation` fields | 46 | no join, no foreign key, no cascade | `N(10,0)` target pk + `Seek()` on the target's CDX; FK graph declared in the schema spec and parsed by the DAL (the pattern already built for MySQL in P3/P7.2); `Orphans()` makes dangling values visible; delete policy `CASCADE / NULL / KEEP` per edge, default `KEEP` |
| Analyze layer (aggregation, KPI, dashboards) | ~8 modules | **no aggregation engine** in DBFCDX | counter DBFs maintained by the same code paths that mutate the data (the P4.2 stock pattern), or `HIX_Pool*` for in-process counters; scan-with-`OrdScope` only for small tables |
| Free-text search | 571 `text` fields | CDX is **prefix-key only** | prefix `Seek()` + a codeblock filter; no stemming, no ranking, no fuzzy |
| Multi-table writes (e.g. leave request + balance) | all modules with 2 tables | **DBFCDX has no transactions**; the MySQL WDO has `BeginTrans/Commit/Rollback`, DBF does not | order the writes, re-read to confirm, and make the residue visible through `Orphans()`; or accept the loss and document it (§7 D-6) |
| `TIMESTAMP` | 181 | no datetime in DBF | `D(8)` + `C(9)`, or `C(20)` ISO |
| Schema change over time | — | **no migration tooling**; a DBF header change means regenerate-the-store | a versioned generator + `migrate_users`-style Harbour CLI tool (the pattern exists at `webapp/migrate_users.prg`) |

### 4.3 Not covered at all

| SME assumption | Why it fails here |
|---|---|
| `NULL` semantics (`IS NULL` / `IS NOT NULL` in 31 CHECKs) | typed blanks only — every predicate must be rewritten |
| `CHECK` cross-field implications | no constraint engine; code only |
| JSON Schema draft 2020-12 validation | HIX's validator is **rule-driven**, not schema-driven; the same field list can drive both, but the schema artefact is not consumed |
| Notion / spreadsheet / Excel artifacts | out of scope for a Harbour service — the CSV/JSON export route covers the data, the tooling does not live here |
| Concurrency across requests | DBFCDX is a file store: `lExclusive`, `Rlock/Unlock`, `auto_close_dbf` — no WAL, no crash journal, no per-record locking |
| R-Tree / spatial / range queries | no R-Tree RDD in this Harbour build |
| XLS/XLSX import | no reader (same blocker as `INVENTREE-RESEARCH.md` §1) |

---

## 5. Coverage of the 87 modules

| Group | Modules | Verdict |
|---|---|---|
| **Covered as-is** — one table, `text/select/number/date/currency/checkbox`, one status field | the great majority of Layers 1, 3, 4, 6, 7, 8 | **build them** |
| **Covered with a counter DBF** — Layer 9 Analyze (`reports-analytics`, `advanced-analytics-dashboard`, `dei-dashboard`, `kpi-tracker`, `credit-cycle-analysis`, `party-ledger-reconciliation`, `day-book`) | ~8 | build only if a counter DBF is acceptable; otherwise defer |
| **Covered with a rename table only** — 51.5 % of names > 10 chars | all | mechanical, generated |
| **Covered with a decision first** — modules with `relation` fields (46) and multi-table modules | ~20 | needs the FK policy decided per edge before the module is built |
| **Deferred** — Scale tier (20), modules > 20 fields (36), `long_text`-heavy modules (76 fields across the corpus) | — | not in the first envelope |
| **Not covered** — anything needing aggregation-as-a-service, full-text search, XLS import, or cross-request atomic writes | — | see §4.3 |

**Recommended first envelope:** the **Starter tier (24 modules) narrowed to 12–18** by the router,
weighted to Layers 1/3/4/6 (Foundation, Onboard, Manage, Engage) — the ones whose verbs are exactly
the nine the audited pattern already ships.

---

## 6. Shape of the new service

```
smeapp/                     (new; sibling of webapp/, same HIX style)
  app.hbp  app.rc           build: hbmk2 app.hbp only            (T7)
  hix.json                  port 9090, ssl, paths.root = www     (T8)
  hix.keys.json  (0600)     keys outside the docroot             (PENTEST §1)
  www/
    routes/web.json         9 routes per module + sys routes
    controllers/masters/<module>.prg     grid|search|show|create|edit|store|update|delete_confirm|delete
    models/                 one UDbf wrapper per table + the DAL
    views/masters/<module>/ Mambo views, one form per create/update
    middlewares/            MyAppAuth / MyAppAuthRole / MyAppAuthRoleEdit / MyAppPublic
    public/                 static, gzip, ETag
  sql/                       SME-derived spec (never executed)
  tools/                     adhoc generators, inside the project folder   (T5)
  data/                      <table>.dbf + <table>.cdx[.fpt]
  test/                      probe + suite scripts per phase
  srs/                       this plan, its results records, its audit
```

**The DAL contract** (carried over from the proven `webapp/` DAL, P3/P4/P7.2):

| Verb | Backing |
|---|---|
| `Grid / Search / Show` | `UDbf:Page()` / `LoadAll(OrdScope, codeblock)` / `Seek()` on the module's CDX tag |
| `Create / Update` | validator pass (19 rule kinds, generated from the module's field list) → `Insert()` / `Update()` |
| `Delete / Delete_confirm` | FK policy resolved per edge (`CASCADE / NULL / KEEP`, default `KEEP`) → refuse `NULL` where the spec says `NOT NULL` → cascade → `Orphans()` |
| `Reconcile / FK-check` | the orphan sweep, already built as `controllers/fkcheck.prg` + `controllers/reconcile.prg` |
| `Health/db` | store probe: DBF header, CDX tag list, record count vs. counter |

---

## 7. Plan — phases, with the compliance grade of each

| Phase | What it does | Blocking artefacts | Compliance |
|---|---|---|---|
| **P0** | Host gate: `hbmk2` present, `DBFCDX` opens a scratch DBF + CDX, `probe_seek`/`probe_fmode` equivalents pass on this machine | `tools/p0_probe.*`, results record | T1–T8 all hold |
| **P1** | **Schema derivation**: read the SME `## Field Reference` tables → one spec per module; emit the **rename table** (924 names), the DBF field specs, the CDX tag list, the validator rule set, and the FK graph from the 46 `relation` fields | `tools/gen-sme-schema.py`, `sql/sme-spec.md`, `sql/sme.sql` (reference only) | T1–T8 hold; **no SQL executed** |
| **P2** | **Store**: create 12–18 `.dbf` + `.cdx`, seed with the module's single example row, verify header/widths/tag names ≤ 10 | `tools/create_*.prg` (pattern: `create_cdx.prg`, `create_dbf_ntx.prg`) | T1–T8 hold |
| **P3** | **DAL**: `UDbf` wrapper per table, the nine verbs, FK graph parsed from the spec, delete policy at the schema edge, `Orphans()` | `www/models/tdalsme.prg` | T1–T8 hold |
| **P4** | **Modules**: one controller + views per module, 9 routes each; scopes in `routes/web.json`; middleware per route | 12–18 × 9 routes | T1–T8 hold |
| **P5** | **Verification**: per-module functional grid (create → grid → search → edit → update → delete_confirm → delete → orphan check), plus the security block (CSRF bound, TLS cookie, keys outside docroot) | `test/*` suites | — |
| **P6** | **Release**: branch delta, changelog, the artefact that `06-release/` still lacks | `06-release/` | — |
| **P7** | **Maintenance**: schema evolution = regenerate + `migrate_*` CLI (pattern `migrate_users.prg`); counter DBFs for the Analyze layer | `07-maintenance/` | — |

**Grading note.** Unlike `INVENTREE-MYSQL-PLAN.md`, **no phase here needs the "No SQL" exception**:
the SQL DDL is read as a spec by a Python generator inside the project folder; the runtime never
opens a database engine. T1 ("only HIX framework and Harbour language") holds because the generator
is a build-time tool, not a runtime dependency — the same standing `gen-inventree-mysql-schema.py`
already has.

---

## 8. Alternatives, and why they were not chosen

| # | Alternative | What it buys | What it costs | Verdict |
|---|---|---|---|---|
| **A** | **DBFCDX only** (this plan) | Full compliance with `DEV-compliance.md` including "No SQL"; reuses the proven RDDCDX POC (`customers`, `states`, `users`) | `NULL`, `CHECK`, joins, transactions, migration all become hand-coded | **Chosen** |
| **B** | **MySQL behind the WDO pool** (already built: P0–P7.2, MariaDB in `webapp/.mysql/`, 38 tables shipped) | `NULL`, FK + `NOT NULL` enforcement, `BeginTrans/Commit/Rollback`, aggregation, joins — removes the three real DBF blockers | needs the **scoped exception** to "No SQL"; a host dependency; a third-party engine | **Fallback** if the module set grows past ~20 tables or needs atomic multi-table writes |
| **C** | **Hybrid: DBFCDX store + `HIX_Pool*` / counter DBFs for aggregation** | Covers the Analyze layer without leaving the envelope | counters can drift from the data; `Orphans()`-style reconciliation is required | **Add to A** when Layer 9 is requested |
| **D** | **Other RDD drivers**: SIX (`src/rdd/hbsix/`), NSX/NTX, user RDD (`usrrdd`) | different index layout, no R-Tree anywhere | unproven against HIX's `HIX_Dbf` wrapper, which defaults to `DBFCDX` | not worth it — the wrapper and the audit are DBFCDX-shaped |
| **E** | **`hix_data_pool` / JSON as the store** | no file format at all | in-memory only, no index, lost on restart, no paging | state for ephemeral counters only |
| **F** | **`hbpgsql` / external DB** | SQL power | breaks T1 and T3 outright | **excluded** |

**Decision rule for the owner:** choose B only when a module needs (a) cross-table atomicity,
(b) `NULL` as a real value, or (c) aggregation over > one table. Everything the SME corpus does
per-module is covered by A.

---

## 9. Open decisions (owner, before P4)

| # | Decision | Why it blocks | Recommendation |
|---|---|---|---|
| D-1 | **Module shortlist** (12–18 of 87) | route count, view count, test matrix | Starter tier, Layers 1/3/4/6, drop `long_text`-heavy and Analyze |
| D-2 | **Public id strategy** | every route URL carries `:id([0-9]+)` | persisted `pk N(10,0)` + CDX tag; **never** recno (`Pack()` renumbers) |
| D-3 | **Rename table ownership** | 51.5 % of names must change | generated once in P1, committed, cited by models/views/routes; never hand-edited |
| D-4 | **FK policy per `relation` edge** (46) | `Delete()` and `Cascade()` resolve it | default `KEEP`; decide per module, as in `FK-POLICY-DECISIONS.md` |
| D-5 | **Enum enforcement point** | 270 `select` fields | validator `in` at the boundary **plus** a DAL probe on `Update()` (a stored value can be edited by another route) |
| D-6 | **Multi-table atomicity** | modules with 2 tables and a shared invariant | accept ordered-writes + reconciliation on A, or move that module to B |
| D-7 | **Concurrency model** | HIX serves concurrent requests; DBFCDX is one file | `lExclusive` + `Rlock/Unlock` per table, one writer per table, document the ceiling |
| D-8 | **`TIMESTAMP` rendering** | 181 fields | `C(20)` ISO-8601 (sortable, trims cleanly) unless a module needs date arithmetic — then `D(8)+C(9)` |
| D-9 | **MEMO vs C(255) for `long_text`** | 76 fields, and `.FPT` is unproven on this app | start with `C(255)` + validator `maxlen 255`; move to `M` only after a P2 probe proves `dbffpt` |

---

## 10. Risks

| Risk | Evidence | Mitigation |
|---|---|---|
| DBFCDX immaturity | `harbour/doc/oldnews.txt:1762` — *"RDD DBFCDX is highly improved, it is very close to be stable now"* | P0 probe gate; per-phase results records; the shipped POC is the reference behaviour |
| Silent truncation | char width clamped to 255 (`dbf1.c:3409`) | validator `maxlen` on every `text` field, generated from the spec |
| Dangling FKs | no `FOREIGN`, default `KEEP` | `Orphans()` route (already built for the MySQL DAL) reused on DBFCDX |
| Unproven types | `D`, `L`, `M` fields do not exist in `webapp/data/` | P2 creates one scratch DBF per type before any module is built |
| Key/tag limits | `CDX_MAXKEY 240`, `CDX_MAXTAGNAMELEN 10` | generator asserts both, fails loudly |
| Record-count limit | `CDX_MAX_REC_NUM 0xFFFFFFFF` | irrelevant at SME volumes; state it, do not engineer for it |
| No `Range` requests | dispatcher has ETag/gzip/chunked only | irrelevant for JSON CRUD; matters only for large static downloads |

---

## 11. What would be produced, and what is not produced now

Produced by this document: **this plan only.** Not produced: `smeapp/`, any `.dbf`/`.cdx`, any
generator, any route, any build. The next session that acts on it starts at **P0** and writes a
`03-implementation/P0-…-RESULTS-<date>.md` record, following the corpus convention that a plan
grades itself against `01-requirements/DEV-compliance.md`.

---

## 12. Traceability

| Claim | Source |
|---|---|
| HIX LOC, middleware count, DBF/UDbf APIs, constants | `src/` (38 131 LOC), `src/mw/` (19), `src/dbf/hix_dbf.prg`, `include/hbrddcdx.h:57,59,77`, `src/rdd/dbf1.c:4106,3409`, `src/rdd/dbfcdx/dbfcdx1.c:8514,8565,8883` — cross-checked against `02-design/INVENTREE-RESEARCH.md` §2 |
| Route/module counts | `webapp/www/routes/web.json` (137 routes, 14 × 9 + 11), `www/controllers/masters/` (14 files) |
| Store on disk | `webapp/data/*.dbf` headers parsed directly (records, field types/widths); no `.fpt` present |
| SME counts | `skills/*/SKILL.md` — `CREATE TABLE` blocks (89 tables, 1 794 field lines) and `## Field Reference` tables (91 sections, 1 566 rows); `references/catalog.md` (10 layers, tiers 24/37/20) |
| Compliance clauses | `01-requirements/DEV-compliance.md` incl. its scoped "No SQL" exception |
| Prior art | `02-design/INVENTREE-RESEARCH.md` (same envelope, different schema source), `02-design/INVENTREE-MYSQL-PLAN.md`, `02-design/FK-POLICY-DECISIONS.md`, `03-implementation/P3-DAL-RESULTS…` |
