# P4.8 (the `users` module on the MySQL DAL) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P4.8** of `webapp/srs/02-design/INVENTREE-MYSQL-PLAN.md` — the step
> the Step 0.2 decision created (**A for `users`, B kept for `customer`**). The
> users module and the login path now run on the MySQL DAL; the `customer` module
> still runs on `UDbf()`/RDDCDX, deliberately, as the surviving proof-of-concept.
> P4.2–P4.7 were not started.

---

## 1. What P4.8 had to prove, and the verdict

| Part | Claim | Result |
|---|---|---|
| The table | a shipped store for the login identity, in the project folder | ✅ `webapp/sql/hix_users.sql` — `users_users`, `UNIQUE KEY ix_name`, `FULLTEXT ft_name`, `version` (P3.7). Not in `sql/inventree.sql`: the artefact's `auth_user` was dropped by P1.2a because HIX owns users, so the table is HIX's and the artefact stays byte-faithful |
| The seeder | a Harbour tool in the project folder, hashing at run time | ✅ `webapp/seed_users_mysql.prg` + `.hbp`; `create`/`seed`/`verify`/`check`/`dump`/`drop`; five accounts seeded, digests 64 hex, salts 32, `RESULT : ok`; **no fixture CSV** — a committed digest is a committed credential |
| Login | the identity comes from the store, not from `data/users.dbf` | ✅ `www/models/modeluser.prg` rewritten over the DAL: one slot per login, bound name, collation for the case-insensitive match, exact confirmation, `_PwMatch`, the dummy KDF paid on every absent name (D-17), the session entry built field by field with **no credentials** (D-05) |
| The module | the nine verbs over the DAL, same routes, same middlewares | ✅ `www/controllers/masters/users.prg` rewritten (mirrors `part.prg`); `www/routes/web.json` untouched — the routes already addressed `/users/…` |
| The views | the row is addressed by its id | ✅ `www/views/masters/users/{grid,show,edit,delete}.html`: `_recno` → `id` (MySQL has no recno — ids are server-assigned, Step 0.3) |
| Retirement | the DBF users store is gone, not shadowed | ✅ `www/models/tusers.prg`, `regenerate_users.prg`, `regenerate_users.hbp` removed; `src/app.prg`'s header now names `./seed_users_mysql` as the seeder |
| Verification | the audited defect ids re-proven over the **new** store | ✅ `test/test_users_mysql.sh` **39 assertions, 0 fail**, every one on store state or on rendered rows |

## 2. What was written

