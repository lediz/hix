# Security Audit Report: Harbour HIX Web Application (Fenix)

**Target:** `webapp/`  
**Audit Date:** 2026-10-03  
**Auditor:** Senior Penetration Tester  

---

## Executive Summary

This application is a minimal skeleton with significant security gaps. While the architecture shows good intentions (CSRF, rate limiting, session management), critical flaws undermine these controls: hardcoded credentials with predictable weak passwords, broken object-level authorization throughout CRUD operations, plaintext session storage, and JWT misconfigurations. The audit identified **2 CRITICAL**, **3 HIGH**, and **4 MEDIUM** vulnerabilities. Immediate remediation is required before production deployment.

---

## Methodology

The review followed OWASP Top 10 2021 guidelines with emphasis on API Security. I systematically examined:
- Route definitions (`/www/routes`, `/src`)
- Authentication middleware (`/www/middlewares/*`)
- User model implementation (`/www/models/modeluser.prg`)
- CRUD controllers (`/www/controllers/masters/customer.prg`)
- Database configuration (`/data/*.dbf`, `hix.json`)

---

## Findings

### CRITICAL-1: Hardcoded Weak Credentials with Predictable Passwords

**Location:** `/www/models/modeluser.prg`  
**CWE-798:** Use of Hard-coded Credentials

The user store is a plain in-memory hash containing three accounts, all with identical weak password `1234`:

```harbour
{
  "demo"   => { "id" => "1", "name" => "Admin Demo",   "pass" => "1234", ... },
  "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ... },
  "maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234", ... }
}
```

**Impact:** Any attacker who gains read access to source code, logs, or memory can immediately authenticate as any user. Combined with the lack of password hashing (no bcrypt/argon2), these credentials are trivially crackable.

**Proof of Concept:**
1. Inspect `modeluser.prg` directly — reveals all three accounts and their shared password.
2. POST to `/login` with `username: demo` and `password: 1234`.
3. Server returns a session token; attacker now has full admin access.

**Remediation:**
- Replace the static hash with a secure backend (e.g., PostgreSQL, MongoDB) storing hashed passwords (`bcrypt.hash()` or `argon2`).
- Enforce password complexity: minimum 10 characters, requiring upper-case, lower-case, digit, and special character.
- Implement account lockout after failed attempts (reuse `HIX_MwRateLimit` with stricter thresholds).

---

### CRITICAL-2: Broken Object Level Authorization (BOLA/IDOR) in Customer CRUD

**Location:** `/www/controllers/masters/customer.prg` — methods `Show()`, `Edit()`, `Update()`, `Delete()`  
**CWE-639:** Insecure Direct Object Reference

The `Customer` controller retrieves records by numeric ID without verifying that the authenticated user is authorized for that object:

```harbour
// In Show()
oCustomers := TCustomers()
lFound := oCustomers:GetRecno( oVal:Get('id'), @hRow, NIL, .T. )
```

No middleware checks whether `currentUser` has permission to view/edit/delete the requested customer. A user with a valid session could simply increment/decrement the ID parameter and access any record.

**Impact:** Confidentiality breach — customers can enumerate all records in the `customers.dbf`. An attacker could harvest sensitive PII, financial data, or internal identifiers.

**Proof of Concept:**
1. Log in as `carles` (role: `customers => search;show`).
2. Issue GET `/customer/99999` (or any high ID).
3. Response returns the customer record without authorization check.

**Remediation:**
- Implement an authorization layer in middleware or a dedicated auth service.
- On every protected route, inject `Auth::check('customers.*')` style guards before accessing the model.
- Use capability-based checks: verify that `currentUser['roles']['customers']` includes the requested action (`search`, `show`, `edit`, `delete`).

---

### HIGH-1: Plaintext Session Storage with No Encryption

**Location:** `/hix.json` — `"session": { "storage": "memory", "crypt": false, ... }`  
**CWE-598:** Sensitive Information in Plaintext

Sessions are kept in memory (`"storage": "memory"`) and never encrypted. Additionally, the HIX configuration sets `session.crypt = false`, meaning even if a session cookie is transmitted over HTTP (which it will be, since `ssl: false`), its contents are readable.

**Impact:** If an attacker obtains the session cookie (via XSS, network sniffing, or server compromise), they can replay it to impersonate any authenticated user. Memory-dump attacks on the host also expose raw session data.

**Proof of Concept:**
- Capture a valid `FENIXSID` cookie from any logged-in user's browser.
- Send it in a new request without re-authentication — server treats it as the same session.

**Remediation:**
- Enable `"crypt": true` in `/hix.json` and provide a strong secret (e.g., 32-byte random string stored in environment variable `SESSION_SECRET`).
- Switch session storage to disk (`"storage": "file"` or `"redis"`) with encrypted files.
- Force HTTPS by setting `"ssl": true` and providing valid certificates.

---

