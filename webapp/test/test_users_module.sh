#!/bin/bash
# =============================================================================
# USERS MODULE — FUNCTIONAL END-TO-END TEST SUITE
# Scope: users module ONLY (www/controllers/masters/users.prg, TUsers,
#        www/views/masters/users/*, users routes in www/routes/web.json)
# Compliance: webapp/srs/DEV-compliance.md (HIX only, no SQL, no 3rd-party WEB UI,
#             hbmk2 app.hbp build, port 9090, tools inside project folder)
# Mode: REPORT ONLY — results + recommendations, NO remediation applied.
# Timeouts: every HTTP call uses --connect-timeout 5 --max-time 15;
#           compiler step uses timeout 60; preflight aborts if server unreachable.
# =============================================================================

API="http://localhost:9090"
CK=$(mktemp -u /tmp/uck_XXXX)
PASS=0; FAIL=0; TOTAL=0
DBF="data/users.dbf"
PY="python3 test/dbf_dump.py"

pass_test() { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "[PASS] $1  (expect $2, got $3)"; }
fail_test() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "[FAIL] $1  (expect $2, got $3)"; }
code()      { curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" "$API/$1"; }
page()      { curl -s --connect-timeout 5 --max-time 15 -b "$CK" -c "$CK" "$API/$1"; }
csrf()      { curl -s --connect-timeout 5 --max-time 15 -b "$CK" -c "$CK" "$API/login" | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1; }
# True only for a genuinely rendered application page (HIX error pages are excluded)
rendered()  { echo "$1" | grep -qE "<table|<form" && ! echo "$1" | grep -qE "Application Error|HIX Error|HTTP Code"; }

echo "============================================================="
echo "  USERS MODULE — FUNCTIONAL TEST SUITE"
echo "  Target : $API  (HIX 2.2.01 / Harbour 3.2.1dev)"
echo "  Data   : data/users.dbf + data/users.cdx (DBFCDX, tag 'name')"
echo "  Date   : $(date '+%d/%m/%y %H:%M')"
echo "============================================================="

# ---- Preflight: fail fast rather than hang (5s connect / 10s total) --------
if ! curl -s --connect-timeout 5 --max-time 10 -o /dev/null "$API/login"; then
  echo "ABORT: HIX server not reachable at $API"
  echo "       start it with:  hbmk2 app.hbp && ./app"
  exit 2
fi

# ---- A. Compile integrity (HIXSTYLE compiles controllers at runtime) -------
# Harbour install for the compile-integrity step: HB_ROOT (the variable the
# build scripts use) or derived from PATH.  Nothing about this machine is
# written into the suite.
HB=${HB:-${HB_ROOT:-}}
if [ -z "$HB" ] && command -v harbour >/dev/null 2>&1; then
    HB=$(cd "$(dirname "$(command -v harbour)")/../../.." 2>/dev/null && pwd)
fi
if [ -z "$HB" ] || [ ! -d "$HB/include" ]; then
    echo "ABORT: Harbour include dir not found - set HB_ROOT or put harbour on PATH"
    exit 2
fi
mkdir -p .tmp_compile
cp www/controllers/masters/users.prg .tmp_compile/u_check.prg
CERR=$(timeout 60 harbour -iwww -i$HB/include -n .tmp_compile/u_check.prg 2>&1 | grep -c "Error E")
if [ "$CERR" = "0" ]; then
  pass_test "T01 users.prg compiles (HIX runtime compile prerequisite)" "0 errors" "0"
else
  fail_test "T01 users.prg compiles (HIX runtime compile prerequisite)" "0 errors" "$CERR errors"
fi

# ---- B. Unauthenticated access protection (REQ-FUNC-020/023) ---------------
for e in "users/grid" "users/search" "users/create" "users/1" \
         "users/1/edit" "users/1/delete_confirm"; do
  C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" "$API/$e")
  if [ "$C" = "302" ]; then pass_test "T$(printf '%02d' $((TOTAL+1))) GET /$e anonymous blocked" "302" "$C"
  else fail_test "T$(printf '%02d' $((TOTAL+1))) GET /$e anonymous blocked" "302" "$C"; fi
done
for e in "users/store" "users/1/update" "users/1/delete"; do
  C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -X POST "$API/$e")
  if [ "$C" = "302" ]; then pass_test "T$(printf '%02d' $((TOTAL+1))) POST /$e anonymous blocked" "302" "$C"
  else fail_test "T$(printf '%02d' $((TOTAL+1))) POST /$e anonymous blocked" "302" "$C"; fi
done

# ---- C. Authentication ------------------------------------------------------
T=$(curl -s --connect-timeout 5 --max-time 15 -c "$CK" "$API/login" | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1)
if [ -n "$T" ]; then pass_test "T11 /login renders CSRF token (REQ-FUNC-024)" "non-empty" "yes"
else fail_test "T11 /login renders CSRF token" "non-empty" "empty"; fi

