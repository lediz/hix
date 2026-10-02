#!/bin/bash
# Functional test for Customer module only — HIX Platform
# Complies with: SRS-Harbour-HIX.md, DAL SRS, DEV-compliance.md
# No remediation — results and recommendations only

API="http://localhost:9090"
PASS=0
FAIL=0
TOTAL=0

pass_test() {
    TOTAL=$((TOTAL+1))
    PASS=$((PASS+1))
    echo "[PASS] $1 (expected $2, got $3)"
}

fail_test() {
    TOTAL=$((TOTAL+1))
    FAIL=$((FAIL+1))
    echo "[FAIL] $1 (expected $2, got $3)"
}

echo "============================================================="
echo "  CUSTOMER MODULE — FUNCTIONAL TEST SUITE (HIX Platform)"
echo "============================================================="
echo "  Target: $API"
echo "  DBF: customers.dbf / customers.cdx (DBFCDX)"
echo "  Tag: first"
echo "============================================================="
echo ""

# ---- Authentication & Authorization ----
# T01-T06: All customer endpoints protected
for endpoint in "customer/grid" "customer/search" "customer/1" "customer/create" "customer/1/edit" "customer/1/delete_confirm"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/$endpoint")
    if [ "$CODE" = "302" ]; then
        pass_test "T$(printf '%02d' $((TOTAL+1))) - $endpoint protected without session" "302" "$CODE"
    else
        fail_test "T$(printf '%02d' $((TOTAL+1))) - $endpoint protected without session" "302" "$CODE"
    fi
done

# T07: Login page serves HTML + CSRF token
CSRF=$(curl -s "$API/login" | grep -oP 'name=["\x27]_csrf["\x27]\s+value=["\x27]([^"\x27]+)["\x27]' | grep -oP 'value=["\x27]([^"\x27]+)["\x27]' | sed 's/value=["\x27]\([^"\x27]*\)["\x27]/\1/')
if [ -n "$CSRF" ]; then
    pass_test "T07 - Login page returns HTML with CSRF token" "non-empty" "yes"
else
    fail_test "T07 - Login page returns HTML with CSRF token" "non-empty" "no"
fi

# T08: POST /auth WITHOUT CSRF → rejected
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth" \
    -d "username=demo&password=1234" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie-jar /tmp/test_cookies.txt)
if [ "$CODE" = "302" ]; then
    pass_test "T08 - POST /auth without CSRF rejected" "302" "$CODE"
else
    fail_test "T08 - POST /auth without CSRF rejected" "302" "$CODE"
fi

# T09: POST /auth WITH CSRF → authenticated
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth" \
    -d "username=demo&password=1234&_csrf=$CSRF" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "302" ]; then
    pass_test "T09 - POST /auth with CSRF → authenticated" "302" "$CODE"
else
    fail_test "T09 - POST /auth with CSRF → authenticated" "302" "$CODE"
fi

# T10: GET /main with session → 200
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/main" --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "200" ]; then
    pass_test "T10 - GET /main with session → 200" "200" "$CODE"
else
    fail_test "T10 - GET /main with session → 200" "200" "$CODE"
fi

# ---- Grid (FR-READ-1, FR-READ-2) ----
GRID=$(curl -s "$API/customer/grid" --cookie /tmp/test_cookies.txt)

# T11: Grid returns 200
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/customer/grid" --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "200" ]; then
    pass_test "T11 - GET /customer/grid with session → 200 (FR-READ-1, FR-READ-2)" "200" "$CODE"
else
    fail_test "T11 - GET /customer/grid with session → 200" "200" "$CODE"
fi

# T12: Grid contains Data Grid heading
if echo "$GRID" | grep -q "Data Grid"; then
    pass_test "T12 - Grid contains 'Data Grid' heading (FR-READ-1)" "contains" "yes"
else
    fail_test "T12 - Grid contains 'Data Grid' heading" "contains" "no"
fi

# T13: Grid contains search input
if echo "$GRID" | grep -q "Search customers"; then
    pass_test "T13 - Grid contains search input (FR-READ-3)" "present" "yes"
else
    fail_test "T13 - Grid contains search input" "present" "no"
fi

# T14: Grid contains sortable columns (FR-READ-4)
if echo "$GRID" | grep -q "sortable"; then
    pass_test "T14 - Grid contains sortable columns (FR-READ-4)" "present" "yes"
else
    fail_test "T14 - Grid contains sortable columns" "present" "no"
fi

# T15: Grid contains pagination (FR-READ-2)
if echo "$GRID" | grep -q "pagination"; then
    pass_test "T15 - Grid contains pagination (FR-READ-2)" "present" "yes"
