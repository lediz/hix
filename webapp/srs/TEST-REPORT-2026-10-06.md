# HIX test suite — failure report and fix recommendations

Run: `./tests/run.sh --fresh`
Tree: `d8d1d1a` (branch `enhance`) · started 2026-10-06T21:18:11+08:00 · elapsed 499 s
Result: **25 slices, 415 case rows, 324 PASS, 48 FAIL, 12 ERROR, 31 NOTE** — `run.sh` exit **1**
(no slice aborted: every recorded rc is 0 or 1)
Of the 60 failing rows the suite counts **9 as defects (5 still unexplained)** and
attributes **51** — `order=15 + harness=41 + tool=2` — each citing the rule and the
check that justified the demotion. The reference run `09-fw-all` adds 7 attributed
rows of its own; it is reported separately and never folded into TOTAL.
Evidence: `tests/.out/` (uncapped `.raw` / `.log` / `.tsv` per slice, `<id>.cls.tsv`
with the class and basis of every row, `checks.tsv`, `index.txt`, `run.log`)

**This document reports. It changes nothing in the code under test.** No file under
`src/` or `webapp/` was modified while producing it. Every claim below is tied to a
recorded evidence row or a `file:line` in the tree as it stands. What *did* change is
`tests/` itself: the reporting defects listed under C9 were fixed in the suite, which
is why the row counts below are lower than in the first run of this report — the same
failures, counted once and classified.

---

## 1. How to read the failures

The 60 failing rows are not 60 defects. They collapse into **9 clusters**, and the
suite now classifies every one of them itself: a row is counted (`product`, `triage`)
unless a rule in `tests/lib/rules.tsv` explains it, and every rule cites a check that
`tests/slices/s07_harness.sh` re-proves against this tree for this run.

| # | Cluster | Rows | Class | Nature | Where the fix belongs |
|---|---|---|---|---|---|
| C1 | `Message not found` — mock IO missing `Drain`/`PeerAlive`/`lUseSSL`/… | 12 (6 tests in `09-fw-all` + the same 6 in their group slices) | `harness` | **test mock gap** over a framework API that moved | `tests/unit/src/hix_test_utils.prg` (TMockIO) |
| C2 | `Argument error` (Harbour EG_ARG/3012) — state an earlier group left behind | 15 | `order` | **latent initialization**, invisible in a single-process run | `src/hix_zombie.prg`, `src/hix_router.prg` |
| C3 | `Audit/A0116` — defaults vs. key generation | 4 (2 assertions × `09-fw-all` and `20-fw-audit-a01`) | `triage` | **test contract vs. framework intent, unresolved** | decision: `tests/unit/src/hix_test_audit.prg` *or* `src/hix_config_app.prg` |
| C4 | `Transport/SSL` — HTTPS tests never run | 2 | `tool` | **coverage hole**, reported as FAIL | `tests/unit/src/hix_test_ssl.prg` |
| C5 | `31-wa-users` — suite aborts, 0 tests run | 1 | `harness` | **test script** hardcodes plain http | `webapp/test/test_users_module.sh` |
| C6 | `32-wa-customer` — 28/50 fail | 28 | `harness` | **test script** one-sided cookie jar | `webapp/test/test_customer_module.sh` |
| C7 | `33-wa-verify` — 3 failures | 3 | `triage` | 2 = **stale fixture / launcher umask**, 1 = launcher umask | `webapp/data/`, launcher, and the suite |
| C8 | `30-repo` — 4 hygiene FAILs | 4 | `product` | 2 = **missing .gitignore rules**, 2 = umask (C7) | `.gitignore`, launcher |
| C9 | Harness reporting defects | — | — | **the suite's own reporting** — fixed, see §10 | `tests/lib/`, `tests/slices/` |

Two properties of the harness shape every number in this document:

* **One row per failure.** A failing unit test used to emit a `FAIL (n)` summary row
   *and* a `:: <assertion>` detail row. `lib/parse_unit.awk` now suppresses the summary
   when its `n` detail rows all appear, and suppresses the phantom `:: ERROR` assertion
   a group raises on an exception. `09-fw-all` reports 9 failing rows for 9 failing
   tests; the 60 rows above are 60 failures, not an inflated count.
* **The unit suite is order dependent — and the suite now says so per row.** Run whole,
   `09-fw-all` reports 3 FAIL + 6 ERROR. Run as independent group slices it adds 15 rows
   across 8 tests that the whole-suite run does not report. `lib/classify.awk` calls
   them `order` only because the same group is `PASS` in `09-fw-all`
   (`basis ref-pass:09-fw-all[/group]`); with `--no-fw-ref` all 15 stay counted:

  ```
  11-fw-routing   Routing/Router  Routing/RouteStream  Routing/OptionalParam   ERROR  Argument error
  14-fw-mw        Middleware/MwFlush                                              ERROR  Argument error
  12-fw-hixstyle  HixStyle/Acl (5 assertions)                                   FAIL   Got: 3012
  18-fw-other     Other/Abort (4 assertions)                                    FAIL   Got: 3012
  20-fw-audit-a01 Audit/A0102  Audit/A0103                                      ERROR  Argument error
  ```

  `order` means "this failure is an artifact of how the suite was sliced", not "this is
  fine". A group that only passes after another group has run is exactly the C2
  fragility: quote `09-fw-all` for the framework's state, and treat the group slices as
  the list of latent initialization bugs a single-process run happens to hide.

