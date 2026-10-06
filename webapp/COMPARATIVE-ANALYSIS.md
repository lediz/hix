# From reference app to hardened service

### What we changed in the HIX webapp, why we changed it, and which published standard each change answers to

---

## Standards register

Every compliance claim in this document is anchored to a published document, not to an internal ticket. The register:

| Short form | Published document |
|---|---|
| **CWE** | MITRE Common Weakness Enumeration (individual weakness IDs cited inline) |
| **OWASP Top 10:2021** | OWASP Top Ten Project, 2021 release (`A01:A2021` … `A10:A2021`) |
| **OWASP API:2023** | OWASP API Security Top 10, 2023 release (`API1:2023` … `API10:2023`) |
| **ASVS** | OWASP Application Security Verification Standard v4.0.3 (verification requirements, cited by section) |
| **OWASP Cheat Sheets** | OWASP *Password Storage*, *Session Management*, *CSRF Prevention*, *Authentication*, *Access Control*, *Security Headers*, *Logging*, *REST Security* cheat sheets |
| **RFC 8446** | *The Transport Layer Security (TLS) Protocol Version 1.3* |
| **RFC 7525** | *Recommendations for Secure Use of Transport Layer Security (TLS) and Datagram Transport Layer Security (DTLS)* |
| **RFC 6797** | *HTTP Strict Transport Security (HSTS)* |
| **RFC 6265** | *HTTP State Management Mechanism* (cookie `Secure` / `HttpOnly` / `SameSite` attributes) |
| **RFC 7034** | *X-Frame-Options Header Field for Clickjacking Protection* |
| **RFC 7239** | *Forwarded HTTP Extension* |
| **RFC 9110** | *HTTP Semantics* (method semantics, `405 Method Not Allowed`) |
| **Fetch Standard** | WHATWG Fetch — `X-Content-Type-Options: nosniff` |
| **CSP** | W3C *Content Security Policy Level 3* |
| **NIST SP 800-63B** | *Digital Identity Guidelines: Authentication and Lifecycle Management* |
| **NIST SP 800-90A / 800-90C** | *Recommendation for Random Number Generation Using Deterministic Random Bit Generators* / *Entropy Sources* |
| **FIPS 180-4** | *Secure Hash Standard* (SHA-256) |
| **ISO/IEC 25010:2011** | *Systems and software quality models* (functional suitability) — used only for the functional grid requirements |
| **Project baseline** | `srs/DEV-compliance.md` and `srs/SRS-DAL-CRUD-WEB-UI.md` — internal requirements, explicitly labelled as such |

Internal defect IDs (`D-01`…`D-16`, `N-01`, `C-001`…`C-010`, suite check names) are **not** used as compliance references in the body; they appear only in the traceability appendix at the end.

---

## 1. The signing keys were a public download

**What changed.** The upstream example commits `www/config.json` containing five HMAC signing keys — and they are the *published defaults*: `H!x@CSRF@2026`, `H!x@JWT@2026`, `H!x@SESSION@2026`, `H!x@TOKEN@2026`, `H!x@RES@2026`. Locally, `www/config.json` is gitignored, the committed template (`www/config.json.example`) has no `keys` section, and the real keys resolve in this order: `HIX_KEY_*` environment variables → `hix.keys.json` (mode `0600`, gitignored, **outside** `paths.root`) → generated at first start with `hb_RandStr()`.

**Why.** `paths.root` is `www/`. HIX's dispatcher blocks sub-directories of the document root but **serves root-level files**. `www/config.json` is a root-level file, so an unauthenticated `GET /config.json` returned the secrets that mint every CSRF token, every session id, every session-file MAC and every resource id. With those bytes an attacker computes a valid CSRF token offline and replays it into a logged-in victim's session.

**How.** `src/app.prg` gained `_AppKeysEnsure()`, which runs **before** `THixServer():Start()` and calls `HIX_KeySet()` for each of the five slots, so the framework never has to read a key from the document root. Any legacy `keys` section found in `www/config.json` is stripped on startup — those bytes are already disclosed, so rotation is mandatory. A belt-and-braces route answers `GET /config.json` with `404`, because routes are matched before static file serving. `gen_keys.sh` creates the store with mode `0600`. The framework was also changed so an application-installed key *overrides* anything in `config.json`, and missing keys are generated in memory rather than written to a served file.

