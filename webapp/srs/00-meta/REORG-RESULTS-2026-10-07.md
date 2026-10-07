# Re-organization results — what was actually done on 2026-10-07

Run: `webapp/srs/` re-filed into SDLC phase folders, per `00-meta/SDLC-REORGANIZATION-PLAN.md`.
Started 2026-10-07T09:2x · the plan was written before it was executed, so this file is the record
of the execution, not a restatement of the plan.

Result: **35 documents moved, 0 lost, 31 still tracked, 9 renamed, 0 deletions.**
Bare-name citations in code are **unchanged** (21 / 14 / 2 / 1 / 2) — the move did not touch a
single one.

---

## 1. What was created and moved

```
8 phase folders: 00-meta 01-requirements 02-design 03-implementation
                 04-verification 05-audit 06-release 07-maintenance

30 moved with `git mv`   (tracked; staged as renames, blob identity preserved)
 5 moved with plain `mv` (untracked: VIGOLIUM-SCAN-PLAN, LETS-ENCRYPT-PLAN,
                          PASSWORD-COMPLIANCE-PLAN, FIX-RECOMMENDATIONS-DEV-COMPLIANT,
                          SDLC-REORGANIZATION-PLAN)
 1 left at the folder root: README.md (the index, regenerated)
```

Distribution after the move: `00-meta` 3 (+ this file, written afterwards) · `01-requirements` 4 · `02-design` 7 ·
`03-implementation` 3 · `04-verification` 5 · `05-audit` 8 · `06-release` 3 · `07-maintenance` 2.

## 2. Renames applied — nine, exactly the plan's R-1…R-4

| Former | Now |
|---|---|
| `rule.md` | `00-meta/SESSION-rules.md` |
| `pentest.md` | `02-design/AUDIT-tasking.md` |
| `TEST-RESULTS-USERS-MODULE.md` | `04-verification/TEST-REPORT-USERS-MODULE.md` |
| `TEST-RESULTS-CUSTOMER-MODULE.md` | `04-verification/TEST-REPORT-CUSTOMER-MODULE.md` |
| `PNT-Harbour-HIX.md.DENSE.Q4` | `05-audit/PNT-Harbour-HIX--DENSE-Q4.md` |
| `PNT-Harbour-HIX.md.DENSE.Q8` | `05-audit/PNT-Harbour-HIX--DENSE-Q8.md` |
| `PNT-Harbour-HIX.md.MOE.3.6` | `05-audit/PNT-Harbour-HIX--MOE-3.6.md` |
| `PNT-Harbour-HIX.md.MOE.3.8` | `05-audit/PNT-Harbour-HIX--MOE-3.8.md` |
| `PNT-Harbour-HIX.md.MOE.3.9` | `05-audit/PNT-Harbour-HIX--MOE-3.9.md` |

The five extension-less audit variants are now `.md`, so `git ls-files 'webapp/srs/**/*.md'` and
any extension-based tool sees them. Before the move they were invisible to that glob.

**Not applied:** the plan's optional R-5 (`AUTH-migrate.md` / `FUNC-testing.md` → `*-tasking.md`).
They kept their names; the decision is recorded here rather than left implicit.

**Not renamed, as the plan required:** `PENTEST-REPORT.md`, `DEV-compliance.md`,
`SRS-Harbour-HIX.md`, `BRUTE-FORCE-PENTEST-PLAN.md`, `COMPARISON-enhance-vs-main.md`,
`README.md`, `UNIFIED.md`, and the two dated run records. Their names are what the code comments
grep for.

## 3. Citations updated (live documents only)

Path-qualified references were the only kind the move could break, so they were chased where the
document is live and left alone where it is a record:

| File | Lines | Change |
|---|---|---|
| `compare-branches.sh` | 10, 34 | `--exclude` example and the `OUT="${3:-…}"` default → `webapp/srs/06-release/COMPARISON-enhance-vs-main.md` |
| `webapp/gen_cert.sh` | 6 | `(webapp/srs/01-requirements/DEV-compliance.md)` |
| `webapp/srs/01-requirements/DEV-compliance.md` | 15, 16 | its own `References:` section → `@webapp/srs/01-requirements/SRS-*.md` |
| `ENHANCE.md` | 16, 17, 106-110, 120-123 | the four corpus links and the layout block (the block also gained a line saying the corpus is phase-filed) |
| `readme.md` | 11 | `webapp/srs/00-meta/UNIFIED.md` |
| `webapp/readme.md` | 54, 66, 79 | `srs/05-audit/PENTEST-REPORT.md` ×2, `srs/02-design/BRUTE-FORCE-PENTEST-PLAN.md` |
| `tests/readme.md` *(untracked)* | 250, 251 | `webapp/srs/04-verification/TEST-REPORT-2026-10-06.md`, `…/PRODUCTION-BLOCKERS-2026-10-07.md` |
| `webapp/test/probe_{entropy,fmode,pwcost}.prg`, `test_users_module.sh`, `verify-users-fixes.sh` *(untracked)* | header lines | `webapp/srs/01-requirements/DEV-compliance.md` |
| `webapp/srs/README.md` | whole file | regenerated from the new tree, phase by phase, with the *Formerly* table |

