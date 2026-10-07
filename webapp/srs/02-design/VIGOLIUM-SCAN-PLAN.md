# Vigolium Scan Plan — automating the audit of the HIX webapp

Scope: the **local** HIX CRUD app in this repository (`https://localhost:9090`), the HIX
framework source at the repository root, and the seeded data in `webapp/data/`. This is an
authorized self-assessment of code we own. **Nothing in this plan may be pointed at a deployed
instance, at a host we do not own, or at real user accounts.**

Status: **plan only.** No phase has been executed. `vigolium` is **not installed** on this machine
(`which vigolium` → not found), so P0 below is real work, not a formality.

Upstream tool: <https://github.com/vigolium/vigolium> — Go CLI (`scan` / `run` / `server` /
`ingest` / `agent` / `export` / `import` / `kit`), docs at <https://docs.vigolium.com/>.
Every flag quoted in this file was taken from those docs on 2026-10-07; re-check with
`vigolium <command> -h` once the binary is installed, since the tool's flag names have changed
across versions (`--session` → `--auth`, `-S` → `--stateless`, `--scan-on-receive` no longer `-S`).

---

## 1. Ground rules (binding — read before running anything)

| Rule | Why |
|---|---|
| Target only `https://localhost:9090` (plus one deliberate `http://` probe) | Nothing may leave the machine. This also rules out `--oast-url` against interact.sh: an out-of-band callback is an outbound request to a third-party service. |
| Use only the seeded accounts in `data/users.dbf` (`admin`, `carles`, `maria`, `John`, `jane`) and rows created with a `zbf<epoch>` prefix | Keeps scan traffic attributable and reversible. |
| Every scan is time-bounded (`--scanning-max-duration`) and every harness loop has a hard cap | A wedged HIX worker (`exec_timeout_ms: 30000`) must not hang the run. |
| Scan **pace stays under the app's own limiters** (§4) | The app rate-limits by IP; a scanner that bursts it produces 403s that look like a WAF and silently truncate coverage. |
| Snapshot before, restore after (`regenerate_users`, `regenerate_data`, delete `.sessions/*`, rotate `hix.keys.json`) | A scan mutates session files, rate-limit buckets, flash records and DBF rows. |
| Never enable a push URL; never upload SARIF to a remote code-scanning tab from this repo | `origin/enhance` is push-disabled by design (`webapp/srs/UNIFIED.md`, *Secrets*). CI/SARIF wiring in §11 is for a **private/local** sink only. |
| Record evidence, do not claim results | Every finding needs request + response + timestamp + the source line that explains it, same discipline as `PENTEST-REPORT.md`. |
| Agent modes (`vigolium agent …`) run **unsandboxed** with Bash/Read/Write/Grep/Glob | Upstream's own security warning. Run them only in a disposable container or an ephemeral CI runner, never with long-lived credentials mounted in. Native `scan` does not have this property — it only issues HTTP. |
| Stop conditions in §12 are binding | Rate-limit and worker-exhaustion probes degrade the service for everyone else on the box. |

---

## 2. What already exists (do not duplicate it)

| Thing | State | Use it for |
|---|---|---|
| `webapp/srs/PENTEST-REPORT.md` | §1…§10 remediation record, defect ids cited in code comments | The **baseline**: a scan must not re-report a closed control as a finding; it must re-confirm the control still holds. |
| `webapp/srs/BRUTE-FORCE-PENTEST-PLAN.md` + `webapp/test/bf_harness.sh` | Plan + implemented harness for BF-* probes | Keep brute-force/timing under its own harness. Vigolium is **not** a brute-force tool (its spidering default-credential attempt is single-flight, capped, negative-control gated). |
| `piolium/audit-state.json`, `piolium/attack-surface/candidates.{jsonl,md}` | Three audits left `in_progress`, all phases failing with `404: {"message":"not found"}` | Vigolium's `agent audit --driver piolium` drives the same piolium harness. Re-run through the dispatcher, do not hand-run it. The 404s are a provider/endpoint problem to fix in P0, not a scan result. |
| `tests/run.sh`, `tests/unit/`, `webapp/test/*.sh` | Existing functional/regression suites | The scan harness must run **after** them and must not assume they pass. |
| `.github/workflows/docs.yml` | Only workflow that exists | Any scan workflow added in §11 must be a new file, and must not trigger the MkDocs deploy. |

