# Users Module — Functional End-to-End Test Report

**Date:** 2026-10-04 09:22
**Scope:** Users module ONLY — `www/controllers/masters/users.prg`, `www/models/tusers.prg`, `www/views/masters/users/*.html`, `users.*` routes in `www/routes/web.json`, `data/users.dbf` + `data/users.cdx`
**Suite:** `test/test_users_module.sh` (60 tests) — new, created inside the project folder
**Target:** `http://localhost:9090` — HIX 2.2.01 (r2609301131) / Harbour 3.2.1dev (r2609180937) / GNU C 16.2.1 / RDD default DBFCDX
**Build:** `hbmk2 app.hbp` (per DEV-compliance.md) — reported "Target up to date"; controllers are compiled at runtime by HIXSTYLE
**Mode:** **Report only — no remediation applied** (per `srs/FUNC-testing.md` convention)

---

## Overall Result

| Metric | Value |
|---|---|
| Total tests | 60 |
| Passed | **22** |
| Failed | **38** |
| Pass rate | **36.7%** |
| Module usable | **NO — 0 of 6 authenticated screens render** |

**Headline:** the users module is **completely non-functional at runtime**. Every authenticated
request into the module returns **HTTP 500 (COMPILER / E0020)**. Authentication, RBAC plumbing,
routing, CSRF and DBF/CDX compliance all pass — the module itself never executes.

---

## Blocking defect (single root cause)

### D-01 — `users.prg` does not compile → all users routes return 500

```
=== Error #1 — 04/10/26 09:17:25 ===
Subsystem  : COMPILER      SubCode : 20
Description: Incomplete statement or unbalanced delimiters
Operation  : line:63
File       : www/controllers/masters/users.prg
```

Independent verification with the Harbour compiler:

```
$ harbour -iwww -i$HB/include -n .tmp_compile/u.prg
u.prg(55)  Error E0020  Incomplete statement or unbalanced delimiters
u.prg(56)  Error E0030  Syntax error "syntax error at '}'"
... 33 errors, "No code generated."
```

**Cause:** Harbour line-continuation. Every multi-line hash literal opened with `{ ;`
requires each continuation line to end with `;`. In `users.prg` the last element of each
literal has **no trailing `;`** (the pattern copied from `customer.prg` does have it).

Failing literal lines: **55, 158, 172, 182, 199, 209, 230, 238, 250, 258, 276, 298**
(12 literals across `Show`, `Update`, `Store`, `delete_confirm`, `delete_action`).

| Line | Content (missing trailing `;`) |
|---|---|
| 55, 158, 276, 298 | `"id" => { "required|number|min:0", "Id", "" }` |
| 172, 230 | `"roles" => "required|string|max:255|field"` |
| 182, 209, 238 | `"input" => hResume` / `"input" => oVal:Resume()` |
| 199, 250 | `"message" => 'User ' + ltrim(str(nId)) + ' was updated!'` |
| 258 | `"errors" => { => },` |

**Recommendation R-01 (P0):** append `;` to the last element line of each of the 12 hash
literals, matching the `customer.prg` style (`... "" } ;` then `} )`). Add a pre-compile gate:
run `harbour -iwww -n <controller>` (or check `.logs/errors.log` for `Subsystem: COMPILER`)
before declaring any module functional — HIXSTYLE swallows this into a 500 at request time.

---

## Test Results by Area

### A. Compile integrity
| ID | Test | Result |
|---|---|---|
| T01 | `users.prg` compiles cleanly | ❌ **FAIL — 33 compiler errors** |

### B. Unauthenticated access protection (REQ-FUNC-020/023)
| ID | Test | Result |
|---|---|---|
| T02–T07 | 6 GET users routes → 302 to /login | ✅ PASS |
| T08–T10 | 3 POST users routes → 302 to /login | ✅ PASS |

