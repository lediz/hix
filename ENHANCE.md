# ENHANCE — the enhancements on this branch

`enhance` is the working branch of this repository. It carries two things at once: the **HIX
framework** (Harbour / xBase++ web server) at the root, and **`webapp/`**, the audited CRUD
application that runs on it. Everything `enhance` adds to the imported upstream history falls into
**two areas**:

1. **the HIX platform itself** — framework changes under [`src/`](src/);
2. **the Example CRUD → `webapp/`** — what turns upstream's
   [`examples/web/crud/`](examples/web/crud/) example into a hardened application;
3. **the store conversion** — what removed the MySQL DAL and the InvenTree-derived module set from
   `webapp/`, and put the application back on the RDDCDX RDD (DBF + CDX).

| | |
|---|---|
| Branch | `enhance`, tracking `origin/enhance` (`https://github.com/lediz/hix.git`) |
| Base | `origin/main` = the imported upstream history, left at `ab31bb4` |
| Delta | `./compare-branches.sh` → [`webapp/srs/06-release/COMPARISON-enhance-vs-main.md`](webapp/srs/06-release/COMPARISON-enhance-vs-main.md) |
| Provenance of the merge | [`webapp/srs/00-meta/UNIFIED.md`](webapp/srs/00-meta/UNIFIED.md) — how the two histories were joined, and the git rules learned the hard way |

---

## 1. The HIX platform

**What.** Seven framework files changed; nothing else outside `webapp/` is functional (the rest is
`.gitignore`, `.gitattributes`, `compare-branches.sh`, docs).

| File | Enhancement | Why |
|---|---|---|
| `src/hix_config_app.prg` | The shipped config defaults **no longer mint signing keys** into `config.json` | that file is `<paths.root>/config.json` — inside the document root, and root-level files there are downloadable (PENTEST-REPORT §1) |
| `src/hix_keys.prg` | Key resolution order: **`HIX_KeySet()` > `config.json` > generated in memory only**; per-install generation | a key that reaches the repository or the docroot is a public key; in-memory generation keeps a fresh install working without persisting a secret |
| `src/hix_csrf.prg` | CSRF tokens are **bound to the session that was served them** (`_HixCsrfCtx`, `_HixCsrfBind`, `HIX_CsrfBound`) | an unbound token is transferable — harvest one from an anonymous page, use it in someone else's session |
| `src/mw/hix_mw_csrf.prg` | The middleware rejects a token that fails `HIX_CsrfBound()` when a session is present; stateless behaviour is unchanged otherwise | closes the binding hole without breaking the middleware's documented standalone use |
| `src/hix_request.prg` | The scheme follows the **actual transport** (`oIO:lUseSSL`); `X-Forwarded-Proto` only overrides when present | `cProtoScheme` was set *only* from forwarded headers, so a standalone TLS server reported `http` and emitted session cookies **without `Secure`** (PENTEST-REPORT §4) |
| `src/hix_mw_loader.prg` | `paths.session` and `session: prefix / crypt / seed / gc_days` from `hix.json` are now honoured | they were parsed and ignored — `"crypt": true` had no effect and session payloads stayed plaintext on disk (PENTEST-REPORT §7) |
| `src/hix_helpers.prg` | `UParam()` falls back to `o:QueryParam()` | `GET` parameters were invisible to controllers, which is why grid search/pagination parameters were dropped |

**Why these and not app-side workarounds.** Each was a framework defect the application could not
close from the outside: the key defaults, the CSRF binding, the cookie `Secure` flag and the ignored
session config all live in code the app only calls. Fixing them in `src/` also means every other HIX
app inherits the fix.

**How they were verified.** Against the real `webapp/app` binary, not in isolation — the framework
half of each remediation is recorded as the counterpart of an app-side commit (e.g. `d14899a` ↔
`b47a497`), and `webapp/test/verify-users-fixes.sh` asserts the security block (H-05a/H-05c session
store modes, C-009 TLS, N-01 CSRF tokens on every write form).

---

## 2. Example CRUD → `webapp/`

