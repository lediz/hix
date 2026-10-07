# Fix recommendations, checked against `DEV-compliance.md` — report only

This document **reports**. It changes nothing under `src/`, `webapp/`, or `data/`, and it does not
run any of the commands it names. It takes the fix recommendations that already exist in the corpus
— `LETS-ENCRYPT-PLAN.md`, `PASSWORD-COMPLIANCE-PLAN.md`, `PRODUCTION-BLOCKERS-2026-10-07.md`,
`BRUTE-FORCE-PENTEST-PLAN.md` BF-10, `site-docs/en/hixstyle/seguridad/ssl.md` — and grades each one
against the binding constraints, then states the **compliant form** of the ones that are not
compliant as written.

Date: 2026-10-07.

---

## 1. The constraint, as written (`webapp/srs/DEV-compliance.md`)

Eight testable clauses. Every recommendation below is graded against them by number.

| Test | Clause (quoted) |
|---|---|
| **T1** | "WebApp must strictly comply with HIX style only." |
| **T2** | "No SQL." |
| **T3** | "No 3rd Party WEB UI." |
| **T4** | "Only HIX framework and Harbour language is allowed." |
| **T5** | "Adhoc tools, scripts, and alike should only be created in project folder." |
| **T6** | "No change will be done outside project folder." |
| **T7** | "Build the WebApp using `hbmk2 app.hbp` only." |
| **T8** | "Web service will use pot 9090." *(sic — "pot")* |

Verdict legend used throughout:

| Mark | Meaning |
|---|---|
| ✅ | Compliant as written. Lands inside the project folder, uses HIX/Harbour only, no build-recipe change, no port change. |
| ⚠️ | Compliant **only under a restated scope** — the action is inherently outside the project folder (issuance, package install, privileged port). The repository stays compliant; the *host* does not. The restatement must be recorded, not assumed. |
| ❌ | Non-compliant as written. The row gives the compliant substitute. |

Two facts that make the build tests decidable:

* `webapp/app.hbp:18` lists exactly one source — `src/app.prg`. Everything under `www/`
  (controllers, models, views, loaders) is transpiled/loaded at runtime, so **a change under
  `www/` never touches T7**. Precedent for the claim is in the code: `webapp/www/models/hpassword.prg:4`
  — "needs no contrib library, so it links into the HIX server without touching `app.hbp`".
* A change to `webapp/src/app.prg` also keeps T7 (it is the one file `app.hbp` already builds).
  A change to the framework at the repository root (`src/hix_*.prg`) is a different build step —
  `go_lib_gcc.sh` → `lib/gcc/libhix_server.a`, documented in `webapp/readme.md:13-19`. T7 governs
  the WebApp; the framework build is its own documented obligation.

---

## 2. TLS / Let's Encrypt recommendations (`LETS-ENCRYPT-PLAN.md`)

