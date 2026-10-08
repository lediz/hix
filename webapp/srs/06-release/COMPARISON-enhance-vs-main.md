# Comparative analysis: `origin/enhance` vs `origin/main`

Generated: 2026-10-08T18:11:59+08:00 · by `compare-branches.sh`

| Ref | SHA | Commits | Files | Tree size |
|---|---|---|---|---|
| `origin/enhance` | `c115250` | 144 | 737 | 38393132 B |
| `origin/main` | `ab31bb4` | 65 | 692 | 38177445 B |

## 1. Topology

| Metric | Value |
|---|---|
| Relationship | **fast-forward: origin/enhance is ahead of origin/main by 79** |
| Merge base | `ab31bb4 — 2.3.10 Move /dll to /resources/dll (2026-10-05)` |
| Unique to `origin/enhance` | 79 |
| Unique to `origin/main` | 0 |
| `origin/main` ⊆ `origin/enhance` | yes |
| `origin/enhance` ⊆ `origin/main` | no |

## 2. Content delta (`origin/main` → `origin/enhance`)

| Metric | Value |
|---|---|
| Files added / modified / deleted / renamed | 131 / 10 / 87 / 3 |
| Lines inserted / deleted | +20242 / -22597 |
| Binary files changed | 7 |
| Shortstat | 231 files changed, 20242 insertions(+), 22597 deletions(-) |
| Excluded from the delta | webapp/srs/06-release/COMPARISON-enhance-vs-main.md |

### Top-level entries only in one side

- only in `origin/enhance`: compare-branches.sh ENHANCE.md 
- only in `origin/main`: tests 

### Largest content changes

```
900	0	webapp/srs/01-requirements/SRS-Harbour-HIX.md
887	0	webapp/srs/01-requirements/SRS-Harbour.md
883	0	webapp/www/controllers/masters/users.prg
707	0	webapp/srs/04-verification/TEST-REPORT-2026-10-06.md
638	0	webapp/www/controllers/masters/customer.prg
589	0	webapp/srs/05-audit/PNT-Harbour-HIX--MOE-3.6.md
570	0	webapp/srs/05-audit/PNT-Harbour-HIX--MOE-3.9.md
510	0	webapp/srs/05-audit/PNT-Harbour-HIX--MOE-3.8.md
469	0	webapp/srs/02-design/BRUTE-FORCE-PENTEST-PLAN.md
445	0	webapp/www/test/index.html
439	0	webapp/src/app.prg
433	0	webapp/srs/05-audit/PNT-Harbour-HIX.md
427	0	webapp/srs/02-design/VIGOLIUM-SCAN-PLAN.md
412	0	webapp/srs/05-audit/PENTEST-REPORT.md
400	0	webapp/srs/02-design/COMPARATIVE-ANALYSIS.md
```

### Changes by top-level directory

```
132 webapp/
87 tests/
7 src/
5 (root)
```

### Renames

```
R088	tests/unit/hix.json	webapp/hix.json
R100	tests/unit/www/img/hix.ico	webapp/resources/images/hix.ico
R100	tests/unit/www/img/logo240.png	webapp/resources/images/logo240.png
```

## 3. Unique commits

### Only in `origin/enhance` (79)