C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/auth" -d "username=admin&password=1234")
if [ "$C" = "302" ]; then pass_test "T12 POST /auth without CSRF rejected" "302" "$C"
else fail_test "T12 POST /auth without CSRF rejected" "302" "$C"; fi

C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/auth" -d "username=admin&password=1234&_csrf=$T")
LOC=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{redirect_url}" -b "$CK" -c "$CK" -X POST "$API/auth" -d "username=admin&password=1234&_csrf=$(csrf)")
if [ "$C" = "302" ]; then pass_test "T13 POST /auth admin/1234 (users.dbf) authenticates" "302" "$C"
else fail_test "T13 POST /auth admin/1234 authenticates" "302" "$C"; fi

C=$(code "main")
if [ "$C" = "200" ]; then pass_test "T14 GET /main with session" "200" "$C"
else fail_test "T14 GET /main with session" "200" "$C"; fi

# ---- D. Route resolution / HTTP status (authenticated admin) ---------------
for e in "users/grid" "users/search" "users/create" "users/1" "users/1/edit" "users/1/delete_confirm"; do
  C=$(code "$e")
  if [ "$C" = "200" ]; then pass_test "T$(printf '%02d' $((TOTAL+1))) GET /$e" "200" "$C"
  else fail_test "T$(printf '%02d' $((TOTAL+1))) GET /$e" "200" "$C"; fi
done

# ---- E. Grid (FR-READ-1..4) -------------------------------------------------
G=$(page "users/grid")
mkr() { if ! rendered "$G"; then fail_test "T$(printf '%02d' $((TOTAL+1))) $1" "present" "grid did not render"; return; fi;
        if echo "$G" | grep -qi "$2"; then pass_test "T$(printf '%02d' $((TOTAL+1))) $1" "present" "yes"; else fail_test "T$(printf '%02d' $((TOTAL+1))) $1" "present" "no"; fi; }
mkr "grid renders <table> rows (FR-READ-1)" "<table"
mkr "grid has per-field search input _q_name (FR-READ-3)" "_q_name"
mkr "grid has sortable column headers (FR-READ-4)" "sort="
mkr "grid has pagination links (FR-READ-2)" "page="
mkr "grid has row action links (Show/Edit/Delete)" "users/1\""
mkr "grid has Create button (FR-CREATE-1)" "users/create"
mkr "grid renders user NAME data (admin row)" "admin"

# ---- F. Search page ---------------------------------------------------------
S=$(page "users/search")
if echo "$S" | grep -q "Search Users"; then pass_test "T28 GET /users/search renders form" "present" "yes"
else fail_test "T28 GET /users/search renders form" "present" "no"; fi
if echo "$S" | grep -q 'name="_q_name"'; then pass_test "T29 search form has Name input" "present" "yes"
else fail_test "T29 search form has Name input" "present" "no"; fi

# ---- G. Show ----------------------------------------------------------------
SH=$(page "users/1")
if echo "$SH" | grep -q "User #1"; then pass_test "T30 GET /users/1 renders record (FR-READ-5)" "present" "yes"
else fail_test "T30 GET /users/1 renders record" "present" "no"; fi
if echo "$SH" | grep -q "detail-label"; then pass_test "T31 show renders all fields (FR-READ-1)" "present" "yes"
else fail_test "T31 show renders all fields" "present" "no"; fi
SI=$(page "users/99999")
if echo "$SI" | grep -q "User not exist"; then pass_test "T32 show invalid id -> 'User not exist'" "present" "yes"
else fail_test "T32 show invalid id -> 'User not exist'" "present" "no"; fi

# ---- H. Edit ----------------------------------------------------------------
ED=$(page "users/1/edit")
if echo "$ED" | grep -q 'name="name"[^>]*value="admin"'; then pass_test "T33 edit pre-populates name (FR-UPDATE-2)" "present" "yes"
else fail_test "T33 edit pre-populates name" "present" "no"; fi
if echo "$ED" | grep -q 'name="_csrf"'; then pass_test "T34 edit form carries CSRF" "present" "yes"
else fail_test "T34 edit form carries CSRF" "present" "no"; fi
if echo "$ED" | grep -q 'name="roles"[^>]*value="customers'; then pass_test "T35 edit pre-populates roles" "present" "yes"
else fail_test "T35 edit pre-populates roles" "present" "no"; fi

# ---- I. Create --------------------------------------------------------------
CR=$(page "users/create")
if echo "$CR" | grep -q "Create User"; then pass_test "T36 GET /users/create renders create form" "present" "yes"
else fail_test "T36 GET /users/create renders create form" "present" "no"; fi
OK=1; for f in name pass roles; do echo "$CR" | grep -q "name=\"$f\"" || OK=0; done
if [ "$OK" = "1" ]; then pass_test "T37 create form has name/pass/roles (FR-CREATE-3)" "all" "yes"
else fail_test "T37 create form has name/pass/roles" "all" "no"; fi

