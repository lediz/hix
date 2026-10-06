# Production blockers — what must be fixed before shipping

Run: `./tests/run.sh --fresh`
Tree: `a807222` (branch `enhance`) · started 2026-10-07T02:48:53+08:00 · elapsed 499 s
Result: **25 slices, 419 case rows, 328 PASS, 45 FAIL, 12 ERROR, 34 NOTE** — `run.sh` exit **1**
(no slice aborted: every recorded rc is 0 or 1)

```
counts   every failing row this run recorded (reference run included):
         code=4 (product=0 triage=4)   tool=2   env=4   harness=41   order=15
```

In the TOTAL row alone: **2 counted defects, 55 attributed**. The reference run
`09-fw-all` contributes 2 counted and 7 attributed of its own and is never
folded into TOTAL.

Evidence: `tests/.out/` as recorded by that run — a later run replaces it, so
re-run the command under *Evidence map* to reproduce rather than reading a
stale `.out`.

**This document reports. It changes nothing under `src/` or `webapp/`.** Every
claim is tied to a recorded evidence row in `tests/.out/` or to a `file:line`
in the tree as it stands. Ranked by what blocks shipping, not by class.

---

## Verdict

| # | Finding | Class | Blocks shipping? | Fix belongs in |
|---|---|---|---|---|
| B1 | Two functional suites verify nothing | `harness` | **yes** | `webapp/test/test_users_module.sh`, `webapp/test/test_customer_module.sh` |
| B2 | The session store's mode is a launcher obligation, not a guarantee | `env` | **yes** | the launcher / a decision about the product guarantee |
| B3 | `Audit/A0116` — test contract vs. framework intent | `triage` | no, but it is the only thing left counted | `tests/unit/src/hix_test_audit.prg` *or* `src/hix_config_app.prg` |
| B4 | Latent initialization of `s_mtxRoutes` / `s_hMutex` | `order` | no | `src/hix_router.prg`, `src/hix_zombie.prg` |
| B5 | `users.dbf` is not the seed the suites assume | `env` | no | re-seed, then re-run |
| B6 | Test key material present in git history | `NOTE` | no | a recorded rotate/purge decision |
| B7 | 41 session files older than this run are not 0600 | `NOTE` | no | one `chmod 600` pass |

---

## B1 — Two of the three functional suites verify nothing

```
31-wa-users     rc=2, aborted, 0 of 46 planned cases ran
32-wa-customer  Total tests : 50   Passed : 22   Failed : 28
```

Both failures are properties of the project's own scripts, and both are
evidenced by grepping those scripts rather than by assumption:

* `webapp/test/test_users_module.sh:13` pins `API="http://localhost:9090"`
  and never reads `TEST_API`, so the slice cannot point it at the TLS-only
  app (`webapp/hix.json` has `"ssl": true`). The script aborts on its own
  preflight with `rc=2`. Check `users.api.hardcoded`.
* `webapp/test/test_customer_module.sh` honours `TEST_API`, and the slice
  points it at `https://localhost:9090`, but its cookie handling is one-sided:
  T08 (`:65-69`) is the **rejected** POST and it is the one that writes the jar
  (`--cookie-jar`), while T09 (`:75-80`) is the authenticating POST and sends
  `--cookie` only. The jar therefore holds the pre-auth session, and every
  session-dependent case after T09 replays it and gets 302. Check
  `customer.cookie.jar` counts the authenticating POSTs that send a CSRF token
  and save no jar.

**Why this blocks shipping.** The 28 failures say nothing about the app, and
neither does the absence of anything else: the users module and the customer
module are effectively unverified by this run. `33-wa-verify` is the only
suite that authenticates successfully against the TLS app (127 cases, 124
pass, 0 counted), and it is what the shipping decision can rest on.

Fixing either script also makes its check stop reporting `ok`, so the
failures come back as `triage` — the demotion cannot outlive its evidence.

---

## B2 — The session store's mode is a launcher obligation

`30-repo perm.session_files` and `33-wa-verify H-05c` are the same fact seen
from two sides. Three facts, all needed to fix it correctly:

**a) The framework cannot set the mode, and says so.**
`src/hix_session.prg:616` (`_HixSessionFileWrite`) writes with
`hb_MemoWrit( cTmp, cFinal )` (`:642`) + `FRename()` (`:649`) and never sets a
mode. `webapp/probe_fmode.hbp` proves the language cannot:
`37-wa-probe-fmode` reports `change mode from Harbour : impossible (umask/chmod not linked)`.
So the effective mode is `0666 & ~umask` of whoever exec'd the binary.

**b) This run reused a server it did not start, with the wrong umask.**

```
tests/.out/run.log:1   reusing the HIX app already answering on https://localhost:9090
ps                     PID 645753  started Tue Oct  6 15:38:35  ./app --port 9090
/proc/645753/status    Umask: 0022          -> files 0644
```

`webapp/go_gcc.sh:26` sets `umask 077` and `:134-139` chmods an existing store
(`chmod 700` + `chmod 600` on its files) precisely because "umask cannot fix an
existing file". `tests/lib/common.sh` would have used `umask 077` too, but
`hix_server_start()` short-circuits when something already answers on the port,
and `run.sh` prefers reusing a live app.

**c) The payload is not in the clear, so this is not a plaintext leak.**
`src/hix_session.prg:624-629` is Encrypt-then-MAC: `hb_blowfishEncrypt` under
a key derived from `s_cSeed`, then `hb_HMAC_SHA256`, then base64. Verified on a
live file this run: 132 bytes on disk → 97 decoded → 64 hex HMAC + `|` +
ciphertext. What `0644` exposes is the sid and the ciphertext; **the store
directory's mode is what actually keeps them private**, and that mode is
launcher-dependent as well.

**Why this blocks shipping.** Any deployment that execs `./app` directly — a
systemd unit, a supervisor, `./app &`, which is exactly what happened here —
lands the store at `0755` with `0644` records. `webapp/go_gcc.sh` is the only
place inside the project folder that can set the mask, and nothing enforces
that a deployment goes through it.

**The decision to make.** Either "session records are private" is a launcher
convention, in which case every deployment path must be documented as such
(`webapp/srs/DEV-compliance.md` is where it belongs), or it is a product
guarantee, in which case Harbour cannot currently provide it and the options
are a small C shim compiled with the app (`fchmod`), writing through
`hb_fCreate` with an explicit mode, or both. Today the code, the probe, the
launcher and the test each encode a different assumption.

The demotion stays falsifiable: start the app through `webapp/go_gcc.sh` and
the check `session.mode.umask` reports `fail`, so a 0644 session file is
counted again.

---

## B3 — `Audit/A0116` is the only thing still counted

```
Audit/A0116 :: A1.16: HIX_ConfigAppDefaults() genera clave jwt distinta
                en cada llamada        Expected: distinct  Got: SAME-KEY
Audit/A0116 :: clave generada tiene >= 32 chars   Expected: >=32  Got: 0
```

Reported twice — once in `09-fw-all`, once in `20-fw-audit-a01` — because it
is two assertions of one test, not four defects.

`tests/unit/src/hix_test_audit.prg:1638-1661` demands that `HIX_ConfigAppDefaults()`
return a `keys` hash with a freshly generated `jwt` value. `src/hix_config_app.prg:113`
deliberately has none: *"NO `keys` section here (PENTEST-REPORT.md §1)"* — secrets
come from `HIX_KeySet()` or `HIX_KeysLoadFromAppConfig()`, in memory only.

**The security half of A0116 passes**, so this is not a secret leak: the
sibling assertions at `:1665-1683` prove `HIX_JwtDefaultKey()` and
`HIX_TokenGetSecret()` use the store key and no hardcoded fallback.

Nothing in this run evidences which side is wrong, so the suite counts the
failure rather than explaining it, and `run.sh` still exits 1. Resolve it by
deleting the two assertions or by shipping the `keys` section; either way the
suite stops reporting a defect.

---

## B4 — Latent initialization: not a production runtime failure today

15 rows, class `order`, present only in the group slices.

* `src/hix_router.prg:18` `STATIC s_mtxRoutes := NIL`, created only at
  `:68` inside `HIX_RoutesLoad()`; thirteen call sites lock it
  (`:216 :403 :467 :475 :486 :518 :560 :567 :657 :776 :1568 :1651 :1678`) and
  only two guard it.
