# Users Module — Status Review

**Date:** 2026-10-05 00:58 (Asia/Manila)
**Scope:** Users module ONLY — `www/controllers/masters/users.prg`, `www/models/tusers.prg`, `www/models/modeluser.prg`, `www/models/hpassword.prg`, `www/middlewares/myapplogin.prg`, `www/views/masters/users/*.html`, `users.*` routes in `www/routes/web.json`, `data/users.dbf` + `data/users.cdx`
**Mode:** **Report only — no remediation applied** (per `srs/FUNC-testing.md`: "report only the test results and recommendations, no remediation")
**Predecessor report:** `TEST-RESULTS-USERS-MODULE.md` (2026-10-04 09:22) — 22/60 pass, module non-functional. This report supersedes it.
**Target:** `http://localhost:9090` — HIX 2.2.01 (r2609301131) / Harbour 3.2.1dev (r2609180937) / GNU C 16.2.1 / RDD default DBFCDX

---

## Overall Result

| Metric | Value |
|---|---|
| Suite | `test/verify-users-fixes.sh` (D-01..D-16) |
| Passed | **70** |
| Failed | **3** (all three triaged as harness/data-state issues, not module defects) |
| Module usable | **PARTIALLY — all 6 authenticated screens render; write forms fail for a real browser (see N-01)** |
| Module deploy-ready | **NO** |

**Headline:** the 09:22 blocker (D-01, controller did not compile → every users route 500) is closed and all 14 catalogued defects are verified fixed against a live server. A **new P0 defect (N-01)** was found in this review: the users write forms render **no CSRF token**, so create/update/delete work for the test harness but fail with `302 → /login` for a real browser. The regression suite masks it.

---

## Repository state

| Item | Value |
|---|---|
| HEAD | `4730cc5` — "users module: fix D-16 — login case handling and loose RDD comparisons", 2026-10-04 10:21:59 +0800 |
| Relevant commits | `02e03fc` close D-01..D-04 → `ea32935` D-15 (views 500 on raw hash subscript) → `4730cc5` D-16 (login case handling, loose RDD comparisons) |
| Working tree | **Mid-flight, uncommitted**: 11 files, **+627 / −304** |
| Uncommitted files | `www/controllers/masters/users.prg` (469 lines), `www/middlewares/myapplogin.prg` (36), `www/models/modeluser.prg` (30), `www/models/tusers.prg` (5), `www/routes/web.json` (4), `www/views/masters/users/edit.html` (11), `grid.html` (4), `show.html` (4), `regenerate_users.prg` (40), `regenerate_users.hbp` (1), `test/verify-users-fixes.sh` (327) |
| New untracked | `www/models/hpassword.prg`, `test/probe_hash.prg`, `test/probe_seek.prg`, `probe_hash`, `probe_seek`, `migrate_users`, `regenerate_users`, `.tmp_verify/`, `.sessions/`, `www/models/modeluser.prg.bak` |
| Risk | Nothing has been committed since 10:21:59 — the entire D-05..D-14 body of work exists only in the working tree. |

---

## Defect status — all 16 from the 09:22 report

