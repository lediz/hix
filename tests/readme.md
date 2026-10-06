# HIX test suite — `tests/`

One entry point, many slices, bounded output.

`tests/run.sh` runs the whole suite: the HIX framework unit tests, the
webapp functional suites, the Harbour probes, and repository hygiene
checks. It never prints more than a fixed number of bytes, so a full run
fits a 64K context window. Everything it observes is written to
`tests/.out/` uncapped, and `tests/slice.sh` fetches any part of it.

Every failure it reports carries a **class**: counted against the code
under test, or explained by evidence that says it is the test script, the
tool, the machine, or the slicing itself. See *How a failure stops being a
defect*.

**This suite reports. It does not fix.** Nothing under `tests/` patches,
regenerates, or repairs the framework, the webapp, or the pre-existing
test scripts. It runs what exists, parses what comes out, and states what
it saw. Where a result is a defect of the code under test, it is listed
under *What the suite currently observes* — untouched.

---

## Layout

```
tests/
  run.sh              the whole suite, sliced          <- start here
  index.sh            re-render the index of the last run, run nothing
  slice.sh            drill into one slice: --cases --log --digest --class --grep
  clean.sh            remove tests/.out
  lib/
    common.sh         paths, env resolution, hix_case, hix_parse, hix_classify
    cap.sh            the byte-budget filter every stdout goes through
    rules.tsv         the only thing allowed to call a failure "not a defect"
    classify.awk    <id>.tsv   -> <id>.cls.tsv: class + basis per row
    index.awk         aggregates the classified rows into the index table
    count_class.awk   one per-slice summary line (used by slice.sh --list)
    parse_unit.awk    `tests/unit/app --cli` output  -> case rows
    parse_wa.awk      webapp suite output            -> case rows (3 modes)
  slices/
    s00_preflight.sh  toolchain, binaries, config, server reachability
    s05_build.sh      --check: are the artifacts present and fresh
                    --framework/--unit/--app: build them (only with --build)
    s07_harness.sh    re-proves, on this tree for this run, every claim a
                    rule in lib/rules.tsv rests on -> .out/checks.tsv
    s10_fw_unit.sh    one file, one filter: Core, Routing, HixStyle, AUTH,
                    Middleware, Transport, Network, Views, Other, Extras,
                    A01, A02, A03, all
    s20_wa_http.sh    webapp/test/{test_users_module,test_customer_module,
                    verify-users-fixes}.sh
    s21_wa_bf.sh      webapp/test/bf_harness.sh phases bf01..bf10 (--bf only)
    s22_wa_probe.sh   webapp/probe_{entropy,hash,pwcost,fmode,seek}
    s30_repo.sh       secrets, .gitignore coverage, portable paths,
                    generated artifacts, runtime file modes, DBF residue
  .out/               evidence (gitignored)
```

---

## Running it

```bash
./tests/run.sh                      # framework + webapp + hygiene
./tests/run.sh --list               # the slice plan, run nothing
./tests/run.sh --fw                 # framework unit slices only (~26s)
./tests/run.sh --wa                 # webapp slices only
./tests/run.sh --bf                 # add the 10 brute-force phases (slow)
./tests/run.sh --build              # compile framework / unit app / webapp first
./tests/run.sh --fw-ref             # + the whole unit suite in one process, as reference
./tests/run.sh --no-fw-ref          # without it, slice-order failures stay counted
./tests/run.sh 33-wa-verify         # one slice
./tests/run.sh --fail-only          # index lists failing cases only
./tests/run.sh --strict             # also fail on failures blamed on harness/tool/env
./tests/run.sh --fresh              # wipe tests/.out first
./tests/run.sh --budget 8000        # shrink stdout further
./tests/run.sh --no-server          # never start webapp/app
```

Drilling into evidence:

```bash
./tests/index.sh                                 # index of the last run
./tests/slice.sh 33-wa-verify --cases --status FAIL
./tests/slice.sh 32-wa-customer --log --grep 'T1[0-9]'
./tests/slice.sh 11-fw-routing --digest --full   # the slice's own summary
./tests/slice.sh 33-wa-verify --log --from 200 --lines 40
./tests/slice.sh --list                          # slices that actually ran
```

Asking the only question that matters — *is this a real failure?*

```bash
./tests/slice.sh 11-fw-routing --cases --class triage   # unexplained failures
./tests/slice.sh 32-wa-customer --cases --noise         # explained, not counted
./tests/slice.sh 32-wa-customer --cases --defect        # counted against the code
./tests/slice.sh 33-wa-verify --cases --class harness --grep 'H-05'
```

