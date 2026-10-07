# Password compliance plan — industry-standard complexity on the webapp's memorized secret

Scope: the one memorized secret this app has — the account password submitted at `POST /auth`
(`webapp/www/routes/web.json`: `sys.auth`) and written at `POST /users/store` /
`POST /users/:id/update`. "Complexity" here means the current published guidance for
**memorized-secret verifiers**, not "add a special character". The standards say the opposite of
the reflexive fix in several places; §4 records that explicitly.

Status: **plan only.** Nothing below has been executed. No file under `src/`, `webapp/`, or
`data/` is modified by this document.

Date: 2026-10-07.

Standards sources, quoted verbatim from the pages fetched on that date — re-check before acting,
the numbers move between revisions:

| Tag | Source |
|---|---|
| **NIST** | SP 800-63-3 rev. B, <https://pages.nist.gov/800-63-3/sp800-63b.html> §5.1.1.1, §5.1.1.2, §5.2.2, key-stretching section |
| **OWASP** | Password Storage Cheat Sheet, <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html> ("To sum up our recommendations" paragraph) |
| **Local** | `webapp/srs/BRUTE-FORCE-PENTEST-PLAN.md` BF-10 (the offline-cost finding that already names this remediation) |

---

## 1. Ground rules (binding — read before running anything)

| Rule | Why |
|---|---|
| **Do not add character-class requirements.** NIST §5.1.1.1: *"No other complexity requirements for memorized secrets SHOULD be imposed."* | The length + blocklist pair is the standard; mandated classes are not. A plan that "reinforces complexity" by demanding `A-z-0-9` is *not* industry standard and measurably reduces entropy per character of user effort. See C-05. |
| Changing the KDF or its work factor **invalidates every stored digest** | `webapp/www/models/hpassword.prg:30-31` states it: "Changing this value invalidates every digest already stored in `users.dbf`: re-seed with `regenerate_users.prg` afterwards." There is no per-record version tag today (§6 D-6 decides whether to add one). A half-migrated store means every existing account silently fails to log in. |
| The seeded passwords and the test fixtures are the same secret as the policy | `"1234"` appears **12 times in 6 tracked files** and **39 times in the untracked local suite** (`webapp/test/`). Raising the minimum length without re-seeding and re-deriving the fixtures breaks the suites — see §7. |
| Never let a plaintext password reach the DBF, a view, the flash, the session, a log, or this document | Already a closed control (D-05, D-07, `PENTEST-REPORT.md §6`). Any new probe tool must obey it too: digests and salts are printable, plaintexts are not. |
| Keep the constant-work path | `PW_DUMMY_SALT` + `_PwHash( cPass, PW_DUMMY_SALT )` on the unknown-name path (`webapp/www/models/modeluser.prg:75`, D-17) exists so an unknown username is not ~4 ms cheaper. Any KDF change must preserve cost parity, or the change re-opens the enumeration oracle. |
| Keep the non-early-exit comparison | `_PwMatch()` (`webapp/www/models/hpassword.prg`) deliberately keeps scanning after a mismatch. Do not "simplify" it to `==`. |
| Measure, do not assume, any work factor | The only defensible iteration count is one measured on the target box against a stated latency budget. `webapp/test/probe_pwcost.prg` already exists for exactly this; §6 extends it, it does not replace it. |
| No new crypto dependency | `webapp/srs/DEV-compliance.md`: HIX + Harbour only. Argon2id, bcrypt, scrypt and PBKDF2 are **not in Harbour** (§8, verified by grep of the Harbour tree). A third-party KDF library is not an option; the plan must say so rather than quietly import one. |
| The blocklist is a file, not a network call | No outbound lookup at registration time. The app must stay functional offline; a remote "has this password been leaked?" query is a dependency and a privacy leak. |

---

## 2. What already exists (do not duplicate it)