| ID | Severity | Status | Evidence (current files) |
|---|---|---|---|
| **D-01** | P0 | **FIXED** | `harbour -iwww -i$HB/include -n www/controllers/masters/users.prg` → *Lines 2093, Functions/Procedures 25*, **0 errors**, C source generated. Suite: D-01a PASS; D-01b PASS on `/users/grid`, `/users/1`, `/users/4/delete_confirm` |
| **D-02** | P0 | **FIXED** | `www/views/masters/users/delete.html:66` → `action="{{ URoute( 'users.delete', HB_HGetDef( hRow, '_recno', 0 ) ) }}"`. D-02a PASS (`/users/6/delete` matches route), D-02b PASS (302 → grid), D-02c PASS (`*` flag set), D-02d PASS (soft-deleted row absent from grid) |
| **D-03** | P0 | **FIXED** (suite run blocked by stale data — see F-1) | `users.prg` `Store()` now: `hData[ 'id' ] := Self:NextId()`, `hData[ 'salt' ] := _PwSalt( cName )`, `hData[ 'pass' ] := _PwHash( cPass, hData[ 'salt' ] )`, `lSuccess := oUsers:Insert( hData, @cError, @nRecno )`. D-03c/D-03d/D-03e/D-03f PASS (validation path, no phantom insert, row readable, non-zero ID) |
| **D-04** | P0 | **FIXED** | `regenerate_users.prg` admin ROLES now include `users:search;show;edit;delete;create`. D-04a PASS (admin reaches `users.create`, HTTP 200); D-04b PASS (maria, no `users:create` → 403) |
| **D-05** | HIGH (SEC) | **FIXED** | `www/models/tusers.prg:17-21` `oUsers:Hide( { 'pass', 'salt' } )` (comment: HIX_DBF:`Row()` builds `hRow` from `::hFields`); `grid.html` Password column and `<td>pass</td>` removed; `show.html` Password row removed; `edit.html` `type="password" value="" autocomplete="new-password"`; `modeluser.prg` no longer writes `hEntry["pass"]`. D-05a..D-05i **all PASS**, incl. D-05g "no 64-hex digest rendered anywhere" |
| **D-06** | HIGH (SEC) | **FIXED** | Search restricted to an allow-list; D-06a PASS (controller search block never touches `pass`/`salt`), D-06b PASS (digest fragment `5d3e06b07e` matches nothing), D-06c PASS (`1234` matches nothing) |
| **D-07** | HIGH (SEC) | **FIXED** | New `www/models/hpassword.prg`: `PW_SALT_LEN 32`, `PW_HASH_ITERATIONS 1000`, `_PwHash()` = 1000× `hb_sha256( salt + hash )`, `_PwMatch()` non-early-exit compare. Wired via `#include "models/hpassword.prg"` in `modeluser.prg`, which re-hashes the submitted password against the stored salt before building the session entry. `/auth` limiter: `myapplogin.prg` `HIX_MwRateLimitFactory( LOGIN_MAX_ATTEMPTS 10, LOGIN_WINDOW_SECS 60 )`. D-07a..D-07f PASS; D-07c PASS (**429 at attempt 4**) |
| **D-08** | MEDIUM | **FIXED** (assertion string stale — see F-2) | `users.prg:505` `cSort := Lower( UGet( 'sort', 'name' ) )`; `users.prg:506-507` `IF Ascan( aSortOk, cSort ) == 0` → falls back to `'name'`. D-08a PASS (`sort=roles` ASC `carles` vs DESC `admin`) |
| **D-09** | MEDIUM | **FIXED** | `users.prg` `NameExists( cName, nExclude )` (`DbSeek( Lower( AllTrim( UStr( cName ) ) ) )` + strict `!=` confirmation) called from both `Store()` and `Update()`. D-09a..D-09f PASS: duplicate `ADMIN` refused, nothing inserted, "already in use" reported on create and on rename, rejected rename left record 2 unchanged |
| **D-10** | MEDIUM | **FIXED** | Flash drained after consumption. D-10a PASS (shown once), D-10b PASS (no leak into a later edit), D-10c PASS (no leak into grid) |
| **D-11** | MEDIUM | **FIXED** | `users.prg` no longer calls `dbcloseall()`; `Destroy()` closes only `Self:oUsers:Close()`. D-11a/D-11b PASS |
| **D-12** | LOW | **FIXED** | `www/routes/web.json`: `users.create` and `users.edit` GET now `middleware: "MyAppAuthRoleEdit"` (previously `MyAppAuthRole`). D-12a/D-12b/D-12c PASS |
| **D-13** | LOW | **FIXED** | No bare `oVal:Get()` remains — all calls pass the field name. D-13a PASS |
| **D-14** | LOW | **FIXED** | `data/` now holds only `customers.cdx/.dbf`, `states.cdx/.dbf`, `users.cdx/.dbf`. D-14a PASS. (`users.cdb`, `users.dbt` deleted in the working tree; `data/check_tag.c` deleted) |
| **D-15** | — (fixed in `ea32935`) | **FIXED** | No raw `hMessage[...]`/`hErrors[...]` subscript left in users views. D-15a PASS; D-15b PASS on all 6 screens; D-15c PASS (`/users/999` renders the not-found path); D-15d/e/f/g PASS (re-render after failed update/create marks `is-invalid` and shows field messages); D-15h PASS (no new `Bound error` during the run) |
| **D-16** | — (fixed in `4730cc5`) | **FIXED** | `regenerate_users.prg` `INDEX ON Lower( field->name ) TAG name`; login compares digests. D-16a..D-16f PASS: partial name `carle` rejected, wrong password rejected, mixed-case `JOHN` logs in, password prefix `9012` rejected, full `9012abcd` accepted |

---

## NEW defect (not in the 09:22 report)

### N-01 — P0 — users write forms render no CSRF token

`@CSRF` (the HIXSTYLE directive that expands to `<input type="hidden" name="_csrf" value="…">`; see `hix/site-docs/en/hixstyle/seguridad/csrf.md`) appears in exactly three views:

