# ENHANCE — the enhancements on this branch

`enhance` is the working branch of this repository. It carries two things at once: the **HIX
framework** (Harbour / xBase++ web server) at the root, and **`webapp/`**, the audited CRUD
application that runs on it. Everything `enhance` adds to the imported upstream history falls into
**two areas**:

1. **the HIX platform itself** — framework changes under [`src/`](src/);
2. **the Example CRUD → `webapp/`** — what turns upstream's
   [`examples/web/crud/`](examples/web/crud/) example into a hardened application;
3. **what the application runs on** — the store conversion (MySQL DAL removed,
   back on the RDDCDX RDD) and the concurrency work that followed it.

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

## 3. The store conversion and the concurrency work

**What.** The MySQL DAL and the schema it was built from were removed; the application was put
back on the RDDCDX RDD (DBF + CDX) the framework already ships. The concurrency tests then ran
against the result.

**Why the removal was possible at all.** At `HEAD`, `hbmk2 app.hbp` **failed to link** — `WDO_InitPoolMySqlEx`
and `WDO_EndPoolMySql` are unresolved because this Harbour build's `hix_server.hbx` does not export
the MySQL WDO. Nothing referenced it, so removing the pool is what made the app link again.

| Removed | Count |
|---|---|
| `www/models/tdalmysql.prg` | 1 |
| `sql/inventree.sql`, `sql/hix_users.sql`, `sql/fixtures/*.csv` | 26 |
| the MySQL host, loader, seeders, harnesses | 12 |
| 12 InvenTree-derived controllers + their views | 60 |
| the 3 MySQL diagnostics, the 2 suites over deleted routes | 5 |
| the 17 MySQL-era plans, generators and result records | 17 |

**Added:** `www/models/tusers.prg` (the credential store over `UDbf()`), `users.prg` and
`modeluser.prg` rewritten onto the DBF, routes cut 137 → 23, `regenerate_users.*` restored.

### The `SET EXACT` trap — and why it is the whole story here

`www/config.json` sets `"exact": false`, so Harbour compares strings only to the length of the
**right** operand. Three consequences, all found as failures and all fixed:

* `"carlesx" != "carle"` is **FALSE** — so `ModelUser`'s guard never fired and a **prefix of a
  username authenticated**. Closed by comparing `Len()` before the strings.
* `a < b` and `a > b` can **both** be false — so the sort comparator could not order rows and
  `?sort=roles` was a no-op. Fixed byte-wise.
* `Ord()` is **not linked** into the HIX server (`Unknown or unregistered function symbol (ORD)`),
  so the rank comes from a table, not `Ord()`.

### Concurrency: measured, not assumed

The binding ceiling is **`pool_hix.workers = 4`**, not `pool_http.workers = 64` — the app runs in
HIXSTYLE mode, so handlers come off the 4-worker pool.

| Axis | Measured |
|---|---|
| Store read/write | **all PASS** — 8 concurrent reads → 1 distinct md5; 6 writes to distinct records all land; 8 writes to the **same** record → exactly one winner, record intact; 12 reads during 4 writes → every read complete; delete during 8 scans → 21 rows each; 10 simultaneous logins → 10 session files, all mode 600 |
| Connections | 12 handlers **queue in waves** (0.013–0.058 s), none lost; 300 simultaneous → 300/300 on repeat; keep-alive reused; pool monitor fires at 82–84 % |
| Hypotheses | the flash is **session-scoped, not a cross-session channel** (C-1 FALSE); the ceiling of 4 is **CONFIRMED**; the lock-failure path (C-5) was **NOT REACHED** — 8-way contention serialised rather than failed |

**Not proven:** the lock-failure path, per-IP isolation, queue overflow past 256, idle-connection
behaviour, and the timeout interaction. Contention peaked at 8–12 writers, below the 3 s `Rlock`
budget.

**Limiter discipline:** `setup.ratelimit.login_max` / `ip_per_min` were widened **for the run only**
and restored to the shipped values (5 / 300) afterwards. `hix.json` was never touched. The users
suite cannot pass at the shipped limiter (57/60 vs 60/60 widened) — a real mismatch between app
config and test suite, not an app defect.

### Still open

The **aesthetics plan is unexecuted** — no CSS or view has been touched. Its measured surface and
12 ranked defects are recorded in `webapp/srs/02-design/AESTHETICS-PLAN.md`; the markup-coupling
risk (the suites grep rendered markup, so a restyle breaks 110 passing assertions) is the thing
that has to be handled before any restyle.

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

The two records that describe this branch's own work:

| File | What it is |
|---|---|
| `webapp/srs/03-implementation/P0-DBFCDX-STORE-RESULTS-2026-10-08.md` | the store conversion — what was deleted, what replaced it, the defects found and fixed, the five **test-suite** bugs fixed along the way |
| `webapp/srs/03-implementation/P7-CONCURRENCY-RESULTS-2026-10-08.md` | the concurrency run — what was measured, and explicitly what was not exercised |

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