---

## 2. Cluster C1 — `Message not found` (6 unit tests, both runs)

**Failing rows** (`09-fw-all`, and the matching group slices):

```
Routing/Request      [EXCEPTION] Message not found
Transport/Chunked    [EXCEPTION] Message not found
Transport/Multipart  [EXCEPTION] Message not found
Network/Proxy        [EXCEPTION] Message not found
Network/Proxied      [EXCEPTION] Message not found
Network/Accept       [EXCEPTION] Message not found
```

**Root cause — confirmed.**
`src/hix_request.prg:222`, inside `THixRequest:Read()`:

```harbour
::cProtoScheme := iif( ::oIO != NIL .AND. ::oIO:lUseSSL, "https", "http" )
```

`THixRequest` now reads `lUseSSL` off the IO channel on **every** `Read()`. The test
double for an IO channel, `CLASS TMockIO` in `tests/unit/src/hix_test_utils.prg:19-33`,
declares `cHeaderData cBodyData cWritten lClosed lWriteFail` and **no `lUseSSL`**.
Harbour resolves a missing instance variable as a message send and falls through to the
class `MSGNOTFOUND` handler (`harbour/src/rtl/tobject.prg:77`, `::Error( "Message not
found", … )`) — which is exactly the string the harness prints.

All six tests build `THixRequest():New( TMockIO … )` and call `Read()`:
`hix_test_request.prg:55`, `hix_test_chunked.prg:68`, `hix_test_multipart.prg:55`,
`hix_test_proxy.prg:31`, `hix_test_proxied.prg:25`, `hix_test_accept.prg:25`.

**Independent confirmation of the exact statement.** `hix_test_multipart.prg` logs its
own progress to `tests/unit/traces/info.txt`. After `./app --cli Multipart` the file
contains only:

```
[Multipart] === HIX_TestMultipart_Run start ===
```

i.e. the exception fires inside the first `_ParseReq()` → `Read()`, before any assertion
is recorded. `THixIO` (`src/hix_io.prg:21`, `:72`) does define `lUseSSL`, which is why
the real server path is unaffected and only mock-based tests break.

**Recommendations (in this order).**

1. **Framework guard — the real fix.** `THixRequest:Read()` must not require an IO
   object to expose `lUseSSL`. `THixRequest:oIO` is public API: any application or
   adapter that supplies its own channel object (the pattern the tests use) breaks with
   an opaque runtime error. Make the lookup total, e.g. test `HB_ISOBJECT( ::oIO )`
   and read the flag through a `PeerAlive()`-style INLINE that tolerates absence, or
   move the scheme decision behind a method `oIO:IsTLS()` with a documented default.
   This also removes the class of bug where a new `THixIO` DATA silently becomes a
   required member of every IO implementation.
2. **Test mock — the fast unblock.** Add `DATA lUseSSL INIT .F.` to `TMockIO`
   (`tests/unit/src/hix_test_utils.prg:24`). One line, restores 6 tests × 2 runs.
   Do this *and* 1; 2 alone leaves the API break in place.
3. **Add a contract test.** A single assertion that `THixRequest():New(oIO)` works
   against a minimal IO object (only `ReadHeaders/Read/Write/WriteChunk/WriteChunkEnd/
   Close`) would have caught this at the commit that introduced `lUseSSL` in `Read()`.

---

## 3. Cluster C2 — `Argument error` / subcode 3012 (8 tests, group slices only)

**What 3012 is.** Harbour raises `EG_ARG` with subcode **3012** when a mutex/thread API
gets a NIL handle — `harbour/src/vm/thread.c:1832` (`hb_mutexParam` →
`hb_errRT_BASE_SubstR( EG_ARG, 3012, … )`). The harness prints the description
("Argument error"); the Acl and Abort tests print the numeric subcode they captured from
the exception object (`hix_test_hixstyle_acl.prg:29`, `hix_test_abort.prg:68-72`), which
is why the index shows `Got: 3012` where a status code was expected.

**Two uninitialized statics are responsible.**

*a) Router.* `s_mtxRoutes` is created **only** inside `HIX_RoutesLoad()`
(`src/hix_router.prg:58`, `:68`). Twelve call sites lock it; only two guard it.

| function | line | NIL guard? |
|---|---|---|
| `HIX_RoutesSnapshot()` | 463 → lock 467 | **no** |
| `HIX_RoutesRestore()` | 473 → lock 475 | **no** |
| `HIX_RouteAdd()` | 343 → lock 403 | **no** |
| `HIX_RouteDelete()` | 484 → lock 486 | **no** |
| `HIX_RouteGroup()` | 550 → lock 560 | **no** |
| `HIX_RouteDispatch()` | 639 → lock 657 | **no** |
| `URoute()` | 763 → lock 776 | guarded at 777 |
| `HIX_RouteList()` | 503 → guard 512 | guarded |

`HIX_RoutesIsInit()` exists at `src/hix_router.prg:113` and the guard idiom is already
written down in a comment at `:509-511` — it is simply not applied at the write sites.