```
www/views/sys/login.html:38                        @csrf
www/views/masters/customer/edit.html:113           @CSRF
www/views/masters/customer/delete.html:164         @CSRF
```

It is **missing** from every users write form:

| View | Form | Posts to | Token rendered? |
|---|---|---|---|
| `www/views/masters/users/edit.html:80` (shared create **and** edit) | `<form method="POST" action="{{ if( cMode == 'create', URoute( 'users.store' ), URoute( 'users.update', … ) ) }}">` | `/users/store`, `/users/:id/update` | ❌ none |
| `www/views/masters/users/delete.html:66` | `<form method="POST" action="{{ URoute( 'users.delete', HB_HGetDef( hRow, '_recno', 0 ) ) }}">` | `/users/:id/delete` | ❌ none |
| `www/views/masters/users/grid.html:217` | `form.innerHTML = '@CSRF';` — **inside a JS string literal**, not expanded by the template engine (rendered grid contains 0 `_csrf`) | JS-built delete form | ❌ none |

Verified live with a valid authenticated admin session:

```
POST /users/1/update  (no _csrf) → 302 -> http://localhost:9090/login
POST /users/1/delete  (no _csrf) → 302 -> http://localhost:9090/login
POST /users/store     (no _csrf) → 302 -> http://localhost:9090/login
```

`HIX_MwCsrfCheck` (applied by `MyAppAuthRoleEdit`, see `www/middlewares/myappauthedit.prg:8-11,22`) rejects them, so **no write operation is reachable from a browser**.

**Why the suite does not catch it:** `test/verify-users-fixes.sh`'s `csrf()` helper harvests the token from `GET /login` and posts it manually (`-d "…&_csrf=$(csrf)"`). The token is stateless-HMAC/session bound, so it is accepted — every write test passes without the form ever carrying a token.

**Same latent pattern in the customer module:** `www/views/masters/customer/grid.html:230` also has `form.innerHTML = '@CSRF';` inside a JS string (rendered customer grid: 0 `_csrf`).

**Recommendation R-01 (P0):** add `@CSRF` to `www/views/masters/users/edit.html` (inside the `<form>` opened at line 80) and `www/views/masters/users/delete.html` (inside the `<form>` at line 66); replace the JS-string `@CSRF` in `users/grid.html:217` and `customer/grid.html:230` with a token injected server-side (e.g. `UCsrfToHtml()` into a data attribute). Add a suite check that asserts each rendered write form contains a `_csrf` input.

---

## Suite failures — triaged

| # | Test | Result | Root cause |
|---|---|---|---|
| **F-1** | `D-03a POST /users/store persists a new row` (expected 7 / got 6) and `D-03b store success redirect` (expected `/users/grid` / got `/users/create`) | ❌ FAIL | **Test-state pollution, not a module defect.** `data/users.dbf` recno 6 is a leftover `zverify` row from an earlier suite run (`regenerate_users.prg:16` seeds only `admin, carles, maria, John, jane`). The suite posts the fixed name `zverify`; `NameExists()` (`users.prg:141-165`) **deliberately counts soft-deleted names** — documented at `users.prg:141-143`: *"A soft-deleted name still counts: re-creating it would resurrect an identity that existing sessions/audit trails may still reference."* → duplicate refused → no insert → redirect to `users.create`. **The suite is not idempotent**: it needs `regenerate_users` (or an equivalent re-seed) before each run, or a unique test name. |
| **F-2** | `D-08b sort key is lower-cased to match the grid hash keys` (expected 1 / got 0) | ❌ FAIL | **Stale assertion.** The suite greps for `cSort    := Lower( UParam( 'sort', 'name' ) )`; the code is `cSort    := Lower( UGet( 'sort', 'name' ) )` at `users.prg:505`. Behaviour is correct — D-08a passed. Fix the assertion string, not the code. |

**Net:** 0 confirmed module defects among the failures; 1 confirmed new defect (N-01) found outside the suite.

---

## Stale runtime error — resolved, not reproducible

`.logs/hix.log:222-230` and `.logs/errors.log` record, at 10:35:54, across all six users screens:

```
Subsystem  : BASE
SubCode    : 6101
Severity   : 2
Description: Unknown or unregistered function symbol
Operation  : HB_HDELKEY
File       : :0
```

No call site remains anywhere in `www/`. `www/controllers/masters/users.prg:120-121` documents the fix:

```prg
// Blank it rather than delete it: hb_HDelKey() is not linked into the
// HIX server binary, and an empty value is never rendered (edit.html
// always posts value="").
IF hb_HHasKey( hOut, 'pass' )
   hOut[ 'pass' ] := ''
ENDIF
```

