# `srs/` — requirements, compliance and audit corpus

The documents the application cites but does not contain: the requirements baseline, the
compliance constraints every session must obey, and the security-audit reports that produced the
defect ids (`D-01…D-16`, `N-01`, `SEC-*`, `H-*`, `C-009`, `BF-*`) written into `webapp/`'s code
comments, test suites and commit messages.

Imported into version control on 2026-10-06 — before that this folder was the only part of the
project not under git, while `webapp/` docs and test headers referenced it by absolute path.

## Specs and constraints

| File | What it is |
|---|---|
| `SRS-Harbour-HIX.md` | The master SRS for the Harbour + HIX web application (73 KB) |
| `SRS-Harbour.md` | SRS for the Harbour console applications side (55 KB) |
| `SRS-DAL-CRUD-WEB-UI.md` | SRS for the CRUD data-access-layer / web-UI flow |
| `DEV-compliance.md` | **The binding constraints**: HIX style only, no SQL, no 3rd-party web UI, tools inside the project folder, port 9090. Cited by the test suites' headers |
| `FUNC-testing.md` | Tasking: functional end-to-end test of the customer module, report only |
| `AUTH-migrate.md` | Tasking: migrate hardcoded authentication to a persistent RDDCDX store |
| `pentest.md` | Tasking / persona prompt for the security audit |
| `rule.md` | Session hygiene rules (repetition / loop prevention) |

## Audit reports

`PNT-Harbour-HIX.md` is the consolidated audit report. The suffixed files are the same audit run by
different models/configurations, kept for comparison — they are **inputs to the remediation**, not
the record of it:

| File | Variant |
|---|---|
| `PNT-Harbour-HIX.md` | consolidated report |
| `PNT-Harbour-HIX.md.DENSE.Q4` / `.DENSE.Q8` | DENSE Q4 / Q8 |
| `PNT-Harbour-HIX.md.MOE.3.6` / `.3.8` / `.3.9` | MOE 3.6 / 3.8 / 3.9 |

## What the remediation record itself is

The *as-fixed* record lives with the code, not here:

* `webapp/PENTEST-REPORT.md` — §1…§10 remediation record (keys out of the docroot, CSRF bound to the
  session, private session store, security headers, …)
* `webapp/BF-01-SURFACE-FINDINGS.md`, `webapp/BRUTE-FORCE-PENTEST-PLAN.md`
* `webapp/STATUS-USERS-MODULE.md`, `webapp/TEST-RESULTS-*-MODULE.md`, `webapp/DAL-CHECKLIST.md`

> Note: paths written *inside* these documents still refer to the pre-unification locations
> (`/home/jack/Projects/pi-agent/webapp`, `/home/jack/Projects/pi-agent/srs/...`). They are
> historical text and were left as written; the corpus now lives at `srs/` in this repository.