| Date | Author | Subject |
|---|---|---|
| 2026-10-08 | lediz | webapp: drop the MySQL DAL and the InvenTree module set, back on RDDCDX |
| 2026-10-08 | lediz | webapp: the module grids carry the audited page chrome |
| 2026-10-08 | lediz | webapp: the left-pane menu lists every module, and every module page carries it |
| 2026-10-08 | lediz | webapp: the remaining CRUD modules on the DAL, and the verification that reaches M3-M5 |
| 2026-10-08 | lediz | webapp: the stock module on the DAL, which is where the FK policy becomes observable |
| 2026-10-07 | lediz | srs: the P7.2 record — the FK surface, the alias bug, and the owner answers |
| 2026-10-07 | lediz | webapp: the orphan check aliases both sides of EXISTS, and the corpus is FK-closed |
| 2026-10-07 | lediz | webapp: the FK policies are declared, undecided is visible, and the orphans have a route |
| 2026-10-07 | lediz | srs: the FK-policy decisions, measured on the shipped schema, with D4 taken |
| 2026-10-07 | lediz | webapp: the cascade is one transaction, and the refusal that proves it is the DAL's own |
| 2026-10-07 | lediz | webapp: users and the login path move onto the MySQL DAL, customer stays the RDDCDX POC |
| 2026-10-07 | lediz | webapp: the part module on the MySQL DAL - reads proven, writes half-proven |
| 2026-10-07 | lediz | webapp: the delete policy moves to the schema edge, and the DAL gains a preview and a borrowed slot |
| 2026-10-07 | lediz | srs: the corpus under the lifecycle folders, and the documents that were never tracked |
| 2026-10-07 | lediz | webapp: the MySQL DAL - the SRS's verbs over the pool, with the version column it needs |
| 2026-10-07 | lediz | webapp: the MySQL/MariaDB pool the app starts with, and the route that reads it |
| 2026-10-07 | lediz | webapp: the shipped MySQL/MariaDB schema, and the tools that load and seed it |
| 2026-10-07 | lediz | tests: untrack webapp/test/ the same way tests/ was untracked |
| 2026-10-07 | lediz | docs: what must be fixed before shipping, ranked webapp/srs/PRODUCTION-BLOCKERS-2026-10-07.md files the same findings the sliced suite reports, ranked by what blocks shipping instead of by cluster: B1 two of the three functional suites verify nothing (test_users_module.sh aborts with rc=2 and runs 0 of 46; test_customer_module.sh throws away the session it authenticated, 28 of 50 fail), B2 the session store's mode is a launcher obligation rather than a guarantee - Harbour links no chmod, so 0666 & ~umask of whoever exec'd ./app decides it, and only go_gcc.sh sets the mask. B3 the A0116 contract is the only thing still counted; B4 the latent mutex initialization is not a production runtime failure today, verified along webapp/src/app.prg:105 -> src/hix_server.prg:268,485. |
| 2026-10-07 | lediz | tests: local tooling, not part of what ships 112 paths under tests/ are untracked with `git rm -r --cached tests/` and the root .gitignore gains `tests/`: the sliced suite (run.sh, slice.sh, index.sh, clean.sh, lib/, slices/) and the unit-test harness (tests/unit: app.hbp, the build scripts, 67 .prg test sources, its www/ views and assets). Nothing was deleted from disk - the suite still runs here and still reports - but a fresh clone has no tests until they are added back. |
| 2026-10-06 | lediz | docs: the numbers as recorded on the tree they were recorded on |
| 2026-10-06 | lediz | docs: what the sliced suite found, cluster by cluster |
| 2026-10-06 | lediz | tests: one entry point, many slices, bounded output |
| 2026-10-06 | lediz | tools: refresh the enhance-vs-main report (UNIFIED.md moved, ENHANCE.md added) |
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

### Only in `origin/main` (0)

| Date | Author | Subject |
|---|---|---|
_(none)_

## 4. Attribution

### Authors — `origin/enhance`
```
79 lediz <14312216+lediz@users.noreply.github.com>
60 Carles Aubia <carles9000@gmail.com>
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
79 lediz <14312216+lediz@users.noreply.github.com>
60 Carles Aubia <carles9000@gmail.com>
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

- fast-forward: origin/enhance is ahead of origin/main by 79
- `origin/enhance` can be merged into `origin/main` as a **fast-forward**.
- Shared history below the merge base is common to both; commits there keep identical SHAs unless history is rewritten.
- The content delta excludes webapp/srs/06-release/COMPARISON-enhance-vs-main.md. The unique-commit count still includes the commit that carries this report — that one is unavoidable while the report is tracked.

## 7. Machine-readable summary

```json
{
  "left": "origin/enhance",
  "left_sha": "c115250e65c4e96ca5ba21d1c9175d502bc5348a",
  "right": "origin/main",
  "right_sha": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "merge_base": "ab31bb4d407204245adb2af62f1232a8b67e5b8a",
  "left_only": 79,
  "right_only": 0,
  "fast_forward_possible": true,
  "diverged": false,
  "excluded": ["webapp/srs/06-release/COMPARISON-enhance-vs-main.md"],
  "files": {"added": 131, "modified": 10, "deleted": 87, "renamed": 3, "binary": 7},
  "lines": {"insertions": 20242, "deletions": 22597}
}
```