`HB_HDelKey` is also absent from the Harbour include tree (`/home/jack/Projects/harbour/include`), confirming the symbol genuinely is unavailable to the HIX server binary. Not reproducible in this review; suite check **D-15h** (no new `Bound error` during the run) PASS.

---

## What is verified working

* `users.prg` compiles clean; all 9 users routes execute (no 500s).
* All 6 authenticated screens render 200, plus the not-found path (`/users/999`).
* Validation re-render works on both create and edit (`is-invalid` + per-field messages).
* Login is DBF/CDX-backed, case-insensitive on `Lower(name)`, exact (no prefix acceptance), digest-based.
* RBAC/scope enforced: users without `users:*` → 403; `users:delete` enforced independently; `users:create` reachable for admin and refused for maria.
* Credentials no longer appear in grid, show, edit, session hash, or rendered HTML (no 64-hex digest anywhere).
* Passwords stored as salted, iterated SHA-256 (PASS C(128) + SALT C(32)); no plaintext seed password in `users.dbf`.
* `/auth` rate-limited per route (429 observed at attempt 4 of 15).
* Column sorting works and is restricted to an allow-list; free-text search restricted to an allow-list.
* NAME uniqueness enforced on create and rename, with user-visible "already in use".
* Flash drained after consumption; no cross-screen leakage.
* `Destroy()` closes only the module's own DAL instance.
* Compliance posture intact: HIX only, HIXSTYLE active, port 9090, DBF+CDX only, zero SQL, tools/scripts inside the project folder.

## Compliance Summary

| Constraint | Status |
|---|---|
| C-001 HIX only | ✅ |
| C-002 No SQL | ✅ |
| C-003 HixStyle MVC | ✅ |
| C-004 DBF/CDX only | ✅ |
| C-005 Mambo views | ✅ (all users screens render) |
| C-006 JSON routes | ✅ (9/9 declare `middleware` + `scope`) |
| C-007 HIX auth middleware + scope | ✅ |
| C-008 Harbour .prg | ✅ (compiles clean — D-01 closed) |
| C-009 SSL/TLS | ⚠️ `ssl = false` |
| C-010 Cross-platform build | ✅ (`hbmk2 app.hbp`) |
| CSRF on every POST form | ❌ **N-01 — users write forms carry no token** |
| No change outside project folder | ✅ |

---

## Open risks and questions (not defects — decisions pending)

1. **Salt entropy** — `_PwSalt( cName )` in `www/models/hpassword.prg` derives the salt from `name + hb_TToS( hb_DateTime() ) + hb_NTOS( Seconds() ) + hb_NTOS( RecCount() )`, i.e. **not a CSPRNG**. The file header states the rationale: `hb_rand` needs the `hbct` contrib and `app.hbp` must not change (DEV-compliance). Salt uniqueness is name-bound; two creates of the same name in the same second would collide (currently blocked by D-09 uniqueness).
2. **Work factor / lockout tuning** — 1000 SHA-256 rounds is a modest work factor. `myapplogin.prg` records that the audit recommendation was **5 attempts / 60 s** but ships **10 / 60** "to keep the automated suite runnable inside a single window"; the file explicitly says to tighten the `#DEFINE` for production.
3. **CSRF secret** — `www/config.json:17` carries a fixed literal `csrf` key. HIX docs warn the fallback key is `H!x@CSRF@2026` and that changing `app_key` invalidates every token issued before (open forms 403 until refresh).
4. **Data hygiene** — `data/users.dbf` still carries the stray `zverify` record (recno 6), which is not part of the `regenerate_users.prg` seed list and which breaks suite idempotency (F-1).
5. **Uncommitted work** — the entire D-05..D-14 remediation body exists only in the working tree; nothing committed since 10:21:59. `www/models/modeluser.prg.bak` is a leftover backup that should be removed or gitignored.
6. **Cross-module carry-over** — N-01's JS-string `@CSRF` pattern and the missing-token class of defect also affect the customer module (`customer/grid.html:230`); fixes in the users module have historically been copied from `customer.prg`, so the reverse propagation is worth a pass.

---

## Recommended order (if remediation is later authorized)

1. **R-01 / N-01** — add `@CSRF` to `users/edit.html:80` and `users/delete.html:66`; fix the JS-string `@CSRF` in `users/grid.html:217` (and `customer/grid.html:230`).
2. Re-seed `data/users.dbf` (`regenerate_users`) before each suite run, or make the suite's test name unique — otherwise D-03a/D-03b will keep failing.
3. Correct the D-08b assertion string (`UParam` → `UGet`) in `test/verify-users-fixes.sh`.
4. Tighten `LOGIN_MAX_ATTEMPTS` to 5 for non-test builds; consider raising `PW_HASH_ITERATIONS`.
5. Commit the working tree (or branch it) — 11 files of remediation are currently uncommitted.

