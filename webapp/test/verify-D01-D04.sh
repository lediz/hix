#!/usr/bin/env bash
# ------------------------------------------------------------------
# verify-D01-D04.sh — targeted verification of defects D-01..D-04
# (see TEST-RESULTS-USERS-MODULE.md).  Scope: users module only.
#
# Complies with srs/DEV-compliance.md:
#   - lives inside the project folder (test/)
#   - HIX/Harbour only, no SQL, no 3rd-party tooling
#   - target server is the HIX app on port 9090
#
# Every network and compiler call is time-bounded so the suite can
# never hang on a wedged HIX worker or a stalled harbour compile.
# ------------------------------------------------------------------
API="http://localhost:9090"
CK=$(mktemp -u /tmp/vdck.XXXXXX)

# --- timeouts -------------------------------------------------------
CT=5                 # curl connect timeout (s)
MT=15                # curl total transfer timeout (s)
HBC_TIMEOUT=60       # harbour compile timeout (s)
CU="curl -s --connect-timeout $CT --max-time $MT"

PASS=0; FAIL=0
P()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
F()   { echo "  FAIL  $1  [expected $2 / got $3]"; FAIL=$((FAIL+1)); }
chk() { if [ "$2" = "$3" ]; then P "$1"; else F "$1" "$2" "$3"; fi; }

cleanup() { rm -rf "$HBC" "$CK"; }
trap cleanup EXIT

# --- helpers --------------------------------------------------------
code() { $CU -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" "$API/$1"; }
page() { $CU -b "$CK" -c "$CK" "$API/$1"; }
csrf() { $CU -b "$CK" -c "$CK" "$API/login" | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1; }
post() { $CU -o /dev/null -w "%{redirect_url}" -b "$CK" -c "$CK" -X POST "$API/$1" -d "$2"; }

do_login() {                       # do_login <user> <pass>
   rm -f "$CK"
   local T
   T=$(curl -s --connect-timeout "$CT" --max-time "$MT" -c "$CK" "$API/login" \
        | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1)
   $CU -o /dev/null -b "$CK" -c "$CK" -X POST "$API/auth" \
       -d "username=$1&password=$2&_csrf=$T"
}

nrec() { python3 - "$1" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
print(int.from_bytes(d[4:8], 'little'))
PY
}

deleted_flag() { python3 - "$1" "$2" <<'PY'
import sys
d   = open(sys.argv[1], 'rb').read()
n   = int.from_bytes(d[4:8],  'little')
r   = int(sys.argv[2])
start  = int.from_bytes(d[8:10],  'little')   # offset of first record
reclen = int.from_bytes(d[10:12], 'little')   # includes the 1-byte deletion flag
off = start + (r - 1) * reclen
sys.exit(0 if 1 <= r <= n and d[off] == 0x2A else 1)
PY
}

# --- pre-flight: server must answer, otherwise abort immediately ----
if ! $CU -o /dev/null "$API/login"; then
   echo "ABORT: HIX server not reachable at $API (timeout ${CT}s connect / ${MT}s transfer)"
   echo "Start it with:  hbmk2 app.hbp && ./app"
   exit 2
fi

echo "=== D-01  compile integrity (users.prg) ==="
HBC=$(mktemp -d /tmp/vdhb.XXXXXX)
timeout "$HBC_TIMEOUT" harbour -iwww -i"${HB_INCLUDE:-$HOME/harbour/include}" \
       -n -o"$HBC/u" www/controllers/masters/users.prg >"$HBC/out.txt" 2>&1
rc=$?
if [ "$rc" -eq 124 ]; then
   F "D-01a users.prg compiles within ${HBC_TIMEOUT}s" "exit 0" "timeout"
else
   NERR=$(grep -c "Error E[0-9]" "$HBC/out.txt")
   chk "D-01a users.prg compiles with 0 errors" "0" "$NERR"
fi
do_login admin 1234
chk "D-01b GET /users/grid executes (runtime compile OK)" "200" "$(code users/grid)"
chk "D-01c GET /users/1 show executes" "200" "$(code users/1)"
chk "D-01d GET /users/4/delete_confirm executes" "200" "$(code users/4/delete_confirm)"

echo "=== D-04  admin holds users:create (scope reachable) ==="
C=$(code users/create)
if [ "$C" = "403" ]; then F "D-04a admin can reach users.create scope" "not 403" "$C"
else P "D-04a admin can reach users.create scope (HTTP $C)"; fi
do_login maria 1234
chk "D-04b user without users:create is refused" "403" "$(code users/create)"
do_login admin 1234

echo "=== D-03  Store() actually inserts ==="
BEFORE=$(nrec data/users.dbf)
LOC=$(post users/store "name=zverify&pass=abcd&roles=customers:search&_csrf=$(csrf)")
AFTER=$(nrec data/users.dbf)
chk "D-03a POST /users/store persists a new row" "$((BEFORE+1))" "$AFTER"
case "$LOC" in
  *"/users/grid")  P "D-03b store success redirects to users.grid";;
  *)               F "D-03b store success redirect" "/users/grid" "$LOC";;
esac
LOC=$(post users/store "name=&pass=&roles=&_csrf=$(csrf)")
case "$LOC" in
  *"/users/create") P "D-03c store validation failure redirects back to users.create";;
  *)                F "D-03c store validation failure redirect" "/users/create" "$LOC";;
esac
chk "D-03d failed validation did not insert" "$AFTER" "$(nrec data/users.dbf)"
if page "users/$AFTER" | grep -q 'zverify'; then P "D-03e inserted row is readable through users.show"
else F "D-03e inserted row readable" "zverify present" "absent"; fi

echo "=== D-02  delete form posts to a routed URL ==="
N=$(nrec data/users.dbf)                 # last record = the one just created
ACT=$(page "users/$N/delete_confirm" | grep -oP '<form method="POST" action="\K[^"]+' | head -1)
case "$ACT" in
  "/users/$N/delete") P "D-02a delete form action is /users/$N/delete (matches route)";;
  *)                  F "D-02a delete form action matches users.delete route" "/users/$N/delete" "$ACT";;
esac
LOC=$(post "users/$N/delete" "id=$N&_csrf=$(csrf)")
case "$LOC" in
  *"/users/grid") P "D-02b POST /users/$N/delete is routed and handled (302 -> grid)";;
  *)              F "D-02b delete POST handled" "/users/grid" "$LOC";;
esac
if deleted_flag data/users.dbf "$N"; then P "D-02c record $N soft-deleted ('*' flag set)"
else F "D-02c soft-delete flag" "'*' set" "not set"; fi

echo
echo "D-01..D-04 verification: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