## 4. Verification sweep (as recorded)

```
git ls-files webapp/srs | wc -l                       31   unchanged
git status --short webapp/srs                         30 R, 1 M, 4 ??   — 0 deletions
bare-name citations in code (.prg/.sh/.c/.hbp)
   PENTEST-REPORT.md              21   (was 21)
   DEV-compliance.md              14   (was 14)
   SRS-Harbour-HIX.md              2   (was  2)
   BRUTE-FORCE-PENTEST-PLAN.md     1   (was  1)
   COMPARISON-enhance-vs-main.md   2   (was  2)
old names still present in code                        0
old names still present in the live entry docs         0
git check-ignore on the new folders                    none ignored
grep -c srs mkdocs.yml                                 0   (docs build unaffected)
```

The trap the plan warned about did not bite: no phase folder is named `tests/`, `tmp/` or `lib/`,
and no renamed file ends in `.bak` or `.log`.

## 5. Deliberate residue

**43 path-qualified references still name the old flat paths inside corpus bodies**, and **7 corpus
documents still mention a former name**. They were not rewritten: `TEST-REPORT-2026-10-06.md`,
`PRODUCTION-BLOCKERS-2026-10-07.md`, `STATUS-USERS-MODULE.md`, `UNIFIED.md` and the audit variants
are records of runs and audits that happened; editing their citations would falsify the record.
`webapp/srs/README.md` resolves them through the *Formerly* table. The heaviest concentrations are
the documents written today (`PASSWORD-COMPLIANCE-PLAN.md` 9, `LETS-ENCRYPT-PLAN.md` 6) and the
generated `COMPARISON-enhance-vs-main.md` 10 — that one refreshes on the next
`compare-branches.sh` run, whose default output path was already updated.

## 6. Deviations from the plan

| # | Deviation | Why |
|---|---|---|
| 1 | `SDLC-REORGANIZATION-PLAN.md` was itself moved into `00-meta/` | the plan predated its own existence; the mapping table could not place it. A corpus process document belongs with the corpus's process documents |
| 2 | Optional R-5 not applied | the plan marked it optional; applying it would rename two more files for no resolved ambiguity |
| 3 | The 5 untracked documents moved with plain `mv` | they are not in git; a fresh clone still has 31 documents, 4 of them in the old flat layout not present at all. Same known gap as the untracked test suite |
| 4 | `tests/readme.md` and the five `webapp/test/` headers were updated **locally only** | both paths are gitignored (`tests/`, `webapp/test/`); the edits do not propagate to a clone |
| 5 | Phase folders are not tracked as directories | git tracks files; the folders exist because each holds at least one file |
| 6 | `git mv` staged the 30 renames but nothing was committed | the commit is a separate decision, like every other change in this repository |

## 7. What the move confirmed about the SDLC itself

The phase folders make the corpus's own thinness visible, and it is unchanged by the move:

* **`03-implementation/` has 3 documents** — the customer module and the users module. Nothing
  records the framework-side changes under `src/`; those exist only as commit messages.
* **`06-release/` has no release artefact at all.** `COMPARISON-enhance-vs-main.md` is a branch
  diff, not a release note; there is no version/tag policy and no application changelog.
* Everything else (01, 02, 04, 05, 07) has artefacts.

That is a finding about the process, not something a re-file can fix.

## 8. Follow-ups, not performed here

* The four plans/reports written today are untracked. If they are to ship, `git add` them — the
  re-organization did not decide that.
* `06-release/` needs a release record before the phase can be called complete.
* `compare-branches.sh` was **not run** during this operation (it fetches branches); its default
  output path was updated so the next run writes into `06-release/`.

## 9. Evidence map

```bash
git ls-files webapp/srs | wc -l
git status --short webapp/srs | awk '{print $1}' | sort | uniq -c
find webapp/srs -type f | sort
for n in PENTEST-REPORT.md DEV-compliance.md SRS-Harbour-HIX.md BRUTE-FORCE-PENTEST-PLAN.md COMPARISON-enhance-vs-main.md; do
  grep -rc "$n" --include='*.prg' --include='*.sh' --include='*.c' --include='*.hbp' . | awk -F: '{s+=$NF}END{print s+0}'
done
grep -rn "TEST-RESULTS-\|srs/pentest\.md\|srs/rule\.md\|srs/DEV-compliance\.md" --include="*.prg" --include="*.sh" --include="*.c" .
grep -rn "webapp/srs/[A-Za-z]" webapp/srs --include="*.md" | grep -v README | wc -l
git check-ignore -v webapp/srs/04-verification/x.md ; grep -c srs mkdocs.yml
sed -n '8,12p;32,36p' compare-branches.sh
```