Direct hits: `hix_test_router.prg:78` (`hSnap := HIX_RoutesSnapshot()` is the *first
statement* of the test), `hix_test_route_stream.prg:41`, `hix_test_optional_param.prg:43`,
`hix_test_mw_flush.prg:58` (all `HIX_RouteAdd`).

*b) Zombie store.* `s_hMutex` is created only in `HIX_ZombieInit()`
(`src/hix_zombie.prg:28`). `HIX_ZombieAdd/Dead/Count/Report/Purge` (`:45 :72 :102 :123
:155`) lock it unguarded. Inside the framework the only caller of `HIX_ZombieInit()` is
`src/hix_server.prg:268` (i.e. `THixServer:Start()`), while
`THixDispatcher:Dispatch()` calls `HIX_ZombieCount()` at `src/hix_dispatcher.prg:297`.
**Consequence: using `THixDispatcher` without ever starting a `THixServer` aborts.**
That is exactly what `HixStyle/Acl` (5 assertions), `Other/Abort` (4 assertions),
`Audit/A0102` (`hix_test_audit.prg:239` `oDisp:Dispatch`) and `Audit/A0103`
(`:331`) do. In the whole-suite run they pass only because `Core/Server` started a
server first and left the zombie mutex alive.

`hix_test_audit.prg:39` states the assumption out loud:
*"NO llamar HIX_MetricsInit/Close ni HIX_ZombieInit — ya inicializados por el servidor
que aloja este test."* The suite has no such host.

**Recommendations.**

1. **Create mutexes eagerly in an `INIT PROCEDURE`, not lazily in a Start().**
   The pattern already exists in this very file: `INIT PROCEDURE _HixRouterMutexInit()`
   (`src/hix_router.prg:38-43`), added for audit A2.06. Apply it to `s_mtxRoutes`,
   `s_mtxActions` and `hix_zombie.prg:s_hMutex`. A mutex handle is not application
   state — creating it has no side effects and cannot be wrong, and it removes the
   race the A2.06 comment describes.
2. **If lazy init is kept, guard every lock site.** Adopt the `HIX_RouteList()` idiom
   (`IF s_hRoutes == NIL ; RETURN …`) at all 12 router locks and all 5 zombie locks,
   and make `HIX_ZombieCount()` return 0 when the store is uninitialized.
3. **Decouple the dispatcher from server lifecycle.** `THixDispatcher` must be usable
   standalone (the ACL tests and the audit tests are legitimate unit-level users of
   it). Either the dispatcher initializes what it needs, or `HIX_ZombieCount()` becomes
   total.
4. **Make the unit suite order-independent by construction.** Either the harness calls
   the module init procedures once in `_RunCli()` before the first group (mirroring
   what `HIX_LoggerInit()`/`HIX_MetricsInit()` already do at `app.prg`), or each group
   slice calls them explicitly. Until then, `09-fw-all` is the only defensible number
   and the group slices will keep inventing failures.

---

## 4. Cluster C3 — `Audit/A0116 hardcoded secrets` (fails in both runs)

```
A1.16: HIX_ConfigAppDefaults() genera clave jwt distinta en cada llamada   Expected: distinct  Got: SAME-KEY
A1.16: clave generada tiene >= 32 chars                                     Expected: >=32      Got: 0
```

**Root cause — the test and the code disagree, and the code is the deliberate one.**
`src/hix_config_app.prg:96-126` (`HIX_ConfigAppDefaults()`) returns `sets`, `dbf`,
`databases` and **no `keys` section on purpose** — see the comment at `:113-121`
(PENTEST-REPORT §1: `config.json` lives under `paths.root` and is served as a static
file, so every key written there was downloadable over `GET /config.json`). Keys now
come from `HIX_KeySet()` at bootstrap, then `config.json > keys` for legacy installs,
then in-memory generation (`src/hix_keys.prg:50-95`, `HIX_KeysLoadFromAppConfig()`).

`hix_test_audit.prg:1642-1661` still asserts the **pre-fix** contract: that
`HIX_ConfigAppDefaults()` itself emits a fresh random `keys.jwt` of ≥32 chars. Both
calls return an empty hash → `""` vs `""` → `SAME-KEY`, length 0.

Side finding: `_HixGenRandKey()` (`src/hix_config_app.prg:129-135`, HMAC-SHA256 over
time+ms+random) is **no longer referenced anywhere** in `src/` — dead code left behind
by that refactor.

**Recommendations.**

1. **Decide the contract first, then write one of the two tests.** The product
   behaviour is defensible; the test is stale. Retarget A0116 to what actually matters:
   * `HIX_ConfigAppDefaults()` contains **no** `keys` section (assert absence — that is
     the security property), and
   * after a server bootstrap, `HIX_KeyExists( "jwt" )` is `.T.` and
     `Len( HIX_KeyGet( "jwt" ) ) >= 32` (the generation path), and
   * no key returned by any default contains the published `H!x@` pattern (already
     covered by the second half of the test, which passes).
2. **Resolve the dead code.** Either wire `_HixGenRandKey()` into
   `HIX_KeysLoadFromAppConfig()`'s generation step (it appears to be the intended
   generator) or delete it. Leaving an unused key generator next to a security test is
   a trap for the next reader.
3. **Keep the "SAME-KEY" wording out of the index** until the contract is settled —
   as written it reads like an active vulnerability and it is not.

---

