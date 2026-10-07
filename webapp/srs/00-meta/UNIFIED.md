# This repository: HIX framework + the webapp that runs on it

> **This file lives in `webapp/srs/`** — it is the record of how the repository was assembled. The
> entry point for *what this branch changes* is [`ENHANCE.md`](../../ENHANCE.md) at the root.

One local git repository holding **both** halves of the stack:

* the **HIX web-server framework** (Harbour / xBase++) at the root — upstream history, tags and
  signed commits untouched, exactly as in the framework checkout it was cut from;
* the **audited CRUD application** under [`webapp/`](../) — its own 26 commits, prefix-rewritten
  under `webapp/` and joined to the framework by a single unrelated-histories merge commit
  (`chore: unify the HIX framework with the webapp that runs on it`).

It was cut on 2026-10-06 from a framework checkout and a separate application checkout. The full
analysis, decision matrix and execution log are in `UNIFY-GIT-PLAN.md`, which stayed outside the
repository.

> **Path convention used throughout this file.** `<repo>` = the root of this repository, wherever
> you cloned it. `$HB_ROOT` = your Harbour build directory. Nothing here hardcodes a machine, a
> username or a checkout name.

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
├── ENHANCE.md                       what this branch enhances and why (entry point)
├── compare-branches.sh              origin/enhance vs origin/main → webapp/srs/COMPARISON-enhance-vs-main.md
├── mkdocs.yml  .github/workflows/docs.yml      root paths still valid
├── webapp/                          the application (26 commits of its own history)
│   ├── app.hbp  go_gcc.sh  hix.json  gen_cert.sh  gen_keys.sh
│   ├── src/ www/ test/ data/ docs/ resources/
│   └── srs/                         requirements, compliance, audit reports, test records,
│                                    plans and analyses — including this file; see srs/README.md
```

`webapp/` descends from the framework's own `examples/web/crud/` (35 of that example's 64 tracked
files are still byte-identical in `webapp/`). Both are kept on purpose: `examples/` is upstream
documentation, `webapp/` is the hardened, audited application.

| | |
|---|---|
| Tracked files | 825 (694 framework + 103 app + 28 `webapp/srs/`) |
| Commits reachable from `main` | 93 — of which **26** are the imported `webapp/` history (2026-10-02…10-06) |
| Tags | `v2.00` `v2.00.03` `v2.1` `v2.2` `ia-v0.2.1` — resolving to the same commits as in the source framework repo |
| Branch | `enhance`, tracking `origin/enhance` — `main` holds the imported upstream history and is no longer merged from |

---

## Build

The app links the framework's build output, so build the framework first. `go_lib_gcc.sh` is mode
644 upstream (run it with `bash`), and its default `HB_ROOT=$HOME/harbour-core` is not this
machine's Harbour:

```bash
cd <repo>
HB_ROOT=/path/to/harbour bash go_lib_gcc.sh       # → hix_server.hbx, lib/gcc/libhix_server.a

cd webapp
./go_gcc.sh --port 9090                           # build + run (it execs ./app)
```

`go_gcc.sh` resolves `${hix}` (used by `app.hbp` for `hix_server.hbx`, `hix_server.hbc`,
`incpaths`, `libpaths`) from its own location: **the parent directory** — this layout, where
`webapp/` sits directly inside the framework — then the `../../..` depth the upstream
`examples/web/crud/` layout needs. A pre-set `hix=` wins over both. If `HB_ROOT` is wrong or unset
it derives the Harbour build from `PATH` before falling back to `$HOME/Projects/harbour` and
`$HOME/harbour`. `app.hbp` itself needs no edit — everything goes through `${hix}`.

Framework unit suite (1979 assertions):

```bash
cd <repo>/tests/unit
HB_ROOT=/path/to/harbour hix=$(cd ../.. && pwd) bash go_gcc.sh --cli
```

---

## Remotes

```
origin  https://github.com/lediz/hix.git   (fetch and push)
```

`enhance` is the working branch and tracks `origin/enhance`; `main` holds the imported upstream
history. **`origin/enhance` is the upstream** — do not merge from the old framework checkout; after
the identity rewrite it still holds pre-rewrite commits that are not ancestors of `enhance`, and
merging from it would reintroduce them. The `upstream-hix` remote that used to point at a local
framework checkout was removed for exactly that reason.

Never enable a push URL without reading the **Secrets** section below.

---

## History rules (learned the hard way)

1. **Never run `git filter-branch -- --all` in this repository.** The first attempt at the secrets
   purge rewrote 52 of 91 commits: upstream hix commits are **GPG-signed** (5 of them, e.g.
   `263585f`) and `filter-branch` drops the `gpgsig` header, which changes every SHA downstream and
   **moved the `v2.1` and `v2.2` tags**. That turns a future `git merge upstream-hix/main` into a
   duplicate-history mess — the exact property this layout was chosen to preserve.
2. **Rewrite the app history before the merge, in a scratch clone**, then merge. That is how the
   `webapp/` prefix rewrite and the secrets purge were finally done.
3. Verified invariant after every rewrite: the 5 tags resolve to the same commits as in the source
   framework repo, the 5 signed commits are reachable with their signatures, and every
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
`<your backup location>/git/{hix,webapp}-2026-10-06.bundle` + `SHA256SUMS` (+ `.head` files). Treat
them as sensitive; delete them once you no longer need a pre-unification restore point.

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

* The two checkouts this repo was cut from (framework, and the application that lived beside it)
  still exist, clean, with their own history — they are the burn-in fallback, not the working copy.
* A symlink kept at the old workspace path pointed here, for anything that still used it; it is no
  longer needed now that the repo has a remote.
* The development server that used to run from the application checkout runs from here:
  `cd webapp && ./go_gcc.sh --port 9090` (TLS on, `https://localhost:9090`).
* Burn in this repo for ~1 week, then retire the old checkouts **by renaming, not deleting**
  (`mv <old checkout> <old checkout>.retired`). Confirm the bundles restore first:
  `git clone <backup>/webapp-2026-10-06.bundle /tmp/r && git -C /tmp/r log --oneline | wc -l` → 26.
* Rollback of the whole unification is to delete this working copy and go back to the two originals
  — they are untouched apart from their own Phase 1 commits.