| Id | Recommendation (as planned) | Lands in | Grade | Compliant form |
|---|---|---|---|---|
| R-T1 | Keep the two config names; point `certs/hix.key` / `certs/hix.crt` at the ACME `privkey.pem` / `fullchain.pem` | `webapp/certs/` (gitignored, `webapp/.gitignore:21`), `hix.json:17,18` unchanged | ✅ | as written — this is the compliant shape and it is the framework's own mapping (`ssl.md:77-78`) |
| R-T2 | Pin `server.allowed_hosts` to the real domain | `webapp/hix.json:15` | ✅ | as written; `_HixHostAllowed` (`src/hix_worker_http.prg:277,279,281`) already implements the control, so no new code is needed — that is what keeps it T1-compliant |
| R-T3 | `server.port` 9090 → **443** | `webapp/hix.json:9` | ❌ **T8** | **Keep 9090.** ACME does not require the app to own 443: HTTP-01 validation is performed by certbot's own bind on **80** of the production host, and the browser reaches the app at `https://<domain>:9090`. HSTS is keyed by host, so the non-standard port is still covered. Record the port as a production-host property, not a config change |
| R-T4 | Issue with `certbot certonly --standalone` (install, `/etc/letsencrypt`, port-80 bind, crawler) | outside the project folder | ⚠️ **T5, T6** | Wrap it in a project-local script (precedent: `gen_cert.sh`, `go_gcc.sh`) and keep certbot's own state inside the project folder with `--config-dir`/`--work-dir`/`--logs-dir` (defaults `/etc/letsencrypt`, `/var/lib/letsencrypt`, `/var/log/letsencrypt`). The irreducible remainder — the outbound ACME request and the inbound crawler — is a **host** action; restate DEV-compliance's scope for the production host and write that restatement into the report. Do not pretend the wrapper makes the network call compliant |
| R-T5 | Restart `./app` after renewal via a systemd unit | outside the project folder | ❌ **T6** | `certbot renew --deploy-hook ./tls_restart.sh`, with `tls_restart.sh` a project-local script (same class as `go_gcc.sh`). The supervisor decision stays inside the folder |
| R-T6 | `setfacl` / `chgrp` on `/etc/letsencrypt/live/…` so the app can read `privkey.pem` | outside the project folder | ❌ **T6** | Use the unprivileged layout (D-4 δ): certbot run with `--config-dir` inside the project folder produces a **user-owned** tree, so no ACL is needed and the app reads it directly. This also removes the L-02 failure mode (guard checks existence, not readability — `webapp/src/app.prg:369` vs `src/hix_io.prg:553,560`) |
| R-T7 | Extend `_TlsGuard()` from an existence test to a readability test | `webapp/src/app.prg:369` | ✅ | as written; it is Harbour + the app's own config read, and `app.prg` is already in `app.hbp` (T7 unchanged) |
| R-T8 | Gate the launcher's `./gen_cert.sh` call so a production install never regenerates a self-signed pair over the ACME one | `webapp/go_gcc.sh:120-121` | ✅ | as written (project-local launcher, T5) |
| R-T9 | Adopt the reverse-proxy shape, D-1 (b) (`server.ssl = false`, `mode: proxied`, nginx/Apache terminates TLS) | third-party server, config outside | ❌ **T4, T6** (and T3 in spirit) | **Do not.** This is why `LETS-ENCRYPT-PLAN.md` D-1 chose (a). Note the conflict: `site-docs/en/hixstyle/seguridad/ssl.md` §Best practices 4 recommends a proxy "in prod" — the framework's own advice is **not** DEV-compliance-compliant. Record the conflict; do not follow the doc |
| R-T10 | ssl.md §Best practices 2: "Port 80 is only for redirecting 301 to https" | a second listener on 80 | ❌ **T8** | Redirect inside the app at 9090 using the framework's own helpers — `UIsHttps()` (`src/hix_helpers.prg:219`), `UScheme()` (225), `src/hix_request.prg:222` already derives `https` from `oIO:lUseSSL` with no proxy headers. No port-80 listener |
| R-T11 | HSTS | already emitted unconditionally: `src/mw/hix_mw_secheaders.prg:91`, `max-age=31536000` | ✅ (no action) | Nothing to build. The recommendation is a **decision**, not a fix: fix the final domain before the first public issuance, because the header is already permanent (R-1) |

**Net for TLS:** the compliant change set is *config + two project-local scripts + one guard
strengthening in `app.prg`*, with the port left at 9090 and no proxy. Everything else about
Let's Encrypt is a host action that must be declared as such.

---

## 3. Password-compliance recommendations (`PASSWORD-COMPLIANCE-PLAN.md`)