| Thing | State | Use it for |
|---|---|---|
| `webapp/srs/PENTEST-REPORT.md` §6 | D-07 (digest not plaintext), D-16 (name normalised once), D-17 (constant work on the unknown-name path), `_PwMatch` non-early-exit | The **baseline**. A compliance pass must re-confirm these still hold; it must not re-report them. |
| `webapp/srs/BRUTE-FORCE-PENTEST-PLAN.md` BF-10 | Already prescribes: raise `PW_HASH_ITERATIONS` (50 000 ≈ 17.8 ms measured), enforce a longer minimum (`auth.prg:42` "currently allows 4"), re-seed after any iteration change | This plan **extends** BF-10 (blocklist, verifier-side length, per-account throttling, plaintext paths) and must not restate its cost model. |
| `webapp/srs/STATUS-USERS-MODULE.md` §"Work factor" / §"Salt entropy" | `PW_HASH_ITERATIONS` 1000 → 10 000 (measured 4.0 ms/hash); salt moved to `hb_RandStr(32)` (arc4random from `/dev/urandom`), verified by `test/probe_entropy.prg` (5000 seeds, 0 duplicates) | The already-closed half. Do not re-litigate salt source. |
| `webapp/test/probe_pwcost.prg` | Times `_PwHash()` at 1000/5000/10000/20000/50000 iterations, 5 reps each | Extend it (P2) to time the *candidate* KDF; keep its output format so the report stays comparable. |
| `webapp/test/probe_entropy.prg`, `probe_hash.prg` | Salt-uniqueness and digest-shape probes | Re-run after any KDF change; `probe_hash.prg` is the cheapest check that the digest still fits the field. |
| `webapp/regenerate_users.prg` | Rebuilds `users.dbf` (ID N,10 / NAME C,40 / PASS C,128 / SALT C,32 / ROLES C,255) with `_PwSalt()`/`_PwHash()` | The re-seed tool every KDF or policy change must be run through. |
| `webapp/srs/PRODUCTION-BLOCKERS-2026-10-07.md` | Ranked shipping blockers B1…B7 | Password policy is **not** in that list today. This is an upgrade, and it must not be presented as a fix for a recorded failure. |

---

## 3. Current state (every claim is a `file:line` in the tree as it stands)