| Path | What | Tracked? |
|---|---|---|
| `sql/hix_users.sql` | the credential table, with the decision recorded in its header | yes |
| `seed_users_mysql.prg` / `.hbp` | the seeder (runtime hashing, `drop` for a suite's leftovers, `check` for D-07) | yes |
| `www/models/modeluser.prg` | login over the DAL | yes (modified) |
| `www/controllers/masters/users.prg` | the nine verbs on the DAL | yes (rewritten) |
| `www/views/masters/users/{grid,show,edit,delete}.html` | `_recno` → `id` | yes (modified) |
| `src/app.prg` | the header's credential line | yes (modified; rebuilt with `hbmk2 app.hbp`, T7 holds) |
| `webapp/.gitignore` | `seed_users_mysql` binary ignored, its sources tracked | yes |
| `www/routes/web.json` | **untouched** | — |
| `test/test_users_mysql.sh` | the functional suite | no — `webapp/test/` is local tooling |

Removed: `www/models/tusers.prg`, `regenerate_users.prg`, `regenerate_users.hbp`.
`data/users.dbf`/`users.cdx` stay on disk as gitignored state nothing reads.

## 3. Facts the plan got wrong, found by running it

| Plan said | Reality on HIX 2.3.10 / Harbour 3.2.1dev / MariaDB 13.0.2 |
|---|---|
| P4.8 "a shipped table for the credential store" | the artefact has no such table — `auth_user` was dropped by P1.2a. The table is HIX's, so it lives in its own `sql/hix_users.sql`; putting it in `sql/inventree.sql` would break `create_mysql_sql`'s 38-table contract and `seed_inventree verify`'s per-table counts |
| a seeded store can be a fixture CSV like the inventory corpus | it cannot. A fixture CSV commits digests and salts; the digests are the password-equivalent for a brute-force attack. The seeder hashes at run time (`hpassword.prg`) |
| the DAL's whitelist is one list per module | it is not enough here. `pass`/`salt` must be writable and readable by the login, and must never reach a view — so the module keeps **two** whitelists: read `{name, roles}`, write `{name, pass, salt, roles}`. This is the replacement for `TUsers():Hide( {'pass','salt'} )` (D-05) |
| the per-column search boxes map onto the DAL's `hLike` | they do not. The DAL's LIKE is an **OR** across the whitelisted columns (P4.1 §3), which widens; the boxes narrow. The free-text `q` goes through `hLike`, the per-column `_q_<col>` boxes are applied as an AND over the returned rows — measured: `_q_name=carles&_q_roles=edit` renders **0 rows**, an OR would render 1 |
| the views keep working on the new store | they address rows with `_recno`. MySQL has no recno, so the four views were changed to `id` |
| a duplicate name is refused by the module (D-09) | the module refuses it **and** the schema's `UNIQUE KEY ix_name` refuses it; two answers, one contract. The suite asserts on the store, not on which path answered |
| a suite can grep the store's own output | the CLI tools print through HIX's console driver, which lays lines out with cursor addressing and loses characters at the wrap. `dump` prints one `QOut()` line `dump:<names>:end` so a pipe sees it intact |
| the login path can rely on the dispatcher's slot reclaim | it must not. `ModelUser()` acquires and closes its own slot; the reclaim hook logs a WARN per request when a handler does not (same finding as P4.1 §7 item 6) |

## 4. Verification actually run

```
$ ./seed_users_mysql seed            created users_users, seeded 5, RESULT : ok
$ ./seed_users_mysql check           checked 5 accounts for a plaintext password, RESULT : ok
$ ./app                              DB_PWD from .mysql/credentials
$ ./test/test_users_mysql.sh
  the store is at its seeded base before the run
  admin/1234 authenticates                      accounts before: 5
  reads: grid / search / create form / show / delete_confirm   200
  no digest or salt is rendered by the grid
  the unfiltered grid shows every account            5 rows
  one box that cannot match returns no row           0 rows   (AND, not OR)
  boxes that both match return the row               1 row
  a box that alone cannot match returns none         0 rows
  store without a token is refused; no account created
  store -> the account was created; a name already in use (any case) refused
  update: no version refused; name omitted refused; version 0 applied,
          name changed; stale version refused, record shown, nothing overwritten
  rename onto a name in use refused; count unchanged; own name intact
  delete_confirm renders the record; delete -> rows back to the base;
          a second delete says it is not there
  seed_users_mysql verify  RESULT : ok
  seed_users_mysql check   RESULT : ok
PASS 39  FAIL 0

$ ./test/test_part_module.sh          PASS 38  FAIL 0   (the part module, unchanged)
```

Login probes, over the new store: `admin/1234` ✅, `ADMIN/1234` ✅ (D-16, the
collation), `jOHN/5678` ✅, `admin/12345` refused, `jane/9012abc` refused (a
prefix is not the password), `nobody/1234` refused.

## 5. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | same routes, same middleware pair, same scopes, Mambo views; only what sits behind the verbs changed |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | the exception is scoped to P1 and the later phases of this plan; `users.prg` and `modeluser.prg` are among them. The `customer` module still contains no SQL — that is the point of keeping it on RDDCDX |
| **T4** HIX + Harbour only | ✅ | `WDO_Get`, the DAL, `UView`/`UFlash`/`UValidate*`, `hb_sha256`/`hb_RandStr` — framework and Harbour core, no new dependency |
| **T5** tools in the project folder | ✅ | `sql/hix_users.sql`, `seed_users_mysql.prg`/`.hbp` under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only host action was the already-documented recreate/seed cycle under `webapp/.mysql/` |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched; `src/app.prg`'s header changed, which `app.hbp` already builds. The tool has its own `.hbp`, like every other tool here |
| **T8** port 9090 | ✅ | untouched |

## 6. What is still open

1. **FK policy.** Still 0 `policy=` on the 78 shipped edges, so every edge is
   KEEP. `users_users` has no FK, so P4.8 did not need one — the decision is
   P4.2's (`stock`), where deleting a part makes the choice observable. The
   artefact records only the distribution (CASCADE 68 / SET_NULL 69 / DO_NOTHING
   3), not the per-edge values, and the model source is not on this checkout, so
   filling them is a product decision, not something to infer.
2. **The customer POC stays.** `data/*.dbf` is state for `customer`/`states`
   only, `hix.json → app.auto_close_dbf` keeps its `true`, and **P5.5 stays
   open** while the POC is in the app. Retiring it is a separate decision.
3. **The DBF-era suites.** `test_users_module.sh` and `verify-users-fixes.sh`
   describe the retired store; both carry a header saying so and pointing at
   `test_users_mysql.sh`. They are not green and are not meant to be — the
   corpus's own lesson (B1: a suite that verifies nothing is a defect) is about
   silent vacuity, and a header that says "retired scope" is not silent.
4. **P4.2–P4.7** (`stock`, `company`, `bom`, `order`, `build`, settings) not
   started.
