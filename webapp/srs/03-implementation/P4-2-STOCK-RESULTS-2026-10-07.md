# P4.2 (the `stock` module) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P4.2** of `webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md` — the
> `stock` module — and stops there: **P4.3–P4.7 were not started**, so M3 is
> partly done and **M4 and M5 are not**.

---

## 1. What P4.2 had to prove, and the verdict

| Part | Claim | Result |
|---|---|---|
| The module | the nine verbs over `stock_stockitem`, same routes shape, same middleware pair | ✅ `www/controllers/masters/stock.prg`, 9 routes in `www/routes/web.json` (46 total), 4 views in `www/views/masters/stock/` |
| The FK policy becomes observable | deleting a `part` touches `stock_stockitem` (`policy=CASCADE`); deleting a `stock_stocklocation` clears `stock_stockitem.location` (`policy=NULL`) | ✅ the `delete_confirm` preview renders the declared modes, and `hix-fk-check` answers **0 orphans** after the delete |
| P3.7 over a new module | a write that omits the version is refused; a stale one is refused and shows the record | ✅ both asserted on state, not on status codes |
| Verification | state before/after each verb | ✅ `test/test_stock_module.sh` **18 assertions, 0 fail**; `seed_inventree verify` → `RESULT : ok` |

## 2. What was written

| Path | What | Tracked? |
|---|---|---|
| `www/controllers/masters/stock.prg` | the nine verbs on the DAL | yes |
| `www/views/masters/stock/{grid,show,edit,delete}.html` | the four views | yes |
| `www/routes/web.json` | +9 routes (46 total), inserted in the file's aligned style | yes |
| `sql/hix_users.sql` | `roles` widened to `varchar(1024)` — the scope string grows with the module surface (504 characters with `stock:*`), and varchar(255) silently truncates, which is an account that quietly loses access | yes |
| `seed_users_mysql.prg` | the admin's roles gained `stock:search;show;create;edit;delete` | yes |
| `test/test_stock_module.sh` | the functional suite | no — `webapp/test/` is local tooling |

## 3. Facts found by running it, not by reading it

| Assumed | Reality |
|---|---|
| A module can be generated from a template | the first generator produced four rounds of compile errors (Harbour's `{ => }` hash literals collide with Python's `str.format`; Mambo's `{{ }}` expression macro collides with the same; `hb_ASort` does not exist; `UValidatePost`'s number rule returns something `Val()` rejects). It was abandoned and the module written directly — the shared shape is a convention to follow, not something to codegen against in this language pair |
| `Val( oVal:Get( 'part' ) )` converts a validated number field | it does not. `Get()` can return NIL and `Val( NIL )` is a BASE error that turns the whole verb into a 500. A guarded `_NumOf()` is in the module, with the reason next to it |
| the delete route resolves from the route name | it resolves from the action: `delete_action@stock.prg`, and a route written `delete@stock.prg` answers `No exist method delete` |
| the grid shows the id of a created row in the same page | the grid paginates at 20 rows; a created row lands on the last page. The suite reads the id from the **create flash** on the page the redirect lands on — the verb's own claim — not from a guessed page |
| the seeded stock items have serials | they do not: `serial` is `\N` in the fixtures, `B123` is the `batch` column. An assertion written against `serial` measures nothing |
| `sys:` is a free scope prefix | it is not. `_ParseRoles` keys the roles hash by the text before `:`, so `sys:fkcheck` and `sys:search;…` collide and the second overwrites the first — the admin silently loses the fk-check scope. The settings module's prefix has to be something else |

## 4. The run

```
$ ./seed_users_mysql seed                       RESULT : ok   (admin gained stock:*)
$ ./app                                         DB_PWD from .mysql/credentials
$ ./test/test_stock_module.sh                   PASS 18  FAIL 0
    store refused without a token; no row created
    store -> the row was created (29 -> 30), id read from the create flash
    update with no version     refused, sent back to the edit form
    update with a stale version refused, sent to the record, "nothing was overwritten"
    update with the version read applied, the record shows the new quantity
    delete_confirm renders the cascade ("as of this page load")
    delete -> back to the grid, 30 -> 29
    hix-fk-check: 0 orphans after the delete

$ ./test/test_part_module.sh                    PASS 38  FAIL 0
$ ./test/test_users_mysql.sh                    PASS 39  FAIL 0
$ ./seed_inventree verify                       RESULT : ok
```

## 5. Compliance

Same eight tests as the other MySQL-DAL modules and the same verdicts: T1 (HIX MVC shape unchanged), T2 (SQL, under the exception recorded 2026-10-07), T4 (HIX + Harbour only), T5 (everything under `webapp/`), T6 (nothing outside it), T7 (`app.hbp` untouched — the module is runtime-loaded), T8 (port 9090 untouched).

## 6. What is still open

1. **P4.3** `company` + `part_supplierpart`, **P4.4** `bom` (recursive resolve with a depth cap and a cycle guard, aggregates from SQL), **P4.5** `order` (one transaction per verb), **P4.6** `build`/`stocktake`/test results, **P4.7** settings/notes/attachments/project codes — **not started**. M3 is therefore partly done; **M4 and M5 are not started**.
2. **P7.3** aggregate reconcile, **P7.4** pool-leak check (1 000 requests), **P7.5** transaction interruption — not built. P7.5 is the check that would prove D4 under a dispatcher timeout, and it is now reachable: `Delete()` is transactional and `stock` deletes touch two tables.
3. **P5.1** aggregates from SQL — the DAL has `COUNT(*)` only; no `SUM`/`AVG` anywhere.
4. The suites are still **not wired into `tests/run.sh`** (P7.1 partial): it registers `31-wa-users`, `32-wa-customer`, `33-wa-verify` and nothing for `part`, `users` on MySQL, `stock` or the FK check.
