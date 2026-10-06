# Security Audit Report — Harbour-HIX Webapp (Fenix CRUD)

**Project**: Fenix Webapp (Customer Management CRUD)
**Language/Framework**: Harbour + HIX Framework
**Database**: DBFCDX (DBF/CDX)
**Audit Date**: 2026-09-30
**Auditor**: Automated Security Review (SRS Pentest)
**Scope**: `www/` (controllers, middlewares, models, views, routes, config)
**Classification**: Internal Assessment

---

## Executive Summary

The Fenix Webapp implements a standard session-based CRUD application with role-based authorization. The architecture is clean and the middleware chain is well-structured. However, several **high-severity** and **medium-severity** findings were identified across authentication, authorization, injection, and configuration categories. The most critical issue is **plaintext credential storage** in the user model, followed by **IDOR via the resource token mechanism** and **insecure session storage**.

**Overall Risk Rating: HIGH**

---

## Findings

### 🔴 C1 — Plaintext Password Storage in User Model

**CWE ID**: CWE-256 (Plaintext Storage of a Password)

**Severity**: **CRITICAL**

**Location**: `www/models/modeluser.prg`

**Technical Explanation**:
The `ModelUser()` function stores all three user passwords as plaintext strings in a static hash:

```harbour
hStore := {
   "demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234", ... },
   "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ... },
   "maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234", ... }
}
```

All three users share the same password (`1234`). Comparison is done via direct string equality:
```harbour
IF hEntry == NIL .OR. ! ( hEntry["pass"] == cPass )
```

**Attack Vector**:
- If the source code is exposed (e.g., via a directory traversal, misconfigured server, or version control leak), all credentials are immediately compromised.
- The static in-memory hash is never hashed — it exists in the server process memory permanently.
- No password complexity requirements are enforced during login.

**PoC**:
```bash
# Simply read the source file — no exploitation needed
curl http://localhost:8080/www/models/modeluser.prg  # If exposed
# Or: grep -r "pass.*=>" www/models/modeluser.prg
```

**Remediation**:
```harbour
// Replace with bcrypt/argon2 verification
FUNCTION ModelUser( cUser, cPass )
   LOCAL hEntry := hb_HGetDef( hStore, Lower( cUser ), NIL )
   IF hEntry == NIL
      RETURN NIL
   ENDIF
   // Verify against stored hash (not plaintext)
   IF ! HBCryptVerify( hEntry["pass_hash"], cPass )
      RETURN NIL
   ENDIF
   RETURN { "id" => hEntry["id"], "name" => hEntry["name"], "roles" => hEntry["roles"] }
ENDFUNC
```

---

### 🔴 C2 — Insecure Direct Object Reference (IDOR) via `_resource_id` Token

**CWE ID**: CWE-639 (Authorization Bypass Through Untrusted Channel) / CWE-284 (Improper Access Control)

**Severity**: **CRITICAL**

**Location**: `www/controllers/masters/customer.prg` (Update, Delete methods)

**Technical Explanation**:
The `Update()` and `Delete()` methods use `UGetResource()` to validate the resource ID. The resource token mechanism (`hix_resource.prg`) works as follows:

1. The view embeds a hidden field: `<input name="_resource_id" value="HMAC(recno, secret)">`
2. On POST, `UGetResource()` validates the HMAC and extracts the recno.

**However**, the resource token is **stateless** — it is not bound to the session. An attacker who obtains a valid `_resource_id` token (e.g., from a shared link, browser history, or intercepted response) can use it on any authenticated session to modify/delete any customer record. The token does not expire (TTL=0 in `HIX_TokenValid(cToken, 0, ...)`).

Furthermore, the **resource secret** is the same as the CSRF secret (`"H!x@RES@2026"` from `www/config.json > keys.resource`), which is published in the source code.

**Attack Vector**:
```bash
# Step 1: Obtain a valid resource token from a legitimate user's form
# (e.g., via XSS on the edit page, or a shared link)
# Step 2: Send a POST to /customer/:id/update with that token
curl -X POST http://localhost:8080/customer/1/update \
  -d "_resource_id=<valid_token>" \
  -d "first=Hacked" \
  -d "last=Attacker" \
  -H "Cookie: FENIXSID=<stolen_session>"
```