**What.** `webapp/` descends from `examples/web/crud/` and keeps the same shape — `app.hbp`,
`src/app.prg`, `www/controllers`, `www/middlewares`, `www/models`, `www/views`, `www/routes`.
Counted over tracked files at `HEAD` — the example has 64 of them:

| | whole tree | app code only<br>(`webapp/` minus `srs/`, `docs/`, `resources/`, `test/`) |
|---|---|---|
| byte-identical in both | 35 | 21 |
| same path, different content | 24 | 24 |
| only in the example | 5 — its four `data/*` files and a tracked `www/config.json` | 19 — its `docs/`, images and data files |
| only in `webapp/` | — | 32 |

`webapp/` tracks 132 files in total, 77 of them app code.

**What `webapp/` adds** (the "only in webapp" set, grouped):

* **A second module** — `www/controllers/masters/users.prg`, `www/models/tusers.prg`, and the
  `www/views/masters/users/{grid,search,edit,show,delete}.html` views. The example has customers
  only.
* **Real authentication** — `www/models/hpassword.prg` (PBKDF2-style hashing, CSPRNG salt) and
  `www/models/modeluser.prg` rewritten; credentials live in `data/users.dbf` with a CDX tag, not in
  source. `migrate_users.prg` seeds it.
* **Operational scripts the example never needed** — `gen_cert.sh` (TLS certificate),
  `gen_keys.sh` (per-install signing keys, 0600, outside `paths.root`), `regenerate_data.prg` /
  `regenerate_users.prg` (seeders), `create_cdx.prg` / `create_dbf_ntx.prg` (schema/index), and the
  `probe_*.prg` tools (entropy, hash, password cost, file mode, index seek).
* **A config that can be committed** — `www/config.json` is ignored and replaced by
  `www/config.json.example`; the example's tracked `config.json` is exactly the mistake that let
  signing keys into history.
* **Test suites** — `webapp/test/`: `test_users_module.sh`, `test_customer_module.sh`,
  `verify-users-fixes.sh`, `bf_harness.sh`, plus `dbf_dump.py` for assertions against the RDD files.

**What changed in the files they share** (the 24 differing paths, in short):

* **Defect closure** — the users module's `D-01…D-16` and the customer module's `D-13` (login case
  handling and loose RDD comparisons, views 500-ing on a raw hash subscript, roles from numeric to
  hash, one search entry per grid column, CDX navigation `DbGoTo` → `DbSkip`).
* **CSRF** — every write form carries a token (`N-01`), which is what made the framework-side
  binding in §1 enforceable.
* **TLS is mandatory** — the app refuses to start without a certificate; `go_gcc.sh` sets
  `umask 077` so the session store and its files land `0700`/`0600` (the app cannot `chmod()` —
  `umask`/`chmod` do not link in Harbour).
* **Build wiring for this layout** — `app.hbp` and `go_gcc.sh` resolve the framework through
  `${hix}`, derived from the script's own location; no path in the build names a machine.

**Why keep both.** `examples/web/crud/` is upstream documentation and stays byte-compatible with the
framework's own docs; `webapp/` is the audited application. They are deliberately not merged — the
example is what a new HIX app starts from, `webapp/` is what it should end up as.

---

## 3. The store conversion

**What.** The MySQL DAL and the schema it was built from were removed, and the application was put
back on the RDDCDX RDD (DBF + CDX) the framework already ships. 100 tracked files deleted, 11 added.

| Removed | Count | Why |
|---|---|---|
| `www/models/tdalmysql.prg` | 1 | the pool DAL — nothing references the MySQL WDO any more |
| `sql/inventree.sql`, `sql/hix_users.sql`, `sql/fixtures/*.csv` | 26 | the MySQL schema and its seed corpus |
| `gen_mysql_db.sh`, `create_mysql_sql.*`, `seed_inventree.*`, `seed_users_mysql.*`, `probe_mysql.*`, `probe_dalmysql.*` | 12 | the host, the loader, the seeders, the harnesses |
| 12 controllers + their views (`part`, `stock`, `bom`, `build`, `company`, `supplier`, `order`, `orderline`, `testresult`, `settings`, `note`, `projectcode`) | 60 | the InvenTree-derived modules — the app is `customer` + `users` + login |
| `www/controllers/{healthdb,fkcheck,reconcile}.prg` | 3 | diagnostics that walked the MySQL FK graph |
| `test/test_fkcheck.sh`, `test/test_reconcile.sh` | 2 | suites over routes that were deleted |
| 17 MySQL-era plans, generators and result records | 17 | they described the DAL that was removed; `git log` is the record of them |