**Standards.**
- **CWE-798** *Use of Hard-coded Credentials* and **CWE-321** *Use of Hard-coded Cryptographic Key* — the defaults are published in the source of the framework.
- **CWE-219** *Storage of Configuration File with Publishable Permissions* and **CWE-668** *Exposure of Resource to Wrong Sphere* — the file sits inside the served document root.
- **CWE-522** *Insufficiently Protected Credentials*, **CWE-320** *Key Management Errors* (category).
- **OWASP Top 10:2021 A02 — Cryptographic Failures**; **OWASP API:2023 API2 — Broken Authentication** (the disclosed key defeats the control that authorises state-changing requests).
- **ASVS v4.0.3 V6 — Cryptographic Practices** (secrets must not be stored where they can be read) and **V14.2 — General Application Configuration**.
- **OWASP Cheat Sheet: *Logging and Monitoring* / *Secrets management*** — secrets belong in the environment or in a file outside the served tree.

**Evidence.** The suite asserts: the docroot config carries no key set; `GET /config.json` returns `404`; the key store lives outside `paths.root`, is `0600`, is gitignored, and every key is ≥ 32 characters and not a published default; no key literal remains in `src/app.prg`.

---

## 2. TLS stopped being optional — and the server refuses to start without a certificate

**What changed.** `hix.json`: port **8080 → 9090**, `ssl: false → true`, `cert_private` / `cert_public` populated. New `gen_cert.sh` creates a self-signed pair with the private key at `0600` and `certs/` gitignored. `src/app.prg` gained `_TlsGuard()`: no certificate, no startup.

**Why.** The project baseline requires SSL/TLS on port 9090; the upstream example ships neither. There is also a trap specific to HIX: the SSL context is built **per connection**, so a missing certificate does not stop the server — it starts and then fails every request. Failing at boot with a message is the only sane behaviour.

**How.** `go_gcc.sh` runs `gen_cert.sh` (idempotent: it only renews a missing or near-expiry certificate) and then execs the binary. The suite asserts TLS 1.3 is negotiated and that plain HTTP on 9090 is refused.

**Standards.**
- **RFC 8446** — TLS 1.3 is the negotiated version.
- **RFC 7525** — minimum configuration guidance for TLS deployments (version, certificate handling).
- **CWE-319** *Cleartext Transmission of Sensitive Information*.
- **OWASP Top 10:2021 A02 — Cryptographic Failures**.
- **ASVS v4.0.3 V9 — Communications Security** (V9.1 requirements, V9.2 strength of communications).
- **Project baseline** — port 9090, TLS mandatory.

---

## 3. Passwords went from a string literal to a work factor

**What changed.** Upstream authentication is a Harbour literal in `www/models/modeluser.prg`:

```harbour
hStore := { "demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234", ... },
            "carles" => { ... "pass" => "1234" }, ... }
```

Locally, `ModelUser` is a class reading `data/users.dbf` through RDDCDX with a CDX index on `Lower(NAME)`. `PASS` is `C(128)` holding **10 000 rounds** of salted SHA-256 with a per-user 32-hex CSPRNG salt. `TUsers():Hide({'pass','salt'})` keeps both out of every view hash.

**Why.** Plaintext credentials in source are unrecoverable: every clone of the repository is a credential leak, and a password cannot be rotated without editing code. The work factor was raised from 1 000 to 10 000 rounds after measuring the real cost (`test/probe_pwcost.prg`: 4.0 ms per hash — negligible at login, 10 000× more expensive for an offline dictionary attack).

**How.** New `www/models/hpassword.prg`: salt length 32, 10 000 iterations of `hb_sha256(salt + hash)`, and `_PwMatch()` with a non-early-exit comparison so a wrong digest cannot be discovered byte-by-byte. Salts come from `hb_RandStr(32)` — Harbour core RTL, which routes to `hb_arc4random_buf` seeded from `/dev/urandom`. That choice mattered: the first implementation derived the salt from name + timestamp + record count, which is *unique-looking but not unpredictable*, and moving to `hb_RandStr` avoided a contrib dependency and therefore avoided changing the build recipe. `test/probe_entropy.prg` ran 5 000 seeds and found zero duplicates. `regenerate_users.prg` seeds the accounts; `migrate_users.prg` moved the old ones across.

**Standards.**
- **CWE-257 / CWE-916** *Password Storage with Insufficient Computational Effort* — plaintext, then unsalted, then a work factor.
- **CWE-330** *Use of Insufficiently Random Values* and **CWE-331** *Insufficient Entropy* — the name/timestamp salt.
- **CWE-208** *Observable Timing Discrepancy* — closed by the constant-time digest comparison.
- **NIST SP 800-63B §5.2.2** (memorized-secret verifiers: salted, iterated hashing with a cryptographically strong salt) and **NIST SP 800-90A / 800-90C** (DRBG and entropy-source requirements behind the CSPRNG claim).
- **FIPS 180-4** — SHA-256 as the primitive.
- **OWASP Top 10:2021 A07 — Identification and Authentication Failures**; **OWASP API:2023 API2 — Broken Authentication**.
- **ASVS v4.0.3 V6.4 — Password hashing**; **V2.4 — Credential Storage**.
- **OWASP Cheat Sheet: *Password Storage***.