### C. Authentication against `users.dbf` (REQ-FUNC-024, migration b3475d0)
| ID | Test | Result |
|---|---|---|
| T11 | `/login` renders CSRF token | ✅ PASS |
| T12 | POST `/auth` without CSRF rejected | ✅ PASS |
| T13 | POST `/auth` admin/1234 (DBF-backed, CDX seek on `Lower(name)`) | ✅ PASS |
| T14 | GET `/main` with session → 200 | ✅ PASS |

### D. Route resolution / HTTP status (authenticated admin)
| ID | Route | Expected | Got |
|---|---|---|---|
| T15 | GET `/users/grid` | 200 | ❌ **500** |
| T16 | GET `/users/search` | 200 | ❌ **500** |
| T17 | GET `/users/create` | 200 | ❌ **403** (see D-03) |
| T18 | GET `/users/1` | 200 | ❌ **500** |
| T19 | GET `/users/1/edit` | 200 | ❌ **500** |
| T20 | GET `/users/1/delete_confirm` | 200 | ❌ **500** |

### E. Grid (FR-READ-1..4) — all unverifiable, page never renders
| ID | Test | Result |
|---|---|---|
| T21–T27 | table rows, `_q_name` input, sortable headers, pagination, row actions, Create button, name data | ❌ FAIL (500) |

### F. Search / Show / Edit / Create / Delete-confirm
| ID | Test | Result |
|---|---|---|
| T28–T29 | search form + Name input | ❌ FAIL (500) |
| T30–T32 | show record, all fields, "User not exist" | ❌ FAIL (500) |
| T33–T35 | edit pre-population, CSRF field, roles pre-population | ❌ FAIL (500) |
| T36–T37 | create form + name/pass/roles fields | ❌ FAIL (403) |
| T38–T39 | delete confirmation card + target record | ❌ FAIL (500) |
| T40 | delete form posts to a **routed** URL | ❌ **FAIL — see D-02** |

### G. Write operations (POST + CSRF)
| ID | Test | Result |
|---|---|---|
| T41 | POST `/users/store` without CSRF → 302 | ❌ FAIL — got **403** (scope check fires before CSRF check) |
| T42 | POST `/users/store` persists a new row | ❌ FAIL — 403, `users.dbf` unchanged (5 records) |
| T43 | store validation failure → flash + re-render | ❌ FAIL (403) |
| T44 | POST `/users/2/update` writes DBF | ❌ FAIL — 500, not persisted |
| T45 | update validation failure → flash + re-render | ❌ FAIL |
| T46 | POST `/users/4/delete` soft-deletes | ❌ FAIL — 500, no `*` flag set |
| T47 | grid excludes soft-deleted record | ❌ unverifiable |

### H. RBAC / scope enforcement (REQ-FUNC-023)
| ID | Test | Result |
|---|---|---|
| T48 | admin ROLES → `/users/create` reachable | ❌ **FAIL — 403** (D-03) |
| T49 | carles (no `users:*`) blocked from `/users/grid` | ✅ PASS (403) |
| T50 | carles blocked from `/users/1/edit` | ✅ PASS (403) |
| T51 | maria (no `users:delete`) blocked from delete_confirm | ✅ PASS (403) |

### I. Credential exposure (REQ-SEC)
| ID | Test | Result |
|---|---|---|
| T52–T54 | grid / show / edit must not expose plaintext password | ❌ **unverifiable at runtime** — but confirmed by source review (D-04) |

### J. DEV-compliance.md constraints
| ID | Constraint | Result |
|---|---|---|
| T55 | C-002/C-004 — DBF + CDX only, no SQL | ✅ PASS |
| T56 | C-003 — `hixstyle.enabled = true` | ✅ PASS |
| T57 | Build/port — server on **9090** | ✅ PASS |
| T58 | C-007 — 9/9 users routes declare middleware | ✅ PASS |
| T59 | REQ-FUNC-023 — 9/9 users routes declare `scope` | ✅ PASS |
| T60 | No SQL / 3rd-party data access in module sources | ✅ PASS |

---

## Findings and Recommendations (no remediation performed)