## 5. Cluster C4 — `Transport/SSL`: the HTTPS tests never run here

```
Transport/SSL :: SSL: curl.exe no localizado — tests HTTPS saltados   Expected: curl.exe  Got: missing
```

(one row per failing test now: the `Transport/SSL  FAIL (1)` rollup the earlier run
reported alongside it is suppressed by the parser — see C9.3. Class `tool`.)

`hix_test_ssl.prg:333-345` resolves the curl binary from Windows-only candidates
(`..\bin\curl\curl.exe`, `%SystemRoot%\System32\curl.exe`,
`Program Files\Git\mingw64\bin\curl.exe`) and finally `curl.exe --version`. On this
machine curl is `curl`. The suite then records a **FAIL** for tests it skipped
(`hix_test_ssl.prg:63`).

**Recommendations.**

1. Resolve `curl` and `curl.exe` (platform-appropriate name, or `#IFDEF
   __PLATFORM__WINDOWS` around the candidate list).
2. Report a genuine **SKIP** with a reason, not a FAIL. Today the failure is
   indistinguishable from a broken TLS transport.
3. Treat the underlying gap as the real finding: **HTTPS transport integration is
   untested on Linux** (`Transport/SSL` is the only suite that drives a real TLS
   server). `33-wa-verify`'s C-009 cases cover TLS from the client side and pass, so
   the gap is narrower than it looks — but the unit-level TLS path has no Linux
   coverage at all.

---

## 6. Cluster C5 — `31-wa-users`: 46 planned cases contribute nothing

```
slice 31-wa-users - webapp users suite (test/test_users_module.sh) rc=2 0s
  FAIL @abort  test/test_users_module.sh aborted (rc=2) - see the log
```

Log tail (`tests/.out/31-wa-users.log`):

```
  Target : http://localhost:9090  (HIX 2.2.01 / Harbour 3.2.1dev)
ABORT: HIX server not reachable at http://localhost:9090
```

**Root cause.** `webapp/test/test_users_module.sh:13` hardcodes `API="http://localhost:9090"`.
`webapp/hix.json:16` sets `"ssl": true`, so plain http gets no plaintext answer (verified:
`curl http://localhost:9090/login` → `000`, curl exit 52 "Empty reply from server"; the
server waits for a TLS handshake and closes; `curl https://localhost:9090/` → 200).
`33-wa-verify`'s C-009c asserts exactly this and passes.
Unlike its siblings, this script **never reads `TEST_API`** — `test_customer_module.sh:6`
does (`API="${TEST_API:-http://localhost:9090}"`), `verify-users-fixes.sh:41` does
(`VERIFY_API`). The slice exports `TEST_API` and records the mismatch as a NOTE
(`preflight.suite_default`), but the script ignores it.

**Recommendations.**

1. Make `test_users_module.sh` honour `TEST_API` (and add `-k`, or rely on
   `CURL_CA_BUNDLE` as the other two suites do). One line at `:13`.
2. Better: have all three suites derive scheme+port from `webapp/hix.json` instead of
   hardcoding `9090`, so a config change cannot silently disable a suite.
3. Highest-value single change in this report: **46 planned cases currently produce
   zero coverage**, and the index hides that behind "cases 3".

---

## 7. Cluster C6 — `32-wa-customer`: 28 of 50 cases fail on a cookie-jar bug

```
32-wa-customer  52 cases | 23 PASS | 28 FAIL
  suite says: Total tests : 50   Passed : 22   Failed : 28
  T10 … T36, T44  (expected 200 / got 302, then "present → no" for every content check)
```

**Root cause — the suite never holds an authenticated session.**
`webapp/test/test_customer_module.sh`:

* `:69` — T08 writes the jar with `--cookie-jar` on a POST that is **deliberately
  rejected** (no CSRF). The jar therefore contains only pre-auth cookies.
* `:80` — T09, the **successful** login (`POST /auth` with `_csrf`), uses `--cookie`
  only. `--cookie` *reads* a jar; it does not save the `Set-Cookie` of the response.
  The session cookie is therefore never stored.
* Every later request (`:88`, `:96`, `:156`, `:173`, `:206`, `:245`, `:283`, …) sends
  the stale jar → 302 → T10 fails, and T12–T36 / T44 fail because they grep HTML that
  was never served (the 302 body is empty).

Secondary defect in the same block: **T09 asserts only `302`** (`:81`). A rejected login
and a successful login both answer 302. The suite can report "authenticated" while
authentication failed — which is precisely what happened here (T09 PASS, T10 FAIL).

**Recommendations.**

1. Use `-c "$JAR"` (write) on the login POST — and on the `GET /login` that mints the
   CSRF cookie — instead of `--cookie-jar` on the rejected POST. Keep `-b "$JAR"` for
   reads. `verify-users-fixes.sh` already models the correct pattern (`-b "$CK" -c "$CK"`
   in its `code()/page()/post()` helpers, `:74-77`).
2. Assert the **redirect target**, not just the code: `-w '%{redirect_url}'` and expect
   `/main` for a successful login, `/login` for a rejected one. This turns T08/T09 into
   discriminating tests.
3. Use one jar path per run (`mktemp -u …`) instead of the fixed `/tmp/test_cookies.txt`
   (`:69` etc.), so two suites or two runs cannot read each other's session.