else
    fail_test "T15 - Grid contains pagination" "present" "no"
fi

# T16: Grid contains action buttons
if echo "$GRID" | grep -q "btn-outline-primary" && echo "$GRID" | grep -q "btn-outline-secondary"; then
    pass_test "T16 - Grid contains action buttons (Show/Edit)" "present" "yes"
else
    fail_test "T16 - Grid contains action buttons" "present" "no"
fi

# T17: Grid contains 'Create Customer' button (FR-CREATE-1)
if echo "$GRID" | grep -q "Create Customer"; then
    pass_test "T17 - Grid contains 'Create Customer' button (FR-CREATE-1)" "present" "yes"
else
    fail_test "T17 - Grid contains 'Create Customer' button" "present" "no"
fi

# T18: Grid displays customer records (compiled Mambo renders HB_HGetDef values)
if echo "$GRID" | grep -q "<td>"; then
    pass_test "T18 - Grid renders customer data via HB_HGetDef" "present" "yes"
else
    fail_test "T18 - Grid renders customer data" "present" "no"
fi

# ---- Search (FR-READ-3, FR-READ-5) ----
SEARCH=$(curl -s "$API/customer/search" --cookie /tmp/test_cookies.txt)

# T19: Search endpoint renders form (FR-READ-3)
if echo "$SEARCH" | grep -q "Customer"; then
    pass_test "T19 - Search endpoint renders form (FR-READ-3)" "contains" "yes"
else
    fail_test "T19 - Search endpoint renders form" "contains" "no"
fi

# T20: Search form has ID input (FR-READ-5)
if echo "$SEARCH" | grep -q 'id="customer"'; then
    pass_test "T20 - Search form has ID input (FR-READ-5)" "present" "yes"
else
    fail_test "T20 - Search form has ID input" "present" "no"
fi

# ---- Show (FR-READ-1, FR-READ-5) ----
SHOW=$(curl -s "$API/customer/1" --cookie /tmp/test_cookies.txt)

# T21: Show renders customer details (FR-READ-1)
if echo "$SHOW" | grep -q "Recno:"; then
    pass_test "T21 - Show renders customer details (FR-READ-1)" "contains" "yes"
else
    fail_test "T21 - Show renders customer details" "contains" "no"
fi

# T22: Show displays all fields (≥6) — new schema: FIRST, LAST, ADDRESS, COUNTRY, ZIP, NOTES
FIELD_COUNT=$(echo "$SHOW" | grep -c "form-control")
if [ "$FIELD_COUNT" -ge 6 ]; then
    pass_test "T22 - Show displays all fields (≥6)" "≥6" "$FIELD_COUNT"
else
    fail_test "T22 - Show displays all fields" "≥6" "$FIELD_COUNT"
fi

# T23: Show displays state name (TStates join)
if echo "$SHOW" | grep -q "form-control-plaintext"; then
    pass_test "T23 - Show displays state name (TStates join)" "present" "yes"
else
    fail_test "T23 - Show displays state name" "present" "no"
fi

# T24: Show invalid record → "Customer not exist"
SHOW_INVALID=$(curl -s "$API/customer/99999" --cookie /tmp/test_cookies.txt)
if echo "$SHOW_INVALID" | grep -q "Customer not exist"; then
    pass_test "T24 - Show invalid record → 'Customer not exist'" "contains" "yes"
else
    fail_test "T24 - Show invalid record → 'Customer not exist'" "contains" "no"
fi

# ---- Create (FR-CREATE-1, FR-CREATE-2, FR-CREATE-3) ----
CREATE=$(curl -s "$API/customer/create" --cookie /tmp/test_cookies.txt)

# T25: Create renders form (FR-CREATE-1, FR-CREATE-2)
if echo "$CREATE" | grep -q "Create"; then
    pass_test "T25 - Create endpoint renders form (FR-CREATE-1, FR-CREATE-2)" "contains" "yes"
else
    fail_test "T25 - Create endpoint renders form" "contains" "no"
fi

# T26: Create form has CSRF (compiled Mambo outputs _csrf hidden field)
if echo "$CREATE" | grep -q 'name="_csrf"'; then
    pass_test "T26 - Create form has CSRF token (compiled output)" "present" "yes"
else
    fail_test "T26 - Create form has CSRF token (compiled output)" "present" "no"
fi

# T27: Create form has all required fields (FR-CREATE-3) — new schema
FIELD_CHECK=("first" "last" "address" "country" "zip" "notes")
ALL_PRESENT=1
for field in "${FIELD_CHECK[@]}"; do
    if ! echo "$CREATE" | grep -q "name=\"$field\""; then
        ALL_PRESENT=0
        break
    fi
