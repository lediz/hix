# Plan: put the InvenTree MySQL schema into `webapp/` — step by step, report only

> **This document plans.** It changes nothing under `webapp/`, `src/`, `data/` or `resources/`,
> runs none of the commands it names, and creates no branch. Every command below is an
> instruction for a later session, not a record of one.
> **Date:** 2026-10-07
> **Inputs:** `INVENTREE-MYSQL-SCHEMA.sql` (the 79-table layout) · `INVENTREE-MYSQL-SCHEMA.md`
> (its provenance) · `INVENTREE-RESEARCH.md` (the DBFCDX variant, its blockers and work packages)
> · `01-requirements/SRS-DAL-CRUD-WEB-UI.md` (the functional flow that must still verify)
> · `01-requirements/DEV-compliance.md` (the binding constraints, tests **T1…T8**)
> · `site-docs/en/wdo/mysql/{index,config,usage,prepared,transactions,installation}.md`
> · `examples/web/hi/www/controllers/api_mysql_demo.prg` (the working MySQL-in-a-handler example)

---

## 0. Verdict before any step

| | |
|---|---|
| Is the schema loadable as-is? | **No.** It is a reference artefact: no FK declarations, no FK targets' own tables, no `NOT NULL` policy decisions, column order indicative. It is the *shape*, not the deliverable |
| Does MySQL remove the DBF blockers? | **Three of the ten hard blockers** in `INVENTREE-RESEARCH.md` §5: no aggregation engine, no atomic multi-table mutation, single-writer DBF. It removes none of the other seven |
| Is the plan compliant as written? | **No.** It is ❌ against **T2 "No SQL"**. It is compliant only under a recorded restatement of that clause (§1) — **that restatement is now recorded (2026-10-07), so P1 and later run ✅ under it**. Host-side steps (MySQL server, Linux `.so`) are ⚠️ against **T6** |
| Honest target | A MySQL-backed DAL for **38 of the 79 tables**, carrying InvenTree's functional flow (inventory nouns + CRUD verbs + order/build mutations), on the audited `webapp/` route/middleware/view pattern |
| Cost, revised | SQL replaces the hand-coded aggregate and counter machinery, so the research estimate drops: **≈ 28–45 k LOC Harbour + templates** instead of 43–70 k, for the same user-visible behaviour |

The one thing MySQL buys that the DBF plan could not get at any cost is **the aggregation engine and
transaction atomicity**. The plan is worth running only because of those two. Everything else in it
is the same work the DBF plan already carries.

## 1. The constraint decision (Step 0 — nothing else may precede it)

`DEV-compliance.md` is binding and says, verbatim: **"No SQL."** A MySQL DAL is SQL. There is no
reading of that clause under which this plan is compliant, so the restatement must be written
before the first line of code, not discovered later.

**Step 0.1** — Record the restatement in `01-requirements/DEV-compliance.md` (a later session edits
it; this one does not). Proposed replacement text for the T2 line:

```
No SQL engine, no SQL library, no third-party database. Database access is allowed
only through the HIX WDO MySQL/MariaDB pool (WDO_Get / Prepare / Execute / Free / Close),
which is part of the HIX framework at this repository's root (src/wdo/mysql/).
```

> **RESOLVED 2026-10-07.** The exception is recorded in
> `01-requirements/DEV-compliance.md` as an *Exception* block, not as a rewrite: the
> original clause stays visible, and the exception is scoped to **P1 and the later
> phases of this plan only** — it does not license SQL anywhere else, including the
> audited `webapp/` DAL as it ships today. The wording there is broader than the
> sketch above (it also pins T4/T5/T6/T7/T8 as still true); it is the authority,
> this block is the intent. P1 and later therefore grade **T2 ✅ under the recorded
> exception**, and Step 0.1 is no longer a gate.

That keeps T4 ("only HIX framework and Harbour") true: the driver is framework code, already
compiled into `hix_server.hbx` (`hix_server.hbp:131-136` list `src/wdo/mysql/*.prg`). **T2 is the
clause that changes; T1, T3, T5, T7, T8 do not.**

