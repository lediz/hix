# P7.2 (the FK orphan check) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P7.2** of `webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md` — the
> FK-orphan route — and it is where the FK-policy decisions stopped being a
> report and started being enforced. P7.3 (aggregate reconcile), P7.4 (pool
> leak) and P7.5 (transaction interruption) were not started.

---

## 1. What P7.2 had to prove, and the verdict

| Part | Claim | Result |
|---|---|---|
| The route | an FK-orphan check that runs after every delete test | ✅ `GET /hix-fk-check`, `controllers/fkcheck.prg`, middleware `MyAppAuthRole`, scope `sys:fkcheck` |
| The gate | admin-only | ✅ the scope is granted to the admin account only — `seed_users_mysql` puts `sys:fkcheck` in the admin's roles string; `carles` (no scope) gets 404, not a partial answer |
| The pool discipline | one slot for the whole route | ✅ one `WDO_Get`, 27 DAL objects `Attach()`-borrowing it, `oConn:Close()` once |
| The answer shape | names the **edge**, not the table | ✅ `{ table, column, target, rows }` — the same shape `Cascade()` renders, so the two halves of the FK surface read alike |
| The graph source | the check cannot disagree with what a delete will do | ✅ the route reads `_DalGraph()`, which is parsed from `sql/inventree.sql` — the single source `Delete()` and `Cascade()` use |
| FK-closed | the seeded corpus has no dangling FK | ✅ **0 orphans across 78 edges** — and the 21 the route first reported were a measurement bug, not a fixture gap (§3) |

## 2. What was written

| Path | What | Tracked? |
|---|---|---|
| `www/controllers/fkcheck.prg` | the route | yes |
| `www/routes/web.json` | +1 route (37 total), inserted in the file's aligned style so the diff stays one line | yes |
| `www/models/tdalmysql.prg` | `OrphansEdge( cCol, cTgt )` split out of `Orphans()`; `Orphans()` sums it | yes |
| `seed_users_mysql.prg` | the admin's roles string gained `sys:fkcheck` | yes |
| `sql/inventree.sql` | 78 `policy=` comments (CASCADE 13 · NULL 19 · KEEP 46) and 26 unkeyed FK columns annotated with why they are inert | yes |
| `part.prg`, `users.prg` | `delete_action()` distinguishes rolled-back / undecided / not-there, and the flash quotes the transaction's own numbers | yes |
| `www/views/masters/part/delete.html` | the preview says "as of this page load" | yes |

## 3. Facts found by running it, not by reading it

| Plan said | Reality on HIX 2.3.10 / Harbour 3.2.1dev / MariaDB 13.0.2 |
|---|---|
| P7.2 "an FK-orphan check route: `SELECT COUNT(...) WHERE <fk> IS NOT NULL AND <target> IS NULL`" | that shape does not work: MariaDB does not enforce FKs, so there is no NULL to find — a dangling FK is a **value with no target row**. The shape is `NOT EXISTS ( SELECT 1 FROM target WHERE id = value )` |
| one count per table is enough | it is not actionable. Per edge it is: `stock_stockitem.location -> stock_stocklocation` says what to fix, `stock_stockitem has 4` does not |
| the corpus has FK gaps (the plan's premise for this route) | it does not. The first run reported **21 orphans** across `part_partcategory.parent` (6), `stock_stocklocation.parent` (5), `part_part.variant_of` (4), `stock_stockitem.parent`/`belongs_to` (1+1), `order_salesorderallocation.line` (4) — and every one of those rows points at a target that **is** seeded. The count was wrong because `EXISTS` was unaliased: for the 7 self-edges (`parent`, `variant_of`, `belongs_to`) MariaDB resolves the outer column to the **inner** row, so the subquery answered for the wrong row. Aliasing both sides (`AS _o`, `AS _i`) gives 0 |
| a check that answers 0 is verified | it is not — a broken check also answers 0. Proven separately: the aliased shape counts **14** `part_part` rows against a target id that does not exist, and **0** against the seeded corpus |
| the DAL's `Orphans()` is one query | it is one per out-edge (worst case 11, `stock_stockitem`), so the route is 78 SELECTs — measured, not assumed, since it runs on every delete test |
| a suite can call the CLI tools and the app without bounds | it cannot. The scratch query tool wedged a size-1 pool on a write path with no `Free()` and never returned; every harness and suite invocation now runs under `timeout` and every `curl` carries `--connect-timeout 5 --max-time 15` |

## 4. The run

```
$ ./seed_users_mysql seed                       RESULT : ok   (admin gained sys:fkcheck)
$ ./app                                         DB_PWD from .mysql/credentials
$ curl -k .../hix-fk-check
  {"ok":true,"tables":27,"edges":78,"total":0,"orphans":[]}
$ curl -k .../hix-fk-check  as carles           404

$ timeout 120 ./probe_dalmysql                  PASS 29  FAIL 0
    step 14  Delete(nId2, { "stock_stockitem" => "KEEP" } )   row kept, orphans grew
    step 15  Delete(nId2, NIL )                               schema policy=CASCADE applied
             ^ the pair is what proves the schema file is the source, not a controller
    step 18  NULL on stock_stockitem.part (NOT NULL)          refused before the first
             statement, rolled back, part row and stock item both still present
    step 18c reason "cascade refused", fresh and not a stale error
$ timeout 600 ./test/test_part_module.sh        PASS 38  FAIL 0
$ timeout 600 ./test/test_users_mysql.sh        PASS 39  FAIL 0
$ timeout 60  ./seed_inventree verify           RESULT : ok   (part_part = 14)
```

## 5. The owner answers taken on this run

| # | Question | Answer | Effect |
|---|---|---|---|
| 1 | the 13 CASCADE edges | **follow the rule** | nothing changed; the derived set stands. The three-hop removal from one part delete is accepted, and `delete_confirm` plus the transaction's own numbers are what make it visible before and after |
| 2 | the 21 pre-existing orphans | **FK-closed** | the corpus was already closed; the fix was the alias in the check (§3) |
| 3 | the subtree verb (`/stock/location/prune?depth=N`) | **keep it out** | nothing built; tree edges carry `policy=KEEP`, `Delete()`/`Cascade()` stay one level |

## 6. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | a route in `www/routes`, a controller in `www/controllers`, the middleware pair and scope format unchanged |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the exception is scoped to P1 and the later phases of this plan; the FK surface is one of them. The `customer` module still contains no SQL — that is the point of keeping it on RDDCDX |
| **T4** HIX + Harbour only | ✅ | `WDO_Get`, the DAL, `USendJson`, `MyAppAuthRole` |
| **T5** tools in the project folder | ✅ | the route, the seeder and the schema are all under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only host action was the already-documented recreate/seed cycle under `webapp/.mysql/` |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched; the route is runtime-loaded, the seeder has its own `.hbp` |
| **T8** port 9090 | ✅ | untouched |

## 7. Still open

1. **P7.3** aggregate reconcile, **P7.4** pool-leak check (1 000 mixed requests, `busy == 0`,
   `SHOW PREPARED STATEMENTS` empty), **P7.5** transaction interruption — none built.
   P7.4 is partly covered by the harness (two DAL objects on one slot, slot returned)
   and by the absence of `reclaiming` lines in the log, but not by a 1 000-request run.
2. **P4.2–P4.7** (`stock`, `company`, `bom`, `order`, `build`, settings) not started.
   The FK surface is now ready for them: 78 declared edges, undecided is visible,
   and the orphan check is green on the seeded corpus.
3. **The subtree verb stays out** by decision, not by omission.