| # | Severity | Finding | Location | Recommendation |
|---|---|---|---|---|
| **D-01** | **P0 / BLOCKER** | 12 multi-line hash literals missing the trailing `;` → 33 compiler errors → every users route 500s | `users.prg` lines 55, 158, 172, 182, 199, 209, 230, 238, 250, 258, 276, 298 | Add trailing `;` to each last element line (customer.prg style). Add a compile gate to the test workflow. |
| **D-02** | **P0** | Delete form posts to a URL that matches no route: `action="{{ URoute( 'users.delete' ) }}"` renders `/users/delete`; the route is `/users/:id([0-9]+)/delete`. Verified: `POST /users/delete` → **403** (unmatched-route response). The hidden `id` body field cannot compensate. | `www/views/masters/users/delete.html:66` | Pass the recno: `URoute( 'users.delete', HB_HGetDef( hRow, '_recno', 0 ) )` — as `customer/delete.html:163` does. |
| **D-03** | **P0** | `Store()` never inserts. `lSuccess` and `nRecno` are declared but never assigned; there is **no `oUsers:Insert()` call anywhere in the file** (verified: only `GetRecno`, `Blank`, `Update`, `Delete` are called). Create is a silent no-op even after D-01 is fixed. *Inherited verbatim from `customer.prg` Store().* | `users.prg:219-266` | Call `lSuccess := oUsers:Insert( oVal:DataFields(), @cError )` and capture `nRecno` before the success branch. |
| **D-04** | **P0** | No user in `users.dbf` holds `users:create`. admin ROLES = `customers:…\|users:search;show;edit;delete`. Routes `users.create` and `users.store` require scope `users:create` → **403 for every account**, so the create flow is unreachable by design. | `data/users.dbf` rec 1; `regenerate_users.prg` aRoles[1] | Add `create` to the admin `users:` op list and re-run `regenerate_users.prg`; or change the create/store scope to an existing op. |
| **D-05** | **HIGH (SEC)** | Plaintext credentials rendered in the UI: grid reads and displays `PASS`, show renders a "Password" row, edit echoes the password in an `<input value=…>`. | `users.prg:392`; `views/masters/users/grid.html:112-125`, `show.html`, `edit.html` | Remove `pass` from the grid projection and from show; use a blank password field on edit with an explicit "change password" action. |
| **D-06** | **HIGH (SEC)** | Free-text grid search `q` matches against `pass` and `roles` as well as `name` → a search oracle that can probe password values. | `users.prg:404-407` | Restrict `q` to non-sensitive fields (`name` only), or add an explicit field allow-list. |
| **D-07** | **HIGH (SEC)** | Passwords remain plaintext in `users.dbf` and are compared with `!=` in `ModelUser`; no hashing/salt, no rate limiting on `/auth`. | `www/models/modeluser.prg` | Hash with a salted digest (Harbour `hb_sha*`/`hb_hmac*`), add `HIX_MwRateLimitFactory` on `/auth`. Consistent with the earlier pentest recommendation. |
| **D-08** | **MEDIUM** | Column sorting is a **no-op**: `cSort := Upper( UParam('sort','name') )` → `'NAME'`, but grid hash keys are lowercase (`hRec['name']`). `HB_HGetDef( cKey, 'NAME', '' )` returns `''` for every row, so no swap ever occurs. This is defect §4.8 from the customer module, copied into the users module. | `users.prg:341`, `390`, `472-474` | Lower-case the lookup key (`Lower(cSort)`) or store grid hash keys upper-case consistently. |
| **D-09** | **MEDIUM** | No uniqueness check on `NAME` for create/update. The CDX tag `name` is built on `Lower(name)`; duplicate names make `DbSeek` return only the first match → ambiguous login identity and silent privilege carry-over. | `users.prg` Store/Update; `tusers.prg` | Check `DbSeek( Lower(name) )` before insert/update and reject duplicates via `cError`. |
| **D-10** | **MEDIUM** | `Edit()` reads the flash and returns early when `hInput` is non-empty, but never calls `oFlash:Clear()`/`Save()` — a validation re-render stays sticky and can re-appear on a later, unrelated edit. | `users.prg:88-96` | Clear the flash after consuming it, as `Grid()` and `Show()` do. |
| **D-11** | **MEDIUM** | `Destroy()` calls `dbcloseall()`, which closes **every** alias in the worker process, not just this request's `USERS`/`CUSTOMERS` aliases — unsafe with `pool_http.workers = 64` and concurrent requests. | `users.prg:527-530` (also `customer.prg`) | Close only the module alias (`oUsers:Close()` / `DbCloseArea()`). |
| **D-12** | **LOW** | Middleware/scope inconsistency: `users.create` (a write-form entry point) uses the read middleware `MyAppAuthRole` while `users.store` uses `MyAppAuthRoleEdit`; `users.search` is scoped `users:search` but renders the same grid search form. | `www/routes/web.json` | Use `MyAppAuthRoleEdit` for create/edit entry points; document the scope vocabulary. |
| **D-13** | **LOW** | `nId := oVal:Get()` is called with no field name in `Update()` and `delete_action()` while the same method is called as `oVal:Get('id')` elsewhere in the same file. | `users.prg:165`, `305` | Use `oVal:Get('id')` consistently. |
| **D-14** | **LOW (hygiene)** | `data/` contains orphan artifacts from the migration experiments: `users.cdb`, `users.dbt` (memo files for a schema that has no M fields), `users_new.ntx`, `test_copy*.dbf/cdx`, `*.bak`. `users.dbf` schema is `ID N(10) NAME C(40) PASS C(40) ROLES C(255)` — no memo field. | `data/` | Remove or gitignore; keep only `users.dbf` + `users.cdx`. |