4. Expected effect: T10–T36 and T44 are one root cause; fixing the jar should restore
   ~27 of the 28 failures without touching the customer module. **Do not start by
   investigating the customer module** — T01–T09 (routing, CSRF rejection, login
   redirect) all pass, and the 302s are the signature of an unauthenticated client, not
   of a broken grid.

Note for whoever runs this by hand: the script calls `curl` **without `-k`**. It only
works against the self-signed dev certificate because the slice exports
`CURL_CA_BUNDLE` (`tests/slices/s20_wa_http.sh` header + `hix_curl_trust` in
`tests/lib/common.sh`). Outside the slice it fails with curl exit 60.

---

## 8. Cluster C7 — `33-wa-verify`: 3 failures, only one of them about the app

`33-wa-verify` is the healthiest webapp suite (127 cases, 123 pass) and the only one
that authenticates against the TLS app. Its three failures are:

### 8.1 `D-09f rejected rename left record 2 unchanged` — stale fixture, not a defect

```
FAIL D-09f rejected rename left record 2 unchanged  [expected carles / got carlesX]
```

`verify-users-fixes.sh:388` compares `dbf row 2` against the literal seed value
`carles`. The DBF on disk holds `carlesX`:

```
$ python3 webapp/test/dbf_dump.py webapp/data/users.dbf
2| |2|carlesX|…
```

and the seek probe sees the same thing (`38-wa-probe-seek.tsv`:
`seek 'carle' -> NAME='carlesX'`). The mutation is written by a **different** suite:
`webapp/test/test_users_module.sh:175` renames `/users/2` to `carlesX` (its T44).
That suite aborted in this run, so the value is residue from an earlier run.

The D-09 sequence itself behaved correctly: D-09a…D-09e all pass (duplicate create
refused, nothing inserted, collision reported, rename refused, collision shown on the
edit form). Only the post-condition comparison against a hardcoded seed name fails.

**Recommendations.**

1. Make D-09f self-contained: read record 2's name **before** the rejected rename and
   compare it **after**. It then tests the property ("a rejected write does not mutate")
   instead of a snapshot of mutable state.
2. Add a fixture fingerprint to the suite's preflight — assert record 2 is `carles` and
   record 4 is `John` — and report a **fixture** failure (SKIP/NOTE with "re-run
   regenerate_users") rather than a module failure when it does not match. The suite's
   own header already documents the reset:
   `hbmk2 regenerate_users.hbp && ./regenerate_users` (server stopped).
3. Consider a `--fresh-data` step in `tests/run.sh`'s webapp plan (report only: it is a
   plan change, not a code fix) so the webapp suites always start from the seed.

### 8.2 `D-16d mixed-case seed name logs in as JOHN` — the DBF is not the current seed

```
FAIL D-16d mixed-case seed name logs in as JOHN  [expected 200 / got 302]
```

`verify-users-fixes.sh:432` logs in as `JOHN` / `5678`, the pair seeded by
`webapp/regenerate_users.prg:18-20` — where `"John"` is mixed-case *on purpose* ("it
proves the Lower(name) CDX tag round-trips").

The on-disk record 4 is **not** that seed:

* name is lowercase `john`, not `John`;
* recomputing the stored digest with the project's own KDF
  (`www/models/hpassword.prg`, `PW_HASH_ITERATIONS 10000`, salt `1695c0bc…`) matches
  password **`1234`**, not `5678`:

  ```
  john 5678     no
  john 1234     MATCH      <- the stored digest is for 1234
  jane 9012abcd MATCH      (record 5 does match the current seed)
  ```

So `users.dbf` was seeded by an older seed list. The login code itself is correct for
case-insensitivity: `www/models/modeluser.prg:54-69` lowercases the input, seeks the
`name` tag, and then requires `Lower(cFound) == cSeek` to defeat the inexact `DbSeek`
(`SET EXACT` is `.F.`). D-16a (index keyed on `Lower(name)`), D-16b (partial name
rejected), D-16c (wrong password rejected), D-16e/D-16f (password prefix vs full) all
pass.

**Recommendations.**

1. Re-seed and re-run before treating this as a product defect:
   `cd webapp && hbmk2 regenerate_users.hbp && ./regenerate_users` **with the server
   stopped**, then `./tests/run.sh 33-wa-verify`. If D-16d still fails on a freshly
   seeded `John/5678`, it becomes a real case-insensitivity finding worth investigating.
2. Same fixture-fingerprint guard as 8.1 — a stale DBF should be reported as a fixture
   problem, not as a login defect.
3. Note the rate-limit interaction for whoever re-runs: D-16 spends 6 `/auth` attempts
   against a 5/60 s limit (`www/middlewares/config.json`), and the suite sleeps
   `LOGIN_WINDOW+5` before it (`verify-users-fixes.sh:423-424`) plus waits mid-block
   (log: `... /auth rate-limit window busy (5/60 s), waiting 125s`). A failure here is
   easy to misattribute to rate limiting; `logged_in()` deliberately reports 429
   separately (`:104-109`), and this run reported 302, so rate limiting was not the cause.

### 8.3 `H-05c session files written by this run are 0600` — launcher umask, and a real design constraint

```
FAIL H-05c session files written by this run are 0600  [expected 0 / got 22]
```

Two separate facts, both needed to fix it correctly.

**a) The framework cannot set the mode, and says so.**
`src/hix_session.prg:616-660` (`_HixSessionFileWrite`) writes with
`hb_MemoWrit( cTmp, … )` + `FRename()` and never sets a mode. `webapp/go_gcc.sh:21-26`
states the constraint: *"HIX writes session files with hb_MemoWrit() + FRename() and
never sets a mode, and Harbour core exposes no umask()/chmod() (they fail to link:
HB_FUN_UMASK / HB_FUN_CHMOD), so the application cannot tighten them from Harbour code
— the launcher is the only place inside the project folder that can."* The project's own
probe agrees (`37-wa-probe-fmode.tsv`: `change mode from Harbour : impossible
(umask/chmod not linked)`). So the effective mode is `0666 & ~umask` of whoever started
the server.