The token remains valid indefinitely. No session binding.

**Remediation**:
- Bind resource tokens to the session: include `session_id` in the HMAC payload.
- Add a TTL to resource tokens (change `HIX_TokenValid(cToken, 0, ...)` to `HIX_TokenValid(cToken, 3600, ...)`).
- Use a separate secret for resource tokens (not the same as CSRF).

---

### 🔴 C3 — Default/Static HMAC Secrets in Configuration

**CWE ID**: CWE-321 (Use of Hard-coded Cryptographic Key)

**Severity**: **CRITICAL**

**Location**: `www/config.json`

**Technical Explanation**:
All cryptographic secrets are hardcoded and published in the source:

```json
"keys": {
   "csrf":    "H!x@CSRF@2026",
   "jwt":     "H!x@JWT@2026",
   "session": "H!x@SESSION@2026",
   "token":   "H!x@TOKEN@2026",
   "resource":"H!x@RES@2026"
}
```

These are the HMAC keys for:
- CSRF token generation/validation
- JWT signing (HS256)
- Session ID generation (HMAC-SHA256)
- Resource ID signing

**Impact**: If the source code is exposed, an attacker can:
- Forge valid CSRF tokens → bypass CSRF protection
- Forge valid JWT tokens → impersonate any user
- Forge valid resource tokens → perform IDOR attacks
- Forge valid session IDs → hijack sessions

**Remediation**:
- Use environment variables or a secrets manager for all keys.
- Rotate keys regularly.
- Never commit secrets to version control.

---

### 🟠 C4 — In-Memory Session Storage (Session Loss on Restart)

**CWE ID**: CWE-367 (Time-of-Check-Time-of-Use Race Condition) / CWE-200 (Information Exposure)

**Severity**: **HIGH**

**Location**: `www/middlewares/config.json` → `setup.session.storage = "memory"`

**Technical Explanation**:
Sessions are stored in-memory (`"storage": "memory"`). When the server restarts, **all active sessions are lost**. This is not a direct vulnerability but creates a denial-of-service condition and means:
- No session persistence across deployments
- No audit trail of active sessions
- Session data is accessible to any process with access to the server's memory

Additionally, the session cookie is **not marked HttpOnly** in the application code (the HIX framework sets `SameSite=Lax` but the HttpOnly flag depends on `HIX_SetCookie` implementation).

**Remediation**:
- Switch to file-based session storage: `"storage": "file"` in `config.json`.
- Ensure `HIX_SetCookie` sets `HttpOnly; Secure; SameSite=Lax`.

---

### 🟠 C5 — Rate Limit Too Permissive on Login

**CWE ID**: CWE-307 (Improper Restriction of Excessive Authentication Attempts)

**Severity**: **HIGH**

**Location**: `www/middlewares/config.json` → `setup.ratelimit`

**Technical Explanation**:
The rate limit is configured as `300 requests per 60 seconds` per IP. This is **extremely permissive** for a login endpoint:
- 300 attempts/minute = 5 attempts/second
- An attacker can try 18,000 passwords per hour
- The default password in the app is `1234` — easily brute-forced

The documentation notes this was raised from `5/60` to `300/60` to support the test suite. In production, this should be `5/60` or `10/60`.

**Attack Vector**:
```bash
# Brute force the login with 300 attempts per minute
for i in $(seq 1 1000); do
  curl -X POST http://localhost:8080/auth \
    -d "username=demo&password=test$i&_csrf=valid" \
    -c cookies.txt
done
```

**Remediation**:
- Set `ip_per_min: 5` for the login endpoint.
- Use `HIX_MwRateLimitFactory(5, 60)` per-route for `/auth`.
- Add exponential backoff or account lockout after N failures.

---

### 🟠 C6 — No HTTPS Enforcement

**CWE ID**: CWE-319 (Cleartext Transmission of Sensitive Information)

**Severity**: **HIGH**

**Location**: `hix.json` → `server.ssl = false`

**Technical Explanation**:
The server is configured with SSL disabled (`"ssl": false`). All traffic — including session cookies, CSRF tokens, and credentials — is transmitted in plaintext over HTTP.