---

## What is actually working

* Session authentication is now genuinely **DBF/CDX-backed** (`admin/1234` authenticates through `users.dbf` via `DbSeek( Lower(name) )` on the `name` tag) — the AUTH migration objective is met.
* `_ParseRoles()` pipe format (`role:ops|role:ops`) is parsed and enforced: users without a `users:*` role are refused (403) on every users route; `users:delete` is enforced independently.
* CSRF middleware protects all users POSTs (verified: POST with a valid session but no `_csrf` → redirect to `/login`).
* Anonymous protection is complete on all 9 users routes.
* Route table is complete and well-formed: 9/9 users routes declare `middleware` **and** `scope`.
* Compliance posture is intact: HIX-only, HIXSTYLE active, port 9090, DBF+CDX only, zero SQL, no third-party web UI.

## Compliance Summary

| Constraint | Status |
|---|---|
| C-001 HIX only | ✅ |
| C-002 No SQL | ✅ |
| C-003 HixStyle MVC | ✅ |
| C-004 DBF/CDX only | ✅ |
| C-005 Mambo views | ✅ (views exist; never executed) |
| C-006 JSON routes | ✅ |
| C-007 HIX auth middleware + scope | ✅ |
| C-008 Harbour .prg | ✅ (but **does not compile** — D-01) |
| C-009 SSL/TLS | ⚠️ `ssl = false` |
| C-010 Cross-platform build | ✅ (`hbmk2 app.hbp`) |
| Build = `hbmk2 app.hbp`, port 9090 | ✅ |
| Tools/scripts inside project folder | ✅ (`test/test_users_module.sh`, `test/dbf_dump.py`) |
| No change outside project folder | ✅ |

**Module readiness: NOT READY.** Recommended order: R-01 (D-01) → D-03 → D-04 → D-02, then
re-run this suite; D-05/D-06/D-07 should be closed before any non-dev deployment.

---

## Session bookkeeping

* Build used: `hbmk2 app.hbp` (no relink required — HIXSTYLE compiles `www/controllers/**` at request time).
* Server: started on `localhost:9090` for the test run, **stopped afterwards**.
* Data: `data/users.dbf` / `data/users.cdx` **unchanged** (md5 verified identical before/after: `b5ef6768…`, `ffd584dc…`). No record was created, updated, or deleted.
* Source: **no remediation applied** — `users.prg`, `tusers.prg`, users views and `web.json` are byte-identical to the state at session start.
* New artifacts (test-only): `test/test_users_module.sh`, `test/dbf_dump.py`, this report.