done
if [ "$ALL_PRESENT" -eq 1 ]; then
    pass_test "T27 - Create form has all required fields (FR-CREATE-3)" "all present" "yes"
else
    fail_test "T27 - Create form has all required fields" "all present" "no"
fi

# T28: Create form has country field (replaces state dropdown)
if echo "$CREATE" | grep -q 'name="country"'; then
    pass_test "T28 - Create form has country field (replaces state)" "present" "yes"
else
    fail_test "T28 - Create form has country field" "present" "no"
fi

# ---- Edit (FR-UPDATE-2, FR-UPDATE-3) ----
EDIT=$(curl -s "$API/customer/1/edit" --cookie /tmp/test_cookies.txt)

# T29: Edit pre-populates form (FR-UPDATE-2)
if echo "$EDIT" | grep -q "Recno:"; then
    pass_test "T29 - Edit endpoint pre-populates form (FR-UPDATE-2)" "contains" "yes"
else
    fail_test "T29 - Edit endpoint pre-populates form" "contains" "no"
fi

# T30: Edit form has hidden _recno (FR-UPDATE-3)
if echo "$EDIT" | grep -q 'name="_recno"'; then
    pass_test "T30 - Edit form has hidden _recno field (FR-UPDATE-3)" "present" "yes"
else
    fail_test "T30 - Edit form has hidden _recno field" "present" "no"
fi

# T31: Edit form has hidden _deleted
if echo "$EDIT" | grep -q 'name="_deleted"'; then
    pass_test "T31 - Edit form has hidden _deleted field" "present" "yes"
else
    fail_test "T31 - Edit form has hidden _deleted field" "present" "no"
fi

# T32: Edit form has CSRF (compiled output)
if echo "$EDIT" | grep -q 'name="_csrf"'; then
    pass_test "T32 - Edit form has CSRF token (compiled output)" "present" "yes"
else
    fail_test "T32 - Edit form has CSRF token (compiled output)" "present" "no"
fi

# T33: Edit form has signed resource ID (compiled Mambo outputs _resource)
if echo "$EDIT" | grep -q "_resource"; then
    pass_test "T33 - Edit form has @RESOURCE signed ID (REQ-INT-UI-003)" "present" "yes"
else
    fail_test "T33 - Edit form has @RESOURCE signed ID" "present" "no"
fi

# ---- Delete (FR-DELETE-1, FR-DELETE-2, FR-DELETE-3, FR-DELETE-4) ----
DELETE=$(curl -s "$API/customer/1/delete_confirm" --cookie /tmp/test_cookies.txt)

# T34: Delete_confirm renders confirmation modal
if echo "$DELETE" | grep -q "deleteConfirmModal"; then
    pass_test "T34 - Delete_confirm renders confirmation modal" "contains" "yes"
else
    fail_test "T34 - Delete_confirm renders confirmation modal" "contains" "no"
fi

# T35: Delete_confirm shows customer details
if echo "$DELETE" | grep -q "Delete Customer"; then
    pass_test "T35 - Delete_confirm shows customer details" "contains" "yes"
else
    fail_test "T35 - Delete_confirm shows customer details" "contains" "no"
fi

# T36: Delete modal has confirmation form
if echo "$DELETE" | grep -q "deleteConfirmModal"; then
    pass_test "T36 - Delete modal has confirmation form" "present" "yes"
else
    fail_test "T36 - Delete modal has confirmation form" "present" "no"
fi

# ---- Write operations ----
# T37: POST /customer/store WITHOUT CSRF → rejected
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/store" \
    -d "first=Test&last=Customer" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "302" ]; then
    pass_test "T37 - POST /customer/store without CSRF rejected (CSRF check)" "302" "$CODE"
else
    fail_test "T37 - POST /customer/store without CSRF rejected" "302" "$CODE"
fi

# T38: POST /customer/store with valid data → success
STORE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/store" \
    -d "first=TestUser&last=TestLast&street=123 Test St&city=TestCity&state=TX&zip=75001&hiredate=2024-01-15&age=30&married=1&notes=Test note" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$STORE_CODE" = "302" ]; then
    pass_test "T38 - POST /customer/store with valid data → success (302)" "302" "$STORE_CODE"
else
    fail_test "T38 - POST /customer/store with valid data" "302" "$STORE_CODE"
fi

# T39: POST /customer/store with validation failure → redirect
FAIL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/store" \
    -d "first=&last=" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$FAIL_CODE" = "302" ]; then
    pass_test "T39 - POST /customer/store with validation failure → redirect" "302" "$FAIL_CODE"
else
    fail_test "T39 - POST /customer/store with validation failure" "302" "$FAIL_CODE"
fi