**b) This run reused a server it did not start, with the wrong umask.**

```
tests/.out/run.log:1   reusing the HIX app already answering on https://localhost:9090
ps:                    PID 645753  started Tue Oct 6 15:38:35  ./app --port 9090
/proc/645753/status:   Umask: 0022
```

`webapp/go_gcc.sh:26` sets `umask 077`, and `tests/lib/common.sh:157` would have used
`umask 077` too (`cd "$HIX_WEBAPP" && umask 077 && exec ./app`) — but `hix_server_start()`
short-circuits when something already answers on the port (`common.sh:152-155`), and
`run.sh` prefers reusing a live app. The app answering 9090 was launched by hand at
15:38 under the default 0022, so every session file it wrote during the run is 0644.
`30-repo`'s `perm.session_files` FAIL is the same fact seen from the other side
(`webapp/.sessions` is 0700 — PASS — its files are 0644 — FAIL).

**Recommendations.**

1. **Immediate, no code change:** start the app through a launcher that sets the mask
   (`webapp/go_gcc.sh`, or let the suite own the server with `--no-server` off and
   nothing already listening), and re-run. `go_gcc.sh:130-136` additionally chmods an
   existing store (`chmod 700` + `chmod 600` on its files) precisely because "umask
   cannot fix an existing file" — the 22 files present now need that one-time tightening.
2. **Make the suite honest about it.** H-05c and `perm.session_files` assert a property
   of the *launcher*, not of the code under test. Either (a) have the suite read the
   server process's umask (`/proc/<pid>/status`) and SKIP with the reason when it is not
   077, or (b) have `tests/run.sh` refuse to reuse a server whose umask it cannot
   verify, and say so in the preflight. As written, a hand-started server silently
   converts a launcher mistake into two FAIL rows.
3. **Decide the product guarantee.** If "session files are 0600" is a security
   requirement rather than a deployment convention, then relying on the launcher's umask
   is not a guarantee — and the project currently has no in-project way to enforce it
   (Harbour exposes no chmod; `probe_fmode` proves it). Options to evaluate, not apply:
   a small C shim compiled with the app that calls `fchmod`/`hb_fputm`, writing the file
   through `hb_fCreate` with an explicit mode, or documenting the requirement in
   `webapp/srs/DEV-compliance.md` as a launcher obligation. Right now the code, the
   probe, the launcher and the test each encode a different assumption.

---

## 9. Cluster C8 — `30-repo`: 18 cases, 11 PASS, 4 FAIL, 3 NOTE

```
FAIL secret.untracked        2 private file(s) one 'git add -A' away: tests/unit/hix_test.crt tests/unit/hix_test.key
FAIL ignore.tests/unit/hix_test.key   not matched by .gitignore
FAIL ignore.tests/unit/hix_test.crt   not matched by .gitignore
FAIL perm.session_files      not 0600: webapp/.sessions/sess_…  (5 listed)
NOTE secret.history          2 path(s) ever added, e.g. tests/unit/hix_test.crt tests/unit/hix_test.key
NOTE secret.untracked.mode   tests/unit/hix_test.key is 0600 but still unignored
PASS perm.keys / perm.appkey / perm.session_dir / path.portable / gen.* / data.residue
```

**Root cause.** `tests/unit/make_test_cert.sh` generates `hix_test.crt` / `hix_test.key`
on first run (`tests/unit/go_gcc.sh` auto-generates them). `.gitignore` covers
`webapp/hix.keys.json`, `webapp/www/config.json`, `webapp/data/*.dbf|cdx`, `tests/unit/app`,
`traces/`, `trace.log`, `nul` — but has **no rule for `tests/unit/*.crt` / `*.key`**.
`secret.history` reports git has seen those two paths added at some point.

**Recommendations.**

1. Add `tests/unit/hix_test.crt` and `tests/unit/hix_test.key` (or a scoped
   `tests/unit/*.crt` / `tests/unit/*.key`) to `.gitignore`. Two lines; clears 3 of the
   4 FAILs.
2. Follow up on `secret.history` separately: decide whether the test key material that
   git has already seen needs to be rotated/purged. It is a self-signed *test* pair, so
   the answer may well be "no action" — but the decision should be recorded, not
   inferred from a NOTE row.
3. `perm.session_files` is C7.3; no separate fix.
4. `data.residue` PASS (20 rows, 0 residue) is worth keeping in view: the suites do
   clean up their own rows. The residue problem in this tree is not DBF rows, it is
   **mutated seed rows** (C7.1, C7.2) — a check that compares seed rows against the
   seeder's expectations would catch what `data.residue` cannot.

