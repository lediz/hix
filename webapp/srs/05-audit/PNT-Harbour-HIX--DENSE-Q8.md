# Harbour HIX Webapp - Security Audit Report (Dense Q8)

**Audit Date:** 2026-10-07  
**Scope:** Authentication, Authorization, Configuration, API Endpoints  
**Framework:** HIX (Harbour) v5.0.0 | Database: RDD DBFCDX | JWT Auth

---

## Executive Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High     | 3 |
| Medium   | 4 |

**Top Risk:** Plaintext credentials and empty admin secret enable trivial unauthorized access.

---

## Findings

### 1. Insecure Direct Object Reference (IDOR) — CWE-639
**Severity:** Critical

**Location:** `/www/controllers/masters/customer.prg` — `Show()`, `Edit()`, `Update()`, `Delete()` methods

**Issue:** All customer CRUD endpoints accept a numeric ID parameter (`:id`) directly from the URL or resource without verifying that the authenticated user owns the record. The middleware stack includes `MyAppAuthRole` with scope checks, but the controller never validates ownership before reading or modifying data.

```harbour
// Example: Show() method — any authenticated user can view any customer
lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )
```

**Exploitation:** An attacker with a low-privilege account (e.g., `carles` limited to `search;show`) could:

1. Log in as carles (password: `1234`, known from demo data).
2. Request `/customer/show/2` — returns the Admin Demo record (`id=1`).
3. Modify the URL to `/customer/edit/1`, bypassing scope checks.
4. Submit a POST to `/customer/store` with modified fields, effectively editing the admin account.

**Remediation:** Enforce ownership validation in every controller method:

```harbour
// In Show/Edit/Update/Delete — after retrieving oCustomers:
LOCAL nOwnerId := UFlashGet( 'owner_id' )  // inject from JWT claims via middleware
IF nOwnerId != nId
   UFlash("customer"):Set({ "type" => 'error', "message" => 'Access denied' })
   RETURN URedirect( URoute('customer.search') )
ENDIF
```

The `MyAppAuthRole` middleware must pass the resource owner ID into flash before controller execution, or controllers should query the user context from a global session variable set by auth.

---

### 2. Hardcoded Demo Credentials — CWE-312 / CWE-524
**Severity:** High

**Location:** `/www/models/modeluser.prg`

**Issue:** The user model contains a static hash with plaintext usernames and passwords:

```harbour
hStore := {
   "demo"   => { "id" => "1", "name" => "Admin Demo",   "pass" => "1234", ... },
   "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ... },
   ...
}
```

No rate limiting or account lockout on failed attempts. This allows trivial enumeration and brute-force attacks, especially in development/deployment environments where the file may be committed or accessible.

**Exploitation:** Attackers can immediately authenticate as `Admin Demo` (id=1) with any password attempt, gaining full system access.

**Remediation:**
- Remove static credentials from codebase.
- Implement a proper user store (e.g., SQLite with hashed passwords using bcrypt or PBKDF2).
- Add login throttling: track failed attempts per IP/account; lock after N failures.

```harbour
// Pseudocode for secure auth store:
FUNCTION ModelUser( cUser, cPass )
   LOCAL hStore := UDBFGet( 'users.dbf' )
   LOCAL lFound := USeek( hStore, { "username" := LOWER( cUser ) }, 1 )
   IF ! lFound || ! ( UHash( hStore["password"] ) == UHash( cPass ) )
      RETURN NIL
   ENDIF
   RETURN { "id" => hStore["id"], "name" => hStore["name"], "roles" => hStore["roles"] }
```

---

### 3. Empty Admin Credentials — CWE-521
**Severity:** High

**Location:** `/hix.json` — `admin` section:

```json
"admin": {
  "enabled": true,
  "user": "",
  "password": "",
  "secret": ""
}
```

The admin account is enabled but has no password or secret key. Additionally, session encryption (`session.crypt`) is disabled.

**Exploitation:** Any request to the admin interface (if exposed) will succeed with empty credentials. Even without direct access, the lack of a secret means JWT tokens and sessions are not cryptographically protected.

**Remediation:**
- Set strong admin password and secret at least 32 characters using a vault.
- Enable session encryption: `"session": { "crypt": true }`.
- Restrict admin routes with a dedicated middleware that verifies both auth and role.