---

## Session bookkeeping
* **Data restored byte-identical:** `data/users.dbf` md5 `a1f73e6edaf65f0801e1cf1754eab4a0`, `data/users.cdx` md5 `c6924813be93d601ba05bf4614b992cb` (snapshot taken before the run, restored after).
* Server started on `localhost:9090` for the review and **stopped afterwards** (port verified closed).
* Only `.logs/access.log` and `trace.log` grew during the review.
* Compile check run in `/tmp` (no project artifacts created): `harbour -iwww -i/home/jack/Projects/harbour/include -n users.prg` → 2093 lines, 25 functions, 0 errors.
* A delegated read-only reviewer run timed out at the 30-minute limit and produced no usable result; every finding in this report was established first-hand in the main session.
* New artifact from this review: this report (`STATUS-USERS-MODULE.md`).

---

# Addendum — remediation applied 2026-10-05

The "report only" constraint was lifted afterwards; the recommended order was executed in full.  This section supersedes the findings above wherever they conflict.

**Suite: 70 PASS / 3 FAIL → 99 PASS / 0 FAIL** (`test/verify-users-fixes.sh`, now covering D-01..D-16 + N-01 + C-009 + SEC).

| Item | Result |
|---|---|
| **N-01** CSRF on write forms | **FIXED** — `@CSRF` added to `users/edit.html` and `users/delete.html`; the JS-string `@CSRF` in `users/grid.html` and `customer/grid.html` replaced with a server-side `data-csrf="{{ HIX_CsrfMakeToken() }}"`. A tokenless POST is still rejected 302 → `/login`; a POST carrying the token its own form rendered is accepted. |
| **Suite idempotency** | **FIXED** — the test row is now `zverify<epoch>`; `data/users.dbf` re-seeded. Three consecutive runs all passed D-03a/D-03b. |
| **F-2 / D-08b** | **FIXED** — assertion string corrected (`UParam` → `UGet`); code was already correct. |
| **Login limit** | **TIGHTENED** — 10/60 → the audit value **5/60**, now config-driven (`www/middlewares/config.json` → `setup.ratelimit.login_max` / `login_window`). Suite made rate-limit-aware. |
| **Work factor** | **RAISED** — `PW_HASH_ITERATIONS` 1000 → **10000** (measured 4.0 ms/hash, `test/probe_pwcost.prg`); `users.dbf` re-seeded; new check D-07g recomputes the stored digest. |
| **Uncommitted work** | **COMMITTED** — `c58ec7a`, `ca3083e`, `a2dba71`, `d40f9cf`. |
| **C-009 SSL/TLS** | **CLOSED** — `server.ssl = true` with a self-signed local certificate from `gen_cert.sh` (`certs/` gitignored, key chmod 600). Plain HTTP on 9090 is refused; suite checks C-009a/b/c. |
| **Salt entropy** | **CLOSED** — `_PwSalt()` now uses `hb_RandStr(32)`, Harbour core RTL (`hb_arc4random_buf`, seeded from `/dev/urandom`), so no `hbct` contrib and no `app.hbp` change. Verified by `test/probe_entropy.prg` (5000 seeds, 0 duplicates). |
| **CSRF secret** | **CLOSED** — the five key literals are out of git. `www/config.json` is gitignored (template `www/config.json.example`); `app.prg` guarantees a strong per-installation key set before the server loads it, with `HIX_KEY_*` env overrides. |

### Compliance after remediation

| Constraint | Status |
|---|---|
| C-001..C-008, C-010 | ✅ unchanged |
| C-009 SSL/TLS | ✅ **TLS 1.3 on 9090; plaintext refused** |
| CSRF on every POST form | ✅ **N-01 closed, guarded by the suite** |
| No committed secrets | ✅ keys generated per install; `certs/` and `www/config.json` gitignored |

### New operational note

`server.autostart` is now `false`.  HIX's `HIX_Navigator()` opened the app with `xdg-open` at startup, and the browser inherited the listening socket: killing the server left port 9090 bound by chromium, so the next start failed with *"Cannot bind port 9090"* while `ss` showed a LISTEN socket with no server behind it.

### Also corrected

`HIX_MwRateLimitSetup()` was being fed `UConfig( "setup", "ratelimit", "ip_per_min" )`, which returns a hash or the default string, so the call was silently ignored and the global limiter kept HIX's built-in 60/60 rather than the declared 300/60.