| Id | Recommendation | Lands in | Grade | Note |
|---|---|---|---|---|
| R-P1 | Verifier length: `auth.prg:42` → `required\|minlen:8\|maxlen:64` | `webapp/www/controllers/auth.prg` | ✅ | Uses HIX's own rule grammar (`src/validator/hix_val_rules.prg:140,151`), so T1 holds; `www/` change ⇒ T7 untouched |
| R-P2 | Registration/change length: `users.prg:337,393` → `minlen:8\|maxlen:64` | `webapp/www/controllers/masters/users.prg` | ✅ | Prefer `minlen`/`maxlen` over `min`/`max`: the string branch of `min` *is* a length check (`hix_val_rules.prg:92-113`) but reads numeric in review |
| R-P3 | Blocklist (C-06): a **codeblock rule** inside `UValidatePost`, denylist file in the project folder, outside the docroot | `users.prg` + e.g. `webapp/.pwdeny/` (gitignored, committed `*.example` template) | ✅ | Codeblock rules are part of the existing grammar (`src/hix_validator.prg:300-312`), so this is HIX style, not a hand-rolled parse. Two non-compliant variants to avoid: fetching a remote blocklist at runtime (breaks T4 and the offline guarantee), and placing the file under `www/` (docroot root-level files are downloadable — `PENTEST-REPORT.md §1`) |
| R-P4 | KDF (C-07): PBKDF2-HMAC-SHA256 composed in Harbour from `hb_hmac_sha256` | `webapp/www/models/hpassword.prg` | ✅ | `hb_hmac_sha256` is Harbour **core RTL** (`$HB_ROOT/src/rtl/hbsha2hm.c`), the same family as the `hb_sha256` already used — so T4 holds and, per the precedent comment at `hpassword.prg:4`, `app.hbp` is not touched. T2 holds (no SQL anywhere in the path) |
| R-P5 | KDF (C-07): Argon2id / bcrypt / scrypt | — | ❌ **T4** | Not reachable: none of them exist in Harbour core or `contrib/hbssl` (verified by grep of the Harbour tree; hbssl exposes `EVP_BYTESTOKEY`/`EVP_DIGEST*`, not `PKCS5_PBKDF2_HMAC`). The compliant report line is "C-07 improved to PBKDF2-HMAC-SHA256 with a measured iteration count; memory-hardness not reachable under T4" |
| R-P6 | Iteration count derived from a measured latency budget, not copied from OWASP's 600 000 | `webapp/test/probe_pwcost.prg` (+ its `.hbp`) | ✅ | Probe is project-local (T5) and already exists. Building it is `hbmk2 webapp/test/probe_pwcost.hbp` — T7's "app.hbp only" clause governs the WebApp; the precedent for adhoc `.hbp` tools is already in the tree (`probe_*.hbp`, binaries in `webapp/.gitignore:7-17`) |
| R-P7 | Per-account consecutive-failure counter with ≤100 bound and escalating wait (30 s → 1 h) | `data/login.dbf` (RDDCDX) + `webapp/www/middlewares/myapplogin.prg:25-26,63-67` | ✅ | RDDCDX/DBF, so T2 holds ("No SQL" — not sqlite, not a database layer). Note the session store cannot hold it: it is per-session, not per-account |
| R-P8 | Pepper (C-08/C-11): a per-verifier secret mixed into the KDF | held like `hix.keys.json` (`webapp/gen_keys.sh`, 0600, outside `paths.root`) | ✅ | Same placement discipline as the five signing keys (`webapp/readme.md:33`) |
| R-P9 | Re-seed after any KDF/policy change | `webapp/regenerate_users.prg:20,43-48,61` | ✅ | Project-local tool; the seeded passwords themselves must satisfy the new policy (they are currently `"1234"`, `"5678"`, `"9012abcd"`) |
| R-P10 | Retire the plaintext path: `migrate_users.prg` writes `hRow["pass"] := "1234"` into `pass C(40)` and `DbAppend`s to an existing DBF | `webapp/migrate_users.prg:22,26,33,47,61` (tracked in git) | ✅ | Deleting/rewriting a project-local tool is inside the folder; git is the rollback mechanism (D-14). Until retired it is an open C-10 violation of OWASP's "never stored in plain text" |
| R-P11 | UI text: stop printing the demo password (`login.html:48` placeholder "Password is 1234..."), state the new policy (`edit.html:99` "Min 4 characters") | `webapp/www/views/…` | ✅ | The app's own views — T3 holds ("No 3rd Party WEB UI" is not implicated) |
| R-P12 | Decide trimming once: the `string` cast already mutates the secret (`src/validator/hix_val_cast.prg:27-30` `AllTrim( UStr( … ) )`) | `hpassword.prg` or the rules | ✅ | Semantic note, not a new dependency: a password with a leading/trailing space is not verifiable as typed today (C-03 caveat) |
| R-P13 | Widen `PASS C(128)` if the digest encoding needs it (a `v2:` tag competes with a 64-byte output) | `webapp/regenerate_users.prg:43-48` + re-seed | ✅ | Schema lives in a project-local tool; forces R-P9 |
| R-P14 | Fixture sweep: `"1234"` = 12 occurrences in 6 tracked files + 39 in the untracked `webapp/test/` suite | tracked files ✅ / untracked suite ⚠️ | ⚠️ | The suite is not in git (untracked on 2026-10-06, `webapp/srs/UNIFIED.md`), so a fresh clone cannot be fixed from the repository. Report that as a known gap rather than claiming the change is self-contained |