---

## 3. Target facts (from the repo, not from memory)

| Fact | Value | Source |
|---|---|---|
| Listener | `localhost:9090`, `ssl: true`, `maxconn: 1024`, `exec_timeout_ms: 30000` | `webapp/hix.json` 9, 16, 6-24 |
| Docroot / session store | `paths.root = www`, `paths.session = .sessions`, certs `certs/` | `webapp/hix.json` 25-33 |
| Session | `storage: file`, `prefix: sess_`, `crypt: true`, `lifetime: 3600`, cookie `FENIXSID`, `max: 100` | `webapp/hix.json` 86-93, `webapp/www/middlewares/config.json` 17-21 |
| Global limiter | **300 req / 60 s per IP** | `webapp/www/middlewares/config.json` 26-29 |
| Login limiter | **5 attempts / 60 s per IP**, `POST /auth` only | `webapp/www/middlewares/config.json` 29-30, `www/middlewares/myapplogin.prg` |
| CSRF | session-bound HMAC token, TTL 3600, failure redirects to `/login` | `src/hix_csrf.prg`, `src/mw/hix_mw_csrf.prg` |
| Auth shape | `POST /auth` (form `username`,`password`) → **302 redirect**, identity written into the session under `_auth_user`; **no JSON token** | `webapp/www/controllers/auth.prg` |
| Route table | 24 routes, incl. `/customer/:id([0-9]+)`, `/users/:id([0-9]+)`, `…/edit`, `…/update`, `…/delete*` | `webapp/www/routes/web.json` |
| Disabled surface | admin panel off, `/hix-slow` → 404, `/config.json` → 404, `/test` only in `dev` | `hix.json` 44-51, `src/app.prg` |
| Spec input | **no OpenAPI/Swagger file exists** in the repo | grep: only `srs/pentest.md` mentions the word |

Consequences that shape the whole plan:

* **The route table is the authoritative attack surface.** Generate seeds from
  `webapp/www/routes/web.json` (expand `:id([0-9]+)` to two real recnos) instead of trusting
  discovery to find them. Discovery stays as a *regression check* ("nothing reachable that the
  table does not list"), not as the source of the work set.
* **There is no bearer token to extract.** Vigolium's login flow is one request + extract;
  `POST /auth` answers with a redirect and a `Set-Cookie`. So the flow is
  `extract: [{source: cookie}]` — and it is blocked by CSRF binding (§7, decision point D2).
* **`session.max = 100` is a scan hazard.** `GET /login` mints an anonymous SID with no limiter.
  A discovery/spidering pass that walks `/login` repeatedly evicts the authenticated session
  mid-scan, and later phases then silently scan as an anonymous user. See §12 stop condition S3.

---

## 4. Pace budget (the arithmetic that keeps the scan honest)

The app's limiter is per-IP and per-minute; the scanner is one IP. Staying under it is the
difference between a real result and a truncated one.

| Knob | Value | Reason |
|---|---|---|
| `--rate-limit` | `5` | 5 rps × 60 s = 300 req/min = exactly the global cap. Use **`4`** for margin (240/min). |
| `-c/--concurrency` | `4` | 64 HTTP workers exist; 4 keeps the queue shallow and the app's `monitor.alert_pct: 75` from firing. |
| `--max-per-host` | `2` | One host in scope. |
| `--rate-limit known-issue-scan=2` | phase-scoped | The nuclei phase is the burstiest; cap it alone. |
| `--scanning-max-duration` | `10m` per phase | Bound on wall-clock, independent of pace. |
| `--no-waf-pacing` | **do not pass** | The app's own 403s are the thing pacing should react to. |

Assert, do not assume: under `--events ndjson` the `scan.started` event carries the `pace` and
`phase_pace` that actually applied. The harness must read those back and fail if they differ from
the table above.

---

## 5. The automation contract (what the harness must guarantee)

One runner, `webapp/test/vigolium_scan.sh` (name TBD; local tooling, untracked like the rest of
`tests/`), which:

1. **Owns its database.** `export VIGOLIUM_DB_PATH=webapp/tmp/vigolium/session.sqlite` so every
   command in the shell reads/writes one file. A pinned path that exists but is unusable is a hard
   error in the tool — that is the point of pinning: no scan silently lands in the shared default
   database.
2. **Owns its project.** `--project-name hix-local-<branch>-<date>` so findings are attributable
   and re-runs dedupe against the same engagement.
3. **Streams events.** `--events ndjson 2>/dev/null | tee events.ndjson` and keeps the file.
   `scan.finished` is always last; **its absence means the process was killed** (CI timeout), not
   that the scan completed. The harness must treat a stream without a terminal event as inconclusive.
4. **Maps exit codes, never `|| exit 1`.** `0` clean · `1` scanner broke · `2` bad invocation ·
   `3` fuzz gate · `4` findings gate tripped. `4` is a *result*, `1` is an *outage*.
5. **Restores state** on every exit path (`set -e` + `EXIT` trap): regenerate DBF, drop `.sessions/*`,
   rotate `hix.keys.json`, delete the scratch DB unless `KEEP_DB=1`.
6. **Never blocks the pipeline.** `--soft-fail` on the scan itself; the harness decides pass/fail
   from the JSONL, so a finding never hides a later teardown step.
7. **Publishes nothing.** Reports stay on disk under `webapp/tmp/`; publishing to GitHub code
   scanning (§11) is a separate, explicitly opt-in step.

---

## 6. Phases

Each phase is independently runnable and idempotent. `Pn` names are for this document.

### P0 — Preflight (blocking)

```bash
curl -fsSL https://vigolium.com/install.sh | bash     # or: npm install -g @vigolium/vigolium
vigolium version
vigolium strategy            # authoritative strategies/intensities/phases for THIS build
vigolium module ls --list-enabled
```

Then, in order:

1. Build the framework, then the app: `HB_ROOT=… bash go_lib_gcc.sh` → `cd webapp && ./go_gcc.sh --port 9090`.
2. `curl -k https://localhost:9090/` returns 200 — the scan must not start against a dead listener.
3. Snapshot: copy `webapp/data/*.{dbf,cdx}` mtimes, list `.sessions/`, record `hix.keys.json` hash.
4. **Decide D1 (TLS).** The app is `ssl: true` with a self-signed `certs/hix.crt`. The docs show no
   `--ignore-ssl` on `scan`. Options: (a) scan `http://localhost:9090` with a separate one-request
   check that the `https` listener refuses plaintext, (b) run the app with `ssl: false` for the scan
   window only, (c) confirm empirically whether the binary trusts the local cert. Record which.
5. Fix the piolium 404s in `piolium/audit-state.json` before P7 — that is a provider/endpoint
   configuration fault, not a finding.

### P1 — Seed generation (deterministic, no network)

```bash
# routes/web.json -> urls.txt  (expand :id([0-9]+) to two real recnos, one anonymous + one per role)
jq -r '.[] | "\(.method) \(.url)"' webapp/www/routes/web.json > webapp/tmp/vigolium/routes.txt
```

Deliverable: `urls.txt` (one URL per line) + `seeds.jsonl` (method, url, middleware chain,
`scope`, expected status). This is the file the whole rest of the plan reads. It is generated,
never hand-edited — same rule as `COMPARISON-enhance-vs-main.md`.

### P2 — Sweep / surface score (one request per target)

```bash
vigolium run probe -T webapp/tmp/vigolium/urls.txt --json --no-response -c 4 \
  --scope-origin strict 2>/dev/null | tee webapp/tmp/vigolium/probe.jsonl
```

A sweep produces **records, not findings**; `0 findings` is the expected result. Read
`surface_score`, `technology`, `status_code`. Use it as the fingerprint baseline: the framework's
own headers and error pages are what later phases compare against.

### P3 — Unauthenticated native scan

```bash
vigolium scan -T webapp/tmp/vigolium/urls.txt \
  --strategy balanced --scope-origin strict \
  --rate-limit 4 -c 4 --max-per-host 2 \
  --scanning-max-duration 10m \
  --format jsonl,html,sarif -o webapp/tmp/vigolium/p3 \
  --events ndjson 2>/dev/null | tee webapp/tmp/vigolium/p3.ndjson
```

`--scope-origin strict` is mandatory: at the default `balanced` mode a scan resolves its work set
from **every stored origin in the project**, ordered by `risk_score DESC`, so an old record can be
scanned before the target and the target can go untouched under a tight duration cap.

Regression assertions this phase must produce (they are checks, not findings):

| Expect | Where |
|---|---|
| `/config.json` → 404, `/hix-slow` → 404, `/test/*` unreachable in `prod` | `hix.json` 44-51, `src/app.prg` |
| no `/hix-*` admin route resolves | `admin.enabled = false` |
| security headers present on every 200 | `secheaders` block, CSP incl. `frame-ancestors 'none'`, `base-uri 'self'` |
| session cookie carries `Secure` + `HttpOnly` + `SameSite` | `src/hix_request.prg` (scheme follows transport) |

### P4 — Authenticated scan + IDOR/BOLA

See §7 for the session file. Two roles: `admin` (primary) and a plain user (compare).

```bash
vigolium scan -T webapp/tmp/vigolium/urls.txt \
  --auth-file webapp/tmp/vigolium/auth.yaml \
  --only dynamic-assessment --scope-origin strict \
  --rate-limit 4 -c 4 --scanning-max-duration 15m \
  --format jsonl,html -o webapp/tmp/vigolium/p4
```

The `authz-compare` module replays every primary request with each compare session; that is the
BOLA/IDOR pass over `/customer/:id` and `/users/:id`. Cross-session replay is
`session.compare_enabled` in config — confirm it is on before claiming the pass ran.

Budget: each session's login consumes one of the **5 login attempts / 60 s**. Two sessions is fine;
a `reauth_interval` shorter than the scan is not.

### P5 — Known-issue scan (CVE + misconfig + secrets)

```bash
vigolium run known-issue-scan -t https://localhost:9090 \
  --known-issue-scan-tags cve,misconfig,headers --known-issue-scan-severities high,critical \
  --rate-limit kis=2 --format jsonl -o webapp/tmp/vigolium/p5
```

Plus the passive secret pass over stored traffic (`kit secret-scan --fail-on-match` → exit `3`):
the point is to prove no signing key reached the docroot or the repo (`src/hix_config_app.prg`,
`src/hix_keys.prg`, `webapp/hix.keys.json`).

### P6 — HIX-specific JS extensions

Built-in modules will not know HIX's own invariants. Plan the extensions (write them in the
implementation phase, not now):

