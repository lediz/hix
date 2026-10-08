# P0–P4 — the DBFCDX shape, what was actually done, 2026-10-08

> **Record of a run.** This file reports what was executed on this checkout.
> The MySQL-era records are in `_retired/`. Anything not listed as measured
> here was **not** run.

---

## 1. What was removed, and why it could be removed

The InvenTree-derived surface and the MySQL engine behind it were deleted.

| Artefact | What it was | Removed because |
|---|---|---|
| `www/models/tdalmysql.prg` | the pool DAL | replaced by the DBF store; nothing else uses it |
| `sql/inventree.sql`, `sql/hix_users.sql`, `sql/fixtures/*.csv` | the MySQL schema and its seed corpus | replaced by the DBF store in `data/` |
| `gen_mysql_db.sh`, `create_mysql_sql.*`, `seed_inventree.*`, `seed_users_mysql.*` | the host, the schema loader, the seeders | there is no host; the store is files in `data/` |
| `probe_mysql.*`, `probe_dalmysql.*` | the host gate and the DAL harness | the gate is the store probe |
| `test/test_fkcheck.sh`, `test/test_reconcile.sh` | suites over routes that were deleted | the routes are gone |
| 12 controllers + their views (`part`, `stock`, `bom`, `build`, `company`, `supplier`, `order`, `orderline`, `testresult`, `settings`, `note`, `projectcode`) | the InvenTree-derived modules | out of scope: the app is `customer` + `users` + login |
| `www/controllers/{healthdb,fkcheck,reconcile}.prg` | the MySQL diagnostics | they walked the MySQL FK graph |
| `.mysql/` | the database itself, its log, its socket, its account password | state, never source — gone with the engine |

`src/app.prg` lost the pool bootstrap (`_DbPoolEnsure`, `_DbReachable`,
`_DbDllDefault`, `_EnvOr`, `APP_MYSQL_BERROR`) and the `hbsocket.ch` include
that only the pool probe used. `www/config.json` lost `"databases": {}`.

## 2. What replaced it

| File | What it is |
|---|---|
| `www/models/tusers.prg` | the credential store: `data/users.dbf` + the `name` CDX tag, opened through the framework's `UDbf()` with the driver `www/config.json` names (`"dbf" -> "rddname": DBFCDX`) — the same shape as the audited `tcustomers.prg` |
| `www/models/modeluser.prg` | the login identity over that store; D-05/D-07/D-16/D-17 restated for a DBF |
| `www/controllers/masters/users.prg` | the nine verbs over `UDbf()`, in `customer.prg`'s audited shape |
| `www/routes/web.json` | 23 routes: `index`, `main`, `sys.login/logout/auth`, `customer.*` (9), `users.*` (9) — down from 137 |

`data/users.dbf` and `data/users.cdx` were **not** created by this change: they
were already on disk, and were restored from `584d442` after a regeneration
attempt corrupted the field order.

## 3. Measured

| Step | Result |
|---|---|
| `hbmk2 app.hbp` | **links clean.** At HEAD it failed with `WDO_InitPoolMySqlEx` / `WDO_EndPoolMySql` unresolved; nothing references the MySQL WDO now, so the error is gone |
| compile of `users.prg` | clean — 2828 lines, 38 functions |
| server startup | starts; banner prints **RDD Default: DBFCDX** |
| `probe_seek` | the CDX seek + exact-match guard on this store: `seek 'admin' -> NAME='admin' exactmatch=YES`, `seek 'carle' -> NAME='carles' exactmatch=NO` (the prefix closed), `seek 'zed' -> no record (Eof)` |
| `probe_pw` | the store and the KDF read back correctly: `stored=[2588bb5e…] calc=[2588bb5e…] match=YES` |
| `POST /auth` (admin/1234, CSRF bound to the SID from `GET /login` with a cookie jar) | **302 → `/main`** — login succeeds over the new path |
| `dbf_dump.py data/users.dbf` | `records=6 live=5 deleted=1` — the soft-delete flag is set and honoured |

## 4. Suite results

Measured with `setup.ratelimit.login_max` widened to 500 for the run
(`www/middlewares/myapplogin.prg` documents this as the way to widen a test
build without editing source). **Production value `login_max: 5` was restored
afterwards and is what ships.** The server was launched with `umask 077` —
`go_gcc.sh:26` — which is what the session-file permission check requires.