**Evidence.** The suite recomputes the stored digest from the database to confirm the declared work factor, confirms no seed password appears in plaintext in the DBF, and confirms every stored salt is 32 hex characters and distinct across users.

---

## 4. Sessions: from process memory to an encrypted, private, rotated store

**What changed.** Upstream: `storage: "memory"`, cookie `FENIXSID`, ttl 3600, no session on the login page, no rotation. Local: `storage: "file"` in `.sessions`, `crypt: true`, `gc_days: 1`, an anonymous session created and persisted at `GET /login`, and `USessionRotate()` on successful login before the identity is written.

**Why.** Three distinct problems.

*Persistence* — a memory store loses every session on restart.
*Confidentiality* — session files on disk held a plaintext JSON payload.
*Fixation* — because the login page now has to carry a session (so its CSRF token can be bound to a session id), that **pre-login session id must not survive into the authenticated session**. Rotating the identifier at the moment of privilege change is the standard control.

**How.** `hix.json` carries the settings; `login.prg` calls `USession():Save()`; `auth.prg` calls `USessionRotate()` and then writes `id`, `name`, `roles` only — never credentials. Encryption is HIX's Encrypt-then-MAC (HMAC-SHA256 over Blowfish-encrypted JSON, base64-wrapped), written atomically (`tmp` + `FRename`) under a per-session bucket mutex.

**The catch.** `hix.json` already supported `"crypt": true`, and it did nothing: the framework's `_MwApplySession()` forwarded only cookie/ttl/max/storage/path, silently dropping `prefix`, `crypt`, `seed` and `gc_days`. Fixing that required editing HIX — see §13.

**Standards.**
- **CWE-311** *Failure to Encrypt Sensitive Data* and **CWE-312** *Cleartext Storage of Sensitive Information* — the plaintext payload.
- **CWE-384** *Session Fixation* — closed by rotation at authentication.
- **CWE-287** *Improper Authentication* (the session-file integrity MAC is keyed by a key that was itself exposed, §1).
- **RFC 6265 §4.1.2.5** — cookie attribute semantics (`Secure`, `HttpOnly`, `SameSite`); the app emits `HttpOnly; SameSite=Lax; Secure`.
- **OWASP Top 10:2021 A07 — Identification and Authentication Failures**; **OWASP API:2023 API2 — Broken Authentication**.
- **ASVS v4.0.3 V3.2 — Session Token Generation**, **V3.3 — Session Token Distribution**, **V3.4 — Session Token Invalidation**.
- **OWASP Cheat Sheet: *Session Management***.

**Evidence.** The suite asserts the session payload on disk is not plaintext JSON, that no cookie is issued before login, that logout destroys the session, and that the session entry contains no credentials.

---

## 5. CSRF: from "a token is present" to "the token belongs to this session"

**What changed.** Upstream `HIX_MwCsrfCheck` verified an HMAC over a random payload: a valid token was valid **for any session, anywhere** — and, given the §1 key disclosure, computable offline. Locally the token payload carries the session id of the request that rendered the form, and the middleware additionally calls `HIX_CsrfBound()`.

**Why.** A stateless CSRF token is a bearer credential: steal it from one session and use it in another, or — if the signing key is public — compute one without stealing anything. Both were demonstrated against the live server: a forged token posted to `/users/store` was accepted and wrote a row; a bad token was rejected.

The application had its own defect here: the users write forms rendered **no token at all**, so create/update/delete worked for the automated harness and failed with `302 → /login` in a real browser. Fixed by adding the token to the edit and delete forms, and by moving the grid's JavaScript-side token out of a JS string into a server-rendered `data-csrf="{{ HIX_CsrfMakeToken() }}"` attribute — the pattern then propagated back to the customer grid.

**How.** `HIX_CsrfMakeToken()` defaults its payload to the current session id; `HIX_CsrfBound()` decodes the payload and compares. When a context has no session (CLI tests, public pages) the binding check is skipped and the original stateless behaviour is preserved, so the framework's documented `@CSRF` usage keeps working.

**Standards.**
- **CWE-352** *Cross-Site Request Forgery*.
- **OWASP Top 10:2021 A01 — Broken Access Control**.
- **ASVS v4.0.3 V4.4 — Handling Token-Based Session State** and the anti-CSRF synchroniser-token requirements in **V4 — Access Control**.
- **OWASP Cheat Sheet: *CSRF Prevention*** (synchroniser token pattern, per-session binding).