**Attack Vector**:
- Man-in-the-middle (MITM) attacker on the same network can:
  - Intercept the `FENIXSID` cookie → hijack sessions
  - Intercept the `_csrf` token → forge requests
  - Intercept credentials on login → capture passwords
  - Perform a man-in-the-middle attack on the login form

**Remediation**:
- Enable SSL: `"ssl": true` in `hix.json`.
- Provide valid certificate paths.
- Add HSTS header (`Strict-Transport-Security: max-age=31536000; includeSubDomains`).

---

### 🟠 C7 — No Content-Security-Policy Header

**CWE ID**: CWE-693 (Protection Mechanism Failure)

**Severity**: **MEDIUM**

**Location**: Application-wide (no CSP configured)

**Technical Explanation**:
No `Content-Security-Policy` header is set. The login page loads Bootstrap from `https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css` — a third-party CDN. Without CSP, if the CDN is compromised, an attacker can inject malicious CSS/JS into the page.

**Remediation**:
```harbour
USetHeader( "Content-Security-Policy",
   "default-src 'self'; style-src 'self' 'unsafe-inline'; " .
   "script-src 'self' 'unsafe-inline'; " .
   "img-src 'self' data:; " .
   "frame-ancestors 'none'; " .
   "form-action 'self'; " .
   "base-uri 'self'; " .
   "upgrade-insecure-requests" )
```

---

### 🟡 C8 — Information Disclosure via `UAuthUser()` in Views

**CWE ID**: CWE-200 (Information Exposure Through Information Retrieval)

**Severity**: **MEDIUM**

**Location**: `www/views/main.html`

**Technical Explanation**:
The main dashboard displays the full user object including roles and ID:

```html
<tr><td>ID</td><td>{{ hb_HGetDef( hUser, 'id', '?' ) }}</td></tr>
<tr><td>Name</td><td>{{ cName }}</td></tr>
<tr><td>Roles</td><td>{{ cRoles }}</td></tr>
```

While this is a dashboard for the authenticated user, exposing the internal role structure (`sales`, `purchases`, `customers`) helps an attacker understand the permission model for privilege escalation attempts.

**Remediation**:
- Do not display the full role hash in the UI.
- Only show the user's display name.

---

### 🟡 C9 — No CSRF on GET Routes

**CWE ID**: CWE-352 (Cross-Site Request Forgery)

**Severity**: **MEDIUM**

**Location**: `www/routes/web.json`

**Technical Explanation**:
Some GET routes are protected by `MyAppAuth` (session + auth) but not by CSRF:
- `GET /main` — displays sensitive user data
- `GET /module_a` through `/module_c` — module access

While GET should be idempotent and not modify state, an attacker could craft a malicious page that loads these resources via `<img>` or `<script>` tags to:
- Leak the CSRF token (if the page renders one)
- Trigger unintended state changes if the framework has any GET-side effects
- Perform timing attacks or fingerprinting

**Remediation**:
- Add `HIX_MwCsrfCheck` to all GET routes that render sensitive data, or
- Ensure `SameSite=Lax` on the session cookie (already done) — this mitigates most CSRF on GET.

---

### 🟡 C10 — DBF File Paths Not Sanitized in Data Model

**CWE ID**: CWE-22 (Path Traversal)

**Severity**: **MEDIUM**

**Location**: `www/models/tcustomers.prg`, `www/models/tstates.prg`

**Technical Explanation**:
The data path is constructed via `hb_dirbase() + UConfig("paths", "data", "data")`. If `UConfig` returns a user-controllable value (e.g., from a config file that could be modified), it could lead to arbitrary file access.

Additionally, the `customers.dbf` and `states.dbf` files have no access control — any process with read access to the data directory can read customer records.

**Remediation**:
- Validate data paths against a whitelist.
- Set file permissions on `.dbf`/`.cdx` files (e.g., `chmod 600`).

---

### 🟡 C11 — Session Cookie Not Set to Secure

**CWE ID**: CWE-614 (Sensitive Cookie in HTTPS Session Without 'Secure' Attribute)

**Severity**: **MEDIUM**

**Location**: `www/middlewares/config.json` → `setup.session`

