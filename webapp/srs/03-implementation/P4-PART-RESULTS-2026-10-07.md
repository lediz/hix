# P4.1 (the `part` module) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P4.1 only** of `webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md` — the
> `part` module — and it is **half verified**: the reads and the create path are
> proven against real state, the update (conflict) and delete paths are not.
> P4.2–P4.7 were not started. Nothing is committed.

---

## 1. What P4.1 had to prove, and the verdict

The nine verbs, each checked over HTTP with a session, asserted on **DB state**
before/after and not on status codes alone (`PRODUCTION-BLOCKERS-2026-10-07.md`
B1 is the lesson).

| Verb | Route | Result |
|---|---|---|
| `part.grid` | `GET /part/grid` | ✅ 200, renders the 14 fixture parts, paged |
| `part.search` | `GET /part/search?q=M2` | ✅ 200, **finds `M2x4 LPHS`** — the LIKE actually matched, not an empty table |
| `part.show` | `GET /part/1` | ✅ 200 |
| `part.create` | `GET /part/create` | ✅ 200, renders the form |
| `part.edit` | `GET /part/1/edit` | ✅ 200, renders the form with the row's `version` |
| `part.store` | `POST /part/store` | ✅ 302, and `part_part` rows **grew by one** |
| `part.delete_confirm` | `GET /part/1/delete_confirm` | ✅ 200, renders the `Cascade()` preview table |
| `part.update` | `POST /part/:id/update` | ⚠️ **not verified** — the suite could not extract the new row's id on the run that exercised it (reads did not carry `id` until the DAL was fixed); the conflict path is therefore unproven end-to-end |
| `part.delete` | `POST /part/:id/delete` | ⚠️ **not verified** — same reason |

Corpus after the run: `part_part = 14`, `stock_stockitem = 29` — back to the
seeded base, so the half-run left no residue.

## 2. What was written

| Path | What | Tracked? |
|---|---|---|
| `webapp/www/controllers/masters/part.prg` | `CLASS PartControllers`, the nine verbs, one pool slot per request | new |
| `webapp/www/views/masters/part/{grid,show,edit,delete}.html` | Mambo views; `@CSRF` on the write forms; `delete.html` renders the cascade preview | new |
| `webapp/www/routes/web.json` | +9 routes (36 total), `parts:search/show/create/edit/delete`, `MyAppAuthRole` / `MyAppAuthRoleEdit` | modified |
| `webapp/regenerate_users.prg` | admin's roles gained `parts:search;show;create;edit;delete`; `data/users.dbf` regenerated (state, gitignored) | modified |
| `webapp/www/models/tdalmysql.prg` | LIKE search (`hLike`), and reads now always return `id` and `version` | modified |
| `webapp/test/test_part_module.sh` | the functional suite — local tooling, gitignored like the other suites | no |

Nothing under `src/`, `data/` (except the regenerated state), `examples/` or
`resources/` changed. **Step 0.2 is still Option B-shaped**: `hix.json →
app.auto_close_dbf` is `true`, `data/*.dbf` is still the app's state, and
`/main` `/users/grid` `/customer/grid` still answer 200 from DBF. The `part`
module is new surface beside them, not a replacement.

## 3. Facts the plan got wrong, found by running it