**Evidence.** The suite logs in as session A, takes the token A's own form rendered, replays it in session B (rejected, redirected to `/login`) and confirms the same token is still valid in A. It also confirms a tokenless POST is rejected and a POST carrying its own form's token is accepted.

---

## 6. The credential endpoint got its own limiter — and the global limiter started working

**What changed.** Upstream declares a global limiter of 300 requests / 60 s. Locally that global limit is still 300/60 — but it is now actually applied, and `/auth` has its own sliding window: **5 attempts / 60 seconds**, overridable from `www/middlewares/config.json`.

**Why.** 300 requests per minute on a login endpoint is a password-spraying licence. And the declared global limit was a mirage: the setup call was fed a config accessor that returns a hash or a default string, so the framework ignored the arguments and kept its built-in 60/60. A control that looks configured and is not configured is worse than none, because it stops people asking.

**How.** `MyAppLogin` composes `SecHeaders + Session + login-rate-limit + CsrfCheck`, the limiter coming from `HIX_MwRateLimitFactory(attempts, window)`. Values are read from the middleware config so a test build can widen them without editing source; the suite waits for a free window instead of failing, and the deliberate `429` probe runs last. Proxy mode stays off, so the limiter key is the socket IP — eight attempts with rotating `X-Forwarded-For` still hit `429`.

**Standards.**
- **CWE-307** *Improper Restriction of Excessive Authentication Attempts*.
- **CWE-204** *Observable Response Discrepancy* — closed by making login do constant work, so an unknown username is not cheaper than a known one (a user-enumeration channel).
- **NIST SP 800-63B §5.1.1** — memorized-secret authenticators, including rate limiting / throttling of online guessing.
- **RFC 7239** — `Forwarded` / `X-Forwarded-*` semantics; the app deliberately does **not** trust those headers, so the limiter cannot be spoofed.
- **OWASP Top 10:2021 A07 — Identification and Authentication Failures**; **OWASP API:2023 API4 — Unrestricted Resource Consumption**.
- **ASVS v4.0.3 V2.2 — Authentication by Claim** (shared secrets, credential stuffing and brute-force controls) and **V2.3 — Authentication by Token**.
- **OWASP Cheat Sheet: *Authentication*** (throttling guidance).

**Evidence.** The suite confirms `429` inside the window, that rotating `X-Forwarded-For` does not reset the window, and that unknown-username and known-username login attempts are indistinguishable in cost.

---

## 7. Every response now carries the four boring headers

**What changed.** No upstream route set a single security header. Locally `HIX_MwSecHeaders` runs first in every middleware group — `MyAppAuth`, `MyAppAuthRole`, `MyAppAuthRoleEdit`, `MyAppLogin` — and a new group, `MyAppPublic`, exists purely so public routes get them too.

**Why.** With no `X-Frame-Options` the app is frameable; with no `X-Content-Type-Options` the browser sniffs content types; with no CSP there is no second line of defence if an injection ever lands; with no HSTS the first plain-HTTP visit is downgrade-able.

**How.** `HIX_MwSecHeadersSetup()` is called once in `src/app.prg` with the CSP from `www/middlewares/config.json`, and the default CSP was written against **what the views actually load**: `self` plus the CDN the inherited Bootstrap-based shell uses, `'unsafe-inline'` for the inline styles the templating engine emits, `form-action 'self'`, `frame-ancestors 'none'`, `base-uri 'self'`. A CSP that breaks the UI gets deleted by the first developer who hits it; this one is enforceable today.

**Standards.**
- **RFC 7034** — `X-Frame-Options`, clickjacking protection.
- **Fetch Standard** — `X-Content-Type-Options: nosniff`.
- **RFC 6797** — HSTS (`Strict-Transport-Security`).
- **W3C Content Security Policy Level 3** — `Content-Security-Policy`, including `frame-ancestors`, `form-action`, `base-uri`.
- **CWE-1021** *Improper Restriction of Rendered UI Layers or Frames*; **CWE-693** *Protection Mechanism Failure* (category).
- **OWASP Top 10:2021 A05 — Security Misconfiguration**.
- **ASVS v4.0.3 V14.3 — HTTP Response Headers**.
- **OWASP Cheat Sheet: *Security Headers***.

**Evidence.** The suite counts the four headers on a response to `/`.

---

## 8. The framework's own front door was closed

**What changed.** `admin.enabled: true → false`. `/hix-slow` replaced with `404`. `AllowDir("test")` granted only when `app.env == "dev"`, and **no directory is ever granted script execution**. `app.env: "dev" → "prod"`, trace off, `autostart: true → false`.