**Added:** `www/models/tusers.prg` (the credential store over `UDbf()`), `www/controllers/masters/users.prg`
and `www/models/modeluser.prg` rewritten onto the DBF, `www/routes/web.json` cut from 137 routes to 23,
`regenerate_users.*` restored, and `webapp/srs/03-implementation/P0-DBFCDX-STORE-RESULTS-2026-10-08.md`.

**Why the removal could be done at all.** At `HEAD`, `hbmk2 app.hbp` **failed to link** — `WDO_InitPoolMySqlEx`
and `WDO_EndPoolMySql` are unresolved because this Harbour build's `hix_server.hbx` does not export the
MySQL WDO. Nothing referenced it, so removing the pool is what made the app link again.

**The `SET EXACT` trap, and why it matters here.** `www/config.json` sets `"exact": false`, so Harbour
compares strings only to the length of the **right** operand. Three consequences, all found as failures
and all fixed:

* `"carlesx" != "carle"` is **FALSE** — so `ModelUser`'s guard never fired and a **prefix of a username
  authenticated** (D-16b). Fixed by closing the prefix with `Len()` before any comparison.
* `a < b` and `a > b` can **both** be false — so `_CompareVal`'s string comparator could not order rows
  and `?sort=roles` was a no-op (D-08a). Fixed by a byte-wise compare over a fixed alphabet.
* `Ord()` is not linked into the HIX server (`Unknown or unregistered function symbol (ORD)`), so the
  rank comes from a table built by concatenation, not `Ord()`.

**Verified.** Against the running binary, all three suites green:
`test_customer_module.sh` **50/50**, `test_users_module.sh` **60/60**,
`verify-users-fixes.sh` **125 PASS / 0 FAIL**. Full record in
[`webapp/srs/03-implementation/P0-DBFCDX-STORE-RESULTS-2026-10-08.md`](webapp/srs/03-implementation/P0-DBFCDX-STORE-RESULTS-2026-10-08.md),
including the five **test-suite** bugs found along the way and the login-limiter caveat (the suites
need `setup.ratelimit.login_max` widened; the shipped value is 5 per 60 s).

---

## Where everything lives

```
src/                     framework: the seven enhanced files above
examples/web/crud/       upstream example, unchanged
webapp/                  the application (controllers, models, views, routes, tests, tools)
webapp/srs/              the corpus: SRS + compliance, audit reports, test records, plans,
                         analyses, and UNIFIED.md (how this repo was assembled) — filed in
                         phase folders 00-meta … 07-maintenance (see 00-meta/SDLC-REORGANIZATION-PLAN.md)
compare-branches.sh      regenerates webapp/srs/06-release/COMPARISON-enhance-vs-main.md
```

---

## How to check any of it

```bash
HB_ROOT=/path/to/harbour bash go_lib_gcc.sh        # framework: hix_server.hbx + libhix_server.a
cd webapp && ./go_gcc.sh --port 9090               # app: build + run (TLS required)
./compare-branches.sh                              # enhance vs main, written to webapp/srs/
```

Reading order for the reasoning behind the app-side changes:
[`webapp/srs/05-audit/PENTEST-REPORT.md`](webapp/srs/05-audit/PENTEST-REPORT.md) (remediation record, §1…§10) →
[`webapp/srs/03-implementation/STATUS-USERS-MODULE.md`](webapp/srs/03-implementation/STATUS-USERS-MODULE.md) (D-01…D-16) →
[`webapp/srs/02-design/COMPARATIVE-ANALYSIS.md`](webapp/srs/02-design/COMPARATIVE-ANALYSIS.md) (example vs app) →
[`webapp/srs/00-meta/UNIFIED.md`](webapp/srs/00-meta/UNIFIED.md) (repository assembly).