* `src/hix_zombie.prg:16` `STATIC s_hMutex := NIL`, created only at
  `:30` inside `HIX_ZombieInit()`; `HIX_ZombieAdd/Dead/Count/Report/Purge`
  (`:45 :72 :102 :123 :155`) lock it unguarded. Harbour raises `EG_ARG`
  subcode **3012** on a NIL mutex handle — which is why `HixStyle/Acl` and
  `Other/Abort` print `Got: 3012` where a status was expected.

**Production is safe today**, verified along the entry path:
`webapp/src/app.prg:105 oServer:Start()` → `src/hix_server.prg:268 HIX_ZombieInit()`
and `src/hix_server.prg:485 HIX_RoutesLoad()`. It bites only if
`THixDispatcher` or the router API is used without a started server — which is
exactly what the ACL, Abort and audit tests do
(`hix_test_audit.prg:39` states the assumption out loud: the suite has no such host).

Worth fixing as an API contract, not as a shipping blocker: the pattern already
exists in the same file, `INIT PROCEDURE _HixRouterMutexInit()`
(`src/hix_router.prg:32-43`, added for audit A2.06). Apply it to `s_mtxRoutes`,
`s_mtxActions` and `src/hix_zombie.prg:s_hMutex`; a mutex handle is not
application state, so creating it eagerly cannot be wrong.

---

## B5 — `users.dbf` is not the seed the suites assume

```
rec 2 NAME 'carlesX' != seed 'carles'   rec 4 NAME 'john' != seed 'John'
```

`webapp/regenerate_users.prg:18-20` seeds `{ "admin", "carles", "maria", "John", "jane" }`
("John" is mixed-case on purpose: it proves the Lower(name) CDX tag round-trips).
The rows on disk are not that seed: record 2 was renamed by
`webapp/test/test_users_module.sh:175` (its T44), and record 4 came from an older
seed list whose digest matches password `1234`, not the seeded `5678`.

So `D-09f` (expected `carles`, got `carlesX`) and `D-16d` (login as `JOHN` → 302)
are leftover state, class `env`, evidenced by the check `seed.users.dbf.stale`,
which diffs the DBF against the seeder's own list.

**Do re-seed before treating `D-16d` as anything:**
`cd webapp && hbmk2 regenerate_users.hbp && ./regenerate_users` with the server
stopped, then `./tests/run.sh 33-wa-verify`. If `D-16d` still fails on a freshly
seeded `John/5678`, it becomes a real case-insensitivity finding worth
investigating — note that D-16 spends 6 `/auth` attempts against a 5/60 s
limit (`webapp/www/middlewares/config.json:26-30` — `window_s 60`, `login_max 5`), so a failure there is easy to
misattribute to rate limiting; `logged_in()` reports 429 separately
(`verify-users-fixes.sh:104-109`) and this run reported 302, so it was not.

---

## B6 — Test key material in git history