---

## 10. Cluster C9 — reporting defects inside `tests/` itself

These do not affect the code under test, but they made the index harder to trust.
All five were open when the first run of this report was taken; the suite was then
fixed, and the numbers in §1 are from the run after it.

1. **`preflight.suite_default` was wrong for `33-wa-verify`. — fixed.**
   `tests/slices/s20_wa_http.sh` computed `default_api="http://localhost:<port>"`
   unconditionally and emitted the NOTE *"test/verify-users-fixes.sh defaults to
   http://localhost:9090, which the TLS-only server refuses"*. `verify-users-fixes.sh:41`
   actually defaults to `https://localhost:9090`. The slice now reads the suite's own
   `API=` line (its `${VAR:-default}` form first) and reports what is really there:
   `33-wa-verify` now records `preflight.suite_default PASS — defaults to
   https://localhost:9090, which suits the TLS-only server (honours VERIFY_API: yes)`,
   while the two suites that do default to plain http keep their NOTE, now quoting the
   line verbatim.
2. **Terminal control sequences leaked into the evidence. — fixed.** `09-fw-all.tsv`
   carried a NOTE row for `Audit/A0103` padded with ~150 spaces before `ok`, because the
   status token arrived after cursor-control escapes. `lib/parse_unit.awk` now trims the
   status before matching it, so `Audit/A0103` is a `PASS` row in the reference run —
   which is also what lets its `Argument error` in `20-fw-audit-a01` be recognised as
   slice-order dependence instead of an unexplained failure.
3. **Row counts overstated failure counts. — fixed.** A failing test emitted a
   `FAIL (n)` summary row plus a `:: ERROR` / `:: <assertion>` detail row. The parser now
   buffers a `FAIL (n)` rollup and only emits it when those `n` detail rows did not all
   appear, and drops the phantom `:: ERROR` assertion a group raises on an exception.
   `09-fw-all`: 17 failing rows → 9, one per failing test.
4. **A skipped test reported as FAIL. — classified, not hidden.** `Transport/SSL` is now
   class `tool` (check `curl.exe.windows`: the suite looks for `curl.exe`, which does not
   exist on Linux) and `31-wa-users`' abort is class `harness` (check
   `users.api.hardcoded`). Both are still listed in the index, under *not defects*, with
   the check that justifies them; neither counts as a defect of HIX. If the suite ever
   gains a `curl.exe` or honours `TEST_API`, the check stops reporting `ok`, the rule goes
   inert, and those rows come back as counted failures.
5. **Slice stdout cap (16 KB) hides the failing-case list for large slices.** Still true,
   still by design: the digest is capped and `tests/slice.sh <id> --cases --class triage`
   is the way to see them. Documented in `tests/readme.md`.

---

## 11. What is *not* broken (so the wrong thing is not "fixed")

* `00-preflight` 40 cases / 34 PASS / 6 NOTE / 0 FAIL — toolchain, binaries, cert,
  config (`admin.enabled=false`, `session storage=file crypt=true`, `app.env=prod`),
  TLS-only reachability all sound.
* `05-artifacts` 6/6 — `hix_server.hbx`, `lib/gcc/libhix_server.a`, `tests/unit/app`
  present and fresh.
* Clean unit groups: `Core` 111/111, `AUTH` 335/335, `Views` 145/145,
  `Audit/A02` 50/50, `Audit/A03` 78/78, `Extras` 35/35.
* The whole `Audit/A03*` and `B1*` remediation set passes in the reference run —
  including `B1S2 session file atomic write`, `B1S3 session gc hmac recheck`,
  `B1A1516 session no hardcoded key`, `A0116`'s sibling `A0118 session file hmac`.
* All five webapp probes pass (`entropy` 5000 seeds / 0 duplicates / 0 malformed,
  `hash`, `pwcost`, `fmode`, `seek`).
* `33-wa-verify` 124/127 — TLS (C-009), Secure cookie (H-03), security headers (H-06),
  session-bound CSRF (H-04a…e), encrypted session payload (H-05b), rate limiting
  (D-07c), password KDF (D-07e), sort allow-list (D-08b/c), users:create scope
  (D-04a/b), credentials never in the UI (D-05).
* `data.residue` PASS — no leftover test rows.

---

## 12. Recommended order of work

Nothing below is applied. Ordered by coverage recovered per unit of change.