Exit codes: `0` no defect, `1` a defect (or, with `--strict`, a failure
attributed to harness/tool/env/slice-order), `2` a slice could not run
(missing binary, missing server, bad slice id).

---

## How the 64K budget is enforced

Three layers, all in `lib/`:

1. **Per slice.** Each slice writes uncapped evidence to
   `tests/.out/<id>.raw` / `.log`, and exactly one TSV row per case to
   `tests/.out/<id>.tsv`; `lib/classify.awk` adds `tests/.out/<id>.cls.tsv`
   with the class and basis of every row. Its own stdout is a *digest* —
   totals, the suite's self-reported counts, and the failing rows — capped
   at 16 KB.
2. **Aggregation.** `lib/index.awk` folds every slice's classified rows
   into one table (cases / pass / fail / skip / error / note / **defect** /
   **noise** / seconds / verdict per slice), a TOTAL row, the reference run
   separately, each slice's exit code, each suite's own self-reported
   assertion counts, and the three failure lists. A full run's index is
   ~20 KB.
3. **stdout.** `run.sh` pipes the index through `lib/cap.sh --budget 65536`.
   If the output would exceed the budget, `cap.sh` keeps a head and a tail
   slice and prints a marker naming the uncapped file. Everything cap.sh
   emits goes to stdout — the report line first, then the body — and the
   report is counted against the budget, so a run never emits more than
   `--budget` bytes:

   ```
   [cap] 266 lines / 18966 bytes - within the 65536 byte budget
   ```

   With a budget too small to hold anything else:

   ```
   [cap] 266 lines / 18966 bytes -> capped to 400 bytes
   HIX TEST SUITE - index
   >>> TRUNCATED by cap.sh: 264 of 266 lines elided (18862 of 18966 bytes).
       full index: tests/.out/index.txt - drill in with tests/slice.sh <id>
   ```

`slice.sh` runs every view through the same filter, so drilling in cannot
blow the window either — it tells you what is still on disk. `--full`
disables the cap for a human at a terminal.

A slice that produces no case rows at all is not silently dropped: its id
appears in the index under *produced no case rows* with the tail of its
digest.

---

## How a failure stops being a defect

Every case row carries a status and, for a failure, a **class**. The class
is what decides whether the failure counts against the code under test:

| class | meaning | counts? |
|---|---|---|
| `product` | the code under test is wrong | yes |
| `triage` | no rule explained it — still a failure, flagged as unclassified | yes |
| `harness` | the project's own test script is what is wrong | no |
| `tool` | an external tool is missing, or is Windows-only | no |
| `env` | machine, config or leftover state, not the code | no |
| `order` | artifact of running a framework group in its own process | no |

A failure is counted unless something *evidences* otherwise. Three pieces
enforce that:

1. **`lib/rules.tsv`** — one row per demotion:
   `rule-id ⇥ case-regex ⇥ detail-regex ⇥ class ⇥ check-id ⇥ reason`.