| Suite | Result |
|---|---|
| `test_users_module.sh` | **60/60** |
| `test_customer_module.sh` | **50/50** |
| `test/verify-users-fixes.sh` | **125 PASS / 0 FAIL** |

Progression of the users suite across the fixes: 41 → 52 → 54 → 57 → 60.
`verify-users-fixes.sh`: 113 → 115 → 118 → 119 → 120 → 122 → 123 → 125 PASS.

Progression of the users suite across the fixes: 41 → 52 → 54 → 57 → 60.
`verify-users-fixes.sh`: 113 → 115 → 118 → 119 → 120 PASS.

### The limiter caveat, stated so it is not lost

At the shipped `login_max: 5` / `login_window: 60`, **neither suite can
complete**: the users suite makes more `POST /auth` calls than the window
allows, and the limiter is a **sliding per-IP bucket**, so waiting a quiet
window does not clear a bucket that is already full. Symptoms are a cascade
of **429** on `/auth` and 302-to-`/login` on every route that needs a session
— which reads as an app defect and is not one. Any future run must widen the
limiter first, or the suites must wait per attempt.

## 5. Defects found in the app, and fixed

Each was found from a failing assertion, not guessed.

| Test | Cause | Fix |
|---|---|---|
| **T47** grid shows a soft-deleted record | `www/config.json` sets `"deleted": false`, so a deleted record is **visible to a scan by default**. `LoadAll()` uses `dbGoTop`/`DbSkip`/`!Eof()`, which honour the flag — the flag was off | wrapped the grid scan in `Set( _SET_DELETED, .T. )` and restored it after — the same discipline `HIX_DBF:CountDeleted()` uses (`src/dbf/hix_dbf.prg:785`) |
| **D-16b** a **prefix** of a username authenticated (`carle` logged in as `carlesX`) | `www/config.json` sets `"exact": false`, so Harbour compares strings only to the length of the **RIGHT** operand: `"carlesx" != "carle"` is **FALSE**. The `ModelUser` guard relied on `!=`, so it never fired | guard is `Len( cFound ) != Len( cSeek ) .OR. Upper( cFound ) <> Upper( cSeek )` — `Len()` closes the prefix before any comparison. Verified by probe: `carle -> REJECTED`, `carlesX -> ACCEPTED` |
| **D-08a** `sort=roles` was a no-op (first row identical ASC and DESC) | Harbour's `<` and `>` on **strings** are `SET EXACT` affected, same as `!=`: with EXACT OFF the comparison only reads the RIGHT operand's length, so `a < b` and `a > b` can BOTH be false. A comparator built on them cannot order the rows, so the sort left the order unchanged | `_CompareVal`'s string branch compares byte-wise via `_CmpBytes`, which walks a fixed alphabet with length-1 `==`/`<>` (exact under EXACT OFF). `Ord()` is not linked into the server (`Unknown or unregistered function symbol (ORD)`), so the rank comes from a table built by concatenation. Verified: ASC starts `carlesX`, DESC starts `admin` |
| **D-15g** `create` re-render showed no field errors | `Create()` passed a literal `{ => }` as `hErrors`, so the form could never mark a field invalid | `Create()` reads the flash's `input` and `errors` like `Edit()` and passes them through. Verified: 3 `is-invalid` markers and all three "The field X is required" messages |
| **T44** `POST /users/2/update` returned 302 but wrote nothing | **`users.dbf` has no `VERSION` field** (header: `ID N(10) NAME C(40) PASS C(128) SALT C(32) ROLES C(255)`). `FieldPos("VERSION")` → 0, `FieldPut(0,…)` fails, and `HIX_DBF:Update()` aborts the whole write | dropped the invented `VERSION` column and P3.7's conflict contract. Adding a field would change the header and invalidate the CDX, so the contract is **dropped, not faked**: last-writer-wins, which is what a single-writer DBF store gives |
| **T32** invalid id should render, not redirect | `Show()` redirected to grid; the audited shape passes `lFound` and renders the view either way, with a blank row on a miss | `Show()` renders `( hRow != NIL )` plus `_BlankRow()` |
| **T44** (second half) | hand-rolling `RLock → FieldPut → Unlock` omitted `DbCommit()`; the audited `HIX_DBF:Update()` does `RLock → FieldPut → DbCommit() → DbUnlock()` (`src/dbf/hix_dbf.prg:606`) | use the audited verb instead of hand-rolling it |
| all `:id` routes → 302 | the public id was resolved through a **persisted `ID` field that is blank in every shipped copy** — `git log` shows `ID` blank in all 7 historical `users.dbf`, and `customers.dbf`'s `ID` is garbage too. The audited `customer` module resolves `:id` with **`GetRecno`** | switched to recno, matching the audited module. **There was nothing to reseed** — the field was never populated, by design |
| `/users/create` → **500** | view arity: `Create()` passed `0` where `edit.html` declares `hErrors := {=>}`, so `HB_HGetDef` got a number → `Argument error` | aligned every `UView` call to the view's declared arity |
| T58/T59 reported 0/9 routes | `web.json` had been rewritten with `json.dumps(indent=2)`, splitting each route across lines; the suites grep `"url": "/users` **per line** | one route per line |