**Why.** Four findings, all reproduced against the live server:

- The **HIX admin panel** could be claimed by an unauthenticated visitor: thirteen system routes (`/hix-setup`, `/hix-login`, `/hix-status`, `/hix-stop`, `/hix-index`, `/hix-trace`, `/hix-cache-clear`, `/hix-bench-start`, …) existed on an app that never uses them.
- **`/hix-slow`** slept a worker for three seconds on every anonymous GET. With a 64-worker HTTP pool, that is a cheap availability attack.
- **`AllowDir( cDir, lAllowExec )` grants *execution* of files in a directory**, bypassing the route table and therefore bypassing middleware and `scope`. The example granted it for `test/`; the grant was inert only because a particular directory did not exist. Inert today is not safe tomorrow.
- **Verbose trace and a server banner** were on by default.

**How.** `HIX_LoadConfig()` is called explicitly **before** `Start()`, because the router decides from `UConfig("admin","enabled")` whether those 13 routes exist at all — without the call the router was built from the framework's built-in defaults and the panel was registered *despite* the config saying otherwise. `_GuardSurface()` then replaces `/hix-slow` and `/config.json` with `404` routes using `HIX_RouteAdd(..., lReplace := .T.)`.

`autostart` is off for a practical reason worth telling: the framework opened the app with `xdg-open`, the browser **inherited the listening socket**, and killing the server left port 9090 bound by the browser — the next start failed with "Cannot bind port 9090" while a LISTEN socket with no server behind it was still visible.

**Standards.**
- **CWE-1188** *Initialization of a Resource with an Insecure Default* and **CWE-278** *Insecure Default Activation Setting* — the admin panel ships enabled.
- **CWE-489** *Active Debug Code* — the demo sleep route and the test harness.
- **CWE-400** *Uncontrolled Resource Consumption* — worker exhaustion.
- **CWE-497** *Exposure of Sensitive System Information to an Unauthorized Control Sphere* and **CWE-668** *Exposure of Resource to Wrong Sphere* — the execution grant and the served harness.
- **CWE-532** *Insertion of Sensitive Information into Log File* — verbose trace on by default.
- **RFC 9110 §15.5.6** — `405 Method Not Allowed`, verified on undeclared verbs.
- **OWASP Top 10:2021 A05 — Security Misconfiguration**; **OWASP API:2023 API9 — Improper Asset Management** (unused framework endpoints left exposed).
- **ASVS v4.0.3 V14.2 — General Application Configuration** (production configuration must disable debug and administrative features) and **V1.2 — Software Supply Chain**.
- **OWASP Cheat Sheet: *REST Security*** (do not ship unused endpoints).

**Evidence.** The suite confirms all eight sampled admin routes return `404`, `/hix-slow` returns `404` in well under one second, and `/test/` is not served in production.

---

## 9. The read screen became a real data grid

**What changed.** Upstream `Search()` is one line:

```harbour
METHOD Search() CLASS Customer
RETU UView( 'masters/customer/search.html' )
```

It renders a page. It runs no query and shows no list. Locally there is a `Grid()` method (with its own route and view) implementing server-side pagination at 20 rows per page, column sorting, and **one search entry per rendered column**.

**Why.** The project's DAL SRS requires a paginated tabular grid, a default page size, search by column via query parameters, column sorting, and row → `GET /{id}` detail. In external terms this is **ISO/IEC 25010:2011 — functional suitability**: the shipped feature did not satisfy the stated functional requirement.

**How — and the three bugs found on the way.**

1. **`DbGoTo` → `DbSkip`.** Navigating a CDX-ordered index by absolute record position returns the wrong rows. Pagination looked like it worked and silently shuffled.
2. **`UParam` → `UGet`.** `UParam()` resolves its fallback with `cVal != xDef`. Under Harbour's default `SET EXACT OFF`, *any* value compares equal to an empty string — so `UParam('q', '')` returned `''` for a parameter that **was present**. That is why per-column search never worked while `?sort=` and `?dir=` (non-empty defaults) did. A language-level comparison setting turned into a missing feature.
3. **Sort keys are lowercase.** Grid hash keys are lowercase, so an uppercase sort key missed the lookup and the sort did nothing. Now the key is lowercased and validated against an allow-list; an unlisted key falls back to the default instead of failing silently.

The allow-list discipline is the security half of the same work: **one list** drives the grid projection, the legal sort keys and the searchable columns. `pass` and `salt` are not in it, so they cannot be read, sorted, searched or rendered. Every search box maps to a column the grid renders, and every column gets a search box.