2. **`slices/s07_harness.sh`** — every rule names a check that re-proves
   the claim on *this* tree for *this* run (grep the test script, look at
   the mock's method list, count the cookie jars). It writes
   `tests/.out/checks.tsv`; `07-harness` is an `env` slice, so it is never
   optional and always runs first.
3. **`lib/classify.awk`** — applies, first match wins: a rule whose check
   says `ok` this run → that rule's class (`basis rule:<id>+<check>`); the
   same case `PASS`ing in the reference run `09-fw-all` → `order`
   (`basis ref-pass:09-fw-all`); the class the slice asserted
   (`basis asserted`); otherwise `triage` (`basis unexplained`).

Two consequences worth stating plainly:

* **A rule whose check no longer holds is inert.** If someone fixes
  `test_customer_module.sh` so it saves its cookie jar, `customer.cookie.jar`
  stops reporting `ok`, the rule stops firing, and those 28 failures come
  back as `triage` and fail the suite. `rules.tsv` cannot be used as a
  place to hide regressions.
* **Nothing is dropped.** Every failure appears in exactly one of the
  index's three lists — *defects*, *unexplained*, *not defects* — and a
  noise row cites the rule and the check that justified it.

`--no-fw-ref` removes the reference run, and with it the `order` class:
every framework failure stays counted. That is the honest default when you
want to know what the slices say on their own.

---

## Slice map

| id | runs | cases | notes |
|---|---|---|---|
| `00-preflight` | toolchain, hbmk2, HB_ROOT/HB_INCLUDE, unit binary + cert, app binary, config, keys, data files, server reachability, TLS-only | 40 | gates everything else |
| `05-artifacts` | `hix_server.hbx`, `lib/*/libhix_server.a`, `tests/unit/app`, staleness vs. sources | 6 | |
| `07-harness` | re-proves each `lib/rules.tsv` check: mock method list, `curl.exe`, hardcoded `API=`, cookie jars, DBF residue writers | 5 | gates every demotion |
| `09-fw-all` | `tests/unit/app --cli` with no filter | 154 | the reference for the group slices (on by default, `--no-fw-ref` to drop) |
| `10-fw-core` … `22-fw-audit-a03` | `tests/unit/app --cli <filter>`, one process per group | 5–29 each | see *order dependence* |
| `30-repo` | secrets tracked/ignored/ever-added, `/home/...` in tracked files, compiler output tracked, runtime file modes, `users.dbf` residue rows | 18 | |
| `31-wa-users` | `webapp/test/test_users_module.sh` | 46 planned, 3 rows | aborts today, see observations |
| `32-wa-customer` | `webapp/test/test_customer_module.sh` | 52 | |
| `33-wa-verify` | `webapp/test/verify-users-fixes.sh` (D-01…D-16) | 127 | slowest slice: rate-limit aware |
| `34..38-wa-probe-*` | `webapp/probe_*.hbp` binaries, ANSI stripped | 3–7 | entropy, hash, pwcost, fmode, seek |
| `40..49-wa-bf*` | `webapp/test/bf_harness.sh` phases BF-01…BF-10 | — | only with `--bf` |

Case counts are from the run recorded under *What the suite currently
observes*; they move with the code under test, not with this suite.

---

## What the suite currently observes

The per-cluster root-cause analysis and fix recommendations live in
`webapp/srs/TEST-REPORT-2026-10-06.md`; this section is what the suite
itself recorded, in its own words.

Measured on the `enhance` branch, tree `d8d1d1a`, 2026-10-06, with
`./tests/run.sh --fresh`: 25 slices, 415 case rows, 323 pass, 48 fail,
12 error, 32 note, 501 s wall clock, 19.0 KB of stdout against a 65536
byte budget. Of those failures, **9 are counted as defects (5 of them
still unexplained) and 51 are attributed** — `order=15 + harness=41 +
tool=2` — each one citing the rule and the check that justified it.
Reported, not repaired.

**1. The framework unit suite is order dependent — 15 rows, class `order`.**
Run whole (`09-fw-all`) it reports 1981 assertions, 1972 passed, 9 failed.
Run as independent group slices it adds failures that do not exist in the
whole-suite run: `Routing/Router`, `Routing/RouteStream`,
`Routing/OptionalParam`, `Middleware/MwFlush`, `Audit/A0102`, `Audit/A0103`
die with `[EXCEPTION] Argument error`; `HixStyle/Acl` (5 assertions) and
`Other/Abort` (4) get HIX error `3012` where the whole run gets 200/403.
Each group slice is a separate process, so state an earlier group leaves
behind is gone. `classify.awk` calls these `order` only because the same
group is `PASS` in `09-fw-all` (`basis ref-pass:09-fw-all[/group]`); run
with `--no-fw-ref` and all 15 stay counted. `09-fw-all` is the number to
quote, the group slices are the number to investigate.

**2. What the unit suite really fails** (`09-fw-all`, after the mock and
the tool are taken out):

```
Audit/A0116 :: A1.16: HIX_ConfigAppDefaults() genera clave jwt distinta
                en cada llamada        Expected: distinct  Got: SAME-KEY
Audit/A0116 :: clave generada tiene >= 32 chars   Expected: >=32  Got: 0
```

These stay `triage` on purpose: the test demands that `HIX_ConfigAppDefaults()`
return a generated `keys` section, and `src/hix_config_app.prg` deliberately
has none ("NO `keys` section here (PENTEST-REPORT.md §1)" — secrets come from
`HIX_KeySet()` or `HIX_KeysLoadFromAppConfig()`, in memory only). The suite
cannot prove which side is wrong, so it counts the failure instead of
explaining it. Everything else in the unit suite is attributed:

```
harness  Routing/Request  Transport/Chunked  Transport/Multipart
         Network/Proxy    Network/Proxied    Network/Accept   (6 groups)
         TMockIO does not answer: Drain hSocket hSSLSession lConnClosed
         lUseSSL oSslMutex PeerAlive  (check mock.io.stale)
tool     Transport/SSL    SSL: curl.exe no localizado — tests HTTPS saltados
         (check curl.exe.windows)
```

**3. Both webapp functional suites address the app over plain http.**
`webapp/hix.json` has `"ssl": true`, so:

- `31-wa-users` — `API="http://localhost:9090"` is hardcoded, the suite
  aborts with `rc=2`, 0 tests run. Class `harness`
  (`wa.users.abort` / check `users.api.hardcoded`): the script ignores
  `TEST_API`, the app is fine.
- `32-wa-customer` — honours `TEST_API`, and the slice points it at
  `https://localhost:9090`, but its cookie handling is one-sided: T08
  writes the jar with `--cookie-jar` from an *unauthenticated* POST, T09
  sends `--cookie` only, so the session cookie of the successful login is
  never stored. T01–T09 pass; T10–T36 and T44 fail with 302 — 28 rows,
  all class `harness` (check `customer.cookie.jar` counts the
  authenticating POSTs that send a CSRF token and save no jar).
- `33-wa-verify` — 127 cases, 123 pass, **3 fail, all counted**:
  `D-09f rejected rename left record 2 unchanged` (expected `carles`, got
  `carlesX`), `D-16d mixed-case seed name logs in as JOHN` (200 expected,
  302 got), `H-05c session files written by this run are 0600`
  (expected 0, got 22). It is the only suite that authenticates
  successfully against the TLS app.

**4. Runtime file modes — counted twice from two sides.** `webapp/.sessions`
is `0700` but the session files inside it are `0644` (`30-repo`
`perm.session_files` FAIL), and `33-wa-verify` `H-05c` sees the same thing
through the app.

**5. Secret material one `git add -A` away.** `tests/unit/hix_test.crt`
and `tests/unit/hix_test.key` are untracked and matched by no
`.gitignore` (`secret.untracked`, `ignore.*` FAIL — 3 counted rows).
`webapp/hix.keys.json` and `webapp/certs/hix.key` are `0600` and ignored
(PASS). Git history has seen those two test files added at some point
(`secret.history` NOTE).

**6. `users.dbf` residue.** 10 rows, 0 residue rows (`data.residue` PASS)
at the time of this run. The rule that would class residue `env`
(check `test.rows.are.test.rows`) stands ready but had nothing to explain.

---

## Cost

On this machine, `./tests/run.sh` (framework + webapp, app already
running): 501 s, of which `33-wa-verify` is 444 s — it is rate-limit aware
and sleeps between requests. `--fw` alone is 26 s. `--build` adds the
compile steps. `--bf` adds the brute-force phases, which are bounded by
the app's own lockout timings.

---

## Adding a slice

1. Write `tests/slices/sNN_<name>.sh`:

   ```bash
   #!/usr/bin/env bash
   set -uo pipefail
   . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
   hix_slice_init "${SLICE_ID:-42-my-slice}"     # creates $HIX_TSV / $HIX_LOG
   hix_env_init                                   # HB_ROOT, HB_INCLUDE, ${hix}

   hix_case "my.check" PASS "detail"              # PASS | FAIL | SKIP | NOTE | ERROR
   ...
   ```

   Run the thing under test into `$HIX_OUT/<id>.raw`, then
   `HIX_SLICE=$id hix_parse parse_wa.awk "$HIX_LOG"` (or `parse_unit.awk`)
   to turn its output into case rows, and finish with a capped digest:

   ```bash
   { echo "my slice - $(grep -c . "$HIX_TSV") cases"
     awk -F'\t' '{c[$3]++} END{for(k in c) printf "  %-6s %d\n", k, c[k]}' "$HIX_TSV"
   } | hix_digest
   ```

2. Register it in `run.sh`'s plan:

   ```bash
   add 42-my-slice wa "$HERE/slices/s42_my.sh"
   ```

Rules a slice must keep: uncapped evidence to `$HIX_OUT`, one TSV row per
case, capped digest to stdout, never write outside `$HIX_OUT`, and never
change the code under test.

3. If a slice's failure is *not* the code's fault, it does not become
   noise by asking nicely — it takes two entries, one in each table:

   ```
   lib/rules.tsv    my.rule <TAB> case-regex <TAB> detail-regex <TAB> harness <TAB> my.check <TAB> why
   slices/s07_harness.sh   check my.check 0 "what it explains" "the evidence, gathered now"
   ```

   The check must be a fact about the harness, the tool or the machine —
   never about HIX — and it must fail again the moment the underlying
   problem is fixed, so the rule cannot outlive its own justification.