**Step 0.2** — Decide which DAL ships. Two options, and the choice is a product decision:

| Option | DAL | Consequence |
|---|---|---|
| **A — MySQL replaces DBFCDX** | `www/models/t*.prg` stop wrapping `UDbf()` and wrap the pool | `hix.json → app.auto_close_dbf` becomes irrelevant; `data/*.dbf` stops being state; the audited customer/users DAL is re-implemented on MySQL and must re-verify |
| **B — MySQL alongside DBFCDX** | DBF keeps users/sessions/states; MySQL holds the inventory domain | smaller blast radius, two data models to keep consistent, `auto_close_dbf` stays `true` |

**Recommendation: A**, because option B leaves the FK graph (165 edges) split across two stores
with no shared key space, which is a correctness surface, not a convenience.

**Decision taken on 2026-10-07 (Step 0.2)** — **A for `users`, B kept for `customer`**:

* **`users` → MySQL.** The credential store stops being a `data/users.dbf` record and becomes
  a table the pool serves, so `www/controllers/masters/users.prg`, `www/models/modeluser.prg`
  (the login path) and the role/scope source all move onto `www/models/tdalmysql.prg`. The
  audited defect closures in that module (D-01…D-16) are properties of the *verbs*, so they
  have to be re-proven over the new store, not assumed to have carried over.
* **`customer` stays on `UDbf()`/RDDCDX, deliberately.** It is the surviving proof-of-concept
  that the DBF path still works end-to-end — the only RDDCDX surface left in the app — and the
  thing a new HIX app starts from (`examples/web/crud/`). It is not a defect to fix; retiring
  the POC is a separate product decision, not part of this plan.
* Consequence: `hix.json → app.auto_close_dbf` keeps its `true` while the POC is in the app, so
  **P5.5 stays open**; `data/*.dbf` is state for `customer`/`states` only, never for users.

**Step 0.3** — Write the two decisions that invalidate later work if left open (mirroring
`INVENTREE-RESEARCH.md` §6, which lists the DBF-side equivalents):

1. **id strategy.** MySQL `int` + `AUTO_INCREMENT` is what the schema says and what Django does.
   It is safe here (unlike DBF `recno`, which `Pack()` renumbers) — but it means ids are **server-
   assigned**, so a create flow must read `oConn:Last_Insert_Id()` after the INSERT, never assume.
2. **delete policy.** InvenTree's FKs are **not enforced by MySQL** (measured from the model source:
   `on_delete=CASCADE` 68, `SET_NULL` 69, `DO_NOTHING` 3, plus 5 `GenericForeignKey`). The DAL must
   implement those three behaviours itself, or deleting a `PartCategory` silently orphaning
   400 `Part` rows is a user-visible bug. Decide per table, record in the plan, before writing
   `delete_action@…`.

---

## 2. What "implement this MySQL schema into webapp" means, precisely

Not: load `INVENTREE-MYSQL-SCHEMA.sql` into a server. That file is 79 tables of InvenTree's whole
DB, including `scim_scimconfiguration`, `plugin_plugin*`, `report_report*`, `importer_dataimport*`,
`machine_machine*` — machinery the envelope cannot build (`INVENTREE-RESEARCH.md` §4 marks them 🟥).

The deliverable is: **the tables the functional flow actually touches**, in MySQL, behind the DAL,
serving the routes the SRS requires. From the artefact's index, that subset is **38 tables**:

| Group | Tables (names exactly as in the artefact) | n |
|---|---|---|
| Inventory core | `part_part` `part_partcategory` `part_partparametertemplate` `part_partparameter` `stock_stocklocation` `stock_stockitem` `company_company` `company_contact` `company_address` `company_manufacturerpart` `part_supplierpart` `part_supplierpricebreak` | 12 |
| BOM / pricing | `part_bomitem` `part_bomitemsubstitute` `part_partrelated` `part_partpricing` | 4 |
| Orders | `order_purchaseorder` `order_purchaseorderlineitem` `order_salesorder` `order_salesorderlineitem` `order_salesorderallocation` `order_salesordershipment` | 6 |
| Build / stocktake / tests | `build_build` `build_builditem` `build_buildline` `part_partstocktake` `stock_stockitemtestresult` `stock_stockitemtracking` | 6 |
| Support | `common_inventreesetting` `common_inventreeusersetting` `common_note` `common_attachment` `common_projectcode` `common_barcodescanresult` `stock_stocklocationtype` `users_owner` `users_userprofile` `users_ruleset` | 10 |