| Extension | Checks | Anchors |
|---|---|---|
| `csrf-binding.js` | a CSRF token harvested from an anonymous `GET /login` is rejected in another session | `src/hix_csrf.prg`, `src/mw/hix_mw_csrf.prg` |
| `session-fixation.js` | the pre-login SID never survives `POST /auth` | `www/controllers/auth.prg` (`USessionRotate`) |
| `flash-leak.js` | a flash message set in one session is never readable in another | `UFlash()` |
| `role-escalation.js` | `roles` mass-assignment on `/users/store`, `/customer/store` | `middleware/config.json` `roles_key: roles` |
| `path-traversal.js` | `..` in path params against the docroot | `PENTEST-REPORT §1` |

Run with `--only extension --ext-dir webapp/tmp/vigolium/ext` (or `--ext <file>`), and
`vigolium ext eval` / `vigolium ext example` to prototype.

### P7 — Agentic (source-aware) — container-only

```bash
# structured, repeatable: agent directs the native scanner
vigolium agent swarm -t https://localhost:9090 --source . --intensity balanced \
  --code-audit --triage --discover --max-duration 20m --format jsonl -o webapp/tmp/vigolium/p7

# source audit only, reusing the piolium harness already in this repo
vigolium agent audit --driver piolium --mode balanced --source . --commit-depth 26

# PR/commit-focused review, cheap
vigolium agent autopilot --source . --last-commits 5 --intensity quick --audit off
```

Hard precondition: run these inside a disposable container with only the repo mounted, no SSH keys,
no cloud credentials, outbound restricted to `localhost:9090` + the provider endpoint. The agent
reads HTTP responses from the target into its context; assume the target can try to take over the
agent.

