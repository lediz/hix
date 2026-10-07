# BF-01 — Pre-auth surface: findings and recommendation

Scope: phase **BF-01** of `BRUTE-FORCE-PENTEST-PLAN.md` (pre-auth surface enumeration /
control regression) against the local HIX CRUD app `https://localhost:9090`, `app.env = "prod"`.
Authorized self-assessment. Nothing in this document describes a host we do not own.

| | |
|---|---|
| Verdict | **BF-01 FAILS** — not "pass with deviation" |
| Baseline commit | `7e4f61a` (`webapp`), framework at the repository root |
| Original run | `.tmp_verify/bf/20261006-075931/` (`BF-01.jsonl`, `BF-01.notes.txt`), first request `2026-10-05T23:59:35Z` |
| Follow-up probes | 17 read-only `GET`s, `2026-10-06T02:2xZ`, recorded in `.logs/access.log` |
| Changes made | **none** — report only. No source, config, data or session file was modified |

---

## 1. What the original run recorded

From `.tmp_verify/bf/20261006-075931/BF-01.notes.txt` (two passes, 40 requests):

| Probe | Code | Body bytes | Plan criterion | Status |
|---|---|---|---|---|
| `/config.json` | 404 | 21 | 404 | met (app route `deny.config`) |
| `/hix-slow` | 404 | 21 | 404 | met |
| `/hix-login` `/hix-admin` `/hix-metrics` `/hix-setup` `/hix-index` | 404 | 374-376 | 404 (not registered) | met |
| `/hix.keys.json` | 404 | 378 | not downloadable | met |
| `/../hix.keys.json` | 404 | 378 | not downloadable | met |
| `/test/index.html` | **403** | 314 | 404 | **deviation** |
| `/test/` | **403** | 314 | 404 | **deviation** |
| `/www/config.json` | **403** | 314 | — | deviation |
| `/..%2f` | **403** | 314 | — | deviation (correct behaviour, see §4) |
| `/public/js/hi.js` | 200 | 57 | served | met |
| `http://localhost:9090/login` | `000`, `curl_exit=52` | — | plaintext refused (C-009) | met |
| body leak scan (keys / SID / stack trace) | clean | — | clean | met |

At the end of the run this was recorded as "PASS with deviation (403 instead of 404)".
That was too generous — see §2.

---

## 2. Follow-up evidence: the surface is wider, and one probe returns 200

17 additional read-only probes (`curl -sk --connect-timeout 5 --max-time 15 -o /dev/null
-w '%{http_code} %{size_download}'`), 2026-10-06:

| Probe | Code / bytes | What it proves |
|---|---|---|
| **`/config.json.example`** | **200 / 258** | a docroot-root file is served. Body is the DAL config: `sets` (`language`, `dateformat`, `decimals`, `epoch`, `exact`, `exclusive`, `fixed`, `softseek`) and `dbf.rddname = "DBFCDX"`. No secret in this file, but the ACL never covered it |
| `/config.json.bak` | 404 / 380 | 404 **only because commit `c83e36b` deleted the file** — not because anything blocks it |
| `/config.json/` | 404 / 21 | the `deny.config` route matches the literal path only |
| `/config.json%2e` | 404 / 379 | framework 404, not the app route — the deny does not normalize |
| `/config.json.` | 404 / 377 | same |
| `/config.json.example/` | 403 / 314 | a trailing slash moves the request onto the ACL path |
| `/test/nope.html` | 403 / 314 | 403 is returned **before** the file is looked up: identical for a real and a non-existent file |
| `/views/` | 403 / 314 | docroot layout is enumerable |
| `/controllers/` | 403 / 314 | " |
| `/models/` | 403 / 314 | " |
| `/middlewares/` | 403 / 314 | " |
| `/loaders/` | 403 / 314 | " |
| `/routes/web.json` | 403 / 314 | route table + scope names disclosed if the ACL is ever loosened |
| `/www/config.json` | 403 / 314 | reproduced from the original run |
| `/test/` | 403 / 314 | " |
| `/index.html` | 404 / 375 | absent root file → framework 404 (contrast with the 200 above) |
| `/favicon.ico` | 404 / 376 | " |

Discriminator that matters: **403 = 314 bytes, 404 = 374-380 bytes, 200 = the file.**
Forbidden and absent are trivially distinguishable, so the docroot layout is an oracle.

