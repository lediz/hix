# Customer Module — Critical Fixes Log

## Change 1: Fixed HIX_MwIsAuth session path (src/mw/hix_mw_session_auth.prg)
## Added fallback check for session["data"]["_auth_user"]
## Backup: src/mw/hix_mw_session_auth.prg.bak
## Status: APPLIED
# Date: 2026-10-02
# Scope: Customer module only (www/controllers/masters/customer.prg, routes, middleware)
# Data files untouched: data/customers.dbf, data/customers.cdx, data/states.dbf

## Change 1: Fix HIX_MwIsAuth Session Path
File: src/mw/hix_mw_session_auth.prg
Reason: HIX_MwIsAuth checks session["_auth_user"] but session structure is session["data"]["_auth_user"]
Impact: All authenticated POSTs redirect to /login — no controller ever runs
Date: 2026-10-02

## Change 2: Fix Route Action Resolution
File: www/routes/web.json
Reason: HIX router can't resolve "controllers/masters/grid@customer.prg" → Customer:Grid()
Impact: 19 routes fail with "No exist method" errors
Date: 2026-10-02

## Change 3: Fix HMAC Keys
File: www/config.json
Reason: All 5 keys use published defaults (H!x@CSRF@2026, etc.)
Impact: All HMAC tokens predictable — security breach
Date: 2026-10-02

## Change 4: Fix HIX_MwCsrfSetup Redirect
File: src/app.prg
Reason: HIX_MwCsrfSetup called with NIL redirect — CSRF failures show blank 403
Impact: CSRF failures invisible to users
Date: 2026-10-02

## Change 5: Fix Compiled View Cache
File: .cached/views/masters/customer/*.hrb
Reason: Stale compiled views (Sep 30) may serve outdated templates
Impact: Intermittent rendering errors, stale CSRF tokens
Date: 2026-10-02

## Change 6: Fix SortGrid Bounds
File: www/controllers/masters/customer.prg
Reason: Bubble sort accesses aCopy[nJ+1] without Empty(aGrid) guard
Impact: Potential crash on empty grid
Date: 2026-10-02

## Change 7: Fix UDbf:Update Type Conversion
File: www/controllers/masters/customer.prg
Reason: Numeric/logical fields passed as strings to DBF — age stored as "35.00000"
Impact: Data corruption on update, age field misformatted
Date: 2026-10-02

## Change 8: Fix LOCAL Declaration Order
File: test/test_customer_module.prg
Reason: Harbour requires LOCAL before executable statements
Impact: Compile failure
Date: 2026-10-02

## Pre-Fix State
- HIX server running on port 9090
- DBF: data/customers.dbf (206KB, 51 records), tag: first
- Sessions: 38 session files
- Errors.log: 1417 entries (52 unknown symbols, 49 bound errors, 30 arg errors, 16 "no method delete_confirm", 2 "no method delete_action", 1 "no method grid")
- All test suite: 47/50 PASS (3 FAIL: search input not found, grid data not found, @RESOURCE not found)
- Root cause: HIX_MwIsAuth checks session["_auth_user"] but structure is session["data"]["_auth_user"]
## Change 2: Fixed route action resolution (www/routes/web.json)
## Changed all "controllers/masters/xxx@customer.prg" to "controllers/masters/customer.prg:MethodName"
## Fixes: "No exist method grid", "No exist method delete_confirm", "No exist method delete_action"
## Status: APPLIED
## Change 3: Replaced default HMAC keys (www/config.json)
## All 5 keys were published defaults (H!x@CSRF@2026, H!x@JWT@2026, etc.)
## Replaced with random 48-char hex strings
## Backup: www/config.json.bak
## Status: APPLIED
## Change 4: Fixed HIX_MwCsrfSetup redirect URL (src/app.prg)
## Was: UConfig("setup","csrf","redirect") -> NIL (blank 403 on CSRF fail)
## Now: "/login" with TTL 3600s (1 hour token validity)
## Backup: src/app.prg.bak
## Status: APPLIED
## Change 5: Cleared stale compiled view cache (.cached/views/masters/customer/*.hrb)
## Files removed: delete.hrb, edit.hrb, grid.hrb, search.hrb, show.hrb (all from Sep 30)
## HIX will recompile from .html source on next request
## Status: APPLIED
## Change 6: Added Empty(aGrid) guard to SortGrid (www/controllers/masters/customer.prg:520)
## Prevents bounds error on empty grid arrays
## Status: APPLIED
## Change 7: Fixed UDbf:Update type conversion (www/controllers/masters/customer.prg:177)
## Added: age -> ltrim(str(Val())), married -> Iif(Val(), ".T.", ".F.")
## Prevents: age stored as "35.00000", married stored as "1" (string)
## Status: APPLIED
## Change 8: LOCAL declaration order (test/test_customer_module.prg)
## Already correct: LOCAL cPath, cCdx, i, aTestData (line 138)
## No change needed - already compliant with Harbour requirements
## Status: VERIFIED (no change required)
## Change 7b: Fix LOCAL declaration in Update() method (www/controllers/masters/customer.prg)
## Moved LOCAL hChanges to top of function (was after executable code on line 236)
## Status: APPLIED
##
## FINAL RESULT: 50/50 PASS (100%)
## All customer module endpoints working correctly.
## No data changes to customers.dbf.
## Server running on port 9090.
