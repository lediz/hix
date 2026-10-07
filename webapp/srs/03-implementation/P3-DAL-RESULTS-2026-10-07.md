# P3 (the DAL) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P3 only** of `INVENTREE-MYSQL-PLAN.md` (P3.1–P3.7). P0, P1 and P2
> are green. P4 was not started: no route and no controller uses the DAL yet, and
> the audited `customer` / `users` modules still run on DBF.

---

## 1. What P3 had to prove, and the verdict

| Step | Claim | Result |
|---|---|---|
| **P3.1** | one DAL object, pool-backed, the SRS's verbs | ✅ `webapp/www/models/tdalmysql.prg`: `Open/Close`, `Count`, `FetchAll`, `FetchPaged`, `Show`, `Insert`, `Update`, `Delete`, `Orphans`, `Errors`. **The plan's verify-by ("the controller for `customer` compiles against it unchanged") is false** — see §2 |
| **P3.2** | every external value through `Prepare` + `BindParam`; nothing concatenated | ✅ `grep` over the DAL for a value concatenated into SQL: **0 hits** (the only `+` near a name is a log message). SQL text is built from code-known names plus `?` placeholders |
| **P3.3** | `oStmt:Free()` before `oConn:Close()`, always | ✅ 200 × 3 mixed calls (Count / Show / FetchPaged) on one slot, then `Count()` still answers; every statement is freed on every path, including the one that broke the sequence |
| **P3.4** | one `WDO_Get` per handler, `Close()` on every exit path, never `New()` | ✅ `Open()` acquires once, `Close()` returns it, idempotent; the DAL contains no `WDO_MySql():New()` |
| **P3.5** | NULL discipline, one predicate | ✅ a field **absent** from the hash → SQL `NULL`; a field **present with `""`** → `''`. Measured: after one insert, `keywords IS NULL` = 15 and `link = ''` = 1 |
| **P3.6** | errors answer the SRS banner, never the server's words | ✅ `Errors()` returns `{"banner" => "System temporarily unavailable. Please try again later.", reason, detail}`; the server's message goes to the log (`_l(..., 4, "tdalmysql")`); the pool's `berror` handler `APP_MYSQL_BERROR` is wired in `src/app.prg` and resolves (no `WDO_WARN_BERROR_NOT_FOUND` in `.logs/hix.log`) |
| **P3.7** | optimistic concurrency on a `version` column | ✅ `Update(nId, nVersion, hFields)` → `UPDATE … SET …, version = ? WHERE id = ? AND version = ?`; first write with the version read → ok, `version` becomes 1; a **stale** version → refused, reason `conflict`, and `description` unchanged (state asserted, not just the return code) |

P3 is green. The gate for P4 is the harness (`./probe_dalmysql`) exiting 0 plus
`/health/db` 200 with `free` never 0.

## 2. What the file actually contains, and the deviation the plan got wrong

**The plan's P3.1 verify-by is wrong.** The audited call surface is `UDbf()`'s
verbs, not the SRS's:

| | |
|---|---|
| `www/models/tcustomers.prg` | `TCustomers() := UDbf()` with `cPath` / `cDbf` / `cCdx` / `cTag` and `Open()` |
| what the controllers actually call | `GetRecno( nRecno, @hRow, NIL, .T. )`, `Blank( .T. )`, `Insert()`, `Update()`, `Delete()`, `Hide()`, `Close()`, and the `c*` members |
| why it cannot compile unchanged | `GetRecno` is **recno-based**, and MySQL has no recno — ids are server-assigned (Step 0.3). Reproducing the UDbf surface over MySQL would mean inventing an ordering that recno implies |

So the DAL ships the SRS verbs, and **P4.1's new `part` controllers call those**.
The audited `customer` / `users` controllers keep running on DBF — Step 0.2
(Option A: MySQL replaces DBFCDX) has still not been taken, and a pool existing
does not imply it.

