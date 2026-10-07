# SDLC re-organization plan for `webapp/srs/` — report only, nothing moved

Scope: the 35 documents in `webapp/srs/` (36 counting this plan), re-filed so the folder reads as a
**software development lifecycle** — requirements → design → implementation → verification → audit →
integration/release → maintenance — with renames only where a current name is actively wrong.

Status: **plan only.** No file has been moved, renamed, or edited. This document is the report;
the moves it proposes are executed only on request.

Date: 2026-10-07.

---

## 1. Ground rules (binding)

| Rule | Why |
|---|---|
| **Move without renaming, by default.** A bare-name citation still resolves after a move | The corpus is found by bare name: `webapp/srs/README.md` says "Code comments cite these by bare name (`PENTEST-REPORT.md §1`, `D-14`, `BF-01`) … grep for the name rather than a path". `grep -rl PENTEST-REPORT.md` still hits after the file moves into a phase folder. A rename breaks all 21 citations in 17 code files; a move breaks none |
| **Never rewrite the prose of a historical report to chase a rename** | `TEST-REPORT-2026-10-06.md` and `PRODUCTION-BLOCKERS-2026-10-07.md` are records of runs that happened; editing their citations falsifies the record. Former names belong in the index (§4), not in the body |
| Code comments are live, not historical | If a file cited from code must be renamed, the code comments are updated in the same change — and that is 17 files for `PENTEST-REPORT.md`. §5 says: do not do it |
| Four of the 35 files are **not in git** | `VIGOLIUM-SCAN-PLAN.md`, `LETS-ENCRYPT-PLAN.md`, `PASSWORD-COMPLIANCE-PLAN.md`, `FIX-RECOMMENDATIONS-DEV-COMPLIANT.md`. A fresh clone has 31, not 35. Re-organizing them is a local action; the gap must be reported, not hidden |
| `git mv` for the 31 tracked, plain `mv` for the 4 untracked | `git mv` preserves blob identity so `git log --follow` still reads the history; `mv` on an untracked file is not a git operation at all |
| One move per phase-folder, verified before the next | A half-moved folder leaves dangling index rows in `README.md` and a corpus that half-describes itself |
| Do not rename to a name a `.gitignore` rule catches | `webapp/.gitignore` and the root `.gitignore` ignore `*.bak`, `trace.log`, `traces/`, `tests/`, `webapp/test/`, `lib/`, `tmp/`, `*.hbx`. A phase folder literally named `tests/` would be **untracked**, silently. §2 T-TRAP |
| Case-only renames are unsafe | The repository is worked on Windows too (`go_msvc64.bat`, `go_mingw64.bat`, `app.rc`, `app.res` in `webapp/app.hbp`). A case-only rename (`pentest.md` → `Pentest.md`) collides on a case-insensitive checkout |

---

## 2. Constraint check (`webapp/srs/DEV-compliance.md`)

| Test | Result for this re-organization |
|---|---|
| T1 HIX style only | n/a — no application code is touched |
| T2 No SQL | n/a |
| T3 No 3rd Party WEB UI | n/a |
| T4 Only HIX + Harbour | ✅ nothing new is introduced; the moves use `git`/`mv` only |
| T5 Adhoc tools in project folder | ✅ every destination is under `webapp/srs/` |
| T6 No change outside project folder | ✅ the whole operation is inside `webapp/srs/` |
| T7 Build with `hbmk2 app.hbp` only | ✅ unaffected — `webapp/app.hbp:18` lists `src/app.prg`; no `.md` is in the build |
| T8 Port 9090 | ✅ unaffected |
| **T-TRAP** | ⚠️ not in DEV-compliance, but binding: the folder for the verification phase must **not** be named `tests/`, `tmp/`, or `lib/`, and no renamed file may end in `.bak` or `.log` — those become invisible to git |

So the re-organization is fully compliant. The only risk is the gitignore trap.

---

## 3. Current shape (measured, not remembered)

```
35 files in webapp/srs/ (before this plan is added)
  31 tracked in git          git ls-files webapp/srs | wc -l
   4 untracked               VIGOLIUM-SCAN-PLAN.md, LETS-ENCRYPT-PLAN.md,
                             PASSWORD-COMPLIANCE-PLAN.md, FIX-RECOMMENDATIONS-DEV-COMPLIANT.md
   5 whose extension is not .md
                             PNT-Harbour-HIX.md.DENSE.Q4 / .DENSE.Q8 / .MOE.3.6 / .MOE.3.8 / .MOE.3.9
```

Naming families present today (the inconsistency the re-organization must resolve, not hide):

