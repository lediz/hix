# `webapp/srs/` — requirements, compliance and audit corpus

The documents the application cites but does not contain: the requirements baseline, the
compliance constraints every session must obey, and the security-audit reports that produced the
defect ids (`D-01…D-16`, `N-01`, `SEC-*`, `H-*`, `C-009`, `BF-*`) written into `webapp/`'s code
comments, test suites and commit messages.  It lives inside `webapp/`, beside the code it governs.

Imported into version control on 2026-10-06 — before that this folder was the only part of the
project not under git, while `webapp/` docs and test headers referenced it by absolute path.  The
same day it absorbed the plans, reports and analyses that had been sitting in the repository root
and in `webapp/`.

**Re-organized into phase folders on 2026-10-07** — the folder now reads as a software development
lifecycle, and every document sits in the phase whose work it belongs to.  The move was
**move-without-rename**: the corpus is cited by bare name, so a move keeps every citation resolving
and only the nine renames below (§ *Formerly*) changed any name.  The plan behind it is
`00-meta/SDLC-REORGANIZATION-PLAN.md`; the record of what was actually done is
`00-meta/REORG-RESULTS-2026-10-07.md`.

## The phases

| Folder | SDLC phase | What sits in it |
|---|---|---|
| `00-meta/` | — | the corpus's own process documents: session hygiene, repository assembly, the re-org plan and its result |
| `01-requirements/` | Requirements & constraints | the SRSs and the binding compliance document |
| `02-design/` | Analysis & design | tasking prompts, reviews against the SRSs, and the plans that precede remediation |
| `03-implementation/` | Implementation | the record of what was changed: fix logs, defect reports, module status |
| `04-verification/` | Verification | run records, module test results, shipping-blocker ranking, compliance grading |
| `05-audit/` | Security audit | the consolidated audit report, its model variants, and the surface findings |
| `06-release/` | Integration & release | branch deltas and the git-remote plans. **No release artefact exists yet** |
| `07-maintenance/` | Maintenance | plans that evolve a system that already works |

## `00-meta/`

| File | What it is |
|---|---|
| `SESSION-rules.md` | Session hygiene rules (repetition / loop prevention) |
| `UNIFIED.md` | The exception: it documents the **whole repository**, not just the app — how the framework and the application came to share one history, plus layout, build order, remotes and git rules. Root `../../ENHANCE.md` is the entry point for what the branch changes |
| `SDLC-REORGANIZATION-PLAN.md` | Plan: re-file the corpus into phase folders; move-without-rename, the safe renames, the eight that are not, the phase gaps the move reveals. Report only |
| `REORG-RESULTS-2026-10-07.md` | What the re-organization actually did, where it deviated, and the verification sweep |

## `01-requirements/`

| File | What it is |
|---|---|
| `SRS-Harbour-HIX.md` | The master SRS for the Harbour + HIX web application (73 KB) |
| `SRS-Harbour.md` | SRS for the Harbour console applications side (55 KB) |
| `SRS-DAL-CRUD-WEB-UI.md` | SRS for the CRUD data-access-layer / web-UI flow |
| `DEV-compliance.md` | **The binding constraints**: HIX style only, no SQL, no 3rd-party web UI, tools inside the project folder, port 9090. Cited by the test suites' headers. It carried a scoped exception to the "No SQL" clause for the MySQL DAL phases; that exception is **retired 2026-10-08** — the MySQL DAL is gone and the clause now binds everywhere, with no exception |

## `02-design/`

| File | What it is |
|---|---|
| `AUTH-tasking.md` | Tasking / persona prompt for the security audit |
| `AUTH-migrate.md` | Tasking: migrate hardcoded authentication to a persistent RDDCDX store |
| `FUNC-testing.md` | Tasking: functional end-to-end test of the customer module, report only |
| `DAL-CHECKLIST.md` | Review of the app against the DAL and Harbour-HIX SRSs |
| `COMPARATIVE-ANALYSIS.md` | Analysis of this app against the framework's own `examples/web/crud/` baseline |
| `BRUTE-FORCE-PENTEST-PLAN.md` | Brute-force / timing probe plan; `test/bf_harness.sh` implements it against the local app only |
| `VIGOLIUM-SCAN-PLAN.md` | Plan: automate the audit with the vigolium scanner (native + agentic), local target only; plan only |

## `03-implementation/`