**Technical Explanation**:
The `FENIXSID` session cookie is set via `HIX_SetCookie` but the `Secure` flag depends on the `HIX_SetCookie` implementation. Without `Secure`, the cookie is sent over unencrypted HTTP connections, enabling MITM interception.

**Remediation**:
- Ensure `HIX_SetCookie` sets `Secure` flag when the connection is HTTPS.
- Or: always enforce HTTPS (see C6).

---

### 🟡 C12 — No Input Sanitization on DBF Fields

**CWE ID**: CWE-89 (SQL Injection) / CWE-79 (Cross-Site Scripting)

**Severity**: **MEDIUM**

**Location**: `www/controllers/masters/customer.prg` (Store, Update)

**Technical Explanation**:
The validator uses `UValidatePost` with field rules like `max:20`, `max:30`, etc. While these limit length, they do not sanitize HTML content. The `notes` field accepts `string|field` with no HTML escaping.

The `{{ HB_HGetDef( hRow, 'notes' ) }}` in `show.html` renders unescaped HTML in the view. If a user stores `<script>alert(1)</script>` in the notes field, it will execute when the record is viewed.

**Attack Vector**:
```bash
# Store XSS payload in customer notes
curl -X POST http://localhost:8080/customer/store \
  -d "first=John&last=Doe&street=123 Main&city=Anytown" \
  -d "state=CA&zip=12345&hiredate=2025-01-01&age=30&notes=<script>alert('XSS')</script>" \
  -d "_csrf=<valid_token>" \
  -c cookies.txt
```

**Remediation**:
- Add `|field` → `|escapedfield` to the `notes` validation rule.
- Or: escape output in the template: `{{ HB_HGetDef( hRow, 'notes' ) }}` → `{{ HB_HGetDef( hRow, 'notes' ) | escape }}`.

---

### 🟢 C13 — Good: CSRF Protection on All State-Changing Routes

**CWE ID**: N/A

**Severity**: N/A

**Positive Finding**: All POST routes that modify state (`/customer/store`, `/customer/:id/update`, `/customer/:id/delete`) use `MyAppAuthRoleEdit` which includes `HIX_MwCsrfCheck`. The CSRF token is stateless (HMAC-based) and uses the app key. The `/auth` login route also has `HIX_MwCsrfCheck`.

---

### 🟢 C14 — Good: Role-Based Access Control

**CWE ID**: N/A

**Severity**: N/A

**Positive Finding**: The `HIX_MwHasRole` middleware correctly checks the `scope` parameter against the user's roles hash. The middleware chain order (`Session → IsAuth → HasRole → CsrfCheck`) ensures authorization is checked before CSRF validation, preventing information leakage about valid CSRF tokens for unauthorized users.

---

### 🟢 C15 — Good: Input Validation on All User Inputs

**CWE ID**: N/A

**Severity**: N/A

**Positive Finding**: All POST inputs are validated with `UValidatePost` including:
- Type checking (`string`, `numeric`, `date`)
- Length limits (`max:20`, `max:30`, etc.)
- Required field enforcement (`required`)
- The `field` modifier ensures only validated fields are included in `DataFields()`

---

## Recommendations Priority Matrix

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| P0 | C1 — Plaintext passwords | Low | Critical |
| P0 | C3 — Static secrets | Low | Critical |
| P1 | C2 — Stateless resource tokens | Medium | Critical |
| P1 | C5 — Permissive rate limit | Low | High |
| P1 | C6 — No HTTPS | Medium | High |
| P2 | C4 — In-memory sessions | Low | High |
| P2 | C7 — No CSP | Low | Medium |
| P2 | C12 — Unescaped DB output | Low | Medium |
| P3 | C8 — Role disclosure | Low | Medium |
| P3 | C11 — Cookie Secure flag | Low | Medium |

---

## Conclusion

The Fenix Webapp has a solid middleware architecture with proper session management, CSRF protection, and role-based authorization. The primary risk vectors are **credential storage** (plaintext passwords), **secret management** (hardcoded HMAC keys), and **session persistence** (in-memory only). These are all easily remediable. The most urgent fix is replacing plaintext password storage with bcrypt/argon2 and moving secrets to environment variables.

---

*Report generated by automated SRS pentest engine.*
*Findings validated against OWASP Top 10 2024 and API Security Top 10.*