| # | Fact | Value | Source |
|---|---|---|---|
| S-1 | Verifier rule | `"password" => { "required\|min:4", "Password", "" }` — **no max** | `webapp/www/controllers/auth.prg:42` |
| S-2 | Registration rule | `"pass" => "required\|string\|min:4\|max:40"` | `webapp/www/controllers/masters/users.prg:393` (`Store()`) |
| S-3 | Password-change rule | `"pass" => "string\|min:4\|max:40"` (empty = keep current) | `webapp/www/controllers/masters/users.prg:337` (`Update()`) |
| S-4 | `min:N` on a string **is** a length check | `ELSE IF Len( UStr( uValue ) ) < nVal` → `VAL_MIN_STR` | `src/validator/hix_val_rules.prg:92-113` |
| S-5 | Rule grammar available for this job | `minlen`/`maxlen` (140/151), `between` (163), `in`/`notin` (192/204), `regex` (249), plus **codeblock rules** (`ValType( aTokensOrig[i] ) == "B"`) | `src/validator/hix_val_rules.prg`, `src/hix_validator.prg:300-312` |
| S-6 | `regex` guard | pattern > 200 chars is rejected; input truncated to 2048 chars before `hb_regex` | `src/validator/hix_val_rules.prg:249-268` |
| S-7 | `string` cast mutates the secret | `uValue := AllTrim( UStr( uValue ) )` — leading/trailing whitespace is stripped **before** hashing | `src/validator/hix_val_cast.prg:27-30` |
| S-8 | KDF | `hb_sha256( salt + hash )` iterated `PW_HASH_ITERATIONS` = **10 000** times, plus the initial compression | `webapp/www/models/hpassword.prg:32, 56-66` |
| S-9 | Measured cost | 1000 → 0.4 ms, 10000 → 4.0 ms, 50000 → 17.8 ms per hash (this box) | `webapp/www/models/hpassword.prg:27`, `webapp/test/probe_pwcost.prg` |
| S-10 | Salt | 32 hex chars = **128 bits**, `hb_RandStr(32)` → SHA-256 → truncated; per-user, regenerated on create and on password change | `webapp/www/models/hpassword.prg:17, 50-52`; `users.prg:362, 417` |
| S-11 | Storage widths | `PASS C(128)` (holds 64 hex), `SALT C(32)` | `webapp/regenerate_users.prg:43-48`; live `webapp/data/users.dbf` header (ID/NAME/PASS/SALT/ROLES) |
| S-12 | Login throttle | **5 attempts / 60 s per client IP**, per-route factory; overridable from `www/middlewares/config.json → setup.ratelimit.login_max/login_window_s` | `webapp/www/middlewares/myapplogin.prg:25-26, 63-67`; `webapp/www/middlewares/config.json:26-30` |
| S-13 | Global limiter | 300 req / 60 s per IP covers `/users/store`, `/users/:id/update` | `webapp/www/middlewares/config.json:26-27` |
| S-14 | Error text is already generic | "Invalid username or password. Please try again." | `webapp/www/controllers/auth.prg:76` |
| S-15 | The UI prints the demo password | login form placeholder `placeholder="Password is 1234..."` | `webapp/www/views/sys/login.html:48` |
| S-16 | The UI states the old policy | create-form placeholder "Min 4 characters" | `webapp/www/views/masters/users/edit.html:99` |
| S-17 | **A tracked tool writes a plaintext password into the store** | `migrate_users.prg` `DBCREATE` with `{ "pass", "C", 40 }` and `hRow[ "pass" ] := "1234"`; it `USE`s the DBF if it already exists and `DbAppend`s | `webapp/migrate_users.prg:22, 26, 33, 35` (three rows: 33/47/61); tracked: `git ls-files` → `webapp/migrate_users.prg` |
| S-18 | In-app test harness uses the weak secret | `form({ username: 'demo', password: '1234' })` | `webapp/www/test/index.html:325` (served only when `app.env = "dev"`, `webapp/hix.json:41` is `prod`) |
| S-19 | Harbour primitives | `hb_sha256`, `hb_sha512`, `hb_hmac_sha256`, `hb_hmac_sha512` (+ `_ctx`/`_init`/`_update`/`_final`), `hb_md5`, `hb_crc32` — **no** bcrypt / scrypt / argon2 / PBKDF2 anywhere in Harbour core or `contrib/hbssl` | grep of `$HB_ROOT/src/rtl/*.c` and `contrib/hbssl/*.c` (hbssl exposes `EVP_BYTESTOKEY`, `EVP_DIGEST*`, not `PKCS5_PBKDF2_HMAC`) |
| S-20 | Fixture coupling | `"1234"`: 12 occurrences in 6 tracked files (`www/test/index.html` 5, `migrate_users.prg` 3, `www/views/sys/login.html` 1, `www/models/hpassword.prg` 1, `src/app.prg` 1, `regenerate_users.prg` 1) + 39 in the untracked `webapp/test/` suite | `git ls-files … \| xargs grep -c 1234` |

---

## 4. Gap analysis — standard vs. this tree