Three of these are **FK targets that the artefact does not define**: `auth_user`, `auth_group`,
`contenttypes_contenttype` (Django's own tables). Step 4 must decide whether to reproduce them
(`auth_user`, `auth_group`) or to drop the FKs that point at them and use HIX's own session/role
model instead. **Recommendation: drop them** — HIX already has users, roles and scopes
(`www/models/tusers.prg`, `www/middlewares/myappauthrole.prg`), and importing Django's `auth_user`
would mean importing Django's password hashing, which the audited app already replaced
(`www/models/hpassword.prg`).

---

## 3. The functional flow being carried (the thing that must verify)

The SRS flow (`SRS-DAL-CRUD-WEB-UI.md` §4) is the contract. InvenTree's own verbs map onto it:

| InvenTree flow | SRS requirement | Route shape (audited pattern) | MySQL operation |
|---|---|---|---|
| part list / search / detail | FR-READ-1…5 | `/part/grid` `/part/search` `/part/:id` | `LIMIT/OFFSET` + `LIKE ?` (wildcards in the value) + PK lookup |
| create part / stock item | FR-CREATE-1…5 | `/part/create` (GET form) → `/part/store` (POST) | `Prepare INSERT` → `Last_Insert_Id()` |
| edit / update part | FR-UPDATE-1…5 | `/part/:id/edit` → `/part/:id/update` | dynamic `SET` list + `WHERE id = ?` + `Affected_Rows()` |
| delete (with confirm) | FR-DELETE-1…4 | `/part/:id/delete_confirm` → `/part/:id/delete` | FK-policy cascade, then `DELETE` |
| receive purchase order | (verb beyond the SRS) | `/order/:id/receive` | **one `BeginTrans`/`Commit`** across `order_*`, `stock_stockitem`, `part_supplierpart` |
| allocate to build | (verb beyond the SRS) | `/build/:id/allocate` | same, across `build_builditem`, `stock_stockitem` |
| BOM expand / substitute | (verb beyond the SRS) | `/part/:id/bom` | recursive resolve, cycle guard, `JOIN` for aggregates |
| stocktake / test result | (verb beyond the SRS) | `/part/:id/stocktake` | INSERT + recomputed counters **in SQL** |
| settings / notes / attachments | (SRS-adjacent) | `/settings/*` `/note/*` | plain CRUD |

The audited app already proves the left-hand column end-to-end for `customer` and `users`
(`02-design/DAL-CHECKLIST.md` §2). The plan re-uses that proof by keeping the route, middleware,
scope, flash and CSRF shape **unchanged** and changing only what is behind the DAL.

---

## 4. Phases and steps

Each step: **what** · **where** · **verify by** · **grade** (✅ compliant · ⚠️ host-scope · ❌ needs
the §1 restatement).

### Phase P0 — the database exists, outside the app

| Step | What | Verify by | Grade |
|---|---|---|---|
| **P0.1** | Confirm the client library is the one already in the project folder: `resources/wdo/mysql/dll/libmysql64.dll` (5.2 MB) / `libmariadb64.dll` (1 MB). Windows only — Linux needs `libmysqlclient.so` / `libmariadb.so` from the distro | `ls resources/wdo/mysql/dll` | ⚠️ T6 on Linux (the `.so` is host-side); ✅ on Windows, the DLL is in the repo |
| **P0.2** | Point the driver at it explicitly, per pool, with the `"dll"` field in `www/config.json` — do **not** rely on `exedir` or `PATH` (the audited app's `go_gcc.sh` copies DLLs next to the binary for other reasons) | `oConn:DllSource()` must report `"override"` (the diagnostic in `site-docs/en/wdo/mysql/config.md`) | ✅ |
| **P0.3** | The MySQL **server** itself: a MariaDB/MySQL instance, one database, one user. This is inherently outside the project folder — the same class of action as `LETS-ENCRYPT-PLAN.md`'s certbot issuance | `mysql -e 'SELECT 1'` | ⚠️ T6 — record it as a host obligation, never as a repo change |
| **P0.4** | Decide the character policy once: `utf8mb4` + `utf8mb4_general_ci` for search columns, `utf8mb4_bin` for exact-match keys (`IPN`, `SKU`, `barcode_hash`). DBF's codepage/`lToUtf8` discipline (`INVENTREE-RESEARCH.md` §3) is replaced by this one decision | `mysql -e 'SHOW CHARACTER SET'` on the DB | ⚠️ T6 (server-side) |

### Phase P1 — the schema becomes a real, loadable schema

| Step | What | Verify by | Grade |
|---|---|---|---|
| **P1.1** | Derive a **shipped** schema file from the artefact: `webapp/sql/inventree.sql` — the 38 tables, in FK dependency order (targets before referrers), with `CREATE TABLE` + `ALTER … ADD CONSTRAINT` replaced by `CREATE TABLE … KEY` (already in the artefact) + explicit `NOT NULL`/`DEFAULT` decisions | `grep -c CREATE TABLE webapp/sql/inventree.sql` = 38 | ✅ (a file in the project folder) |
| **P1.2** | Resolve every gap the artefact left open, **in the file**, before loading: (a) FK-target tables `auth_user`/`auth_group` dropped per §2 → the 6 `settings.AUTH_USER_MODEL` FKs become plain `int` columns with no index, or are removed; (b) `users_apitoken`'s DRF-inherited columns either reproduced from djangorestframework or dropped along with the whole table (drop it — HIX has JWT + `HIX_KEY_TOKEN`); (c) `longtext`/`json` columns get no `DEFAULT` (MySQL rejects one) | a `-- DECISION:` comment per resolved gap | ✅ |
| **P1.3** | **Verify the row-width envelope** (this is already measured, and it passes): widest table is `part_bomitem` at **22 616 bytes** of `varchar`/`char` at `utf8mb4`; MySQL 8's row limit is 65 535 bytes (1 MiB since 8.0.4). No table needs splitting — `longtext`/`json` are stored out-of-row and do not count | the arithmetic over the artefact, quoted in the plan | ✅ |
| **P1.4** | Add the indexes the artefact does **not** have and the flow needs: `KEY` on every `parent`/`category`/`location` (already present as FK keys), `FULLTEXT` on `name` + `description` + `keywords` for global search, `UNIQUE` on `IPN`/`SKU`/`barcode_hash` where InvenTree declares them | `mysql -e 'SHOW INDEX'` per table | ✅ |
| **P1.5** | Seed data with a **Harbour CLI tool in the project folder**, the pattern the corpus already uses (`create_dbf_ntx.prg`, `migrate_users.prg`): `webapp/create_mysql_sql.prg` — reads `sql/inventree.sql`, splits on `;`, feeds `oConn:Exec()`, reports per-statement errors. `WDO_MySql():New()` is legitimate here (CLI, not a handler — `site-docs/en/wdo/mysql/index.md`) | `./create_mysql_sql` exits 0; `SELECT COUNT(*)` = 0 per table | ✅ T5 (tool inside the project folder) |
| **P1.6** | Seed fixtures: InvenTree's own YAML fixtures (`part/fixtures/part.yaml`, `stock/fixtures/location.yaml`, `order/fixtures/order.yaml`) are the natural seed corpus. A Harbour tool `webapp/seed_inventree.prg` reads a CSV/JSON equivalent and bulk-INSERTs with one `Prepare` outside the loop (`prepared.md` "Bulk INSERT") | row counts match the fixture files | ✅ |
| **P1.7** | `.gitignore`: `sql/` is **source** (tracked); no runtime DB state lives in the repo. Add nothing that could commit a database | `git check-ignore -v webapp/sql/inventree.sql` → not ignored | ✅ |

### Phase P2 — the pool is configured and the app starts with it

| Step | What | Verify by | Grade |
|---|---|---|---|
| **P2.1** | Fill the `"databases": {}` block that already exists in `webapp/www/config.json` with the `mysql` pool (`config.md` Method 1 — declarative). Fields that matter here, not defaults: `driver`, `host`, `port`, `db`, `pool_size`, `timeout_ms`, `ping`, **`read_timeout_s`**, `connect_timeout_s`, `dll`, `berror` | `HIX_InitPoolsFromConfig()` logs `WDO_LOG_POOLS_INIT` "1 pool(s) iniciado(s) OK" | ✅ |
| **P2.2** | **`read_timeout_s` must exceed `exec_timeout_ms`.** `hix.json → server.exec_timeout_ms = 30000` → set `read_timeout_s: 45`. If it is left at the 30 s default, MySQL kills a 30 s query before the dispatcher does and the slot becomes a zombie that never returns to the pool (`config.md` warning) | a query of 31 s returns a MySQL error, not a dispatcher timeout | ✅ |
| **P2.3** | Size the cascade: `MySQL max_connections > HIX pool workers ≥ WDO pool_size`. `hix.json → pool_http.workers = 64` → WDO `pool_size` 8–12, MySQL `max_connections` = pool + 30. Little's Law: 500 req/s × 10 ms = 5 slots | `/health/db` route returning `WDO_PoolStats("mysql")` — `free` never 0 | ✅ |
| **P2.4** | Startup ordering: `Start()` calls `HIX_InitPoolsFromConfig()` (`src/hix_server.prg:238`) and **aborts if a declared pool fails**. With the `mysql` block present, the app cannot start without a reachable MySQL. Decide explicitly: keep the abort (production-correct) or `HIX_InitPoolsFromConfig(.F.)` + 503 handlers (dev-friendly). Do not discover this by watching `==> Error: Cannot load MySQL DLL` | start with MySQL down; the app must either abort loudly or answer 503 with `WDO_PoolStats` diagnostics | ✅ |
| **P2.5** | Credentials must not sit in the docroot. `www/config.json` is inside `paths.root` and its root-level files are downloadable (`PENTEST-REPORT.md` §1; `src/app.prg` already 404s `/config.json` and strips keys from it). Read `DB_HOST`/`DB_USER`/`DB_PWD` from the environment and use `WDO_InitPoolMySqlEx()` in `src/app.prg` instead of the declarative block, following the existing `HIX_KEY_*` pattern | `curl -k https://localhost:9090/config.json` → 404, and the served JSON contains no password | ✅ |

### Phase P3 — the DAL: one object, pool-backed, same public API

The audited models are one-liners over `UDbf()` (`www/models/tcustomers.prg`: `cPath`/`cDbf`/`cCdx`/`cTag`/`Open()`). The MySQL DAL keeps the same call sites so the controllers do not change shape.

| Step | What | Verify by | Grade |
|---|---|---|---|
| **P3.1** | Write `www/models/tdalmysql.prg`: a class with `Open()`, `FetchPaged(nLimit,nOffset,hFilter)`, `FetchAll()`, `Show(nId)`, `Insert(hFields)`, `Update(nId,hFields)`, `Delete(nId)`, `Count(hFilter)`, `Errors()` — the verbs the SRS names, not the verbs MySQL names | the controller for `customer` compiles against it unchanged | ✅ |
| **P3.2** | **Hard rule inside it:** every value that came from a form, URL, JSON or session goes through `Prepare` + `BindParam`/`BindParams`; nothing is concatenated. `Query()` is only for SQL built entirely in code with no external input (`prepared.md` decision tree: "if you would write `Escape()`, write `Prepare()`") | grep the DAL for `+ hb_NToS(` / `+ c` inside a query string → zero hits | ✅ |
| **P3.3** | **`oStmt:Free()` before `oConn:Close()`, always, in `FINALLY`.** Forgotten `Free()` leaves statements alive on the pooled connection (`prepared.md` danger box; `SHOW PREPARED STATEMENTS` accumulates them) | a 1 000-hit loop, then `SHOW PREPARED STATEMENTS` on the server → 0 | ✅ |
| **P3.4** | One `WDO_Get("mysql")` per handler, `oConn:Close()` on every exit path. Never `WDO_MySql():New()` in a controller (the driver logs a warning if it sees it) | `/health/db` `WDO_PoolStats` busy returns to 0 after each request | ✅ |
| **P3.5** | NULL discipline. DBF's "blank ≠ NULL" risk (`INVENTREE-RESEARCH.md` §8) becomes MySQL's: `IS NULL` vs `= ''`, and `BindParam` with an empty string sends `''` not `NULL` (`prepared.md` warning). One predicate used everywhere: `Undef(hVal)` → `NIL` | a table of every optional field, tested both ways | ✅ |
| **P3.6** | Error mapping: `berror` → a named Harbour function that logs with `le()` and answers 500 with the SRS's banner text ("System temporarily unavailable. Please try again later", §5.3), never the MySQL error string (which leaks table names) | a forced SQL error returns the banner, not `Unknown column 'x'` | ✅ |
| **P3.7** | Optimistic concurrency (SRS §5.2 "concurrency control"): add a `version int DEFAULT 0` column to the mutable tables (a deliberate deviation from the artefact, recorded), and make `Update` do `UPDATE … WHERE id = ? AND version = ?` + `Affected_Rows()`; 0 rows → 409 conflict, the SRS's "conflict warning, not blind overwrite" | two sessions edit the same part; the second gets 409 | ✅ |

### Phase P4 — the CRUD verbs, one module at a time

Order of modules = order of risk, cheapest first, and **the verification harness is built with the first module, not after the last** (`INVENTREE-RESEARCH.md` §9.5; `PRODUCTION-BLOCKERS-2026-10-07.md` B1 is the lesson: two of three functional suites verified nothing).

| Step | Module | Steps inside it | Grade |
|---|---|---|---|
| **P4.1** | `part` (12 tables in play) | routes in `www/routes/web.json` (the `customer.*` block is the template: `grid` `search` `create` `store` `show` `edit` `update` `delete_confirm` `delete`), controllers `controllers/masters/*@part.prg`, views `masters/part/{grid,edit,delete}.html`, middleware `MyAppAuthRole`/`MyAppAuthRoleEdit`, scope `parts:search`/`parts:create`/`parts:edit`/`parts:delete` | ✅ |
| **P4.2** | `stock` | same shape; `stock_stockitem` FKs to `part_part` and `stock_stocklocation` make the FK-policy decision from Step 0.3 observable — test delete here | ✅ |
| **P4.3** | `company` + `part_supplierpart` | price breaks, currency columns (`price` + `price_currency` `char(3)`) | ✅ |
| **P4.4** | `bom` | recursive resolve with a depth cap and a cycle guard; **aggregates now come from SQL** (`SUM`, `COUNT`, `AVG`) instead of the counter tables the DBF plan needed | ✅ |
| **P4.5** | `order` (receive / allocate) | **one transaction per verb**: `oConn:BeginTrans()` … `Commit()`, or `oConn:Transaction(bCode)`; `TRY/CATCH/FINALLY` with `Rollback` in `CATCH` and `Close()` in `FINALLY` (`transactions.md`) | ✅ |
| **P4.6** | `build`, `stocktake`, `test results` | same | ✅ |
| **P4.7** | settings / notes / attachments / project codes | plain CRUD; attachments keep files on disk (`HIX_SafePathAllowed`) and store only the path in `varchar(100)` | ✅ |
| **P4.8** | `users` — the app's own store, not InvenTree's (Step 0.2's Option A) | a shipped table for the credential store (the artefact's `auth_user` was dropped by P1.2a because HIX owns users, so the table is HIX's and its addition is a recorded decision), `www/controllers/masters/users.prg` re-implemented on the DAL, `www/models/modeluser.prg` (login) reading it, a Harbour seeder replacing `regenerate_users.prg`, and D-01…D-16 re-proven over the new store | ✅ **done 2026-10-07** — see `03-implementation/P4-8-USERS-RESULTS-2026-10-07.md` |

### Phase P5 — the machinery MySQL replaces

These steps **delete** work from the DBF plan; they are listed so the deletion is deliberate, not accidental.

| Step | DBF-plan machinery | MySQL substitute | Grade |
|---|---|---|---|
| **P5.1** | `tcounter.prg` maintained aggregates + `ApplyStockDelta()` choke point + reconcile route | `SELECT SUM(...)`, `COUNT()`, `AVG()` over the FK indexes; the 209 ORM aggregation call sites become SQL | ✅ |
| **P5.2** | journal DBF + `HIX_PoolLock` + replay for multi-table atomicity | `BeginTrans`/`Commit`/`Rollback`; the pool auto-rolls back a slot closed mid-transaction (`transactions.md`) | ✅ |
| **P5.3** | the 10-char rename table (30.8 % of InvenTree's field names exceed `CDX_MAXTAGNAMELEN 10`) | **not needed** — MySQL identifiers take the full names; the API emits them directly | ✅ |
| **P5.4** | `Rlock(3 s)` / `DbCommit` / `DbUnlock` single-writer discipline | pool slots + MySQL; the SRS's optimistic-concurrency step (P3.7) replaces the lock | ✅ |
| **P5.5** | `hix.json → app.auto_close_dbf` | set `false` under Option A (Step 0.2); keep `true` under Option B | ✅ |

### Phase P6 — the machinery MySQL does **not** replace (do not pretend otherwise)

Carried forward unchanged from `INVENTREE-RESEARCH.md` §5, minus the three MySQL removes:

1. no permissions graph beyond role + scope (`RuleSet`/`Owner` tables exist in the schema but the
   graph is not built by MySQL);
2. no template/PDF/imaging/markdown pipeline;
3. no QR / DataMatrix generator;
4. no plugin VM compatible with InvenTree's plugins;
5. no SPA toolchain — Mambo views, and the product description must say so;
6. no HTTP `Range` in HIX's static dispatcher → attachments stay whole-file;
7. **still no schema-migration tool**: 185 migrations of history remain a bespoke Harbour tool per
   change (the `webapp/` pattern). MySQL adds `ALTER TABLE` syntax, not a migration runner.

### Phase P7 — verification, built with P4.1

| Step | What | Grade |
|---|---|---|
| **P7.1** | Sliced suite in `tests/` (local tooling, untracked — the root `.gitignore` rule), asserting **on DB state before/after each verb**, not on HTTP codes | ✅ T5 |
| **P7.2** | An FK-orphan check route (`/hix-fk-check`, admin-gated): for each of the 165 FK columns, `SELECT COUNT(...) WHERE <fk> IS NOT NULL AND <target> IS NULL` — must be 0 after every delete test | ✅ |
| **P7.3** | An aggregate-reconcile route: SQL `SUM` vs any cached value; the DBF plan's "aggregate drift" risk disappears, but the check stays because the DAL caches | ✅ |
| **P7.4** | A pool-leak check: 1 000 mixed requests, then `WDO_PoolStats` `busy == 0` and `SHOW PREPARED STATEMENTS` empty | ✅ |
| **P7.5** | A transaction-interruption check: kill the request mid-`BeginTrans` (dispatcher `exec_timeout_ms`), assert the pool's automatic rollback left the tables unchanged | ✅ |

---

## 5. Sequencing and where to stop

| Milestone | Steps | Gate to proceed |
|---|---|---|
| **M1 — the DB exists and the app starts with it** | 0.1–0.3, 1.1–1.7, 2.1–2.5 | `inventree migrate`-equivalent load + `/health/db` green + pool stats sane |
| **M2 — one DAL, one module, verified** | 3.1–3.7, 4.1, 7.1–7.5 | the sliced suite asserts state changes for `part`; **do not start M3 until this is green** |
| **M3 — inventory core** | 4.2–4.4 | FK-orphan check 0; aggregates reconcile |
| **M4 — mutations** | 4.5–4.6, 7.5 | transaction interruption leaves state unchanged |
| **M5 — support tables + thin UI** | 4.7, views | the SRS's FR-* checklist re-scored against `part` the way `DAL-CHECKLIST.md` scored it for `customer` |
| **Stop here** | — | API parity beyond the flow, reports/labels, and any SPA-shaped UI are not worth starting (research §9.4) |

---

## 6. Compliance grading of the plan as a whole

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | every step keeps the HIX MVC shape: `www/models` DAL, `www/controllers` verbs, `www/views` Mambo, `www/routes` JSON, middlewares, scopes |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the clause is exempt for P1 and the later phases of this plan; `01-requirements/DEV-compliance.md` carries the Exception block, scoped to this plan only, and still forbids SQL everywhere else |
| **T3** No 3rd-party web UI | ✅ | Mambo views; MySQL is a database, not a UI |
| **T4** Only HIX + Harbour | ✅ | the driver is framework code: `hix_server.hbp:131-136` → `src/wdo/mysql/{wdo_mysql,wdo_mysql_stmt,wdo_mysql_stmt_bin,wdo_mysql_pool}.prg`, already in `hix_server.hbx` |
| **T5** Tools in the project folder | ✅ | `create_mysql_sql.prg`, `seed_inventree.prg`, `sql/inventree.sql` all under `webapp/`, following `create_dbf_ntx.prg`/`migrate_users.prg` |
| **T6** No change outside the project folder | ⚠️ | P0.3 (MySQL server), P0.4 (charset), P0.1 on Linux (the `.so`). Host obligations, recorded as such — same class as `LETS-ENCRYPT-PLAN.md` certbot |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` lists exactly one source, `src/app.prg`; everything under `www/` is runtime-loaded, so DAL/controller/model changes never touch the build. Only P2.5 (env credentials) edits `src/app.prg`, which `app.hbp` already builds |
| **T8** Port 9090 | ✅ | untouched by every step |

---

## 7. Evidence — how each number in this plan was obtained

| Claim | Source |
|---|---|
| 79 tables / 895 columns / 165 FKs / 24 unique keys (9 composite) | the artefact's own index block, `webapp/srs/02-design/INVENTREE-MYSQL-SCHEMA.sql` |
| `on_delete` distribution CASCADE 68 / SET_NULL 69 / DO_NOTHING 3 / 5 `GenericForeignKey` | AST over `src/backend/InvenTree/*/models.py` in the sparse clone |
| widest row 22 616 bytes (`part_bomitem`), 0 tables over 65 535 | arithmetic over the artefact: `varchar(n)`/`char(n)` × 4 (utf8mb4) + 1 per column |
| `www/config.json` already has `"databases": {}` | `webapp/www/config.json` |
| `Start()` auto-inits pools and aborts on failure | `src/hix_server.prg:238` `HIX_InitPoolsFromConfig()`; `:384` `HIX_EndPoolsFromConfig()` |
| `exec_timeout_ms = 30000`, `pool_http.workers = 64`, `auto_close_dbf = true` | `webapp/hix.json` |
| DLLs already in the repo | `resources/wdo/mysql/dll/{libmysql64.dll 5 191 680 B, libmariadb64.dll 1 028 968 B}` |
| driver is framework code | `hix_server.hbp:131-136` |
| `app.hbp` builds one source | `webapp/app.hbp` → `src/app.prg` |
| pool / prepared / transaction API | `site-docs/en/wdo/mysql/{index,config,usage,prepared,transactions}.md`; working example `examples/web/hi/www/controllers/api_mysql_demo.prg` (284 lines) |
| DAL pattern and its known-bad calls | `www/models/tcustomers.prg`, `www/routes/web.json`, `02-design/DAL-CHECKLIST.md` |
| the verification lesson | `04-verification/PRODUCTION-BLOCKERS-2026-10-07.md` B1 |
| the DBF variant's blockers, packages, cost | `INVENTREE-RESEARCH.md` §5 §7 §8 |