`secret.history` NOTEs that `tests/unit/hix_test.crt` and `tests/unit/hix_test.key`
were ever added, at commits `5f708be` ("Added tests/unit to check all the
functionalities of the HIX server") and `2553536` ("Add. vrs. 2.1 - Linux
support"). They are not tracked now (`secret.tracked` PASS).

They are a self-signed **test** pair generated by `tests/unit/make_test_cert.sh`
(`tests/unit/go_gcc.sh` runs it on demand), and they are now ignored by
`tests/.gitignore:13-14`. The production material is separate and clean:
`webapp/hix.keys.json` and `webapp/certs/hix.key` are `0600`, ignored, and
never tracked.

Record the decision — rotate or accept — rather than inferring "no action" from
a NOTE row.

---

## B7 — Leftover session files

`perm.session_files.leftover` NOTEs 41 files older than this run that are not
0600. `perm.session_files` itself now asserts only about files this run wrote;
`HIX_RUN_TS` (`lib/common.sh`, exported once by `run.sh`) is what makes that
split possible. One `chmod 600` pass over `webapp/.sessions` clears it;
`webapp/go_gcc.sh:134-139` already does that on every launch.

---

## Clean in this run — do not "fix" these

`secret.tracked` (no key/cert tracked) · `path.portable` (no absolute home
paths in tracked files) · `gen.tracked`, `gen.data.tracked`, `gen.config.tracked`
(`www/config.json` untracked — the original key leak) · `srv.tls_only` (plain
http refused, `000`) · `app.keys.mode` / `app.key.mode` `0600` ·
`app.keys.outside_docroot` · `app.cert.expiry` → `Oct  6 04:10:17 2027 GMT` ·
`cfg.session.crypt` (`crypt=true`) · `data.residue` (23 rows, 0 residue — the
suites clean up after themselves).

And `33-wa-verify`: 127 cases, 124 pass, **0 counted**. The app authenticates
and behaves correctly over TLS.

---

## Order of work

1. Fix the two test scripts (B1) — nothing can be certified until they run.
2. Decide the session-store guarantee (B2) and make every deployment path
   satisfy it.
3. Re-seed `users.dbf` (B5), then re-run `33-wa-verify` before reading `D-16d`.
4. Settle the `A0116` contract (B3) — it is the last thing left counted.
5. Apply the `INIT PROCEDURE` pattern to the router and zombie mutexes (B4).
6. Record the key-material decision (B6).

---

## Evidence map

```
# the run itself
./tests/run.sh --fresh
./tests/index.sh                                   # index of the last run
./tests/slice.sh 07-harness --digest --full        # which demotion rules hold now
tests/.out/checks.tsv                              # check-id  ok|fail  evidence
tests/.out/index.txt                               # uncapped index

# B1
./tests/slice.sh 31-wa-users --digest
./tests/slice.sh 32-wa-customer --cases --status FAIL

# B2
./tests/slice.sh 37-wa-probe-fmode --cases         # chmod from Harbour: impossible
ps -o pid,lstart,cmd -C app ; grep Umask /proc/<pid>/status
grep -n "chmod\|umask" webapp/go_gcc.sh

# B3
./tests/slice.sh 20-fw-audit-a01 --cases --defect

# B4
cd tests/unit && ./app --cli Acl                   # 3012 with no host server
./tests/run.sh --no-fw-ref 12-fw-hixstyle          # order rows stay counted

# B5
python3 webapp/test/dbf_dump.py webapp/data/users.dbf
./tests/slice.sh 33-wa-verify --cases --class env

# B6
git log --all --oneline --diff-filter=A -- tests/unit/hix_test.key tests/unit/hix_test.crt
```

Key source locations cited:
`src/hix_session.prg:616,624-629,642,649` · `src/hix_router.prg:18,32-43,68,216,403,467,475,486,560,657,776` ·
`src/hix_zombie.prg:16,28,30,45,72,102,123,155` · `src/hix_server.prg:268,485` ·
`src/hix_config_app.prg:113` · `src/hix_request.prg:222` ·
`tests/unit/src/hix_test_audit.prg:39,1638-1683,239,331` ·
`tests/unit/src/hix_test_hixstyle_acl.prg:29` · `tests/unit/src/hix_test_abort.prg:68-72` ·
`tests/unit/src/hix_test_utils.prg:19-33` · `tests/.gitignore:13-14` ·
`webapp/src/app.prg:68,105` · `webapp/go_gcc.sh:26,134-139` ·
`webapp/test/test_users_module.sh:13,175` · `webapp/test/test_customer_module.sh:65-69,75-80` ·
`webapp/test/verify-users-fixes.sh:104-109,388,423-432,539` ·
`webapp/regenerate_users.prg:18-20` · `webapp/probe_fmode.hbp` ·
`tests/lib/common.sh` (`HIX_RUN_TS`, `hix_server_pid`, `hix_server_umask`, `hix_umask_mode`) ·
`tests/lib/rules.tsv` (`repo.perm.session.umask`, `wa.verify.session.umask`, `wa.verify.stale.seed`) ·
`tests/slices/s07_harness.sh` (checks `session.mode.umask`, `seed.users.dbf.stale`).

See also `TEST-REPORT-2026-10-06.md` (§14 addendum) for the per-cluster root-cause
analysis behind B1–B7 and for the suite-side fixes that landed after it.