**Standards.**
- **ISO/IEC 25010:2011** — functional suitability (the grid requirements themselves).
- **CWE-200** *Exposure of Sensitive Information to an Unauthorized Actor* — closed by the field allow-list.
- **CWE-862** *Missing Authorization* — the class of failure an unvalidated sort or search key can open.
- **ASVS v4.0.3 V5.1 — Input Validation** and **V5.3 — Activating Security Controls from Frameworks**; **V4.3 — Access Control at the Request Level** for field-level exposure.
- **OWASP Cheat Sheet: *Access Control*** (deny-by-default field lists).

---

## 10. Delete stopped being a POST from a grid row

**What changed.** Upstream: one POST route keyed on the record resource. Local: `delete_confirm` (GET, renders a confirmation page) and `delete_action` (POST, CSRF-guarded, posting to a **routed** URL).

**Why.** The delete form posted to a URL that was not in the route table, so the state-changing request could not be authorised, scoped or CSRF-checked the way every other write was. A destructive action also deserves a confirmation step — a design requirement as much as a UX one.

**How.** The delete views post to the routed URL for the record, carrying the CSRF token. Soft delete uses the framework's own delete primitive, and the `_deleted` flag is now honoured by the uniqueness check, so a soft-deleted name cannot be resurrected by re-creating it.

**Standards.**
- **CWE-352** *Cross-Site Request Forgery* (a delete that bypasses the CSRF middleware).
- **CWE-862** *Missing Authorization* and **CWE-639** *Authorization Bypass Through User-Controlled Key*.
- **OWASP Top 10:2021 A01 — Broken Access Control**; **OWASP API:2023 API1 — Broken Object Level Authorization**.
- **ASVS v4.0.3 V4.3 — Access Control at the Request Level** and **V11 — Business Logic** (confirmation of destructive operations).

---

## 11. Two bugs that were compliance failures in disguise

**`Val()` on a logical value.** `customer.prg` did `Val(hChanges["married"])` — but the validator had already converted the field to a Harbour logical, and `Val()` accepts strings only. `Val(.T.)` throws *Argument error (1098)*, so **every** customer update flashed an error while the record may or may not have been written. Fixed by removing the conversion.
→ **CWE-754** *Improper Check for Unusual or Exceptional Conditions*; **ASVS v4.0.3 V7 — Error Handling and Logging**; **ISO/IEC 25010 — functional suitability**. This is the case that proves a functional suite must run against a live server, not a compile check.

**`oVal:Get()` with no field name.** The validator's `Get()` with no key returns the *first* validated value — today that happens to be `id`. Add any second validated URL parameter and the write silently retargets a different record. Fixed to `Get('id')`.
→ **CWE-639** *Authorization Bypass Through User-Controlled Key*; **OWASP API:2023 API1 — Broken Object Level Authorization**; **ASVS v4.0.3 V4.3**. Nothing is wrong until someone adds a parameter — which is exactly why the rule is "always name the field".

**Mass assignment, verified rather than fixed.** Injecting `id`, `salt` or `_deleted` into a create request does nothing: only fields explicitly marked as writable reach the data layer, the id comes from the model's own sequence, and the salt is generated. Verified live.
→ **CWE-915** *Improperly Controlled Modification of Dynamically-Determined Object Attributes*; **OWASP API:2023 API3 — Broken Object Property Level Authorization**; **ASVS v4.0.3 V4.3 / V5.1**.

---

## 12. Session file permissions: the fix Harbour cannot make

**What changed.** `go_gcc.sh` now sets `umask 077` before building and exec'ing the server, and tightens any session store an earlier, looser umask already created. Store `0700`, session files `0600`.

**Why.** The framework writes session files with `hb_MemoWrit()` + `FRename()` and never sets a mode, so they inherit the process umask. Under the usual `0022` the store is created **0755** and its records **0644** — world-readable session data inside a world-traversable directory.

**How — and this is the interesting part.** We first tried to fix it inside the application, and proved that we cannot:

| Attempt | Result |
|---|---|
| Call `umask()` from Harbour | link failure: `undefined reference to HB_FUN_UMASK` |
| Call `chmod()` from Harbour | link failure: `undefined reference to HB_FUN_CHMOD` |
| Find them in a contrib | not in core, not in `hbct` |
| Read a mode with `hb_DirGet()` | not linked either |
| Read a mode with `Directory()` | returns entries whose attribute field is not character |
| `hb_DirCreate()` | produced **0755** under umask `0022` — so the private store was luck, not design |