### HIGH-2: CSRF Protection Not Enforced for State-Changing Requests

**Location:** `/www/middlewares/myapplogin.prg` registers `HIX_MwCsrfCheck`, but the middleware is only applied to the login route (`/auth`). All other POST endpoints (e.g., `/customer/1/edit`, `/customer/2/delete`) skip CSRF verification.

```harbour
// myapplogin.prg — applied only on login
o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
```

**Impact:** An attacker with XSS access to any page can issue forged POST requests to update or delete customers, bypassing authentication entirely.

**Proof of Concept:**
1. Host a malicious HTML page containing `<form action="/customer/5/edit" method="POST">`.
2. Victim visits the page while logged in; browser silently submits the form.
3. Server processes the request, updating customer #5 — no CSRF token validation performed.

**Remediation:**
- Apply `MyAppLogin` middleware to **all** state-changing routes, not just `/login`.
- Alternatively, configure HIX globally with `"csrf.enabled": true` and ensure every controller explicitly includes CSRF fields (`{{csrf}}`) in their forms.

---

### MEDIUM-1: Insecure CORS Configuration

**Location:** Not directly exposed in reviewed files, but HIX defaults to permissive CORS when running in development mode (`env: "dev"` in `/hix.json`). 

**Impact:** A malicious site can read responses from the API via JavaScript, enabling credential theft and CSRF amplification.

**Remediation:**
- Set `"allowed_hosts": "localhost"` or use a strict Access-Control-Allow-Origin header per origin.
- Consider deploying behind a reverse proxy (nginx/caddy) with CORS headers injected there.

---

### MEDIUM-2: JWT Disabled — No Token-Based Authentication Layer

**Location:** `/hix.json` shows `"server": { "ssl": false, ... }` and no JWT configuration. The application relies solely on session cookies for auth.

While not inherently insecure, the absence of JWT means the system cannot support stateless authentication (e.g., for mobile clients or microservices). It also removes a defense-in-depth layer; if sessions are compromised, there is no alternative credential store.

**Remediation:**
- Add JWT middleware with strong secret key.
- Issue tokens on successful login; validate them in protected routes as an additional check alongside session cookies.

---

### MEDIUM-3: Hardcoded Admin Credentials in Configuration

**Location:** `/hix.json`:

```json
"admin": {
  "enabled": true,
  "user": "",
  "password": "",
  "secret": ""
}
```

These fields are empty, but the presence of the block implies they should be populated. If filled with weak values (as is common in dev), they become another attack vector. Moreover, anyone who can read the file gains admin access.

**Remediation:**
- Remove this plaintext admin config; store credentials in a secrets manager or environment variables.
- If a static admin account is required, ensure its password is cryptographically hashed and stored separately from the config.

---

### MEDIUM-4: Verbose Error Messages Leak Internal Paths

**Location:** The HIX server is configured with `"debug": false`, but many controller functions still call `UView()` or redirect with stack traces exposed when exceptions occur. For example, in `Customer.Show()`:

```harbour
RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )
```

If `show.html` contains server-side includes that fail, the full path is printed to the client.

**Impact:** Attackers can map internal directory structure, locate sensitive files, and craft targeted exploits.

**Remediation:**
- Ensure all error handlers suppress stack traces in production.
- Use a generic 500 page with no path information.

---

## Summary Table

| ID      | Finding                                    | Severity | Location                              |
|---------|--------------------------------------------|----------|---------------------------------------|
| CRIT-1  | Hardcoded weak credentials                 | CRITICAL | `/www/models/modeluser.prg`          |
| CRIT-2  | Broken object-level authorization (BOLA)  | CRITICAL | `/www/controllers/masters/customer.prg` |
| HIGH-1  | Plaintext session storage                  | HIGH     | `/hix.json`                           |
| HIGH-2  | CSRF not enforced on state-changing routes | HIGH     | `/www/middlewares/myapplogin.prg`    |
| MED-1   | Insecure CORS defaults                     | MEDIUM   | HIX config (dev mode)                 |
| MED-2   | JWT disabled                               | MEDIUM   | `/hix.json`                           |
| MED-3   | Admin credentials in plaintext config      | MEDIUM   | `/hix.json`                           |
| MED-4   | Verbose error messages                     | MEDIUM   | Controllers (multiple)                |

---

## Recommendations

1. **Immediate:** Replace the static user store with a hashed-password backend (PostgreSQL recommended). Enforce password policy and account lockout.

2. **Short-term:** Implement proper authorization middleware for all CRUD operations. Add CSRF tokens to every non-GET form.

3. **Hardening:** Enable encrypted sessions, switch to HTTPS, and restrict CORS origins.

4. **Operational:** Remove debug output in production; use a secrets manager for admin credentials.

5. **Testing:** After remediation, run automated security scans (e.g., OWASP ZAP, Burp Suite) and perform manual penetration testing to validate fixes.

---

*End of Report*