## 6. Test-suite bugs found, and fixed

Three assertions were wrong for reasons that first read as app defects.

| Test | The app was correct; the assertion was not | Fix |
|---|---|---|
| **T33** edit pre-populates name | the app renders `value="admin"`, but the DBF field is `C(40)` so it is **blank-padded**. The grep demanded `value="admin"` with the closing quote immediately after | dropped the closing quote from the pattern |
| **T43/T45** validation failure → flash + re-render | `-L` on a **POST** redirect re-issues the POST and lands on a **405** with a 386-byte error page. A browser would show the redirect target as a **GET** | POST to `/dev/null`, then GET the redirect target and grep that |

## 7. Defects found in the test suites, and fixed

Five assertions were wrong for reasons that first read as app defects.

| Test | The app was correct; the assertion was not | Fix |
|---|---|---|
| **T33** edit pre-populates name | the app renders `value="admin"`, but the DBF field is `C(40)` so it is **blank-padded**. The grep demanded `value="admin"` with the closing quote immediately after | dropped the closing quote from the pattern |
| **T43/T45** validation failure → flash + re-render | `-L` on a **POST** redirect re-issues the POST and lands on a **405** with a 386-byte error page. A browser would show the redirect target as a **GET** | POST to `/dev/null`, then GET the redirect target and grep that |
| **D-05d / D-08b / D-08c / D-11b** | literal source-text greps over the old implementation's exact spelling (`Hide( { 'pass', 'salt' } )`, 4-space alignment, `aSortOk`, `::oUsers:`). The rewrite legitimately changed all four | re-pointed at the current shape; `D-05d` re-asserted as behaviour (views never `FieldGet` PASS/SALT) rather than the replaced `Hide()` call |
| **D-09f** rejected rename left record 2 unchanged (expected `carles`, got `carlesX`) | **test-order artifact.** An earlier phase of the same run renamed recno 2. The rename *was* rejected; the store simply isn't pristine when the assertion runs | capture the value **before** the rejected rename and compare against that |
| **H-05c** session files are 0600 | **launch, not code.** The app was started directly, so it did not inherit `umask 077` from `go_gcc.sh:26`; 3676 session files were `0644`. `go_gcc.sh:130` documents that a store created under a looser umask keeps 0644 records and that umask cannot fix existing files | launched with `umask 077`; new session files are `0600` |

## 8. What is NOT proven

Not run at all: `test_customer_module.prg`, `bf_harness.sh`, `bf_timing.py`,
and the probes `probe_entropy` / `probe_hash` / `probe_pwcost` (only
`probe_seek` and `probe_pw` were run).

## 8. Compliance grading

| Clause | Grade | Evidence |
|---|---|---|
| T1 HIX framework + Harbour only | ✅ | the store is `www/models/tusers.prg` over the framework's `UDbf()` (`src/dbf/hix_dbf.prg`); no third-party library |
| T2 HIX style only | ✅ | the modules are the audited nine-verb shape; `hix.json` `hixstyle.enabled` true (asserted by the suite, PASS) |
| T3 no 3rd-party web UI | ✅ | unchanged |
| T4 only HIX + Harbour | ✅ | no database engine, no SQL library — there is nothing to link, and the link is clean |
| T5 tools in the project folder | ✅ | `regenerate_users.*` under `webapp/`; no new tool was added |
| T6 nothing outside the project folder | ✅ | the store is `webapp/data/`; `.mysql/` was deleted, not moved |
| T7 `hbmk2 app.hbp` only | ✅ | `app.hbp` unchanged and links |
| T8 port 9090 | ✅ | `hix.json` untouched |
| "No SQL", no exception | ✅ | no engine is opened anywhere; `sql/` is now empty and nothing reads a schema |