### P8 — Triage and reporting

```bash
vigolium finding --min-severity medium --with-records -j -o webapp/tmp/vigolium/findings.json
vigolium agent triage <finding-id>          # per finding: confirm or retire, updates verdict in place
vigolium export --format html,markdown,sarif -o webapp/tmp/vigolium/report
```

An export that was never written now exits `1` with `error.code: "export_failed"` and **outranks**
the `--fail-on` gate — retry the export, not the scan.

### P9 — Teardown

Restore per §1 rule 6, delete the scratch DB, and re-run the existing suites
(`tests/run.sh`, `webapp/test/verify-users-fixes.sh`) to prove the scan did not leave the app in a
mutated state.

---

## 7. Session file sketch (decision point D2)

`POST /auth` is CSRF-gated: the middleware rejects a token that fails `HixCsrfBound()` when a
session is present, and the token is bound to the session that was served it. Vigolium's login
flow is **one** request (`login: {url, method, body, extract}`), so it cannot do
`GET /login` → scrape token → `POST /auth`. Options, pick one and record it:

| Option | How | Cost |
|---|---|---|
| **A. Static cookie** (default) | Log in once with `curl` (GET `/login` → extract CSRF → POST `/auth` with it), capture `FENIXSID`, write it into the auth file as a static header | Session TTL 3600 s; must re-mint per run; the harness owns the 3-line curl |
| B. Dev-mode bypass | run the app with a test middleware that skips `CsrfCheck` | Changes the thing under test — invalidates the audit |
| C. Extension-driven auth | a JS extension performs the two-step login and sets headers | More code, but keeps the real CSRF path |

Option A sketch (`webapp/tmp/vigolium/auth.yaml`, resolved from `session_dir` if not absolute):

```yaml
sessions:
  - name: admin
    role: primary
    headers:
      Cookie: "FENIXSID=${ADMIN_SID}"
  - name: carles
    role: compare
    headers:
      Cookie: "FENIXSID=${USER_SID}"
```

`${VAR}` interpolation is honoured in config/session files; the SIDs come from the harness, never
committed.

---

## 8. Artifact layout and git policy

```
webapp/tmp/vigolium/            # gitignored by the existing **/tmp/* rule
├── urls.txt  seeds.jsonl       # generated (P1)
├── auth.yaml                   # generated per run, never committed (holds live SIDs)
├── probe.jsonl  p3.ndjson …    # event streams
├── session.sqlite              # VIGOLIUM_DB_PATH; deleted on teardown unless KEEP_DB=1
└── p3.jsonl p3.html p3.sarif   # exports
```

Nothing under this path is committed (the `.gitignore` rule `**/tmp/*` already covers it). The
**plan** is committed; the **run output** is not. Committed artifacts are the derived reports only,
and only when they change a defect record — those go into `webapp/srs/` as a dated report
(`VIGOLIUM-REPORT-<date>.md`), following the `TEST-REPORT-2026-10-06.md` precedent: produced by
the run, never hand-edited.

---

## 9. Exit-code mapping (the harness's `case` block)

```bash
vigolium scan … --fail-on high --soft-fail --format jsonl -o p3
case $? in
  0) verdict="clean-or-gate-not-tripped" ;;
  4) verdict="findings-at-or-above-high" ;;   # ran to completion; a result, not a failure
  2) verdict="bad-invocation"; hard_fail ;;
  *) verdict="scanner-outage"; hard_fail ;;   # 1: it never got that far
esac
```

`--soft-fail` forces `0`, so with it the verdict must come from the JSONL/`scan.finished`
`findings_by_severity`, not from `$?`. Choose one of the two, not both.

---

## 10. Finding → corpus mapping

A finding is only "new" if it is not already closed in the corpus. Before writing anything down:

| Vigolium output | Maps to | Action |
|---|---|---|
| `authz-compare` on `/users/:id`, `/customer/:id` | `BF-*` / `PENTEST-REPORT` BOLA sections | confirm or regress |
| missing/weak security header, cookie flags | `PENTEST-REPORT §4` | regression check |
| path traversal / docroot file | `PENTEST-REPORT §1` | regression check |
| JWT/secret disclosure, key in `config.json` | `src/hix_keys.prg` rules | regression check |
| CSRF token transfer | `src/hix_csrf.prg` enhancement | regression check |
| anything else | new defect id `V-nn` in a dated report | new |