| # | Requirement (quoted) | Now | Verdict | Fix belongs in |
|---|---|---|---|---|
| C-01 | NIST §5.1.1.2: *"Verifiers SHALL require subscriber-chosen memorized secrets to be at least 8 characters in length."* | `min:4` at the **verifier** (`auth.prg:42`) | **FAIL** | `auth.prg:42` + the seeded store (S-10/S-11) |
| C-02 | NIST §5.1.1.2: *"Verifiers SHOULD permit subscriber-chosen memorized secrets at least 64 characters in length."* | create/change cap `max:40` (`users.prg:337, 393`); verifier has no max | **FAIL** (40 < 64) | `users.prg:337, 393` → `max:64` or more; keep the verifier's max ≥ the registration max |
| C-03 | NIST §5.1.1.2: *"All printing ASCII [RFC 20] characters as well as the space character SHOULD be acceptable… Unicode SHOULD be accepted as well."* | `string` cast accepts anything and `AllTrim`s it (S-7); no charset filter present | **PASS with a caveat**: leading/trailing whitespace is silently altered before hashing, so a password ending in a space is not verifiable as typed | `hpassword.prg` / the rules — decide trimming once, in one place |
| C-04 | NIST §5.1.1.2: *"verifiers MAY replace multiple consecutive space characters with a single space character prior to verification"* | not implemented | **OPTIONAL**, not a defect | `hpassword.prg` normalisation, if C-03's caveat is kept |
| C-05 | NIST §5.1.1.1: *"No other complexity requirements for memorized secrets SHOULD be imposed."* | none imposed | **PASS — and do not change it** | nothing. Any "must contain a digit/uppercase" rule added by this plan would be a deviation. |
| C-06 | NIST §5.1.1.1: *"If the CSP or verifier disallows a chosen memorized secret based on its appearance on a blacklist of compromised values, the subscriber SHALL be required to choose a different memorized secret."* | no blocklist; the seeded passwords **are** blocklist members (`"1234"`, `"5678"`, `"9012abcd"` — `regenerate_users.prg:20`) | **FAIL** | a project-local denylist + a codeblock rule (S-5) on the two registration paths only |
| C-07 | NIST key-stretching: *"A memory-hard function SHOULD be used… Examples of suitable key derivation functions include PBKDF2 [SP 800-132] and Balloon… the key derivation function SHALL use an approved one-way function such as Keyed Hash (HMAC)"*; *"the iteration count SHOULD be as large as verification server performance will allow, typically at least 10,000 iterations."* | 10 000 iterations of **plain** `hb_sha256(salt + hash)` — not HMAC-based, not memory-hard | **PARTIAL**: count meets the "typically at least 10,000" floor; the construction does not (no keyed function, no memory hardness). OWASP is blunter: *"Fast hashing algorithms such SHA-256 are not suitable for password storage."* | `hpassword.prg` — see D-1 and §8 for what is actually reachable |
| C-08 | NIST: *"verifiers SHOULD perform an additional iteration of a key derivation function using a salt value that is secret and known only to the verifier… at least the minimum security strength specified in the latest revision of SP 800-131A (112 bits)"* | per-user salt is 128 bits but is **stored in the clear** next to the digest; there is no verifier-secret component | **PARTIAL** (per-user salt passes the size test; the *secret* salt / pepper does not exist) | `hpassword.prg` + a pepper sourced like `hix.keys.json` (`webapp/gen_keys.sh`) |
| C-09 | NIST §5.2.2: *"the verifier SHALL limit consecutive failed authentication attempts on a single account to no more than 100"* + escalating wait (*"e.g. 30 seconds up to an hour"*) | throttle is **per client IP** (5/60 s), not per account; no consecutive-failure counter exists | **FAIL** (the standard's per-account bound is unimplemented; the IP bound is stricter in aggregate but a single account can be sprayed from rotating IPs) | `myapplogin.prg` / a per-account bucket in the session store or a small DBF |
| C-10 | OWASP: *"Passwords should never be stored in plain text"* | `migrate_users.prg` writes plaintext `1234` into `pass C(40)` and appends to an existing DBF (S-17) | **FAIL — latent plaintext path** | retire/quarantine `migrate_users.prg`; it predates the D-07 schema |
| C-11 | OWASP: *"Consider using a pepper to provide additional defense in depth"* | none | **OPTIONAL** | D-8 |
| C-12 | Digest encoding headroom | `PASS C(128)` holds 64 hex; a 32-byte KDF output fits exactly, a 64-byte output fills the field, and a version prefix (`v2:`) would not fit alongside 64 bytes | **CONSTRAINED** | D-6 (encoding) + `regenerate_users.prg` schema if widened |
| C-13 | OWASP bcrypt note: *"a password limit of 72 bytes"* | not applicable (no bcrypt) — but any future switch to it would silently truncate C-02's 64-char policy | **NOTE** | recorded in D-1's rejection rationale |

---

## 5. Decision points (record the answer before running the phases)

**D-1 — the KDF.** Reachable options only (S-19):

| Option | Construction | Verdict |
|---|---|---|
| (a) raise `PW_HASH_ITERATIONS` on the existing plain-SHA loop | `hb_sha256(salt + hash)` × N | Cheapest, but OWASP calls SHA-256 unsuitable and NIST wants an approved **keyed** one-way function. Keep only as an interim. |
| (b) **PBKDF2-HMAC-SHA256 built in Harbour** from `hb_hmac_sha256` (Harbour RTL, S-19) | F = PRF(P,S,1) ⊕ PRF(P,S,2) ⊕ … with the standard counter block | **Chosen.** Satisfies C-07's "approved one-way function (HMAC)" and NIST's PBKDF2 example. Cost is bounded by the latency budget, not by OWASP's 600 000 (see §8). |
| (c) `EVP_BYTESTOKEY` via `hbssl` (already linked, `hix_server.hbc:19`) | OpenSSL's legacy EVP key derivation | Rejected: MD5-based by default, not a KDF the standards endorse. |
| (d) Argon2id / bcrypt / scrypt | not present in Harbour core or contrib (S-19) | **Not reachable without a third-party dependency**, which `DEV-compliance.md` forbids. Record this as the ceiling, do not silently import a library. |

**D-2 — the latency budget, and the iteration count derived from it.** NIST's rule is
*"as large as verification server performance will allow"*. State the budget as a number first
(e.g. login p95 ≤ 500 ms, against `exec_timeout_ms = 30000`, `webapp/hix.json:22`), then take the
largest iteration count `probe_pwcost` measures under it. Do **not** copy OWASP's 600 000 as a
constant: at the measured ~0.4 ms per SHA-256 call (S-9), 600 000 HMAC iterations is minutes per
login in Harbour, not milliseconds. The measured number and its box go in the report.

**D-3 — length policy.** `min:8` at the verifier (C-01) and at registration; `max:64` at
registration (C-02) with the verifier's max ≥ registration's max, so a password that could be
created can always be verified. Use `minlen`/`maxlen` (S-5) rather than overloading `min`/`max`,
whose string branch is a length check (S-4) but whose name reads numeric in a review.

**D-4 — the blocklist (C-06).** A project-local file, **outside the docroot** (the docroot's root
level is downloadable — `PENTEST-REPORT.md §1`), e.g. `webapp/.pwdeny/` gitignored with a committed
`*.example` template. Matching rule: exact, case-insensitive, plus the trivial transforms users
actually apply (trailing digit, leetspeak `a→@`, `e→3`, `s→5`, `o→0`, capitalisation). Source list:
record which list, its size, and its licence — do not fetch it at runtime.

**D-5 — per-account throttling (C-09).** Where the counter lives: the session store is per-session,
not per-account, so it cannot hold it. Options: a small DBF (`data/login.dbf`, keyed by account
name, mirroring the RDDCDX pattern already used for `users.dbf`), or a hash in `www/config.json`
(rejected: docroot, and rewritten by HIX at startup). Record the choice, the counter reset rule,
the ≤100 bound, and the escalating wait (30 s → 1 h, NIST §5.2.2).

**D-6 — digest encoding and migration.** Either a per-record version tag (so old digests can be
re-hashed on next login instead of re-seeded) or an explicit full re-seed. With `PASS C(128)` the
tag costs bytes (C-12). Decide one; do not leave both live.

**D-7 — fixtures (S-20).** Every `"1234"` is a policy statement. Re-seed with passwords that
themselves satisfy the new policy (≥8, not on the blocklist), and re-derive the suite expectations
in the same change. The untracked `webapp/test/` suite is not in git, so a fresh clone cannot be
fixed from here — record that.

**D-8 — pepper (C-08/C-11).** If adopted: a per-verifier secret held like `hix.keys.json`
(0600, outside `paths.root`, `webapp/gen_keys.sh`), mixed into the KDF before the salt. Rotation
then invalidates the store, so it interacts with D-6.

---

## 6. Phases

Each phase ends with a verification command and a stop condition. Do not continue on an
unverified phase.

### P0 — inventory (harmless, local)

```bash
grep -n 'min:4\|max:40' webapp/www/controllers/auth.prg webapp/www/controllers/masters/users.prg
grep -n 'PW_HASH_ITERATIONS\|PW_SALT_LEN\|PW_DUMMY_SALT' webapp/www/models/hpassword.prg
grep -c 1234 $(git ls-files webapp | grep -E '\.(prg|sh|html|json)$')
git ls-files webapp | grep migrate_users
```

Stop: any line in §3 that no longer matches → the tree moved; re-derive §3/§4 before continuing.

### P1 — freeze the policy numbers (no code)

Write D-1…D-8 into the header of this file as a decision block. Stop: an undecided D-* blocks
every later phase.

### P2 — measure the candidate KDF (probe only, no app change)

Extend `webapp/test/probe_pwcost.prg` (untracked, adhoc, project-local) with the D-1 (b)
construction timed at several iteration counts, and keep the existing SHA loop rows so the numbers
stay comparable. Record: ms/hash, login p95 against the D-2 budget, and the offline guesses/s/core
that BF-10 asks for.

```bash
hbmk2 webapp/test/probe_pwcost.hbp && ./probe_pwcost
```

Stop: if the candidate KDF cannot meet the D-2 budget at any iteration count above the current
10 000, the honest outcome is "C-07 cannot be improved on this runtime" — record that and stop.

### P3 — verifier length (C-01, C-02)

`auth.prg:42` → `required|minlen:8|maxlen:<D-3 max>`. Verification: a 7-char POST to `/auth` is
rejected **before** `ModelUser()` runs (no KDF work spent on rejected input — this also removes an
oracle), and an 8-char one reaches the digest comparison. Confirm the generic error still appears
(S-14).

Stop: a rejected input that still paid the KDF cost is a fail.

### P4 — registration/change length (S-2, S-3)

`users.prg:337, 393` → `minlen:8|maxlen:<D-3 max>`. Verification: `POST /users/store` with a 7-char
`pass` returns the flash error and inserts nothing (D-03's "no phantom insert" must still hold);
`POST /users/:id/update` with an empty `pass` still keeps the current password.

Stop: any path where a short password reaches `_PwHash()` is a fail.

### P5 — blocklist (C-06)

Codeblock rule (S-5) on `/users/store` and `/users/:id/update` only — **not** on `/auth`: the
verifier must not refuse to verify a password an existing account legitimately holds. Message must
say "this password is too common, choose another" and must not echo the password (D-05).

Verification: a known-blocklist value is refused at creation; a leetspeak variant of it is refused
per D-4's transform list; the password is absent from the flash, the access log and
`.logs/hix.log`.

Stop: a blocklist miss on a top-100 value.

### P6 — KDF change + re-seed (C-07, C-08, D-6)

Order matters: change `hpassword.prg`, then re-seed with `regenerate_users.prg`, then re-run
`probe_hash.prg`/`probe_entropy.prg` for digest shape and salt uniqueness, then re-confirm D-17
(cost parity on the unknown-name path with the new KDF) and `_PwMatch`'s non-early-exit.

Stop: an account that cannot log in after this phase, or a `PASS` field whose content exceeds
C(128), or a stored digest that is not the new construction.

### P7 — per-account throttle (C-09)

Implement D-5, then verify with the existing harness discipline (`webapp/test/bf_harness.sh` is
rate-limit aware — it waits for a free slot rather than failing): 101 consecutive failures against
one account from **different** IPs must lock that account, and the wait must escalate.

Stop: a spray that rotates IPs and never hits the per-account bound.

### P8 — plaintext and UI paths (C-10, S-15, S-16, S-18)

`migrate_users.prg` → retire or rewrite to the D-07 schema (it must never `DbAppend` plaintext to
an existing DBF). `login.html:48` placeholder → stop printing the demo password. `edit.html:99`
placeholder → state the new policy. `www/test/index.html:325` fixture → the new seeded secret.

Stop: any plaintext password reachable in the UI, the harness, or a tool.

### P9 — report (a new document, not this one)

Must carry: the decision block, the measured numbers with the box they were measured on, the
C-01…C-13 table with each verdict moved to PASS or explicitly "not reachable on this runtime"
(D-1 (d)), the offline-cost figure BF-10 demands, and the suite re-run result. Then update
`webapp/srs/README.md` and `webapp/readme.md:32`-style rows if the storage format changed.

---

## 7. Blast radius of the length change (why sequencing matters)

```
tracked in git      "1234" occurrences
  www/test/index.html          5   (dev harness form)
  migrate_users.prg            3   (plaintext seed tool)
  www/views/sys/login.html     1   (UI placeholder)
  www/models/hpassword.prg     1   (comment/example)
  src/app.prg                  1
  regenerate_users.prg         1   (the seeded passwords themselves)
  total                       12
untracked webapp/test/        39   (test_users_module.sh 14, bf_harness.sh 12,
                                       verify-users-fixes.sh 9, test_customer_module.sh 2,
                                       probe_seek.prg 2)
```

The untracked suite is not in git (`webapp/srs/UNIFIED.md`; the suite was untracked on 2026-10-06),
so P7/P8 cannot fix a fresh clone's tests. Record that as a known gap rather than pretending the
change is self-contained.

---

## 8. Compliance ceiling (state it, do not resolve it silently)

`webapp/srs/DEV-compliance.md` allows HIX + Harbour only. The industry-standard algorithms the
standards name are **not reachable**:

| Named by | Present in this runtime? |
|---|---|
| Argon2id (OWASP first recommendation: 19 MiB memory, t=2, p=1) | no |
| scrypt (OWASP fallback: N=2^17, r=8, p=1) | no |
| bcrypt (OWASP legacy: work factor ≥10, 72-byte limit) | no |
| PBKDF2 (NIST example; OWASP FIPS-140 figure 600 000 with HMAC-SHA-256) | **not as a primitive** — but its HMAC-SHA-256 PRF is composable from `hb_hmac_sha256` (Harbour RTL, S-19) |
| HMAC-SHA-256/512, SHA-256/512 | yes (`$HB_ROOT/src/rtl/hbsha2hm.c`, `hbsha2.c`) |

So the honest target is **PBKDF2-HMAC-SHA256 with a measured iteration count**, and the honest
statement in the report is: the iteration count is bounded by Harbour's speed and the D-2 latency
budget, not by OWASP's 600 000; memory-hardness is unavailable. Say that, with the measurement,
rather than claiming compliance with a number the runtime cannot reach.

---

## 9. Stop conditions and do-not list

* Do not apply the new policy to the verifier only, or to registration only — C-01 and C-02 must
  hold on both sides or the store and the gate disagree.
* Do not add character-class rules (C-05).
* Do not re-seed before the KDF decision is frozen (D-6/D-7) — a re-seed destroys the current
  digests.
* Do not run `migrate_users` against the live `data/` directory while it still writes plaintext
  (S-17).
* Do not put the blocklist or the per-account counter under `www/` (docroot is downloadable).
* Do not echo a submitted password into a flash, an error, or the access log (D-05).
* Do not claim "compliant" in a report for C-07 without the measured iteration count and the
  §8 caveat.
* This document changes nothing. Any phase that needs a code edit ends there until the user asks
  for the edit.

## 10. Evidence map (re-verify, do not trust this file)

```bash
grep -n 'password\|min:4' webapp/www/controllers/auth.prg
grep -n 'pass.*min:4' webapp/www/controllers/masters/users.prg
grep -n 'PW_HASH_ITERATIONS\|hb_sha256\|hb_RandStr' webapp/www/models/hpassword.prg
grep -n 'min\|max\|minlen\|maxlen\|regex' src/validator/hix_val_rules.prg | head -40
grep -n 'string' src/validator/hix_val_cast.prg
grep -n 'LOGIN_MAX_ATTEMPTS\|login_max' webapp/www/middlewares/myapplogin.prg
grep -n 'ratelimit' -A4 webapp/www/middlewares/config.json
grep -n '1234' webapp/migrate_users.prg webapp/regenerate_users.prg webapp/www/views/sys/login.html
python3 - <<'EOF'   # live DBF schema, not the tool's claim
import struct; d=open('webapp/data/users.dbf','rb').read(512)
n=(struct.unpack('<H',d[8:10])[0]*32-1)//32
print([(d[32+i*32:43+i*32].rstrip(b' \0').decode(), chr(d[43+i*32]), d[48+i*32]) for i in range(n)])
EOF
grep -rhoE "hb_(hmac_sha256|hmac_sha512|sha256|sha512)" $HB_ROOT/src/rtl/*.c | sort -u
grep -rli "bcrypt\|argon\|scrypt\|pbkdf2" $HB_ROOT/src $HB_ROOT/contrib
hbmk2 webapp/test/probe_pwcost.hbp && ./probe_pwcost
```