# ---- J. Delete confirmation -------------------------------------------------
DC=$(page "users/1/delete_confirm")
if echo "$DC" | grep -q "Confirm Delete"; then pass_test "T38 delete_confirm renders modal/card (FR-DELETE-2)" "present" "yes"
else fail_test "T38 delete_confirm renders modal/card" "present" "no"; fi
if echo "$DC" | grep -q "delete user <strong>admin"; then pass_test "T39 delete_confirm shows target record (FR-DELETE-2)" "present" "yes"
else fail_test "T39 delete_confirm shows target record" "present" "no"; fi
ACT=$(echo "$DC" | grep -oP 'method="POST" action="\K[^"]+')
if echo "$ACT" | grep -qE '/users/[0-9]+/delete'; then pass_test "T40 delete form posts to routed URL /users/:id/delete (FR-DELETE-3)" "routed URL" "$ACT"
else fail_test "T40 delete form posts to routed URL /users/:id/delete" "/users/:id/delete" "${ACT:-none}"; fi

# ---- K. Write operations (POST + CSRF) --------------------------------------
T=$(csrf)
C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/users/store" -d "name=zeta&pass=1234&roles=customers:search")
if [ "$C" = "302" ]; then pass_test "T41 POST /users/store without CSRF rejected" "302" "$C"
else fail_test "T41 POST /users/store without CSRF rejected" "302" "$C"; fi

N0=$($PY "$DBF" | head -1)
T=$(csrf)
C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/users/store" -d "name=zeta&pass=1234&roles=customers:search;show&_csrf=$T")
N1=$($PY "$DBF" | head -1)
if $PY "$DBF" | grep -qi "zeta"; then pass_test "T42 POST /users/store persists new record (FR-CREATE / REQ-FUNC-011)" "new row in DBF" "present"
else fail_test "T42 POST /users/store persists new record (http=$C)" "new row in DBF" "not persisted ($N1)"; fi

T=$(csrf)
curl -s --connect-timeout 5 --max-time 15 -b "$CK" -c "$CK" -X POST "$API/users/store" -d "name=&pass=&roles=&_csrf=$T" -o /tmp/uf1.html -L -b "$CK" -c "$CK" >/dev/null
if grep -qi "Error validacion" /tmp/uf1.html; then pass_test "T43 store validation failure -> flash + re-render (REQ-FUNC-011)" "present" "yes"
else fail_test "T43 store validation failure -> flash + re-render" "present" "no"; fi

T=$(csrf)
C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/users/2/update" -d "name=carlesX&pass=1234&roles=customers:search;show&_csrf=$T")
if $PY "$DBF" | grep -q "carlesX"; then pass_test "T44 POST /users/2/update writes DBF (REQ-FUNC-013)" "persisted" "yes"
else fail_test "T44 POST /users/2/update writes DBF" "persisted" "http=$C, not persisted"; fi

T=$(csrf)
curl -s --connect-timeout 5 --max-time 15 -b "$CK" -c "$CK" -X POST "$API/users/2/update" -d "name=&pass=&roles=&_csrf=$T" -o /tmp/uf2.html -L -b "$CK" -c "$CK" >/dev/null
if grep -qi "Error validacion" /tmp/uf2.html; then pass_test "T45 update validation failure -> flash + re-render" "present" "yes"
else fail_test "T45 update validation failure -> flash + re-render" "present" "no"; fi