Documented in `test/probe_fmode.prg`. The only lever left **inside the project folder** is the launcher. Hence `umask 077` in `go_gcc.sh`, plus a startup sweep for pre-existing files. Running `./app` directly bypasses it and the application cannot self-correct — that limitation is written into `readme.md` rather than hidden.

**Standards.**
- **CWE-276** *Incorrect Default Permissions* and **CWE-732** *Incorrect Permission Assignment for Critical Resource*.
- **CWE-219** *Storage of Configuration File with Publishable Permissions* (same class as §1: sensitive material with permissive modes).
- **OWASP Top 10:2021 A05 — Security Misconfiguration**; **A02 — Cryptographic Failures** for the payload inside those files.
- **ASVS v4.0.3 V8 — Data Protection and Privacy** (local storage of sensitive data) and **V14.2 — General Application Configuration** (file and directory permissions).
- **OWASP Cheat Sheet: *Session Management*** (server-side session stores must be protected from local disclosure).

**Evidence.** The suite asserts the store directory is `0700` and that every session file written during the run is `0600`.

---

## 13. The compliance violation we should own: the framework was patched

Everything above stayed inside the project folder. This section did not, and an honest report says so.

The project baseline states: *"No change will be done outside project folder."* The local framework checkout is **1 commit ahead of `origin/main`** with **6 further files modified and uncommitted** (+202 / −36):

| File | Upstream behaviour | Local behaviour |
|---|---|---|
| `hix_helpers.prg`, `hix_mw_loader.prg` | `UParam()` misses query params; `paths.session` not forwarded | both fixed |
| `hix_config_app.prg` | generates a `keys` section into `<paths.root>/config.json` | no `keys` section at all |
| `hix_csrf.prg` (+93) | stateless CSRF token | token bound to the session id; `HIX_CsrfBound()` added |
| `hix_keys.prg` (+84) | `config.json` keys win; timestamp-derived generation | application-installed key wins; CSPRNG key generation; missing keys generated in memory, never written to the served file |
| `hix_mw_loader.prg` | `session.prefix/crypt/seed/gc_days` silently dropped | forwarded to the session setup call |
| `hix_request.prg` | scheme derived only from `X-Forwarded-Proto`, so a TLS server reported `http` | scheme follows the real transport |
| `mw/hix_mw_csrf.prg` | token signature check only | also the session-binding check |

**Why it matters.** Four checks in the regression suite — the `Secure` cookie, session-bound CSRF, the encrypted session payload, and "keys are never read from the document root" — pass **only** against this patched framework. Deploy the identical application against stock `origin/main` and those four controls silently disappear. A green suite would then be describing a system that does not exist.

**Standards implicated.**
- **CWE-1188** *Initialization of a Resource with an Insecure Default* — the framework's own defaults (keys in the served config, admin panel enabled, plaintext sessions).
- **CWE-614** *Sensitive Cookie in HTTPS Session Without 'Secure' Attribute* and **CWE-311** *Failure to Encrypt Sensitive Data* — the two consequences the framework edits remove.
- **OWASP Top 10:2021 A05 — Security Misconfiguration** and **A06 — Vulnerable and Outdated Components**.
- **OWASP API:2023 API9 — Improper Asset Management** (unused, insecure-by-default framework surface).
- **ASVS v4.0.3 V1.2 — Software Supply Chain** and **V14.2 — configuration**: a dependency must be pinned to a version whose behaviour the application's verification actually describes.
- Upstream defects belong upstream: the framework project, not this repository, is the place to fix them.

**What the right answer is** (recommendation, not action): these are upstream defects, not local features. They belong in a pull request to the framework project, with the application depending on a tagged framework version and the build documentation stating that dependency explicitly. Until then, the deviation must be declared rather than discovered later.

---

## 15. Compliance ledger

