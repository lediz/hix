# P1 (the shipped schema) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P1 only** of `INVENTREE-MYSQL-PLAN.md` (P1.1–P1.7). P0 was already
> green (`P0-MYSQL-HOST-RESULTS-2026-10-07.md`). P2 and later were not started:
> `www/config.json` still has `"databases": {}`, `src/app.prg` is untouched, the
> WebApp was not rebuilt, and `webapp/data/*.dbf` is still the app's state.

---

## 1. What P1 had to prove, and the verdict

| Step | Claim | Result |
|---|---|---|
| **P1.1** | a shipped schema file, 38 tables, FK dependency order, `CREATE TABLE … KEY` inline, explicit `NOT NULL`/`DEFAULT` decisions | ✅ `webapp/sql/inventree.sql`, 66 481 bytes, `grep -c '^CREATE TABLE'` = **38**, MariaDB accepted **all 38 statements, 0 errors** |
| **P1.2** | every gap the artefact left open, resolved **in the file** | ✅ 26 `-- DECISION P1.2a` comments (one per FK whose target is not shipped), `users_apitoken` dropped whole, `longtext`/`json` no-DEFAULT **asserted** over the artefact (the derivation raises if it ever finds one) |
| **P1.3** | the row-width envelope | ✅ recomputed over the shipped file: widest is `part_bomitem` at **22 616 bytes** of `varchar`/`char` at `utf8mb4` (4/char + 1), MariaDB 8's limit is **65 535** — the plan's number, reproduced, 0 tables need splitting |
| **P1.4** | the indexes the flow needs | ✅ **21 `FULLTEXT KEY ft_name/ft_description/ft_keywords`**, **11 `KEY ix_IPN/ix_SKU/ix_barcode_hash`**, 78 FK keys, 8 UNIQUE, 38 PRIMARY. Read back from the server with `DESCRIBE` (see §3: `SHOW INDEX` does not work here) |
| **P1.5** | a Harbour CLI loader in the project folder | ✅ `webapp/create_mysql_sql.prg` + `.hbp`; `./create_mysql_sql load` → 38 statements, 0 errors; `./create_mysql_sql verify` → `COUNT(*) = 0` for all 38 tables; **exit 0** |
| **P1.6** | seed fixtures, bulk-INSERT style | ✅ `webapp/seed_inventree.prg` + `.hbp`; **150 rows into 25 tables**, every table's `SELECT COUNT(*)` equal to its CSV row count; **exit 0** |
| **P1.7** | `sql/` is source, no DB state in the repo | ✅ `git check-ignore -q webapp/sql/inventree.sql` → not ignored; `webapp/create_mysql_sql` and `webapp/seed_inventree` **are** ignored (line 61/62 of `webapp/.gitignore`); `.mysql/` still ignored |

P1 is green. The gate for P2 is: `./create_mysql_sql recreate` exits 0 and
`./seed_inventree verify` exits 0 with the counts above.

## 2. What the file actually contains