| Family | Members | Problem |
|---|---|---|
| `SRS-*` | 3 | consistent, but says nothing about phase |
| `PNT-*` + suffixed variants | 6 | the 5 suffixed ones are **not `.md`** — invisible to `*.md` globs and to any tool that indexes by extension |
| `TEST-*` | 4 | `TEST-REPORT-<date>` vs `TEST-RESULTS-<module>` — two shapes for one kind |
| `*_PLAN.md` / `GIT_*_PLAN.md` | 6 | plans are scattered: two are about the git remote, three about the app, one about the audit |
| `*-REPORT.md` | 4 | audit report, test report, blockers report — same suffix, three phases |
| lowercase | 4 | `pentest.md`, `rule.md`, `DEV-compliance.md`, `AUTH-migrate.md`, `FUNC-testing.md` — mixed case, and `DEV-compliance.md` is cited from 13 code files |
| dated | 2 | `TEST-REPORT-2026-10-06.md`, `PRODUCTION-BLOCKERS-2026-10-07.md` — dates are correct for run records; keep them |
| single-word | 2 | `UNIFIED.md` (whole repository), `README.md` (the index) |

---

## 4. Proposed shape — phase folders, names kept

Folders carry the phase number and the phase name; **file names stay as they are** unless §5 says
otherwise. This is the whole point of the move-without-rename rule: the phase is expressed by the
location, the citation is preserved by the name.

```
webapp/srs/
  README.md                      <- the index; regenerated last, lists former paths if any
  00-meta/
  01-requirements/
  02-design/
  03-implementation/
  04-verification/
  05-audit/
  06-release/
  07-maintenance/
```

Mapping of all 35:

| Phase folder | Files placed in it |
|---|---|
| *(root)* | `README.md` (index — keep the name: tooling and editors surface it automatically) |
| `00-meta/` | `rule.md` (session hygiene — process, not product), `UNIFIED.md` (whole-repository history/layout) |
| `01-requirements/` | `SRS-Harbour.md`, `SRS-Harbour-HIX.md`, `SRS-DAL-CRUD-WEB-UI.md`, `DEV-compliance.md` |
| `02-design/` | `AUTH-migrate.md`, `FUNC-testing.md`, `pentest.md` (tasking/persona prompts), `DAL-CHECKLIST.md` (review against the SRSs), `COMPARATIVE-ANALYSIS.md` (app vs the framework's own `examples/web/crud/` baseline), `BRUTE-FORCE-PENTEST-PLAN.md`, `VIGOLIUM-SCAN-PLAN.md` |
| `03-implementation/` | `CHANGELOG-CUSTOMER-FIXES.md`, `BUG-UPDATE-FLASH-ERROR.md`, `STATUS-USERS-MODULE.md` |
| `04-verification/` | `TEST-REPORT-2026-10-06.md`, `TEST-RESULTS-USERS-MODULE.md`, `TEST-RESULTS-CUSTOMER-MODULE.md`, `PRODUCTION-BLOCKERS-2026-10-07.md`, `FIX-RECOMMENDATIONS-DEV-COMPLIANT.md` |
| `05-audit/` | `PENTEST-REPORT.md`, `BF-01-SURFACE-FINDINGS.md`, `PNT-Harbour-HIX.md` + its 5 variants |
| `06-release/` | `COMPARISON-enhance-vs-main.md`, `GIT_REMOTE_MIGRATION_PLAN.md`, `GIT_AUTH_PLAN.md` |
| `07-maintenance/` | `LETS-ENCRYPT-PLAN.md`, `PASSWORD-COMPLIANCE-PLAN.md` |

Two judgement calls, recorded rather than buried:

* **`VIGOLIUM-SCAN-PLAN.md` in 02, not 07.** It plans an audit of the app as it stands, i.e. it
  precedes remediation — design-stage. `LETS-ENCRYPT-PLAN.md` and `PASSWORD-COMPLIANCE-PLAN.md`
  evolve a system that already works, i.e. maintenance. If the reader prefers "all future work is
  maintenance", the two moves swap; nothing else changes.
* **`PENTEST-REPORT.md` in 05, not 03.** It is a §1…§10 *remediation* record — the record of
  implementation — but it is the audit corpus's spine and 17 code files cite it. Keeping it with
  the audits keeps the defect ids (`D-01…D-16`, `N-01`, `SEC-*`, `H-*`, `C-009`) resolvable in one
  place. Its alternative home is `03-implementation/`.

---

## 5. Renames — only these, and only after the moves

| # | Rename | Why | Blast radius | Verdict |
|---|---|---|---|---|
| R-1 | `PNT-Harbour-HIX.md.DENSE.Q4` → `PNT-Harbour-HIX--DENSE-Q4.md` (and `.Q8`, `.MOE.3.6/3.8/3.9`) | the 5 files are not `.md`; they are invisible to extension-based tooling and to `git ls-files '*.md'` | 0 code citations; the base name `PNT-Harbour-HIX.md` (8 in-corpus refs) is untouched | **do it** |
| R-2 | `TEST-RESULTS-USERS-MODULE.md` → `TEST-REPORT-USERS-MODULE.md`, `TEST-RESULTS-CUSTOMER-MODULE.md` → `TEST-REPORT-CUSTOMER-MODULE.md` | one kind, two shapes today | 2 and 1 refs, all inside `webapp/srs/` | **do it** |
| R-3 | `pentest.md` → `AUDIT-tasking.md` | lowercase, single word, and the name collides in reading with `PENTEST-REPORT.md` | 3 refs, all inside `webapp/srs/` | **do it** (not a case-only rename) |
| R-4 | `rule.md` → `SESSION-rules.md` | the name says nothing; it is session hygiene | 1 ref, inside `webapp/srs/` | **do it** |
| R-5 | `AUTH-migrate.md` → `AUTH-migrate-tasking.md`, `FUNC-testing.md` → `FUNC-testing-tasking.md` | mark them as tasking, matching `pentest.md`'s role | 1 and 3 refs, inside `webapp/srs/` | optional |

**Do not rename — with the reason:**

| File | Reason |
|---|---|
| `PENTEST-REPORT.md` | **21 citations in 17 code files** (`src/hix_config_app.prg`, `src/hix_csrf.prg`, `src/hix_keys.prg`, `src/hix_mw_loader.prg`, `webapp/src/app.prg`, `webapp/gen_keys.sh`, `webapp/go_gcc.sh`, `webapp/www/controllers/login.prg`, 5 `www/middlewares/*.prg`, 2 `www/models/*.prg` — 15 of them tracked). A rename breaks the corpus's own lookup rule |
| `DEV-compliance.md` | **14 citations in 13 code files** — the test-suite headers and adhoc tools quote it as the constraint document |
| `SRS-Harbour-HIX.md` | 2 citations in code (`webapp/test/test_customer_module.{prg,sh}`) |
| `BRUTE-FORCE-PENTEST-PLAN.md` | 1 citation in `webapp/test/bf_harness.sh` (untracked — cannot be fixed from the repo anyway) |
| `COMPARISON-enhance-vs-main.md` | **generated**: `compare-branches.sh:34` `OUT="${3:-webapp/srs/COMPARISON-enhance-vs-main.md}"`, and the usage lines 9-10 name the path. Moving it requires editing the script; renaming it requires editing the script and re-running it. Move only, and update the script's default in the same change if the folder changes |
| `README.md` | tooling convention; it is the folder's index |
| `UNIFIED.md` | 13 refs (6 in-corpus, 7 in other docs, incl. root `ENHANCE.md` pointing at it) |
| `TEST-REPORT-2026-10-06.md`, `PRODUCTION-BLOCKERS-2026-10-07.md` | dated run records; the date is the identity |

---

## 6. Sequence

Each step ends with a check. Stop on a failed check; do not continue with a half-moved corpus.

**P0 — inventory and freeze the mapping.** Confirm the 35/31/4/5 counts of §3 before moving
anything.

```bash
ls webapp/srs | wc -l ; git ls-files webapp/srs | wc -l
ls webapp/srs | grep -v '\.md$'
git status --short webapp/srs
```

**P1 — create the phase folders** (empty folders are not tracked by git; they become visible with
their first file).

**P2 — move the 31 tracked files with `git mv`, one phase folder at a time**, name unchanged, per
§4.

```bash
git mv webapp/srs/SRS-Harbour.md webapp/srs/01-requirements/
# … one per file
git status --short webapp/srs        # expect: only the renames just made
git ls-files webapp/srs | wc -l     # must still be 31
```

Stop: any `D` (deletion) without a matching `A` (addition) — that is a move that lost a file.

**P3 — move the 4 untracked files with plain `mv`.** Record in the index that they are local-only.

**P4 — apply R-1…R-4 of §5** (the renames), after the moves, so each rename is a single-step
`git mv` from the final folder. Update `compare-branches.sh:34` and its usage lines only if
`COMPARISON-enhance-vs-main.md`'s path changed — it did (it moves to `06-release/`).

**P5 — regenerate the index.** `webapp/srs/README.md` is the corpus's table of contents; its three
tables must be rebuilt from the new tree, and a provenance line added in the corpus's existing
voice ("Re-organized into phase folders on 2026-10-07 — before that the folder was flat").
List every R-* rename as "formerly `webapp/srs/<old>`" so a reader holding an old citation from a
historical report can still find the file.

**P6 — verification sweep.**

```bash
# every bare-name citation still resolves
for f in $(git ls-files webapp/srs); do b=$(basename "$f"); grep -rl "$b" --include="*.prg" --include="*.sh" --include="*.c" . ; done
# no old name survives outside historical prose
grep -rl -e 'TEST-RESULTS-\|pentest\.md\|rule\.md' --include="*.prg" --include="*.sh" --include="*.c" .
# nothing became invisible to git
git ls-files webapp/srs | wc -l          # 31 still
git status --short webapp/srs | grep '^ D'
# the docs build is untouched
grep -n 'srs' mkdocs.yml                 # expect: no output
```

Stop: a code comment that names a file which no longer exists under that name.

---

## 7. Blast radius (the evidence behind §5's do-not-rename list)

```
name                             cited inside webapp/srs   cited in code (.prg/.sh/.c/.hbp)   cited in other docs
PENTEST-REPORT.md                13                        21  (17 files, 15 tracked)         5  (3 files)
DEV-compliance.md                20                        14  (13 files,  6 tracked)         0
UNIFIED.md                        6                         0                                 7  (2 files)
SRS-Harbour-HIX.md                6                         2  (2 files,  0 tracked)         0
COMPARISON-enhance-vs-main.md     6                         2  (1 file: compare-branches.sh)  3
BRUTE-FORCE-PENTEST-PLAN.md       9                         1  (1 file,  untracked)           1
COMPARATIVE-ANALYSIS.md           1                         0                                 2
STATUS-USERS-MODULE.md            3                         0                                 2
PRODUCTION-BLOCKERS-2026-10-07.md 6                         0                                 1
TEST-REPORT-2026-10-06.md         3                         0                                 1
GIT_REMOTE_MIGRATION_PLAN.md      4                         0                                 0
LETS-ENCRYPT-PLAN.md              5                         0                                 0
FIX-RECOMMENDATIONS-DEV-COMPLIANT.md 1                      0                                 0
```

Everything not listed has ≤3 references and none in code — those are the safe renames in §5.

---

## 8. What the re-organization reveals (the corpus's own completeness gap)

Filing by phase makes the missing artefacts visible, which the flat folder does not:

| Phase | Present? | Finding |
|---|---|---|
| 01 requirements | ✅ 4 | the baseline exists and is binding |
| 02 design | ✅ 7 | tasking + review + plans |
| 03 implementation | ⚠️ 3 | only the customer module and the users module have a record; nothing records the framework-side changes (`src/hix_*.prg`) — those live in commit messages only |
| 04 verification | ✅ 5 | two run records, two module results, one blockers ranking, one compliance grading |
| 05 audit | ✅ 8 | one consolidated report + 5 model variants + surface findings |
| 06 release | ⚠️ 3 | **no release record at all** — no version/tag policy, no changelog for the application as a whole; `COMPARISON-enhance-vs-main.md` is a branch diff, not a release note |
| 07 maintenance | ✅ 2 | TLS and password evolution |

So the re-organization is also a report on the SDLC itself: phases 03 and 06 are thin, and 06 has
no release artefact. That is a finding to carry forward, not something this move can fix.

---

## 9. Do-not list

* Do not rename the eight files in §5's second table. Their citations are the corpus's lookup
  mechanism.
* Do not edit historical reports' bodies to chase a rename (§1).
* Do not name a phase folder `tests/`, `tmp/`, `lib/`, or give a file a `.bak`/`.log` suffix — git
  will stop seeing it (§2 T-TRAP).
* Do not do a case-only rename (Windows checkouts, §1).
* Do not treat the 4 untracked files as part of the repository's shape (§1).
* Do not hand-edit `COMPARISON-enhance-vs-main.md` — it is regenerated; re-run
  `compare-branches.sh` after its path default is updated.
* This document moves nothing. Every `git mv` above is a proposal.

## 10. Evidence map

```bash
ls webapp/srs | wc -l ; git ls-files webapp/srs | wc -l ; ls webapp/srs | grep -v '\.md$'
git ls-files webapp/srs > /tmp/tracked ; ls webapp/srs > /tmp/all ; comm -13 /tmp/tracked /tmp/all
grep -rl 'PENTEST-REPORT\.md' --include='*.prg' --include='*.sh' --include='*.c' . | sort
grep -rl 'DEV-compliance\.md'  --include='*.prg' --include='*.sh' --include='*.c' . | sort
grep -n 'OUT=' compare-branches.sh
grep -n 'srs' mkdocs.yml ; sed -n '1,20p' .github/workflows/docs.yml
grep -n 'tests/\|tmp/\|lib/\|\.bak\|\.log' .gitignore webapp/.gitignore
sed -n '1,60p' webapp/srs/README.md          # the index that must be regenerated
git --version                                # git mv available (2.56.0)
```