| Requirement | Source | Status |
|---|---|---|
| TLS 1.3, plaintext refused | RFC 8446, RFC 7525 · ASVS V9 · OWASP A02 | ✅ |
| Cookie attributes `Secure`, `HttpOnly`, `SameSite` | RFC 6265 §4.1.2.5 · ASVS V3.3 | ✅ |
| Secrets not stored in the served tree | CWE-798, CWE-321, CWE-219 · ASVS V6, V14.2 | ✅ |
| Salted, iterated password hashing with CSPRNG salts | NIST SP 800-63B §5.2.2, SP 800-90A/90C · FIPS 180-4 · CWE-916, CWE-330 | ✅ |
| Constant-time credential comparison | CWE-208 | ✅ |
| Authentication throttling | NIST SP 800-63B §5.1.1 · CWE-307 · ASVS V2.2 | ✅ |
| No user enumeration by timing | CWE-204 | ✅ |
| Session identifier rotation at login | CWE-384 · ASVS V3.4 | ✅ |
| Encrypted, permission-restricted session store | CWE-311, CWE-276, CWE-732 · ASVS V8, V14.2 | ✅ |
| CSRF token bound to the session | CWE-352 · ASVS V4.4 | ✅ |
| Object-level and field-level authorisation | CWE-639, CWE-915, CWE-862 · API1/API3 · ASVS V4.3 | ✅ |
| Method semantics enforced | RFC 9110 (`405` on undeclared verbs) | ✅ |
| Security response headers | RFC 7034, RFC 6797, Fetch Standard, W3C CSP L3 · ASVS V14.3 | ✅ |
| Unused/debug framework surface disabled | CWE-1188, CWE-489, CWE-400 · ASVS V14.2, V1.2 | ✅ |
| Output encoding (XSS) | CWE-79 · OWASP A03 | ✅ (verified live) |
| No SQL, no process execution, no third-party UI | project baseline | ✅ |
| Functional grid (pagination, page size, column search, sorting, row detail) | project DAL SRS · ISO/IEC 25010 functional suitability | ✅ |
| Regression coverage of the above | ASVS "verify, don't assume" principle | ✅ 125 checks, 125 pass / 0 fail |

---

## Appendix — internal traceability

The project's own defect and constraint IDs, mapped to the standards they correspond to. They are listed here so the earlier reports remain traceable, not as compliance references.

| Internal ID | Subject | Standard |
|---|---|---|
| `C-009` | SSL/TLS required | RFC 8446 · ASVS V9 |
| `C-001`, `C-002`, `C-004`, `C-008` | HIX/Harbour only, no SQL, DBF/CDX, `hbmk2 app.hbp` | project baseline |
| `D-05`, `D-06` | credentials rendered in views / reachable by search | CWE-200 · ASVS V4.3 |
| `D-07` | plaintext passwords, no brute-force limit | CWE-916, CWE-307 · NIST SP 800-63B |
| `D-08` | column sort silently no-op | ISO/IEC 25010 (functional suitability) |
| `D-09` | duplicate/soft-deleted name accepted | CWE-20 · ASVS V5.1 |
| `D-12` | GET write routes not CSRF/scope guarded | CWE-862 · API5:2023 |
| `D-13` | unqualified validator field lookup | CWE-639 · API1:2023 |
| `D-15` | raw hash subscript in views → 500 | CWE-754 · ASVS V7 |
| `D-16` | loose index seek accepted partial names | CWE-287 · ASVS V2.2 |
| `N-01` | write forms rendered no CSRF token | CWE-352 · ASVS V4.4 |
| Pentest §1 | signing keys served over HTTP | CWE-798, CWE-321, CWE-219 |
| Pentest §2 | admin panel claimable unauthenticated | CWE-1188, CWE-278 |
| Pentest §3 | sleep route → worker exhaustion | CWE-400 |
| Pentest §4 | cookie without `Secure` on TLS server | CWE-614 · RFC 6265 |
| Pentest §5 | stateless CSRF token | CWE-352 |
| Pentest §6 | user enumeration by timing | CWE-204 |
| Pentest §7 | plaintext session payload, permissive store | CWE-311, CWE-276 |
| Pentest §8 | no security headers | CWE-1021 · RFC 7034, RFC 6797 |
| Pentest §9 | test harness reachable, execution grant | CWE-489, CWE-497 |
| Pentest §10 | verbose diagnostics, server banner | CWE-532 |

---

## The one-paragraph version

The upstream example gave us routing, middleware composition, role scope checks, a stateless CSRF check, a session store, a single-module CRUD flow and a browser test page — all on plain HTTP with hard-coded default keys (**CWE-798**) and an administrative panel enabled by default (**CWE-1188**). We kept the shell, the assets and the MVC pattern untouched, and rebuilt everything a standard cares about: credentials from source literals to salted iterated hashing (**NIST SP 800-63B §5.2.2**, **CWE-916**), sessions encrypted, private and rotated (**RFC 6265**, **CWE-384**), CSRF tokens bound to the session (**CWE-352**), the credential endpoint throttled (**NIST SP 800-63B §5.1.1**), security headers on every response (**RFC 7034**, **RFC 6797**, **W3C CSP L3**), the framework's unused surface closed (**ASVS V14.2**), the read screen brought up to the stated functional requirements (**ISO/IEC 25010**), and a second module built to the same rules. The one thing that belongs to neither tree is the patched framework itself — seven edits outside the project folder, six uncommitted, with four of our green checks resting on them (**ASVS V1.2**, **OWASP A06**).