```json
"admin": {
  "enabled": true,
  "user": "admin",
  "password": "xK9#mP2$vL8@qR4!nT7&yU1*wZ3",
  "secret": "HIX-SECRETPASS2026"
}
```

---

### 4. JWT Token Not Verified in Middleware — CWE-287
**Severity:** High

**Location:** `/www/middlewares/myappauth.prg` and `myappauthrole.prg`

Both middleware files chain:

```harbour
o:Add( UMiddleware():New( "HIX_MwSession" ) )
o:Add( UMiddleware():New( "HIX_MwIsAuth"   ) )
```

However, the HIX framework's `MwIsAuth` does not validate JWT payload contents (e.g., expiration, issuer). There's no middleware to enforce role claims from the token. The controller-level scope checks (`"scope": "customers:edit"`) are applied but may be bypassed if the session is manually forged or if an attacker can manipulate request headers.

**Exploitation:** An attacker could craft a valid-looking JWT (or replay one) and, because the middleware trusts the session cookie without verifying token integrity, gain unauthorized access to protected endpoints.

**Remediation:**
- Add a custom JWT validation middleware:

```harbour
FUNCTION MwJwtValidate( oCtx )
   LOCAL hToken := HIX_GetHeader( "Authorization" )
   IF ! hToken || ! JwtVerify( hToken[1], UMwConfig( "auth", "secret" ) )
      RETURN UStatus( 401, "Unauthorized" )
   ENDIF
   // Store decoded claims in oCtx for later use
RETURN o:MwNext()
```

- Chain `MwJwtValidate` before `HIX_MwSession` in both `MyAppAuthRole` and `MyAppAuth`.

---

### 5. Verbose Error Exposure — CWE-209
**Severity:** Medium

**Location:** Multiple controllers, e.g., `customer.prg`'s `Update()`:

```harbour
UFlash("customer"):Set( { "errors" => oVal:GetErrors(), "input" => hResume } )
```

When validation fails, the full list of errors and the submitted payload are flashed back to the user. In production, this leaks sensitive field names, default values, and potentially database schema hints.

**Remediation:** Strip internal fields from flash payloads in production mode:

```harbour
IF UMwConfig( "app", "env" ) == "prod"
   // Remove 'errors' and transform 'input' to sanitized version
   oFlash:Remove( { "errors", "password", "ssn", "secret" } )
ENDIF
```

---

### 6. Missing CSRF Protection — CWE-352
**Severity:** Medium

All state-changing routes (`/customer/store`, `/customer/update`, `/customer/delete`) are POST endpoints without any anti-CSRF token mechanism. The HIX framework does not appear to enforce CSRF tokens on middleware stacks.

**Exploitation:** An attacker with XSS in any page can submit a hidden form targeting these endpoints, modifying or deleting customer records on behalf of logged-in users.

**Remediation:**
- Implement a CSRF token per session (store in `session.csrftoken`).
- Require the token in all POST/PUT/DELETE requests; reject if missing or mismatched.

```harbour
// In middleware:
LOCAL cToken := UPost( "csrf" )
IF empty( cToken ) || cToken != USession( "csrftoken" )
   RETURN UStatus( 403, "CSRF token missing/invalid" )
ENDIF
```

---

### 7. No Rate Limiting on Authentication Endpoints — CWE-307
**Severity:** Medium

The `/login` route (`POST /login`) and password reset flows lack any throttling. Combined with the hardcoded demo credentials, this makes brute-force attacks trivial.

**Remediation:** Apply per-IP or per-account rate limiting using a simple Redis-backed counter or file-based lock:

```harbour
LOCAL nFailed := UGetCounter( "login_fail:" + cIp )
IF nFailed >= 5
   RETURN UStatus( 429, "Too many attempts. Try again in 60s." )
ENDIF
UIncrement( "login_fail:" + cIp, 1 )
```

---

## Recommendations Summary

| Priority | Action |
|----------|--------|
| **P0** | Remove hardcoded passwords; migrate to hashed credential store |
| **P0** | Set admin password and enable session encryption |
| **P1** | Add ownership checks in all customer CRUD endpoints |
| **P1** | Implement JWT validation middleware |
| **P2** | Reduce error verbosity in production |
| **P2** | Add CSRF tokens to all state-changing requests |
| **P2** | Deploy rate limiting on login and sensitive routes |

---

*Report generated by automated SRS pentest workflow. Review all findings before deployment.*