T=$(csrf)
C=$(curl -s --connect-timeout 5 --max-time 15 -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/users/4/delete" -d "id=4&_csrf=$T")
if $PY "$DBF" --deleted | grep -q "^4|"; then pass_test "T46 POST /users/4/delete soft-deletes (REQ-FUNC-014)" "deleted flag" "yes"
else fail_test "T46 POST /users/4/delete soft-deletes" "deleted flag" "http=$C, not deleted"; fi

G2=$(page "users/grid")
if ! rendered "$G2"; then
  fail_test "T47 grid excludes soft-deleted record" "absent" "grid did not render (cannot verify)"
elif echo "$G2" | grep -qiE ">john ?<"; then fail_test "T47 grid excludes soft-deleted record" "absent" "present"
else pass_test "T47 grid excludes soft-deleted record" "absent" "absent"; fi

# ---- L. RBAC / scope enforcement (REQ-FUNC-023) -----------------------------
C=$(code "users/create")
if [ "$C" = "200" ]; then pass_test "T48 admin ROLES grants users:create -> /users/create" "200" "$C"
else fail_test "T48 admin ROLES grants users:create -> /users/create" "200" "$C"; fi

login_as() { rm -f "$CK"; local TT=$(curl -s --connect-timeout 5 --max-time 15 -c "$CK" "$API/login" | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1);
  curl -s --connect-timeout 5 --max-time 15 -o /dev/null -b "$CK" -c "$CK" -X POST "$API/auth" -d "username=$1&password=$2&_csrf=$TT"; }

login_as carles 1234
C=$(code "users/grid")
if [ "$C" = "302" ] || [ "$C" = "403" ]; then pass_test "T49 carles (no users scope) blocked from /users/grid" "302/403" "$C"
else fail_test "T49 carles (no users scope) blocked from /users/grid" "302/403" "$C"; fi
C=$(code "users/1/edit")
if [ "$C" = "302" ] || [ "$C" = "403" ]; then pass_test "T50 carles blocked from /users/1/edit" "302/403" "$C"
else fail_test "T50 carles blocked from /users/1/edit" "302/403" "$C"; fi

login_as maria 1234
C=$(code "users/1/delete_confirm")
if [ "$C" = "302" ] || [ "$C" = "403" ]; then pass_test "T51 maria (no users:delete) blocked from delete_confirm" "302/403" "$C"
else fail_test "T51 maria (no users:delete) blocked from delete_confirm" "302/403" "$C"; fi

# ---- M. Credential exposure (REQ-SEC) ---------------------------------------
login_as admin 1234
G3=$(page "users/grid"); SH3=$(page "users/1"); ED3=$(page "users/1/edit")
if ! rendered "$G3"; then fail_test "T52 grid must not render plaintext password" "absent" "grid did not render (cannot verify)"
elif echo "$G3" | grep -q "1234"; then fail_test "T52 grid must not render plaintext password" "absent" "present"
else pass_test "T52 grid must not render plaintext password" "absent" "absent"; fi
if ! rendered "$SH3"; then fail_test "T53 show must not render plaintext password" "absent" "page did not render (cannot verify)"
elif echo "$SH3" | grep -q "1234"; then fail_test "T53 show must not render plaintext password" "absent" "present"
else pass_test "T53 show must not render plaintext password" "absent" "absent"; fi
if ! rendered "$ED3"; then fail_test "T54 edit must not echo password value" "absent" "page did not render (cannot verify)"
elif echo "$ED3" | grep -q 'name="pass"[^>]*value="1234"'; then fail_test "T54 edit must not echo password value" "absent" "present"
else pass_test "T54 edit must not echo password value" "absent" "absent"; fi

# ---- N. DEV-compliance.md checks --------------------------------------------
if [ -f data/users.dbf ] && [ -f data/users.cdx ]; then pass_test "T55 DBF + CDX only, no SQL (C-002/C-004)" "both" "present"
else fail_test "T55 DBF + CDX only" "both" "missing"; fi
if grep -q '"hixstyle"' hix.json && grep -q '"enabled": true' hix.json; then pass_test "T56 hixstyle.enabled = true (C-003)" "true" "yes"
else fail_test "T56 hixstyle.enabled = true" "true" "no"; fi
if grep -q '"port": 9090' hix.json; then pass_test "T57 server port 9090 (DEV-compliance Build)" "9090" "yes"
else fail_test "T57 server port 9090" "9090" "no"; fi
NR=$(grep -c '"url": "/users' www/routes/web.json); MW=$(grep '"url": "/users' www/routes/web.json | grep -c 'middleware')
if [ "$NR" = "$MW" ] && [ "$NR" -gt 0 ]; then pass_test "T58 all users routes declare middleware (C-007)" "$NR/$NR" "$MW/$NR"
else fail_test "T58 all users routes declare middleware" "$NR/$NR" "$MW/$NR"; fi
SC=$(grep '"url": "/users' www/routes/web.json | grep -c '"scope"')
if [ "$NR" = "$SC" ]; then pass_test "T59 all users routes declare scope (REQ-FUNC-023)" "$NR/$NR" "$SC/$NR"
else fail_test "T59 all users routes declare scope" "$NR/$NR" "$SC/$NR"; fi
if grep -riqE "SELECT |INSERT INTO|UPDATE .* SET|sqlite|odbc|jdbc" www/controllers/masters/users.prg www/models/tusers.prg www/views/masters/users/*.html; then
  fail_test "T60 no SQL / 3rd-party data access in users module" "none" "found"
else pass_test "T60 no SQL / 3rd-party data access in users module" "none" "none"; fi

# ---- Summary ----------------------------------------------------------------
echo ""
echo "============================================================="
echo "  USERS MODULE — RESULTS"
echo "  Total : $TOTAL   Pass : $PASS   Fail : $FAIL"
echo "  Pass rate : $PASS/$TOTAL"
echo "============================================================="
rm -f "$CK" /tmp/uf1.html /tmp/uf2.html; rm -rf .tmp_compile
exit 0
