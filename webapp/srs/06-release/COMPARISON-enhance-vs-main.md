# Comparative analysis: `origin/enhance` vs `origin/main`

Generated: 2026-10-06T15:04:31+08:00 · by `compare-branches.sh`

| Ref | SHA | Commits | Files | Tree size |
|---|---|---|---|---|
| `origin/enhance` | `4e15981` | 120 | 826 | 39217148 B |
| `origin/main` | `ab31bb4` | 65 | 692 | 38177445 B |

## 1. Topology

| Metric | Value |
|---|---|
| Relationship | **fast-forward: origin/enhance is ahead of origin/main by 55** |
| Merge base | `ab31bb4 — 2.3.10 Move /dll to /resources/dll (2026-10-05)` |
| Unique to `origin/enhance` | 55 |
| Unique to `origin/main` | 0 |
| `origin/main` ⊆ `origin/enhance` | yes |
| `origin/enhance` ⊆ `origin/main` | no |

## 2. Content delta (`origin/main` → `origin/enhance`)

| Metric | Value |
|---|---|
| Files added / modified / deleted / renamed | 133 / 10 / 0 / 0 |
| Lines inserted / deleted | +19583 / -34 |
| Binary files changed | 7 |
| Shortstat | 143 files changed, 19583 insertions(+), 34 deletions(-) |
| Excluded from the delta | webapp/srs/COMPARISON-enhance-vs-main.md |

### Top-level entries only in one side

- only in `origin/enhance`: compare-branches.sh ENHANCE.md 
- only in `origin/main`: —

### Largest content changes

```
900	0	webapp/srs/SRS-Harbour-HIX.md
887	0	webapp/srs/SRS-Harbour.md
751	0	webapp/test/test_customer_module.prg
735	0	webapp/www/controllers/masters/users.prg
646	0	webapp/test/bf_harness.sh
638	0	webapp/www/controllers/masters/customer.prg
608	0	webapp/test/verify-users-fixes.sh
589	0	webapp/srs/PNT-Harbour-HIX.md.MOE.3.6
570	0	webapp/srs/PNT-Harbour-HIX.md.MOE.3.9
510	0	webapp/srs/PNT-Harbour-HIX.md.MOE.3.8
469	0	webapp/srs/BRUTE-FORCE-PENTEST-PLAN.md
445	0	webapp/www/test/index.html
445	0	webapp/test/test_customer_module.sh
434	0	webapp/src/app.prg
433	0	webapp/srs/PNT-Harbour-HIX.md
```

### Changes by top-level directory

```
131 webapp/
7 src/
5 (root)
```

### Renames

```
(none)
```

## 3. Unique commits

### Only in `origin/enhance` (55)