| | |
|---|---|
| Tables | **38** — the plan's subset, verbatim |
| Columns | **517** |
| FK relations kept | **78** (as `KEY fk_…`, MySQL's only share of the relation) |
| FK relations dropped | **26** — targets `auth_user`, `auth_group`, `contenttypes_contenttype`, and two InvenTree tables outside the subset (`common_selectionlist`, `part_parttesttemplate`) |
| Indexes added by P1.4 | 21 FULLTEXT + 11 exact-match KEY |
| UNIQUE | **8**, all of them InvenTree's own — **none invented**. The plan says "UNIQUE on `IPN`/`SKU`/`barcode_hash` where InvenTree declares them"; InvenTree does not declare those three unique, so they got a plain `KEY` for lookup and nothing more |
| Order | FK dependency order, topologically sorted over the 78 kept edges: `stock_stocklocationtype` … `part_part` … `stock_stockitem` … `users_ruleset`. Self-edges (`part.variant_of → part.id`) are not treated as dependencies |
| Seed corpus | **25 CSVs, 150 rows**, the CSV equivalent of InvenTree's own Django fixtures at the same commit the artefact came from (`575fbdc9072dee89bc5624cb7b2604829826f552`) |
| Shipped tables with no fixtures | 13: `common_attachment` `common_barcodescanresult` `common_inventreeusersetting` `common_note` `common_projectcode` `company_address` `part_partpricing` `part_partstocktake` `stock_stockitemtracking` `stock_stocklocationtype` `users_owner` `users_ruleset` `users_userprofile` |

## 3. Facts the plan got wrong, found by running it

These are the corrections a later session must not re-discover.

| Plan said | Reality on MariaDB 13.0.2 / Harbour 3.2.1dev |
|---|---|
| P1.4 "verify by `mysql -e 'SHOW INDEX'` per table" | **`SHOW INDEX` does not parse.** `SHOW INDEX t`, `SHOW KEY t`, `SHOW KEYS t`, `SHOW INDEXES t`, `SHOW KEY STATISTICS FOR t`, `SHOW KEY CONFIGURATION FOR t`, `SHOW COLUMNS t` are all rejected through the WDO driver, quoted and bare alike. **`DESCRIBE <table>`** is the form that parses, and its 4th field is the key flag (`PRI`/`UNI`/`MUL`); `create_mysql_sql` and `seed_inventree` count keyed columns with it |
| `json` columns are a JSON type | MariaDB reports them as **`longtext`** in `DESCRIBE` — `json` is an alias, not a native type on this server. 33 of them ship in these 38 tables (the artefact has 62 across all 79); `SELECT … JSON_…` functions are not available |
| `oConn:Exec()` for the loader (P1.5's own words) | kept from P0: `Exec()` raises a DynCall "Argument error" for the account statements, so **every** call here is `Query()` + `FetchAll(.F.)` + `Free()`, and writes go through **`Prepare` + `BindParam` + `Execute`** |
| Harbour's `Main` receives an argument array | it does not. `Main( aArg )` receives the **first argument as a string** — `LEN( aArg )` returned 4 for `load`, then `aArg[ 1 ]` raised "Argument error: array access". Both tools take `Main( cModeArg )` |
| a backtick is safe in Harbour source | the preprocessor eats it (P0's row, re-hit): `"`"` became an empty string, `_PosIn( stmt, "" )` returned 0 and the loader found **0 tables out of 38**. Both tools build it as `CHR( 96 )` |
| `POS()` and `IIF()` exist | neither is in the RTL this build links. Own `_PosIn()` helper; the `iif()` call was replaced with an `IF` |
| `SELECT COUNT(*)` returns a number | it came back textual on this path and `nGot != nWant` against a Harbour number raised **BASE/1072 "Argument error: <>"**. `VALTYPE()` is available, so the comparison coerces |
| an empty CSV cell means NULL | it must not. `NOT NULL` + `DEFAULT ''` and `NULL` are two different things, and P3.5 is about exactly that. The corpus writes **MariaDB's own `\N` for NULL** and an empty cell for the empty string; the converter decides which one applies from the schema, not from the fixture |
| the fixtures supply every NOT NULL column | they do not. `external`, `is_template`, `is_customer`, `link`, `pack_quantity`, `barcode_hash`, `reference`, `received`, `notes` were all omitted by a fixture that shares the column with one that supplies it — MariaDB's `STRICT_TRANS_TABLES` (P0.4) answered **"Column 'x' cannot be null"**. The DEFAULT the schema already decided is what lands |
| a fixture field maps to a column | `content_type: ['part', 'part']` on `model_type`, which is a plain `int` once its FK target is not shipped. The converter **reports** it (`common.parameter.model_type is list on a int column`) and leaves the column alone; it does not stringify a list into an int |
| the fixture corpus is in the repo | it is not. Nothing on this checkout is an InvenTree clone, so the YAML was fetched from the pinned commit into `/tmp`, and only its **CSV equivalent** went into `webapp/sql/fixtures/` |
| `django-mptt`'s `level` is a column | the artefact carries `tree_id`/`lft`/`rght` only. The fixtures' `level:` is reported as not-in-schema, not rendered as a `varchar(255)` column — the artefact's own lesson (`StockItem.IN_STOCK_FILTER`) |

## 4. What was written

| Path | What | Tracked? |
|---|---|---|
| `webapp/sql/inventree.sql` | the shipped schema: 38 tables, dependency order, decisions in the file | yes (not ignored; nothing commits it yet) |
| `webapp/sql/fixtures/<table>.csv` × 25 | the seed corpus, CSV equivalent of InvenTree's fixtures | yes |
| `webapp/create_mysql_sql.prg` + `.hbp` | P1.5 loader: `load` / `recreate` / `verify` | yes |
| `webapp/seed_inventree.prg` + `.hbp` | P1.6 seeder: `seed` / `verify`, one `Prepare` outside the loop | yes |
| `webapp/.gitignore` | `+ create_mysql_sql` `+ seed_inventree`, and a comment saying `sql/` is source and must stay tracked | yes |
| `webapp/srs/02-design/derive-shipped-schema.py` | artefact → shipped schema (P1.1/P1.2/P1.3/P1.4) | tooling |
| `webapp/srs/02-design/fixtures_to_csv.py` | InvenTree's YAML fixtures → CSV (P1.6 corpus) | tooling |

Nothing was added under `src/`, `www/`, `data/`, `examples/`, `resources/`.
`www/config.json` still has `"databases": {}` — **P2.1 was not taken**, so the
app still cannot see this database and still does not need it.

## 5. Verification actually run

```
$ ./gen_mysql_db.sh status                       -> running (pid 439670)

$ ./create_mysql_sql load
  schema  : sql/inventree.sql        bytes : 66481
  tables  : 38 (expected 38)         stmts : 38
  server  : 13.0.2-MariaDB           P0.2 : override /usr/lib/libmysqlclient.so
  loaded  : 38 statements, 0 errors
  count<every table> = 0             index<every table> = N keyed of M cols
  RESULT : ok                        rc = 0

$ ./create_mysql_sql recreate                    -> drops the 38 it names, recreates
  RESULT : ok                        rc = 0

$ ./seed_inventree seed
  seeded stock_stocklocation = 7 rows (7 in the CSV)   seeded part_part = 14 (14)
  … 25 tables, every one matching …                    13 report "no fixtures"
  RESULT : ok                        rc = 0

$ ./seed_inventree verify
  count<every table> == its CSV row count, 0 for the 13 without fixtures
  RESULT : ok                        rc = 0

$ git check-ignore -q webapp/sql/inventree.sql   -> not ignored
$ git check-ignore -v webapp/create_mysql_sql    -> webapp/.gitignore:61:create_mysql_sql
$ git check-ignore -v webapp/seed_inventree      -> webapp/.gitignore:62:seed_inventree
```

* **idempotency**: `recreate` drops only the tables the file names — never the
  database, which also holds MariaDB's own `test`, `performance_schema`, `sys`
  (P0 §5.1). A second `seed` after a `load` without `recreate` would double the
  counts; `verify` is what catches that, and it is the check P7.1 will re-use.
* **no interactive hang**: every statement is inside `TRY/CATCH/FINALLY`, both
  tools were run under `timeout`, and the failure modes that used to open
  Harbour's "Quit" dialog are all caught.

## 5.1 Restart hazards found while cycling this step

| Found | Effect | Handling |
|---|---|---|
| `create_mysql_sql load` run twice against a live host | the second run answers "table already exists" × 38 and exits 1 | that is the point of `recreate`; do not "fix" `load` by ignoring the error |
| the seeder's `Prepare` is per table, its `Free()` is in `FINALLY` | a `Prepare` that raises leaves `oStmt` NIL and the `FINALLY` guard skips it — correct, but a forgotten `Free()` would leave statements alive on a pooled connection (`SHOW PREPARED STATEMENTS` accumulates them) | kept exactly as `prepared.md`'s defensive pattern; P7.4's 1 000-hit check still has to run, this only proves the shape |
| `EXIT` inside `TRY` (a `BEGIN SEQUENCE`) | breaks the sequence and skips the rest of the corpus, silently | the row loop sets a flag and counts instead; the failure is reported per row |
| the CSVs are regenerated, not edited | `rm -rf webapp/sql/fixtures` then re-run the converter; hand edits to a CSV are lost | the converter is the source of the corpus; say so in the file it writes? it does not — this table is the record |

## 6. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | the app is untouched; the two tools are CLI, the pattern `create_dbf_ntx.prg` / `migrate_users.prg` already sets |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the clause is exempt for **P1 and the later phases of this plan**; `01-requirements/DEV-compliance.md` carries the Exception block and still forbids SQL everywhere else — including the `webapp/` DAL as it ships today, which is unchanged |
| **T4** HIX + Harbour only | ✅ | the driver is framework code (`src/wdo/mysql/*.prg` → `hix_server.hbx`); both tools link `${hix}/hix_server.hbx` + `.hbc` and build with `hbmk2` |
| **T5** tools in the project folder | ✅ | `sql/inventree.sql`, `sql/fixtures/`, `create_mysql_sql.prg`, `seed_inventree.prg` all under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only outside action was fetching InvenTree's fixture YAML into `/tmp`; what ships is the CSV inside the folder. The database remains under `webapp/.mysql/`, gitignored |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched; each tool has its own `.hbp`, like every other probe/tool here |
| **T8** port 9090 | ✅ | untouched; MariaDB listens on 3306 |

## 7. Ready for P2, and what P2 must not assume

Ready: a MariaDB 13.0.2 answering on 127.0.0.1:3306, database `inventree`,
account `harbour`@`localhost`, **38 shipped tables loaded and seeded with 150
fixture rows**, and a proven path from Harbour to it (`WDO_MySql():New(...)`
with the library pinned, `Query()`/`Prepare()` for everything).

P2 must not assume:

1. **that the app can see any of this.** `www/config.json` still has
   `"databases": {}`. P2.1 fills it; `Start()` calls `HIX_InitPoolsFromConfig()`
   and **aborts** if a declared pool fails, so adding the block without
   `./gen_mysql_db.sh start` makes the app unstartable (P0 §7 said the same).
2. **that `SHOW INDEX` works.** It does not, in any spelling, through this
   driver. `DESCRIBE <table>` is the introspection that works.
3. **that `json` columns behave as JSON.** They are `longtext` on MariaDB.
4. **that the 13 tables without fixtures are empty by design.** They are empty
   because InvenTree's fixtures do not cover them; P4 will fill them through the
   DAL, and P7.1 must assert state before/after each verb, not HTTP codes
   (`PRODUCTION-BLOCKERS-2026-10-07.md` B1 is the lesson).
5. **that FKs are enforced.** MySQL/MariaDB carries only the `KEY` index. The
   78 relations are the DAL's policy surface (Step 0.3: CASCADE 68 / SET_NULL 69
   / DO_NOTHING 3), and the 26 dropped ones have no relation at all — their
   columns are plain ints whose key space is HIX's users module.
6. **that ids come from `Last_Insert_Id()`.** The seed flow inserts the fixtures'
   `pk:` explicitly, because the fixtures' FK values are pks. Only the create
   flow reads `Last_Insert_Id()` (Step 0.3).
7. **that the DBF state went away.** `webapp/data/*.dbf` and
   `hix.json → app.auto_close_dbf` are untouched — Step 0.2 (Option A) was **not**
   taken this session.