| File | What it is |
|---|---|
| `CHANGELOG-CUSTOMER-FIXES.md` | Customer-module fix log |
| `BUG-UPDATE-FLASH-ERROR.md` | Single-defect report: the update flash error |
| `STATUS-USERS-MODULE.md` | Users-module status report (D-01…D-16), report-only |
| `P0-DBFCDX-STORE-RESULTS-2026-10-08.md` | What the removal and the DBFCDX shape actually did: what was deleted, what replaced it, what was measured (link clean, login 302 → `/main`, `probe_seek`, `probe_pw`), and what was **not** proven (the customer suite is 21/50 because the login limiter is 5 per 60 s and the suite makes 7 `/auth` calls) |
| *(removed 2026-10-08)* | The MySQL-era plans, generators and result records were **deleted** with the MySQL DAL they described — 17 documents. They are not in the tree; `git log` is the record of them |

## `04-verification/`

| File | What it is |
|---|---|
| `TEST-REPORT-2026-10-06.md` | What `../../tests/run.sh` found, cluster by cluster (C1…C9), with the fix recommendations and a §14 addendum for the suite-side fixes that landed after it. Produced by the suite, never the other way round |
| `TEST-REPORT-USERS-MODULE.md` · `TEST-REPORT-CUSTOMER-MODULE.md` | End-to-end functional test results |
| `FR-RESCORE-PART-2026-10-08.md` | The SRS's FR-* checklist re-scored against `part` and the MySQL module surface — **that surface was deleted 2026-10-08**; the scoring is kept as history of the shape it scored, not of what ships |
| `PRODUCTION-BLOCKERS-2026-10-07.md` | The same findings ranked by what blocks shipping (B1…B7): two suites that verify nothing, and the session-store mode being a launcher obligation. Report-only |
| `FIX-RECOMMENDATIONS-DEV-COMPLIANT.md` | Report: every fix recommendation in the corpus graded against the eight clauses of `DEV-compliance.md` (✅ / ⚠️ host-scope / ❌ with the compliant substitute). Report only — it applies nothing |

## `05-audit/`

`PENTEST-REPORT.md` is the §1…§10 remediation record — keys out of the docroot, CSRF bound to the
session, private session store, security headers, … Cited by defect ids in the code comments.
`PNT-Harbour-HIX.md` is the consolidated audit report; the suffixed files are the same audit run by
different models/configurations, kept for comparison — they are **inputs to the remediation**, not
the record of it:

| File | Variant |
|---|---|
| `PENTEST-REPORT.md` | remediation record |
| `BF-01-SURFACE-FINDINGS.md` | attack-surface findings behind the BF-* ids |
| `PNT-Harbour-HIX.md` | consolidated report |
| `PNT-Harbour-HIX--DENSE-Q4.md` / `--DENSE-Q8.md` | DENSE Q4 / Q8 |
| `PNT-Harbour-HIX--MOE-3.6.md` / `--MOE-3.8.md` / `--MOE-3.9.md` | MOE 3.6 / 3.8 / 3.9 |

## `06-release/`

| File | What it is |
|---|---|
| `COMPARISON-enhance-vs-main.md` | Generated by `../../compare-branches.sh` — `origin/enhance` vs `origin/main`. Do not hand-edit; re-run the script (its default output path was updated to this folder on 2026-10-07) |
| `GIT_REMOTE_MIGRATION_PLAN.md` | Plan: move the remote to `github.com/lediz/hix`, branch `enhance` |
| `GIT_AUTH_PLAN.md` | Plan: git authentication for that remote |

## `07-maintenance/`

| File | What it is |
|---|---|
| `LETS-ENCRYPT-PLAN.md` | Plan: replace the locally generated TLS pair (`./gen_cert.sh`) with a Let's Encrypt / ACME certificate via `certbot`, wired into the same `cert_private`/`cert_public` keys; plan only |
| `PASSWORD-COMPLIANCE-PLAN.md` | Plan: bring the memorized secret to industry standard (NIST SP 800-63B + OWASP) — verifier/registration length policy, blocklist, KDF reachable from Harbour's own primitives, per-account throttling, plaintext paths; plan only |

## Formerly

The nine renames. A historical report that cites one of these old names still means this file —
the bodies of the reports were not rewritten, because they are records of runs that happened:

| Former name | Now |
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

Everything else kept its name; only its folder changed.

Code comments cite these by bare name (`PENTEST-REPORT.md §1`, `D-14`, `BF-01`), which is how they
are meant to be found — grep for the name or the defect id rather than a path.  That rule still
holds after the move, which is why the move did not rename the eight files that code cites.

> Note: these reports were written before the unification, when the application and the framework
> lived in two separate checkouts. Where a report says `webapp/` it means the application checkout
> of that moment, and `$HB_ROOT` means its author's Harbour build. No absolute filesystem paths are
> kept in the corpus.