Historical impact of the same mechanism: `www/config.json.bak` carried the **old signing keys**
until `c83e36b` deleted it ("chore: delete www/config.json.bak - it still carried the old signing
keys"). It sat in the docroot root, which is exactly the location the ACL skips. The `deny.config`
route never protected it, because that route matches `/config.json` and nothing else.

---

## 3. Root cause — three distinct mechanisms

Request path through the dispatcher (`hix_dispatcher.prg`, `Dispatch`):

```
normalize  :195
traversal guard (raw + percent-decoded ".." "\" NUL)  :205-210   -> 403  (403 sent at :208)
hixstyle asset prefix rewrite (/js /css /images ...)  :213-217
cRelDir derived from the URL directory                :224
_HixCheckACL                                           :233 -> :536-566  -> 403
_HixResolveIndex (directory -> index, 404)             :238 (body at :576)
existence / extension handling                         :243+      -> 404 / 200
```

### 3.1 Root-file gap — the actual fail

`_HixCheckACL()` is only consulted when the request has a non-empty relative directory:

```
hix_dispatcher.prg:557
   IF aAllowDirs != NIL .AND. ! Empty( cRelDir )
```

`cRelDir` is derived from the URL's directory component (`:224`). For a file sitting directly in
the docroot root it is empty, so **the hixstyle whitelist is skipped entirely** and the request
falls through to static serving. The whitelist itself is strict — with `hixstyle.enabled = true`
(`hix.json:119-125`; `hixstyle.public` is absent from the file and defaults to `.T.` at
`hix_dispatcher.prg:1777-1780`) the dispatcher auto-allows only `public` (`hix_server.prg:499-505`),
and the app adds `test` only when `_AppEnv() == "dev"` (`src/app.prg:76-78`).

Consequence: any file placed at the docroot root is downloadable regardless of the zero-trust
whitelist. Today that is `www/config.json` (protected only by the literal `deny.config` route) and
`www/config.json.example` (not protected at all → 200).

This cannot be fixed by deleting files: `www/config.json` is the runtime app config, read from
inside the docroot (`src/app.prg:45` `#DEFINE HIX_APP_CONFIG "www/config.json"`), and the framework
itself flags the location as sensitive (`hix_config_app.prg:113-118`: "HIX serves root-level
docroot files, so every key written here was downloadable over plain GET /config.json"). The fix
belongs at the serving layer.

### 3.2 403 instead of 404 on non-whitelisted directories

`_HixCheckACL` answers `HIX_HttpError( oReq, 403 )` at `hix_dispatcher.prg:548` (deny list) and
`:562` (not in whitelist), **before** `_HixResolveIndex` (`:238`) and before any existence check.
Hence `/test/*` → 403, and `/test/nope.html` is byte-identical to `/test/index.html`. The plan's pass
criterion (`/test/*` → 404) is unmet, and the uniform 314-byte body maps the docroot.

### 3.3 `/..%2f` → 403 is correct and should stay

That response comes from the traversal guard at `hix_dispatcher.prg:205-210`, which percent-decodes
before testing for `..`, `\` and NUL (the `[A1.02]` fix), and logs `DISP_PATH_TRAVERSAL`. It is not
an ACL response. It is the only 403 in the phase that is behaving as designed.

---

## 4. Recommendation (priority order)

### R-1 — Close the root-file gap. Highest priority; this is the fail.

Make the ACL apply to root-level files: do not skip the whitelist when `cRelDir` is empty
(`hix_dispatcher.prg:557`), or deny root-level requests by extension/dotfile
(`.json`, `.bak`, `.old`, `.example`, `.keys.json`, `.*`) at the serving layer.

App-level interim option, no framework change: extend `_GuardSurface()` (`src/app.prg:125-133`)
with a catch-all root pattern that answers 404 for anything not explicitly routed, following the
existing `deny.config` / `hix.slow` pattern. Feasible: the router supports path wildcards
(`hix_router.prg:909-920`, `*` outside `()` → `.*`) and routes are matched before the dispatcher,
which is only a fallback (`hix_server.prg:487` "Dispatcher como fallback segun dispatch_mode").

Candidate worth evaluating but **not** proposing yet: `app.dispatch_mode = "routes"`
(`hix_server.prg:488`) removes the dispatcher's ability to serve docroot files at all. Must first
be verified against `/public/*` static asset serving, which currently depends on the dispatcher.

### R-2 — Make forbidden indistinguishable from absent in `prod`.

`_HixCheckACL` should answer 404 rather than 403 (`hix_dispatcher.prg:548`, `:562`), keeping 403
only for the traversal guard. This is what makes the criterion hold for *every* path rather than
the handful we probed, and it removes the docroot-layout oracle.

Verified safe: the framework 404 body reflects the requested path
(`hix_error.prg:713-715` `cDetail := "Route: " + oReq:cPath`) but the detail is escaped with
`UHtmlEncode` (`hix_error.prg:831`), so converting 403 → 404 introduces no reflection surface.

This is an upstream change in the framework (`src/`). Gate it on `app.env == "prod"` or a config
flag: 403 is the semantically correct answer in development, and the framework already conditions
a 403 on `env` for the HIXSTYLE-dormant hint (`hix_error.prg:719-723`).

### R-3 — Do not ship `www/test/` in a production install.

Complementary hygiene only, and explicitly **not** a fix: because the ACL answers before existence
is consulted (§3.2), `/test/anything` still returns 403 with the directory gone. It removes the
payload, not the code.

### R-4 — Keep `/..%2f` at 403 and amend the plan for that one probe.

Change the criterion to "400/403, never 200/302". Folding traversal into 404 would only blur an
active attack signature that already produces a `DISP_PATH_TRAVERSAL` log line.

### R-5 — Do not relax the plan's Pass line to accept 403.

The plan's own Fail rule is "any 200/302 on those paths", under which 403 would pass. That
reasoning is only defensible once R-2 lands. While 403 is 314 bytes and 404 is 374-380 bytes,
accepting 403 means accepting an enumeration oracle.

---

## 5. Re-test criteria (what a passing BF-01 must show)

1. No `200` on any path outside the explicit route table and `public/` — this is the current fail.
2. Every probe returns 404 except the traversal probe (400/403).
3. `/test/nope.html` and `/test/index.html` are byte-identical, and equal to the generic 404 for a
   non-existent path (`/index.html`).
4. `/config.json.example`, `/config.json.bak`, `/config.json/`, `/config.json%2e`, `/config.json.`
   all return the same code and body length as `/index.html`.
5. `/views/ /controllers/ /models/ /middlewares/ /loaders/ /routes/web.json` indistinguishable
   from a non-existent top-level directory.
6. Unchanged regressions: `/public/js/hi.js` still 200, plaintext still refused, no key / SID /
   stack trace in any body.

Probe list to add to the plan: the docroot directory set, the root-file variants above, and the
existence pair `/test/nope.html` vs `/test/index.html`.

---

## 6. Evidence-quality blockers to fix before a re-run can be cited

Per plan §8 ("a phase is `NOT TESTED` unless its evidence file exists"), the current BF-01
evidence is not citable as-is:

1. `.tmp_verify/bf/20261006-075931/BF-01.jsonl` is **not valid JSON** — `"ttfb":,` with an empty
   value on every line (40/40 lines fail `json.loads`).
2. Fields are shifted in the same file: `redirect` carries the byte count and `size` carries
   seconds. The harness `req()` printf ordering is the cause.
3. The plan's probe list contains bare `hix.keys.json` (no leading slash) → `status 000` is a curl
   failure, not a server response. The second pass used `/hix.keys.json` → 404, which is the valid
   result.
4. The 17 follow-up probes exist only in `.logs/access.log`; they need to be re-run through the
   harness into a run directory before they can back a finding.

---

## 7. Related open items outside BF-01

Recorded during the same review, listed here so they are not lost; not BF-01 scope.

- **Global rate limiter does not exist.** `src/app.prg:90` calls `HIX_MwRateLimitSetup()`, which
  only sets parameters; no middleware group attaches `HIX_MwRateLimit`. Only the per-route
  `HIX_MwRateLimitFactory` on `/auth` (`www/middlewares/myapplogin.prg:74`) is in force. Measured:
  340 `GET /` in one window → `200=340 429=0` (`BF-03.notes.txt`). The "300 req / 60 s" budget in
  plan §2 is fiction.
- **BF-04 bucket key is not attacker-controlled** (highest-value phase, PASS): 429 from attempt 6;
  rotating `X-Forwarded-For`, `cf-connecting-ip` and `Forwarded:` buys no extra budget
  (5×302 / 15×429 each), identical to the no-header control. Evidence:
  `.tmp_verify/bf/20261006-075931-rerun/BF-04.notes.txt`.
- **BF-04 sub-check (b) is vacuous**: `wait_slot` (125 s cooldown) runs before the "new cookie jar
  must still be limited" probe, so the recorded 302 proves nothing; "the limiter counts attempts
  regardless of CSRF outcome" is still inconclusive.
- **Harness reporting bug**: `first 429 at attempt: 7` is off by one — `codes` has a leading space,
  so `tr ' ' '\n' | grep -n` shifts every index (`test/bf_harness.sh:283`). Real onset is attempt 6.
- **BF-09 evidence format gap**: only 2 JSONL lines; the parallel bursts live in
  `BF-09.login.txt` / `BF-09.auth.txt` instead of per-request JSONL.
- `BRUTE-FORCE-PENTEST-PLAN.md` still states "Status: plan only. No phase has been executed yet."
  All ten phases have been executed; `BRUTE-FORCE-RESULTS.md` (plan §8 deliverable) is not written.

---

## 8. Reproduce

```bash
# the 17 follow-up probes (read-only, localhost only)
for u in /config.json.example /config.json.bak /config.json/ /config.json%2e /config.json. \
         /config.json.example/ /test/nope.html /views/ /controllers/ /models/ /middlewares/ \
         /loaders/ /routes/web.json /www/config.json /test/ /index.html /favicon.ico; do
  printf '%-24s %s\n' "$u" "$(curl -sk --connect-timeout 5 --max-time 15 -o /dev/null \
      -w '%{http_code} %{size_download}' "https://localhost:9090$u")"
done

# the original phase
./test/bf_harness.sh bf01          # evidence -> .tmp_verify/bf/<stamp>/BF-01.*
```

Restore after any run (plan §9): `rm -f .sessions/*`, `sha256sum -c
.tmp_verify/bf-baseline/hashes.txt` (currently all `OK`).