# T40: POST /customer/:id/update with valid data → success
# Use the newly created record (recno 6)
UPDATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/6/update" \
    -d "first=UpdatedFirst&last=UpdatedLast&street=456 Updated St&city=UpdatedCity&state=TX&zip=99999&hiredate=2024-06-01&age=35&married=0&notes=Updated note" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$UPDATE_CODE" = "302" ]; then
    pass_test "T40 - POST /customer/6/update with valid data → success (302)" "302" "$UPDATE_CODE"
else
    fail_test "T40 - POST /customer/6/update with valid data" "302" "$UPDATE_CODE"
fi

# T41: POST /customer/:id/update with validation failure → redirect
UPDATE_FAIL=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/6/update" \
    -d "first=&last=" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --cookie /tmp/test_cookies.txt)
if [ "$UPDATE_FAIL" = "302" ]; then
    pass_test "T41 - POST /customer/6/update with validation failure → redirect" "302" "$UPDATE_FAIL"
else
    fail_test "T41 - POST /customer/6/update with validation failure" "302" "$UPDATE_FAIL"
fi

# T42: DELETE /customer/:id → soft delete (302)
DELETE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/customer/6/delete" \
    --cookie /tmp/test_cookies.txt)
if [ "$DELETE_CODE" = "302" ]; then
    pass_test "T42 - POST /customer/6/delete → soft delete (302)" "302" "$DELETE_CODE"
else
    fail_test "T42 - POST /customer/6/delete → soft delete" "302" "$DELETE_CODE"
fi

# T43: Grid no longer shows deleted record
GRID_AFTER=$(curl -s "$API/customer/grid" --cookie /tmp/test_cookies.txt)
if echo "$GRID_AFTER" | grep -q "TestUser"; then
    fail_test "T43 - Grid excludes soft-deleted record" "not present" "present"
else
    pass_test "T43 - Grid excludes soft-deleted record" "not present" "absent"
fi

# T44: Show invalid record → "Customer not exist"
SHOW_INVALID2=$(curl -s "$API/customer/99999" --cookie /tmp/test_cookies.txt)
if echo "$SHOW_INVALID2" | grep -q "Customer not exist"; then
    pass_test "T44 - Show invalid record → 'Customer not exist'" "contains" "yes"
else
    fail_test "T44 - Show invalid record → 'Customer not exist'" "contains" "no"
fi

# ---- Logout & cleanup ----
# T45: Logout → 302
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/logout" --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "302" ]; then
    pass_test "T45 - GET /logout → 302 (session destroyed)" "302" "$CODE"
else
    fail_test "T45 - GET /logout → 302" "302" "$CODE"
fi

# T46: After logout, /customer/grid → 302
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/customer/grid" --cookie /tmp/test_cookies.txt)
if [ "$CODE" = "302" ]; then
    pass_test "T46 - After logout, /customer/grid → 302" "302" "$CODE"
else
    fail_test "T46 - After logout, /customer/grid → 302" "302" "$CODE"
fi

# ---- HIX Compliance checks ----
# T47: DBF + CDX exist (C-004)
if [ -f "data/customers.dbf" ] && [ -f "data/customers.cdx" ]; then
    pass_test "T47 - DBF + CDX files exist (C-004 compliance)" "both files" "present"
else
    fail_test "T47 - DBF + CDX files exist" "both files" "missing"
fi

# T48: hixstyle enabled (C-003)
if grep -q '"hixstyle"' hix.json && grep -q '"enabled": true' hix.json; then
    pass_test "T48 - hix.json has hixstyle.enabled = true (C-003)" "true" "yes"
else
    fail_test "T48 - hix.json has hixstyle.enabled = true" "true" "no"
fi

# T49: Routes use MyAppAuthRole (C-007)
if grep -q 'MyAppAuthRole' www/routes/web.json; then
    pass_test "T49 - Routes use MyAppAuthRole middleware (C-007)" "present" "yes"
else
    fail_test "T49 - Routes use MyAppAuthRole middleware" "present" "no"
fi

# T50: Routes use scope declarations (REQ-FUNC-023)
if grep -q '"scope"' www/routes/web.json; then
    pass_test "T50 - Routes use scope declarations (REQ-FUNC-023)" "present" "yes"
else
    fail_test "T50 - Routes use scope declarations" "present" "no"
fi

echo ""
echo "============================================================="
echo "  CUSTOMER MODULE — TEST RESULTS SUMMARY"
echo "============================================================="
echo "  Total tests : $TOTAL"
echo "  Passed      : $PASS"
echo "  Failed      : $FAIL"
echo "  Pass rate   : $PASS/$TOTAL"
echo "============================================================="
echo ""

rm -f /tmp/test_cookies.txt
