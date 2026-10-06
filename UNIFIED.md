# This repository: HIX framework + the webapp that runs on it

One local git repository holding **both** halves of the stack:

* the **HIX web-server framework** (Harbour / xBase++) at the root — upstream history, tags and
  signed commits untouched, exactly as in `~/Projects/hix`;
* the **audited CRUD application** under [`webapp/`](webapp/) — its own 26 commits, prefix-rewritten
  under `webapp/` and joined to the framework by a single unrelated-histories merge commit
  (`chore: unify the HIX framework with the webapp that runs on it`).

It was cut on 2026-10-06 from `~/Projects/hix` and `~/Projects/pi-agent/webapp`. The full analysis,
decision matrix and execution log are in `~/Projects/pi-agent/UNIFY-GIT-PLAN.md`.

**Why the framework is at the root and the app is a subdirectory:** the upstream MkDocs CI triggers
on root `site-docs/**` and `mkdocs.yml`, and `mkdocs.yml` / `examples/` all assume root paths. The
app was 127 tracked files / 26 commits (cheap to rewrite, 120 after untracking its build
artifacts); the framework is 634 files / 71 commits with 5 tags and signed upstream history
(expensive). Root = framework keeps upstream re-merging clean.

---

## Layout

```
.                        ← HIX framework (upstream layout, unchanged)
├── src/  tests/  examples/  site-docs/  changes/  resources/   (dll/ moved to resources/dll/)
├── hix_server.hbp / .hbc            framework build
├── go_lib_gcc.sh                    → hix_server.hbx + lib/gcc/libhix_server.a
├── compare-branches.sh              origin/enhance vs origin/main → webapp/srs/COMPARISON-enhance-vs-main.md
├── mkdocs.yml  .github/workflows/docs.yml      root paths still valid
├── webapp/                          the application (26 commits of its own history)
│   ├── app.hbp  go_gcc.sh  hix.json  gen_cert.sh  gen_keys.sh
│   ├── src/ www/ test/ data/ docs/ resources/
│   └── srs/                         requirements, compliance, audit reports, test records,
│                                    plans and analyses (28 files) — see srs/README.md
└── UNIFIED.md                       this file
```

`webapp/` descends from the framework's own `examples/web/crud/` (33 of its 64 files were
byte-identical to that example when this repo was cut). Both are kept on purpose: `examples/` is
upstream documentation, `webapp/` is the hardened, audited application.

| | |
|---|---|
| Tracked files | 825 (694 framework + 103 app + 28 `webapp/srs/`) |
| Commits reachable from `main` | 93 — of which **26** are the imported `webapp/` history (2026-10-02…10-06) |
| Tags | `v2.00` `v2.00.03` `v2.1` `v2.2` `ia-v0.2.1` — resolving to the same commits as in `~/Projects/hix` |
| Branch | `enhance`, tracking `origin/enhance` — `main` holds the imported upstream history and is no longer merged from |

---

## Build

The app links the framework's build output, so build the framework first. `go_lib_gcc.sh` is mode
644 upstream (run it with `bash`), and its default `HB_ROOT=$HOME/harbour-core` is not this
machine's Harbour:

```bash
cd ~/Projects/hix-unified
HB_ROOT=/home/jack/Projects/harbour bash go_lib_gcc.sh      # → hix_server.hbx, lib/gcc/libhix_server.a

cd webapp
./go_gcc.sh --port 9090                                     # build + run (it execs ./app)
```

`go_gcc.sh` resolves `${hix}` (used by `app.hbp` for `hix_server.hbx`, `hix_server.hbc`,
`incpaths`, `libpaths`) by trying, in order: **the parent directory** (this layout), then
`$HOME/Projects/hix`, then the older `../../..` / `../../../..` depths. `app.hbp` itself needs no
edit — everything goes through `${hix}`.

Framework unit suite (1979 assertions):

```bash
cd ~/Projects/hix-unified/tests/unit
HB_ROOT=/home/jack/Projects/harbour hix=$(cd ../.. && pwd) bash go_gcc.sh --cli
```

---

## Remotes — this repo is local-only

```
upstream-hix   /home/jack/Projects/hix   (fetch)
upstream-hix   DISABLED                  (push)
```

Every push URL is `DISABLED`; nothing has ever been pushed from here. `upstream-hix` is a
**fetch-only** remote pointing at the local `~/Projects/hix` checkout, which in turn has the real
GitHub URL configured (`https://github.com/lediz/hix.git`, push also `DISABLED`).

Sync upstream work when you want it:

```bash
git -C ~/Projects/hix fetch origin            # upstream main has moved: 8095424 → ab31bb4,
                                              # and there is an 'enhance' branch
git -C ~/Projects/hix-unified fetch upstream-hix
git -C ~/Projects/hix-unified merge upstream-hix/main      # framework paths only
```

Never enable a push URL here without reading the **Secrets** section below.

---

## History rules (learned the hard way)

1. **Never run `git filter-branch -- --all` in this repository.** The first attempt at the secrets
   purge rewrote 52 of 91 commits: upstream hix commits are **GPG-signed** (5 of them, e.g.
   `263585f`) and `filter-branch` drops the `gpgsig` header, which changes every SHA downstream and
   **moved the `v2.1` and `v2.2` tags**. That turns a future `git merge upstream-hix/main` into a
   duplicate-history mess — the exact property this layout was chosen to preserve.
2. **Rewrite the app history before the merge, in a scratch clone**, then merge. That is how the
   `webapp/` prefix rewrite and the secrets purge were finally done.
3. Verified invariant after every rewrite: the 5 tags resolve to the same commits as in
   `~/Projects/hix`, the 5 signed commits are reachable with their signatures, and every
   framework-side SHA is byte-identical to the source repo.

---

## Secrets

`webapp/` history used to contain, and no longer contains:

* `www/config.json` + `www/config.json.bak` — the five HIX signing keys, in the clear;
* `sessions/sess_*` — 56 signed session records;
* `.logs/access.log`, `.logs/errors.log`, `hb_out.log`.

They were removed from history on 2026-10-06 (61 objects) and the repo was `gc`'d; a sweep of
`git rev-list --all --objects` now returns 0 matches. Keys are per-installation today
(`gen_keys.sh` → `hix.keys.json`, 0600, outside `paths.root`, `HIX_KeySet()` wins over config), and
`certs/`, `hix.keys.json`, `www/config.json`, `sessions/` are all ignored.

**Backups are the only pre-rewrite record of those blobs:**
`~/backups/git/{hix,webapp}-2026-10-06.bundle` + `SHA256SUMS` (+ `.head` files). Treat them as
sensitive; delete them once you no longer need a pre-unification restore point.

---

## Test matrix — two server modes

`test_users_module.sh` and `test_customer_module.sh` hardcode `http://localhost:9090`, while
`verify-users-fixes.sh` asserts TLS (block C-009). They therefore need **different** server modes;
flip `hix.json → server.ssl` and restart between them (restore it afterwards).

| Suite | Server mode | Baseline = unified (verified equal) |
|---|---|---|
| `test/test_users_module.sh` | `ssl: false` — `API` is hardcoded to `http://localhost:9090`, no override | 55 / 60 |
| `test/test_customer_module.sh` | `ssl: false` — honours `TEST_API=`, but its `curl` has no `-k`, so it cannot reach the self-signed TLS server | 20 / 50 |
| `test/verify-users-fixes.sh` | `ssl: true` — asserts block C-009 (TLS negotiated, plain HTTP refused) | PASS=125 FAIL=0 |
| `test/bf_harness.sh` | `ssl: true`, `app.env = prod` — brute-force / timing probe, local app only | see `webapp/srs/BRUTE-FORCE-PENTEST-PLAN.md` |
| `tests/unit` (`--cli`) | n/a (no HTTP) | 1979 total / 1970 passed / 9 failed |

Those pass counts are pre-existing failures, not regressions — the *failure sets* are identical to
the pre-unification baseline. The customer suite's failures are mostly `/auth` rate-limit (429)
cascades; the suites share the per-IP login budget in `www/middlewares/config.json`.

The suites write into `data/*.dbf` and generate `u_check.c`; both are ignored or reverted, so
`git status` stays clean.

---

## Migration status

* `~/Projects/hix` and `~/Projects/pi-agent/webapp` still exist, clean, with their own history —
  they are the burn-in fallback, not the working copy.
* `~/Projects/pi-agent/hix` symlinks to `~/Projects/hix-unified` (shim for anything that used the
  old workspace path).
* The development server that used to run from `~/Projects/pi-agent/webapp` now runs from here:
  `cd webapp && ./go_gcc.sh --port 9090` (TLS on, `https://localhost:9090`).
* Burn in this repo for ~1 week, then retire the old ones **by renaming, not deleting**:
  `mv ~/Projects/hix ~/Projects/hix.retired`, same for `webapp`. Confirm the bundles restore first:
  `git clone ~/backups/git/webapp-2026-10-06.bundle /tmp/r && git -C /tmp/r log --oneline | wc -l` → 26.
* Rollback of the whole unification is `rm -rf ~/Projects/hix-unified` — the two originals are
  untouched apart from their own Phase 1 commits.