| Date | Author | Subject |
|---|---|---|
| 2026-10-06 | lediz | docs: move UNIFIED.md into webapp/srs/, replace it at root with ENHANCE.md |
| 2026-10-06 | lediz | tools: refresh the enhance-vs-main report |
| 2026-10-06 | lediz | paths: nothing in the repo names this machine |
| 2026-10-06 | lediz | docs: gather plans, reports and analyses under webapp/srs/ |
| 2026-10-06 | lediz | tools: refresh the enhance-vs-main report (srs/ paths moved) |
| 2026-10-06 | lediz | docs: move srs/ under webapp/ |
| 2026-10-06 | lediz | webapp: stop tracking generated C from the .prg tools |
| 2026-10-06 | lediz | webapp: retire migrate_dbf, give the adhoc tools .hbp build files |
| 2026-10-06 | lediz | webapp: no tool hardcodes another checkout's data path |
| 2026-10-06 | lediz | webapp: seeders resolve their data dir instead of a hardcoded stale path |
| 2026-10-06 | lediz | chore: untrack webapp/data — the DBF/CDX files are runtime state |
| 2026-10-06 | lediz | data: customers.cdx header byte 0x0b 0x66 -> 0x68 |
| 2026-10-06 | lediz | compare-branches.sh: exclude the report's own output from the delta |
| 2026-10-06 | lediz | tools: add compare-branches.sh; track the enhance-vs-main report |
| 2026-10-06 | lediz | docs: record removing the upstream-hix remote; upstream is origin/enhance |
| 2026-10-06 | lediz | docs: track the git-remote migration and auth plans |
| 2026-10-06 | lediz | chore: keep the local git-migration planning notes untracked |
| 2026-10-06 | lediz | docs: reflect upstream's dll/ move to resources/dll/ in the layout |
| 2026-10-06 | lediz | Merge remote-tracking branch 'origin/enhance' |
| 2026-10-06 | lediz | docs: correct the counts and the test-mode caveats |
| 2026-10-06 | lediz | docs: document the unified repository |
| 2026-10-06 | lediz | chore: ignore the unit-test harness output (trace.log, traces/, tests/unit/app, nul) |
| 2026-10-06 | lediz | build: resolve ${hix} from the parent directory in the unified layout |
| 2026-10-06 | lediz | chore: line-ending and binary attributes for the unified tree |
| 2026-10-06 | lediz | docs: import srs/ - the requirements/compliance corpus the app cites (was un-versioned) |
| 2026-10-06 | lediz | chore: unify the HIX framework with the webapp that runs on it |
| 2026-10-06 | lediz | chore: untrack build artifacts and logs; add the brute-force harness + comparative analysis |
| 2026-10-06 | lediz | chore: ignore lib/, *.hbx, generated hix_helpers.c, *.bak |
| 2026-10-06 | lediz | security: framework half of the webapp pentest remediation (PENTEST-REPORT §1,§5) |
| 2026-10-06 | lediz | docs: BF-01 surface findings - docroot-root files bypass the hixstyle ACL |
| 2026-10-05 | lediz | chore: stop tracking session files; users.dbf re-seeded |
| 2026-10-05 | lediz | docs: penetration test and secure code review report |
| 2026-10-05 | lediz | test: HARDEN block for the pentest remediations; every suite call time-bounded |
| 2026-10-05 | lediz | app: one search entry per grid column, in both modules; D-13 in customer |
| 2026-10-05 | lediz | security: private session store - the launcher sets umask 077 (PENTEST-REPORT.md §7) |
| 2026-10-05 | lediz | security: pentest remediation - keys out of the docroot, framework surface closed |
| 2026-10-05 | lediz | chore: delete www/config.json.bak - it still carried the old signing keys |
| 2026-10-05 | lediz | app: refuse to start without the TLS certificate; make go_gcc.sh usable here |
| 2026-10-05 | lediz | docs: add the remediation addendum to the users-module status report |
| 2026-10-05 | lediz | test: suite runs over TLS and verifies the keys/salt fixes |
| 2026-10-05 | lediz | security: enable TLS, generate signing keys per install, CSPRNG password salts |
| 2026-10-05 | lediz | chore: stop tracking build artifacts, widen .gitignore, add the status report |
| 2026-10-05 | lediz | test: users suite is now idempotent, CSRF-aware and rate-limit aware |
| 2026-10-05 | lediz | views: N-01 - every write form now carries a CSRF token |
| 2026-10-05 | lediz | users module: close D-05..D-14, tune login limit and password work factor |
| 2026-10-04 | lediz | users module: fix D-16 — login case handling and loose RDD comparisons |
| 2026-10-04 | lediz | users module: fix D-15 — views 500'd on raw hash subscript |
| 2026-10-04 | lediz | users module: close defects D-01..D-04 |
| 2026-10-03 | lediz | fix: roles from numeric to hash — users.dbf ROLES C(255), ModelUser _ParseRoles, ALLTRIM, test creds admin/1234 |
| 2026-10-03 | lediz | auth: migrate to users.dbf with RDDCDX index |
| 2026-10-02 | lediz | Fix: single search input for First name, per-field AND logic, session ttl 60→3600, cPath fix, whitelist customer dir, edit view quote fix, autocomplete prevention |
| 2026-10-02 | lediz | Fix UParam to read query params (o:hQueryParams fallback); pass cPath to HIX_MwSessionSetup from paths.session config |
| 2026-10-02 | lediz | Fixes: per-field grid search, session persistence (ttl + path), whitelist, edit view quote fix |
| 2026-10-02 | lediz | Fix customer grid pagination: DbGoTo→DbSkip for CDX index navigation, add .gitignore |
| 2026-10-02 | lediz | Migrate customer DBF: combine street+city+state into address, add country, remove hiredate/married/dummy |

### Only in `origin/main` (0)

| Date | Author | Subject |
|---|---|---|
_(none)_

## 4. Attribution

### Authors — `origin/enhance`
```
60 Carles Aubia <carles9000@gmail.com>
55 lediz <14312216+lediz@users.noreply.github.com>
4 Charly <carles9000@gmail.com>
1 Giuseppe Bogetti <orangesocks@users.noreply.github.com>
```

### Authors — `origin/main`
```
60 Carles Aubia <carles9000@gmail.com>
4 Charly <carles9000@gmail.com>
1 Giuseppe Bogetti <orangesocks@users.noreply.github.com>
```

### Committers — `origin/enhance`
```
60 Carles Aubia <carles9000@gmail.com>
55 lediz <14312216+lediz@users.noreply.github.com>
5 GitHub <noreply@github.com>
```

### Email domains unique to one side

```
(none — both sides share the same author email domains)
```

### Signed commits

- `origin/enhance`: 5 signed
- `origin/main`: 5 signed

## 5. Tags

```
ia-v0.2.1 -> fcdc28b
v2.00 -> c9fc5a5
v2.00.03 -> 95c6fea
v2.1 -> 2553536
v2.2 -> d8d66d9
```

## 6. Findings

- fast-forward: origin/enhance is ahead of origin/main by 55
- `origin/enhance` can be merged into `origin/main` as a **fast-forward**.
- Shared history below the merge base is common to both; commits there keep identical SHAs unless history is rewritten.
- The content delta excludes webapp/srs/COMPARISON-enhance-vs-main.md. The unique-commit count still includes the commit that carries this report — that one is unavoidable while the report is tracked.

## 7. Machine-readable summary

```json
{
  "left": "origin/enhance",
  "left_sha": "4e15981644565fb1938678184ff64acf0fcd86e8",
  "right": "origin/main",
  "right_sha": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "merge_base": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "left_only": 55,
  "right_only": 0,
  "fast_forward_possible": true,
  "diverged": false,
  "excluded": ["webapp/srs/COMPARISON-enhance-vs-main.md"],
  "files": {"added": 133, "modified": 10, "deleted": 0, "renamed": 0, "binary": 7},
  "lines": {"insertions": 19583, "deletions": 34}
}
```