**Net for passwords:** every substantive recommendation is ✅. The only ❌ in the set is the
KDF algorithm itself (R-P5), and the only ⚠️ is the test-fixture sweep. That is why the password
work is far more inside the constraint than the TLS work.

---

## 4. Cross-check of the recommendations that already exist elsewhere in the corpus

| Id | Existing recommendation | Where it belongs | Grade |
|---|---|---|---|
| B1 | Two functional suites verify nothing (`test_users_module.sh` aborts rc=2, 0 of 46; `test_customer_module.sh` 28 of 50 fail) | `webapp/test/*.sh` | ✅ T5 — but ⚠️: those files are untracked, so the fix is local-only |
| B2 | Session-store mode is a launcher obligation, not a guarantee | launcher (`go_gcc.sh` umask/chmod pass) | ✅ launcher-side is compliant. The alternative — enforce the mode inside the app — is ❌ **T4**: Harbour links no `chmod`, so it would need a contrib/foreign dependency |
| B3 | `Audit/A0116` test contract vs framework intent | `tests/unit/src/hix_test_audit.prg` *or* `src/hix_config_app.prg` | ✅ both are inside the project folder (repo root is the project folder) |
| B4 | Latent initialization of `s_mtxRoutes` / `s_hMutex` | `src/hix_router.prg`, `src/hix_zombie.prg` | ✅ T1/T4; rebuild is the framework's own step (`go_lib_gcc.sh`), not `app.hbp` |
| B5 | `users.dbf` is not the seed the suites assume | re-seed via `regenerate_users.prg` | ✅ |
| B6 | Test key material present in git history | rotate + purge | ✅ T5/T6 (git is in the folder) — irreversible, so record the decision before doing it |
| B7 | 41 session files older than the run are not 0600 | one `chmod 600` pass | ✅ |
| BF-10 | Raise `PW_HASH_ITERATIONS`, enforce a longer minimum, re-seed | `hpassword.prg`, `auth.prg:42`, `regenerate_users.prg` | ✅ — and it is the same shape as R-P4/R-P6/R-P9; do not treat it as a separate fix |
| ssl.md §Best practices 4 | "Behind a proxy in prod" | nginx/Apache | ❌ **T4, T6** — see R-T9 |
| ssl.md §Best practices 2 | HTTP→HTTPS redirect on port 80 | second listener | ❌ **T8** — see R-T10 |
| ssl.md §Best practices 6 | "No committed keys. `certs/*.key` never to the repo" | `webapp/.gitignore:21` | ✅ already satisfied; extends unchanged to `privkey.pem`/`fullchain.pem` |

---

## 5. The violations list, in one place

Non-compliant as written, with the compliant substitute:

| # | Would violate | Substitute |
|---|---|---|
| V-1 | `server.port = 443` (T8) | keep 9090; ACME challenge on the host's 80; `https://<domain>:9090` |
| V-2 | reverse proxy terminating TLS (T4, T6) | HIX terminates TLS directly — `LETS-ENCRYPT-PLAN.md` D-1 (a) |
| V-3 | systemd unit / cron / `setfacl` / `chgrp` outside the folder (T6) | project-local restart script; certbot `--config-dir` inside the folder |
| V-4 | package install + `/var/lib`, `/var/log` state (T5, T6) | declare it a host action; keep certbot's dirs in the folder |
| V-5 | Argon2id / bcrypt / scrypt library (T4) | PBKDF2-HMAC-SHA256 from Harbour RTL `hb_hmac_sha256` |
| V-6 | remote blocklist lookup at registration (T4, offline) | project-local denylist file, outside `www/` |
| V-7 | enforcing the store guarantee inside the app via `chmod` (T4) | launcher-side obligation, stated as such (B2) |
| V-8 | a second listener on port 80 for the redirect (T8) | in-app redirect via `UIsHttps()`/`UScheme()` |