| Pri | Action | File(s) | Recovers |
|---|---|---|---|
| **P1** | Login POST writes the cookie jar; assert `redirect_url` instead of bare 302 | `webapp/test/test_customer_module.sh:69,80` | ~27 cases (C6) |
| **P1** | Honour `TEST_API` (+ `-k`/`CURL_CA_BUNDLE`) | `webapp/test/test_users_module.sh:13` | 46 cases (C5) |
| **P1** | `DATA lUseSSL INIT .F.` in `TMockIO` | `tests/unit/src/hix_test_utils.prg:24` | 6 tests in both unit runs (C1) |
| **P2** | Guard `::oIO:lUseSSL` in `THixRequest:Read()`; make the IO contract total | `src/hix_request.prg:222` | removes the API break behind C1 |
| **P2** | `INIT PROCEDURE` for `s_mtxRoutes`, `s_mtxActions`, `hix_zombie:s_hMutex` (pattern already at `hix_router.prg:38`) | `src/hix_router.prg`, `src/hix_zombie.prg` | 8 tests, and ends the order dependence (C2) |
| **P2** | NIL guards at the 12 router + 5 zombie lock sites; `HIX_ZombieCount()` → 0 when uninitialized | same | defence in depth for C2 |
| **P2** | Make `THixDispatcher` usable without a started `THixServer` | `src/hix_dispatcher.prg:297` | Acl, Abort, A0102, A0103 standalone |
| **P3** | Re-seed `users.dbf` from the current `regenerate_users.prg` (server stopped) | `webapp/data/` | D-16d, and clears `carlesX` (C7.1, C7.2) |
| **P3** | Start the app under `umask 077` (or let the suite own it); one-time `chmod 600` on existing `.sessions/*` | launcher, `webapp/.sessions/` | H-05c, `perm.session_files` (C7.3, C8) |
| **P3** | `.gitignore` rules for `tests/unit/*.crt` / `*.key` | `.gitignore` | 3 FAILs (C8) |
| **P4** | Retarget A0116 to the real contract; resolve dead `_HixGenRandKey()` | `tests/unit/src/hix_test_audit.prg:1638-1661`, `src/hix_config_app.prg:129` | 1 test in both unit runs (C3) |
| **P4** | Resolve `curl` **and** `curl.exe`; report SKIP, not FAIL | `tests/unit/src/hix_test_ssl.prg:333-345` | honest TLS coverage status (C4) |
| **P4** | Make D-09f compare before/after instead of a hardcoded seed name; add a seed fingerprint preflight | `webapp/test/verify-users-fixes.sh:388` | removes fixture-dependent failures (C7.1) |
| **P5** | Fix `preflight.suite_default` per suite; strip ANSI in parsers; add a distinct-test count | `tests/slices/s20_wa_http.sh`, `tests/lib/parse_*.awk`, `tests/lib/index.awk` | trustworthy index (C9) |

**Two decisions are needed before any code changes**, because they are contract
questions, not bugs:

1. **Should `HIX_ConfigAppDefaults()` emit keys at all?** The code says no (for a good
   reason, `hix_config_app.prg:113-121`); the test says yes. Pick one and make the other
   match (C3).
2. **Is "session files are 0600" a product guarantee or a launcher obligation?**
   Harbour cannot chmod (proven by `probe_fmode`), so today it is a launcher obligation.
   Either enforce it with a compiled helper or document it as an obligation — but the
   test, the launcher, and the framework should state the same thing (C7.3).

---

## 13. Evidence map (how to re-check any claim above)

```bash
./tests/index.sh --full                                   # the whole index, uncapped
./tests/slice.sh 09-fw-all --cases --status FAIL --full   # reference unit run
./tests/slice.sh 11-fw-routing --log --full               # raw "Argument error" run
./tests/slice.sh 32-wa-customer --cases --status FAIL
./tests/slice.sh 33-wa-verify --log --grep 'D-09|D-16|H-05' --full
./tests/slice.sh 30-repo --cases --full

# single unit test, for root-causing
cd tests/unit && HB_ROOT="$HB_ROOT" HB_INCLUDE="$HB_ROOT/include" \
  ./app --cli Multipart          # -> [EXCEPTION] Message not found   ($HB_ROOT = the Harbour install)
cat tests/unit/traces/info.txt   # -> only "=== HIX_TestMultipart_Run start ===" (C1 proof)

# fixture state
python3 webapp/test/dbf_dump.py webapp/data/users.dbf      # 2|carlesX  4|john

# launcher umask of the app the suite reused
ps -o pid,lstart,cmd -C app ; grep Umask /proc/<pid>/status # Umask: 0022
```

Key source locations cited:
`src/hix_request.prg:222` · `src/hix_router.prg:38,58,68,113,343,403,463,467,503,512` ·
`src/hix_zombie.prg:28,45,72,102,123,155` · `src/hix_dispatcher.prg:297` ·
`src/hix_server.prg:268` · `src/hix_config_app.prg:96,113-121,129` ·
`src/hix_keys.prg:50-95` · `src/hix_session.prg:616-660` ·
`tests/unit/src/hix_test_utils.prg:19-33` · `tests/unit/src/hix_test_router.prg:78` ·
`tests/unit/src/hix_test_audit.prg:39,1638-1661` ·
`tests/unit/src/hix_test_hixstyle_acl.prg:29` · `tests/unit/src/hix_test_abort.prg:68-72` ·
`tests/unit/src/hix_test_ssl.prg:63,333-345` ·
`webapp/test/test_users_module.sh:13,175` ·
`webapp/test/test_customer_module.sh:6,69,80` ·
`webapp/test/verify-users-fixes.sh:41,388,423-432,539` ·
`webapp/regenerate_users.prg:18-20,73` · `webapp/www/models/modeluser.prg:54-69` ·
`webapp/go_gcc.sh:21-26,130-136` · `tests/lib/common.sh:150-166` ·
`harbour/src/vm/thread.c:1832` (EG_ARG 3012) · `harbour/src/rtl/tobject.prg:77`
(MSGNOTFOUND → "Message not found").