Every row must carry: module id, URL, request, response, timestamp, and the source line. A finding
with no source line is a false positive by this repo's own standard (`pentest.md`: "do not
hallucinate").

---

## 11. CI wiring (optional, local/private sink only)

A new workflow file (`.github/workflows/scan.yml`) must not trigger `docs.yml` (that one is
path-gated to `site-docs/**` and `mkdocs.yml`, so it is safe by construction). Shape:

```yaml
- name: build + boot app            # HB_ROOT=… bash go_lib_gcc.sh; ./go_gcc.sh --port 9090
- name: native scan
  run: vigolium scan -S -t https://localhost:9090 --strategy lite --soft-fail \
       --format sarif,jsonl -o results
- name: upload SARIF                # only if the repo's Code Scanning setting allows it
  uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: results.sarif }
```

Notes: `-S` (stateless) in CI keeps the run off the shared DB; `--strategy lite` skips browser
spidering; findings carry stable `partialFingerprints` so GitHub tracks one alert across re-scans.
Given this repo's push-disabled remote, treat SARIF upload as **off by default** and keep the
artifact local.

---

## 12. Stop conditions

| # | Condition | Action |
|---|---|---|
| S1 | `waf.block` event for the host | The app's own limiter is filtering scan traffic. **Results for that host are incomplete** — do not publish a clean bill of health. Slow down and re-run, or mark inconclusive. |
| S2 | `phase.progress` stops advancing `requests_sent` for > 2 min | HIX worker wedge. Kill, capture the last event, run `tests/run.sh` to see app state. |
| S3 | authenticated session evicted mid-scan (`.sessions/sess_*` count reaches `max: 100`) | Later phases are scanning anonymously. Abort, re-mint SIDs, reduce anonymous `GET /login` traffic (exclude `/login` from discovery seeds). |
| S4 | login limiter tripped (5/60) | Abort the auth phase; do not retry — retrying is brute force against our own limiter. |
| S5 | `scan.finished` absent in the NDJSON | Process killed (timeout/SIGKILL). Inconclusive, not clean. |
| S6 | any `error` event | Non-fatal by construction — the scan carried on. Record it; the phase's coverage is partial. |

---

## 13. Build order (task list for the implementation phase)

1. P0 install + verify + TLS decision (D1).
2. Seed generator from `routes/web.json` → `urls.txt` + `seeds.jsonl`.
3. Snapshot/teardown script (must pass standalone before any scan runs).
4. Runner skeleton: DB pinning, project name, `--events ndjson`, exit-code `case`, `EXIT` trap.
5. P2 probe → fingerprint baseline recorded.
6. P3 unauthenticated scan + the four regression assertions in §3.
7. Auth minting (option A) + P4 IDOR pass.
8. P5 known-issue + secret pass.
9. P6 extensions (five, per §6).
10. P7 agentic in a container (only after 1–9 pass).
11. P8 triage loop + report; write `VIGOLIUM-REPORT-<date>.md` into `webapp/srs/` if anything is new.
12. P9 teardown + re-run existing suites.
13. CI workflow (last; optional; SARIF upload off).

## 14. Open questions to settle before implementing

* **D1 TLS** — how does the installed build treat the self-signed local cert (§6 P0, step 4)?
* **D2 Auth** — static cookie (A) vs extension-driven two-step login (C) (§7).
* **D3 OAST** — out of scope by the localhost rule; if blind-XSS/SSRF coverage is required, it needs
  a **local** callback endpoint, which must be built, not assumed.
* **D4 Database** — one pinned session DB per run, or one shared engagement DB with
  `--project-name` isolation? (Shared DB needs `--db-isolate` if any phase runs `-P`.)
* **D5 Agentic scope** — is running `vigolium agent` acceptable on this machine at all, or
  container-only from the start? Upstream's own guidance says container.
* **D6 Version drift** — pin the installed `vigolium version` in the report header; the flag names
  in this plan are from the 2026-10-07 docs and several were renamed across releases.
