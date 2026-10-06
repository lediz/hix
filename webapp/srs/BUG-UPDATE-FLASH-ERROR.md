# Bug Report: Error Flash After Customer Update Confirmation

## Symptom
After confirming a customer update (POST to `/customer/:id/update`), the user receives an error flash message ("Error validacion") instead of the expected success message ("Customer X was updated!"). The update appears to silently fail — the record may or may not be updated, but the user always sees an error.

## Root Cause
**File:** `www/controllers/masters/customer.prg`, line 241–244 (`METHOD Update()`)

```harbour
hChanges := oVal:DataFields()
IF !empty( hChanges[ "age" ] )
   hChanges[ "age" ] := ltrim( str( Val( hChanges[ "age" ] ) ) )
ENDIF
IF !empty( hChanges[ "married" ] )
   hChanges[ "married" ] := Iif( Val( hChanges[ "married" ] ) != 0, ".T.", ".F." )  // ← CRASH HERE
ENDIF
```

**The bug is on line 244:** `hChanges[ "married" ]` is a **logical value** (`.T.` or `.F.`) because the validation rule `"married" => "logic|field"` in `UValidatePost()` (line 211) converts the input to a Harbour logical type. Calling `Val()` on a logical value throws **Argument error (1098)**:

```
[ERROR] [worker_http] Handler error [/customer/6/update]: Argument error (VAL)
```

`Val()` only accepts string arguments in Harbour. `Val(.T.)` and `Val(.F.)` both throw.

## Evidence

### 1. Server-side error logged
```
[2026-10-02 13:24:38] [ERROR] [worker_http] Handler error [/customer/6/update]: Argument error (VAL)
```

### 2. User sees 500 Internal Server Error
```
HTTP/1.1 500 Internal Server Error
<tr><td class='col'>HTTP Code</td><td>1098</td></tr>
```

### 3. The `married` checkbox in the edit form
- The checkbox has a stray `1` attribute (not `checked`) — it's not pre-checked for married records
- When checked, the form sends `married=1` (string)
- `UValidatePost()` with rule `"logic|field"` converts `1` → `.T.` (logical)
- `DataFields()` returns the logical value
- `Val(.T.)` → **Argument error**

### 4. The `age` field has a similar guard issue
- Line 238: `IF !empty( hChanges[ "age" ] )` guards against empty age
- But if `age` is a valid string like `"35"`, `Val("35")` works fine
- If `age` is somehow not a string (unlikely with `|numeric` rule), same crash would occur

### 5. The `married` guard on line 241 is misleading
- `IF !empty( hChanges[ "married" ] )` — `empty(.T.)` returns `.F.`, so the guard passes
- The guard does NOT prevent the crash; it only prevents calling `Val()` on an empty string
- When `married` IS present (checkbox checked), the guard passes and `Val()` is called on a logical → crash

## Impact
- **All update operations where the user is married (checkbox checked) will crash** with a 500 error
- The user sees an error flash message and is redirected back to the edit form
- No data is persisted (the crash occurs before `oCustomers:Update()` is called)
- The `cError` variable is never populated because the crash happens before `UDbf:Update()` is reached
- The flash message shown is the **unhandled exception** (Argument error), not a business validation error

## Affected Routes
- `POST /customer/:id/update` (line 211 validation rule `"married" => "logic|field"`)

## Not Affected
- `POST /customer/store` (Create) — same `logic|field` rule exists on line 296, so **Create also crashes** when `married=1`
- The Store method at line 296 has the same pattern but does NOT have the `Val()` conversion guard — it passes `oVal:DataFields()` directly to `UDbf:Insert()`. This may or may not work depending on whether `UDbf:Insert()` handles logical values natively.