Nothing in the ✅ set requires a new build target, a new library, a new port, or a file outside
`webapp/` or the repository root.

---

## 6. What is compliant, ranked by what it unblocks (still report only)

1. **R-P1, R-P2** — verifier and registration length. Smallest change, largest compliance gap
   closed (C-01, C-02), no new dependency, no build change. Blocked only by R-P9 (re-seed) and
   R-P14 (fixtures).
2. **R-P4 + R-P6** — the KDF construction and its measured cost. Closes the "SHA-256 is not
   suitable" gap to the ceiling the constraint allows; must ship with the §8-style caveat.
3. **R-P3** — blocklist. Closes C-06, which the seeded passwords themselves fail.
4. **R-P10** — retire `migrate_users.prg`. Closes the only true plaintext path (C-10). Cheap.
5. **R-P7** — per-account throttle. Closes C-09; needs a new project-local DBF, the most
   implementation-heavy item in the set.
6. **R-T1, R-T2, R-T7, R-T8** — the compliant TLS core: names, host pinning, guard
   strengthening, launcher gate. All inside the folder.
7. **R-T4, R-T5, R-T6** — TLS on a production host: ⚠️ items that need the scope restatement
   written down before they are attempted, and a domain decision that does not exist yet
   (`webapp/hix.json:8` is `localhost`; no deploy target exists in the repository).
8. **R-P8, R-P11, R-P12, R-P13** — pepper, UI text, trimming decision, field width.

---

## 7. Evidence map (re-derive, do not trust this file)

```bash
cat webapp/srs/DEV-compliance.md
grep -n 'src/app.prg' webapp/app.hbp                       # T7 is decidable: one source file
grep -n 'min:4\|max:40' webapp/www/controllers/auth.prg webapp/www/controllers/masters/users.prg
grep -n 'minlen\|maxlen\|regex\|between\|notin' src/validator/hix_val_rules.prg | head
grep -n 'aTokensOrig\[ i \] ) == "B"' src/hix_validator.prg   # codeblock rules exist (T1)
grep -n 'AllTrim( UStr' src/validator/hix_val_cast.prg         # the cast mutates the secret
grep -n 'PW_HASH_ITERATIONS\|hb_sha256' webapp/www/models/hpassword.prg
grep -n 'login_max\|login_window' webapp/www/middlewares/config.json webapp/www/middlewares/myapplogin.prg
grep -n '1234' webapp/migrate_users.prg                        # the plaintext path
grep -n '"port"' webapp/hix.json                               # T8: 9090
grep -rhoE "hb_(hmac_sha256|hmac_sha512|sha256|sha512)" $HB_ROOT/src/rtl/*.c | sort -u
grep -rli "bcrypt|argon|scrypt|pbkdf2" $HB_ROOT/src $HB_ROOT/contrib
grep -n 'libs=hbssl' hix_server.hbc
```

## 8. What this report does not do

* It does not apply any fix. No file under `src/`, `webapp/`, or `data/` is modified.
* It does not decide the domain, the latency budget, the iteration count, or the blocklist source
  — those are the D-* decisions in the two plans, and each ⚠️/❌ row above still needs one.
* It does not re-rank the shipping blockers; `PRODUCTION-BLOCKERS-2026-10-07.md` owns that ranking.
  §4 only grades those recommendations against DEV-compliance.
* It does not treat DEV-compliance as immutable. Where the framework's own documentation
  (`ssl.md` §Best practices 2 and 4) contradicts it, the contradiction is recorded (R-T9, R-T10)
  rather than resolved by editing either document.
