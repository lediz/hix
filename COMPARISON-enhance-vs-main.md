# Comparative analysis: `origin/enhance` vs `origin/main`

Generated: 2026-10-06T13:59:48+08:00 · by `compare-branches.sh`

| Ref | SHA | Commits | Files | Tree size |
|---|---|---|---|---|
| `origin/enhance` | `e1cb9ca` | 106 | 830 | 39263822 B |
| `origin/main` | `ab31bb4` | 65 | 692 | 38177445 B |

## 1. Topology

| Metric | Value |
|---|---|
| Relationship | **fast-forward: origin/enhance is ahead of origin/main by 41** |
| Merge base | `ab31bb4 — 2.3.10 Move /dll to /resources/dll (2026-10-05)` |
| Unique to `origin/enhance` | 41 |
| Unique to `origin/main` | 0 |
| `origin/main` ⊆ `origin/enhance` | yes |
| `origin/enhance` ⊆ `origin/main` | no |

## 2. Content delta (`origin/main` → `origin/enhance`)

| Metric | Value |
|---|---|
| Files added / modified / deleted / renamed | 138 / 10 / 0 / 0 |
| Lines inserted / deleted | +19848 / -34 |
| Binary files changed | 13 |
| Shortstat | 148 files changed, 19848 insertions(+), 34 deletions(-) |

### Top-level entries only in one side

- only in `origin/enhance`: GIT_AUTH_PLAN.md GIT_REMOTE_MIGRATION_PLAN.md srs UNIFIED.md webapp 
- only in `origin/main`: —

### Largest content changes

```
900	0	srs/SRS-Harbour-HIX.md
887	0	srs/SRS-Harbour.md
751	0	webapp/test/test_customer_module.prg
735	0	webapp/www/controllers/masters/users.prg
646	0	webapp/test/bf_harness.sh
638	0	webapp/www/controllers/masters/customer.prg
608	0	webapp/test/verify-users-fixes.sh
589	0	srs/PNT-Harbour-HIX.md.MOE.3.6
570	0	srs/PNT-Harbour-HIX.md.MOE.3.9
510	0	srs/PNT-Harbour-HIX.md.MOE.3.8
469	0	webapp/BRUTE-FORCE-PENTEST-PLAN.md
445	0	webapp/www/test/index.html
445	0	webapp/test/test_customer_module.sh
434	0	webapp/src/app.prg
433	0	srs/PNT-Harbour-HIX.md
```

### Changes by top-level directory

```
120 webapp/
15 srs/
7 src/
6 (root)
```

### Renames

```
(none)
```

## 3. Unique commits

### Only in `origin/enhance` (41)

| Date | Author | Subject |
|---|---|---|
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
41 lediz <14312216+lediz@users.noreply.github.com>
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
41 lediz <14312216+lediz@users.noreply.github.com>
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

- fast-forward: origin/enhance is ahead of origin/main by 41
- `origin/enhance` can be merged into `origin/main` as a **fast-forward**.
- Shared history below the merge base is common to both; commits there keep identical SHAs unless history is rewritten.

## 7. Machine-readable summary

```json
{
  "left": "origin/enhance",
  "left_sha": "e1cb9ca432d7366610513f47e4ad2a07faba9336",
  "right": "origin/main",
  "right_sha": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "merge_base": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "left_only": 41,
  "right_only": 0,
  "fast_forward_possible": true,
  "diverged": false,
  "files": {"added": 138, "modified": 10, "deleted": 0, "renamed": 0, "binary": 13},
  "lines": {"insertions": 19848, "deletions": 34}
}
```