| Plan said | Reality on HIX 2.3.10 / Harbour 3.2.1dev |
|---|---|
| P4.1 "controllers `controllers/masters/*@part.prg`" | the action `grid@part.prg` resolves the class as **the first class in the compiled module** (`src/hix_dispatcher.prg:253` takes the class name from the file, and `_HixRunHrbClass` loads it). With `#include 'models/tdalmysql.prg'` at the **top**, the DAL's class answered and the verb was missing: `Handler error [/part/grid]: No exist method grid`. The audited `customer.prg` / `users.prg` put model includes at the **end** — that placement is load-bearing, not style |
| a class named for the module | `CLASS Part` → `Error E0002 Redefinition of procedure or function 'PART'` — Harbour's xBase RTL already exports `PART()`. Class names must not collide with RTL functions; `PartControllers` is what shipped |
| the DAL's read verbs | they returned only the whitelisted columns, so the grid had no `id` and the suite could not address the row it had created. Reads now always carry `id` and `version` — the routes address rows by id, and the next write has to carry the version back (P3.7) |
| FR-READ-2 "search" across the rendered columns | joining the LIKE terms with **AND** returns 0 records for every real query (`q=M2` → 0). A search bar is an **OR** of LIKEs, parenthesised so an equality filter ANDs against it correctly |
| P3.7 "the second session gets **409**" | the audited app signals writes through `UFlash` + `URedirect` — every write response is a 302 with a flash, there is no status channel. The conflict is therefore a flash of its own kind ("nothing was overwritten") redirecting back to the edit form, which satisfies SRS 5.2's *warning*, but the HTTP 409 the plan names is **not implemented** |
| P4.1's scope names | `parts:*` had to be granted in the users DBF, not in the route: `regenerate_users.prg`'s admin role string gained the third group. Regenerating also re-hashes passwords with new salts, so sessions issued before are invalidated |
| the URL shape | `part.show` is `/part/:id([0-9]+)`, so `/part/show?id=1` is **not** the show route — it fell through to the static dispatcher (`Dispatch: directorio no en whitelist [/part/show]`, 403). The views link `/part/<id>` |

## 4. Verification actually run

```
$ ./test/test_part_module.sh                      (app started with DB_PWD set)
  ok   admin/1234 authenticates
       part_part rows before: 14
  ok   GET /part/grid
  ok   GET /part/search?q=M2
  ok   GET /part/1 (show)
  ok   GET /part/create (form)
  ok   GET /part/1/edit (form)
  ok   GET /part/1/delete_confirm
  ok   search found the fixture part
  ok   POST /part/store
  ok   rows grew by one
  ...  the id-dependent half did not run to completion on this pass

$ ./create_mysql_sql verify                       after cleanup
  part_part = 14          stock_stockitem = 29    (back to the seeded base)

$ ./gen_mysql_db.sh status                        running
  app stopped, 9090 free
```

* **the reads are the proof**: `search?q=M2` returning the fixture part means the
  LIKE, the whitelist, the bound wildcards and the pool slot all work end-to-end
  through a real handler — the thing P3 could only test from a CLI.
* **the writes are not**: `store` is proven (row count grew); `update` and
  `delete` were never exercised against a known row id, so the conflict path and
  the cascade-then-delete sequence remain unverified.

## 5. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | the module is the audited MVC shape: `www/routes` JSON, `controllers/masters/*@part.prg`, `www/views/masters/part/`, the same middleware pair and scope format |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the exception is scoped to P1 and the later phases of this plan; the `part` module is one of them. The audited `customer` / `users` modules still contain no SQL |
| **T4** HIX + Harbour only | ✅ | `WDO_Get`, the DAL, `UView`/`UFlash`/`URedirect`/`UValidate*` are framework code; no third-party dependency |
| **T5** tools in the project folder | ✅ | everything is under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only host action was the already-documented recreate/seed cycle under `webapp/.mysql/` |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched — the module is runtime-loaded, so P4.1 needed **no build** (unlike P3.6, which edited `src/app.prg`) |
| **T8** port 9090 | ✅ | untouched; the suite ran against the existing self-signed TLS |

## 6. Ready for P4.2, and what P4.2 must not assume

Ready: a working module shape (routes, middleware, scopes, views, one slot per
handler) and a DAL whose reads are proven through HTTP.

P4.2 must not assume:

1. **that the update or delete verbs work.** They were never exercised against a
   known row. P4.2 (`stock`) is where the FK policy becomes observable — it has to
   start by proving `update` (version conflict) and `delete` (policy) on `part`
   before adding a second module on top of an unproven half.
2. **that a conflict is an HTTP 409.** It is a flash + redirect in this app
   (§3). Anything that wants a real 409 needs a response channel the audited
   app does not have.
3. **that the search is AND.** It is an OR of LIKEs across the whitelisted
   columns, parenthesised.
4. **that reads return only the whitelisted columns.** They carry `id` and
   `version` on top, and the views depend on it.
5. **that the module retired anything.** Step 0.2 is still open; DBF still serves
   `customer` and `users`.
6. **that the harness is part of what ships.** `webapp/test/test_part_module.sh`
   is local tooling; the shipped verification harness is P7.1's sliced suite.