| | |
|---|---|
| `New( cTable, aCols )` | `aCols` is a **column whitelist**. The KEYS of a field hash are external input as well — they become column names in the SQL — so unknown keys are dropped and logged, never quoted into a statement. The plan's signature took only `hFields`; this deviation is recorded here |
| FK graph | read from `sql/inventree.sql` at runtime (`CREATE TABLE` + `KEY \`fk_…\` (col) /* -> target.id */`), cached once per process. The object carries no second copy of the relations, so it cannot drift from what loaded |
| `Delete( nId, hPolicy ) | policy per **target table** (`CASCADE` / `NULL` / anything else = keep). Default is DO_NOTHING: it leaves the orphan visible to `Orphans()` instead of guessing |
| `Orphans()` | `SELECT COUNT(*) … WHERE fk IS NOT NULL AND NOT EXISTS ( target.id = fk )` per FK column |

## 3. Facts the plan got wrong, found by running it

| Plan said | Reality on HIX 2.3.10 / Harbour 3.2.1dev / MariaDB 13.0.2 |
|---|---|
| P3.7 "add a `version int DEFAULT 0` column to the mutable tables" | it is not in P1's shipped file (`grep -c version` was **0**), so it had to be added to the **derivation** (`derive-shipped-schema.py`), then `./create_mysql_sql recreate` — which **drops the tables and wipes P1's 150 seeded rows**, so `./seed_inventree seed` has to run again. Applied to all 38 tables, not to a judgement of which are mutable (P4.7 edits the support tables through plain CRUD too; a per-table judgement would be an unrecorded guess) |
| `oConn:Affected_Rows()` for the conflict test | it reports **0 for a prepared UPDATE** on this driver. The statement's own count is what works: `oStmt:Row_Count()` (prepared.md lists it as "rows affected (INSERT/UPDATE/DELETE) or returned (SELECT)"), read **before** `Free()` |
| the create flow reads `oConn:Last_Insert_Id()` | it returns **0 after `oStmt:Free()`**. Read while the statement is alive; the DAL keeps it in `::nLastId` |
| `SELECT COUNT(*)` returns a number | it came back **textual** on this path, and comparing it with a Harbour number raises **BASE/1072 "Argument error: <>"**. `_DalRowNum()` coerces with `VALTYPE()`/`VAL()` — the same coercion P2's health route needed |
| `le()` is available to a model | `le()` is a `#xtranslate` in `src/include/hix_logger.ch`. A runtime-loaded model must not depend on that header being on the runtime include path, so the DAL calls the framework function directly: `_l( msg, 4, "tdalmysql" )` |
| `TRY / CATCH / FINALLY` are Harbour syntax | they are `#xcommand` macros in `src/include/hix_const.ch` (P0's row, re-hit). The DAL uses the core form — `BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }` and the `Free()` guard **after** the sequence, which runs on every path — so it compiles without that header |
| a helper can return rows through an out-parameter | it cannot. Harbour re-binding a parameter breaks the reference, so the caller kept its old NIL — every DAL call silently "failed with no error". The helpers return the rows: **NIL = it failed**, an **EMPTY array = it ran and found nothing**. That distinction is load-bearing in `Count()`, `Show()` and `_DalWhy()` |
| P3.3's verify-by `SHOW PREPARED STATEMENTS` | same family as `SHOW INDEX`, which this MariaDB rejects through the driver in every spelling (P1 §3). Not used; the check is 200 × 3 mixed calls on one slot followed by a working `Count()` |
| Step 0.3's policy is available per FK | the artefact records only the **distribution** — CASCADE 68 / SET_NULL 69 / DO_NOTHING 3 — not which FK is which, and the per-FK values would need the InvenTree model source, which is not on this checkout. So `Delete()` ships DO_NOTHING as the default and the policy hash is filled per module when P4 decides it. Guessing per FK would be a silent product decision |
| the FK-orphan check is meaningful for the subset | `Orphans()` on `part_part` is **4 today**, and those are FKs to targets outside the shipped subset (`part_parttesttemplate`, `common_selectionlist`) — the columns are shipped, the tables are not, so the target row can never exist. P7.2's check has to exclude those edges |
| the DAL is runtime-loaded, so no rebuild | true for the DAL, but P3.6's `berror` handler lives in `src/app.prg`, which `app.hbp` builds — so P3 does rebuild the app (6 848 312 B) |

## 4. What was written

| Path | What | Tracked? |
|---|---|---|
| `webapp/www/models/tdalmysql.prg` | the DAL (P3.1–P3.7) | new |
| `webapp/src/app.prg` | `hParams["berror"] := "APP_MYSQL_BERROR"` and the non-static handler that logs with `_l(..., 4, "mysql")` (P3.6) | modified |
| `webapp/srs/02-design/derive-shipped-schema.py` | the `version` column, with the `-- DECISION P3.7` line in every table | modified |
| `webapp/sql/inventree.sql` | regenerated: 38 tables, **38 `version` columns**, 555 columns total | modified |
| `webapp/test/probe_dalmysql.prg` + `webapp/probe_dalmysql.hbp` | the harness (local tooling, like the other probes — `webapp/test/` is gitignored) | no |

Nothing was added under `www/controllers/`, `www/routes/` (P4.1's job), `data/`,
`src/wdo/` or `resources/`. **No framework file was edited.**

## 5. Verification actually run

```
$ python3 webapp/srs/02-design/derive-shipped-schema.py … > webapp/sql/inventree.sql
  38 tables, 38 version columns
$ ./create_mysql_sql recreate   RESULT : ok   rc=0     (38 CREATE TABLE, 0 errors)
$ ./seed_inventree seed         RESULT : ok   rc=0     (150 rows, 25 tables)
$ ./seed_inventree verify       RESULT : ok   rc=0

$ ./probe_dalmysql              PASS 16  FAIL 0   rc=0
  1  part_part rows before: 14
  2  inserted id: 10018            keywords IS NULL = 15   link = '' = 1
  3  Show id 10018 version 0
  4  update with version 0: ok                       version = 1 asserted
  5  stale update refused, reason: conflict          description unchanged
  6  Count(IPN=P3-IPN-1) = 1        FetchPaged(1,0) = 1 row
  7  rows after a bad insert: 15 (expected 15)       banner is the SRS text ? .T.
     detail names the table ? .F.
  8  parts in category 8: 2         orphans in part_part before: 4
  9  after 200 x 3 calls, Count() still answers: 15
 10  delete -> rows after: 14

$ hbmk2 app.hbp && ./app        (DB_PWD from .mysql/credentials)
  app.prg: MySQL/MariaDB pool 'mysql' … pool_size=8 read_timeout_s=45
  » WDO Loaded  MariaDB 2.0
  /config.json            -> 404
  /health/db  no session  -> 302
  /health/db  session     -> {"ok":true,"driver":"MYSQL","size":8,"busy":0,"free":8,"closed":false}
  /main /users/grid /customer/grid -> 200 200 200   (DBF DAL not regressed)
  .logs/hix.log: no WDO_WARN_BERROR_NOT_FOUND       (the handler resolved)
```

* **state, not codes**: every assertion reads the table before and after the
  verb (`PRODUCTION-BLOCKERS-2026-10-07.md` B1 is the lesson — two of three
  functional suites verified nothing).
* **idempotency**: the harness deletes its own rows at start and at the end, so
  a second run measures from the same base (14).

## 5.1 Restart hazards found while cycling this step

| Found | Effect | Handling |
|---|---|---|
| a harness run that stops half way | leaves rows in `part_part`, and the next run's "rows before" is wrong | the harness deletes `IPN = 'P3-IPN-1'` and `name = 'P3 harness part'` at start; final state verified back to 14 |
| `create_mysql_sql recreate` after the schema changed | wipes the seeded corpus silently | `seed_inventree seed` is part of the sequence, and `verify` is what proves it |
| the DAL's helpers returning rows through an out-parameter | every call looked like "failed with no error recorded", which reads as a working DAL that does nothing | the helpers return the rows; the record says why |
| `Errors()` returning NIL for a conflict | the caller indexing it crashes with BASE/1068 "Argument error: array access" | the conflict branch sets `cErrSafe` as well as `cLastReason` |

## 6. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | the DAL is a Harbour CLASS in `www/models/`, the same place and shape as `tcustomers.prg` / `tusers.prg`; it is runtime-loaded, so no controller or view change needs a build |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the exception is scoped to P1 and the later phases of this plan; the DAL is one of them. The audited `www/models/t*.prg` still contain no SQL, and nothing outside this plan does |
| **T4** HIX + Harbour only | ✅ | `WDO_Get`, `Prepare/BindParam/Execute/Free`, `Row_Count`, `Last_Insert_Id`, `_l()` are framework code; the DAL includes only `hbclass.ch` |
| **T5** tools in the project folder | ✅ | everything is under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only host action was the already-documented recreate/seed cycle inside `webapp/.mysql/` |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched, still lists exactly `src/app.prg`; the DAL needed no build at all |
| **T8** port 9090 | ✅ | untouched; the checks ran against the existing self-signed TLS |

## 7. Ready for P4, and what P4 must not assume

Ready: a DAL whose verbs are verified against real state, a pool the app starts
with, and a schema that carries `version` in all 38 tables.

P4 must not assume:

1. **that any route or controller uses the DAL yet.** `/health/db` is the only
   new route and it deliberately borrows no slot. P4.1 writes the `part`
   routes/controllers/views and calls these verbs.
2. **that the audited `customer` / `users` modules moved.** They still run on
   DBF (`hix.json → app.auto_close_dbf` is `true`, `data/*.dbf` is still state).
   Step 0.2 is a product decision to record, not something a DAL implies.
3. **that `Delete()` cascades by default.** It does not: the default is DO_NOTHING
   and the orphan stays visible to `Orphans()`. The per-FK policy is not in the
   artefact (only the distribution), so P4 decides it per module and passes it in
   `hPolicy`.
4. **that `Orphans()` is 0 today.** It is 4 on `part_part`, from FKs to tables
   outside the shipped subset. P7.2's check must exclude those edges or it will
   fail forever.
5. **that `Affected_Rows()` works for prepared writes.** It reports 0; the
   statement's `Row_Count()` read before `Free()` is the count.
6. **that a conflict is an error.** `Update()` returning `.F.` with
   `Errors()["reason"] == "conflict"` is a **409** the view turns into the SRS's
   "conflict warning, not blind overwrite"; `"not found"` is a 404. The two are
   different answers and the DAL distinguishes them with a second query.
7. **that the harness is part of what ships.** `webapp/test/probe_dalmysql.*` is
   local tooling, gitignored like the other probes — the shipped verification
   harness is P7.1's sliced suite, which asserts on DB state.

---

## 8. Added before P4.1, where the design question forced it

Three things had to be decided before the first CRUD module, and all three
change this file rather than a controller.

### 8.1 Step 0.3 lives in the schema, keyed by edge — not in the module

The policy is a property of the **edge**, and the edges into one table come
from everywhere: **15 edges point at `part_part`**, from `build_build`,
`company_manufacturerpart`, `part_supplierpart`, `stock_stockitem`,
`part_bomitem` (×2), `part_bomitemsubstitute`, `part_partpricing`,
`order_salesorderlineitem`, `part_partstocktake`, `stock_stockitemtracking`
and `part_part` itself — ten distinct tables across four modules. A master
that deletes `part_part` would have to read the stock, build, order and bom
modules' declarations, so the policy cannot live in a master.

It is declared next to the relation, in the shipped schema's FK comment:

```
KEY `fk_stock_stockitem_part` (`part`)  /* -> part_part.id  policy=CASCADE */
```

`_DalGraph()` parses it (`_DalPolicy()` accepts only `CASCADE`, `NULL`,
`KEEP`), and `_DalMode( cOther, cCol, hOverride )` resolves **override >
schema > KEEP**. `Delete()` and `Cascade()` both call it, so there is one
resolver and one source.

**Open decision, deliberately not filled:** no `policy=` is present on any
of the 78 shipped edges today, so every edge is KEEP. The per-FK values are
not in the artefact — it records only the distribution (CASCADE 68 / SET_NULL
69 / DO_NOTHING 3) — and the model source is not on this checkout. Filling
them is a product decision per module (P4.2 is where it becomes observable),
not something to guess.

### 8.2 `Cascade( nId, hOverride )` — the preview `delete_confirm` needs

Per referring table: the mode that applies and how many rows it touches,
plus a `total`. This is what the confirm view shows **before** the destructive
verb runs (SRS FR-DELETE-1…4) — with 15 edges into `part_part`, "this removes
400 stock items" has to be visible before clicking, not after.

### 8.3 `Attach( oConn )` — one slot per handler, not per table

`TDalMySql:Open()` used `WDO_Get` itself, so a module touching twelve tables
would take twelve slots from a pool of **eight** (`hix.json → pool_http.workers
= 64`, WDO `pool_size = 8`) and block on the ninth against the pool timeout.
`Attach( oConn )` borrows the handler's connection: `Close()` then leaves it
alone (`::lOwn` is `.F.`), and the handler closes the slot once in its own
`FINALLY`. The verb guards changed from `! ::lOwn .OR. ::oConn == NIL` to
`::oConn == NIL`, which is what makes borrowed use legal.

### 8.4 Verified (harness steps 11–16, `./probe_dalmysql` PASS 23 FAIL 0)

| Step | Asserted on state |
|---|---|
| 11 | two DAL objects (`part_part`, `stock_stockitem`) on **one** slot: `WDO_PoolStats` busy = 1, free = 3 of 4 |
| 12 | a dependent `stock_stockitem` row exists (rows 29 → 30) |
| 13 | `Cascade( nId2, { "stock_stockitem" => "CASCADE" } )` → total 1, mode `CASCADE`, rows 1 — the preview before the delete |
| 14 | `Delete( nId2, NIL )` with **no policy declared**: the dependent row is **kept** (30 → 30) and `Orphans()` on `stock_stockitem` grew — the default cannot silently destroy data |
| 15 | `Delete( nId2, { "stock_stockitem" => "CASCADE" } )`: the dependent row is removed, while the row step 14 left behind stays — the override applied, the default not |
| 16 | parts and stock rows back to the base (14 / 29), and `seed_inventree verify` answers `RESULT : ok` |

The harness deletes its own rows by id and by marker (`IPN` for parts,
`serial` for stock items) at start and at the end, so a run that stops half
way cannot move the base — an earlier version of it did leave residue, which
`seed_inventree verify` caught.

---

## 9. D4 — the cascade is one transaction (2026-10-07, after the fact)

The FK-policy record left one decision answerable without the owner: **D4,
atomicity**. It is a property of the verb, not a value per edge, so it was
taken here.

### 9.1 What was wrong

`Delete()` ran the row's `DELETE` and then one statement per referring edge —
up to 16 statements for `part_part` (15 in-edges) — loose. A cascade that
fails at statement 3 of 16 leaves the store half-deleted and answers as if
nothing happened. The pool's auto-rollback does not cover this: it fires when
a slot is **closed** mid-transaction, and this verb returns normally.

### 9.2 What was changed

| Change | Where | Why |
|---|---|---|
| `BeginTrans()` before the first statement, `Commit()` after the last, `Rollback()` on any failure; the return says `{ "deleted" => 0, "rolledback" => .T. }` | `Delete()` | the driver's own pattern (`site-docs/en/wdo/mysql/transactions.md`); P5.2's journal replay is the DBF machinery this replaces |
| `_DalPrepared()` returns `{}` instead of `NIL` when a write touched nothing | `_DalPrepared()` | a write that matched no rows is not a failure. Conflating the two would roll back a cascade that succeeded — found by running the harness, not by reading the code |
| the NULL policy is refused **by the DAL** on a NOT NULL FK column | `Delete()` + `_DalGraph()` (a new `nn` map parsed from the shipped schema) | D2's fact, enforced: MariaDB accepts `SET <col> = NULL` on a NOT NULL integer and writes `0`, which is a dangling FK, not a NULL. 26 of the 78 shipped edges cannot carry the policy, and discovering that after the first statement ran would leave a half-applied cascade |
| `Errors()` is cleared at the start of `Delete()` and `Update()` | both verbs | the flash quotes the reason; a verb that has not failed yet must not report the previous verb's failure. Measured before the fix: a refused cascade reported `conflict` from an earlier `Update()` test |
| the handlers distinguish a rolled-back cascade from "the row was not there" | `part.prg`, `users.prg` `delete_action()` | "nothing was changed" is not "not there" |

### 9.3 Harness steps 17–19 (`./probe_dalmysql`, bounded)

| Step | Asserted on state |
|---|---|
| 17 | a CASCADE cascade over a fresh part + its stock item commits together: parts 14 → 15, stock 29 → 30 after, both statements landed |
| 17b | after a committed cascade `Errors()` answers **NIL** — the channel is not sticky |
| 18 | `Delete( nId3, { "stock_stockitem" => "NULL" } )` is refused by the DAL's D2 guard (`stock_stockitem.part` is NOT NULL): `deleted = 0`, `rolledback = .T.`, and **the part row and the stock item are both still there** — the provisional `DELETE` was undone, not committed |
| 18c | the reason is `cascade refused`, fresh rather than the previous verb's `conflict` |
| 19 | the rolled-back row is intact: `Show( nId3 )` returns the name that was inserted |
| 20 | the corpus is back at its base (14 / 29), `seed_inventree verify` → `RESULT : ok` |

```
$ timeout 120 ./probe_dalmysql            PASS 29  FAIL 0     (was 23/0 before D4)
$ timeout 600 ./test/test_part_module.sh  PASS 38  FAIL 0
$ timeout 600 ./test/test_users_mysql.sh  PASS 39  FAIL 0
```

### 9.4 Timeouts

Every network and compiler call in the suites is now time-bounded — `curl`
carries `--connect-timeout 5 --max-time 15`, every tool call runs under
`timeout 60`, and the suites are meant to be run as `timeout 600 ./test/<suite>.sh`
— the same discipline `verify-users-fixes.sh` documents in its header. Without
it a wedged HIX worker or a Harbour compile turns the suite into a hang. The
harness hit exactly that: an unguarded `hb_HGetDef( Errors(), … )` on a NIL
error hash raised `BASE/1123`, which opens Harbour's interactive "Quit" dialog
and never returns. Fixed with a guard (`_Reason()`), the same trap
`create_mysql_sql.prg` documents in its header.

### 9.5 Still open after D4

D1 (the per-edge values), D3 (recursion depth and the cycle guard over the
7 self-edges), D5 (preview vs perform), D6 (orphans), D7 (the 52 FK-annotated
columns with no `KEY`), D8 (tables with no delete surface). D2 is now enforced
by the DAL rather than discovered at the server, but the per-edge choice
between CASCADE and KEEP for those 26 edges is still the owner's.
