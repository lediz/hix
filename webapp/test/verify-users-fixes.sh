#!/usr/bin/env bash
# ------------------------------------------------------------------
# verify-users-fixes.sh — regression verification for the users module
#
# Covers every defect closed in the users module:
#   D-01 compile integrity          D-08 column sort no-op
#   D-02 unrouted delete form       D-09 NAME uniqueness
#   D-03 Store() never inserted     D-10 sticky flash
#   D-04 users:create scope         D-11 dbcloseall() in Destroy()
#   D-05 credentials in the UI      D-12 middleware/scope inconsistency
#   D-06 search probing secrets     D-13 bare oVal:Get()
#   D-07 plaintext passwords        D-14 orphan data/ artifacts
#   D-15 view hash-subscript 500s   D-16 login case handling / RDD ==
#   N-01 CSRF token on every users write form (browser path)
#   C-009 TLS enabled, plaintext HTTP refused
#   SEC  signing keys and password salts generated, never committed
#
# Complies with srs/DEV-compliance.md: lives inside the project folder,
# HIX/Harbour only, no SQL, no 3rd-party tooling, server on port 9090.
#
# Every network and compiler call is time-bounded so the suite can never
# hang on a wedged HIX worker or a stalled Harbour compile.
#
# Idempotency (F-1): the row this suite creates is named zverify<epoch>, so it
# can never collide with a leftover test row from an earlier run.  NameExists()
# deliberately counts soft-deleted names, so a fixed name such as 'zverify'
# would be refused on the second run and D-03a/D-03b would fail.  Run
# `hbmk2 regenerate_users.hbp && ./regenerate_users` (server stopped) to reset
# data/users.dbf to the five seed users.
#
# Login budget: /auth is rate-limited per IP.  The limit is config-driven
# (www/middlewares/config.json -> setup.ratelimit.login_max / login_window,
# default 5 / 60 s).  The suite reads those values and every login waits for a
# free slot instead of failing, so it runs at any configured limit - it is just
# slower at a tighter one.  The deliberate rate-limit probe is at the very end.
# ------------------------------------------------------------------
API="${VERIFY_API:-https://localhost:9090}"
CK=$(mktemp -u /tmp/vdck.XXXXXX)

# Unique per run: see "Idempotency" above.
TESTNAME="zverify$(date +%s)"

# Effective /auth rate limit (kept in sync with www/middlewares/myapplogin.prg)
LOGIN_MAX=$(python3 -c "import json;print(json.load(open('www/middlewares/config.json'))['setup']['ratelimit'].get('login_max',5))")
LOGIN_WINDOW=$(python3 -c "import json;print(json.load(open('www/middlewares/config.json'))['setup']['ratelimit'].get('login_window',60))")

# --- timeouts -------------------------------------------------------
CT=5                 # curl connect timeout (s)
MT=15                # curl total transfer timeout (s)
HBC_TIMEOUT=60       # Harbour compile timeout (s)
# -k: the dev certificate is self-signed (./gen_cert.sh).  It is harmless over
# plain http, so it is always passed rather than branched on the scheme.
CU="curl -s -k --connect-timeout $CT --max-time $MT"

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

auth_post() {                      # auth_post <user> <pass> -> HTTP code of POST /auth
   rm -f "$CK"
   local T
   T=$(curl -s -k --connect-timeout "$CT" --max-time "$MT" -c "$CK" "$API/login" \
        | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1)
   $CU -o /dev/null -w "%{http_code}" -b "$CK" -c "$CK" -X POST "$API/auth" \
       -d "username=$1&password=$2&_csrf=$T"
}

do_login() {                       # do_login <user> <pass>
   # /auth is rate-limited per IP.  A previous run (or the rate-limit probe at
   # the end of this suite) can leave the window exhausted, which would make
   # every authenticated check fail with 302.  Wait for a free slot instead of
   # failing, so the suite is correct at any configured login_max.
   # HIX's limiter is a weighted sliding window: after a burst it needs roughly
   # two quiet windows before the previous window's weight drops out, hence the
   # 2*window pause rather than a single one.
   local n C
   for n in 1 2 3; do
      C=$(auth_post "$1" "$2")
      if [ "$C" != "429" ]; then return 0; fi
      echo "  ... /auth rate-limit window busy ($LOGIN_MAX/$LOGIN_WINDOW s), waiting $((LOGIN_WINDOW*2+5))s (attempt $n)" >&2
      sleep $((LOGIN_WINDOW*2+5))
   done
   return 1
}

logged_in() {                      # logged_in <user> <pass> -> HTTP code of /main
   # 429 is reported as 429, not folded into the expected 302: a blocked
   # attempt must never look like a correctly rejected credential.
   if ! do_login "$1" "$2"; then echo 429; return; fi
   code main
}

login_admin() {
   do_login admin 1234
}

# Token as rendered inside a given page's own <form> (browser path, N-01)
form_csrf() {                      # form_csrf <path> -> first _csrf value rendered by that page
   page "$1" | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1
}

# DBF introspection (pure python stdlib, no external tooling)
dbf() { python3 - "$@" <<'PY'
import sys
d = open('data/users.dbf', 'rb').read()
n      = int.from_bytes(d[4:8],   'little')
start  = int.from_bytes(d[8:10],  'little')
reclen = int.from_bytes(d[10:12], 'little')
mode   = sys.argv[1]
if mode == 'count':
    print(n); sys.exit(0)
if mode == 'flag':
    r = int(sys.argv[2]); off = start + (r-1)*reclen
    sys.exit(0 if 1 <= r <= n and d[off] == 0x2A else 1)
if mode == 'row':
    r = int(sys.argv[2]); rec = d[start+(r-1)*reclen+1 : start+(r-1)*reclen+reclen]
    print(rec[0:10].decode().strip()); print(rec[10:50].decode().strip())
    print(rec[50:178].decode().strip()); print(rec[178:210].decode().strip())
    sys.exit(0)
if mode == 'schema':
    nf = (start - 32 - 1) // 32
    for f in range(nf):
        o = 32 + f*32
        print(d[o:o+11].rstrip(b'\x00').decode(), chr(d[o+11]), d[o+16], d[o+17])
    sys.exit(0)
if mode == 'col':
    name = sys.argv[2].upper()
    nf = (start - 32 - 1) // 32
    for f in range(nf):
        o = 32 + f*32
        if d[o:o+11].rstrip(b'\x00').decode().upper() == name:
            print('%s %d' % (chr(d[o+11]), d[o+16])); sys.exit(0)
    print('missing'); sys.exit(0)
if mode == 'plaintext':
    # any of the seed passwords present verbatim in the file?
    for pw in sys.argv[2:]:
        if pw.encode() in d:
            print(pw); sys.exit(0)
    print(''); sys.exit(0)
if mode == 'digest':
    r = int(sys.argv[2]); rec = d[start+(r-1)*reclen+1 : start+(r-1)*reclen+reclen]
    print(rec[50:178].decode().strip()); sys.exit(0)
PY
}

# --- pre-flight: server must answer, otherwise abort immediately ----
if ! $CU -o /dev/null "$API/login"; then
   echo "ABORT: HIX server not reachable at $API (timeout ${CT}s connect / ${MT}s transfer)"
   echo "Start it with:  ./gen_cert.sh && hbmk2 app.hbp && ./app"
   exit 2
fi

ERR_BEFORE=$(grep -c "Bound error" .logs/errors.log 2>/dev/null || echo 0)

# ==================================================================
echo "=== D-01  compile integrity (users.prg) ==="
HBC=$(mktemp -d /tmp/vdhb.XXXXXX)
timeout "$HBC_TIMEOUT" harbour -iwww -i"${HB_INCLUDE:-$HOME/harbour/include}" \
       -n -o"$HBC/u" www/controllers/masters/users.prg >"$HBC/out.txt" 2>&1
if [ "$?" -eq 124 ]; then
   F "D-01a users.prg compiles within ${HBC_TIMEOUT}s" "exit 0" "timeout"
else
   chk "D-01a users.prg compiles with 0 errors" "0" "$(grep -c 'Error E[0-9]' "$HBC/out.txt")"
fi
login_admin
for R in users/grid users/1 users/4/delete_confirm; do
   chk "D-01b GET /$R executes" "200" "$(code $R)"
done

# ==================================================================
echo "=== D-04  admin holds users:create (scope reachable) ==="
C=$(code users/create)
if [ "$C" = "403" ]; then F "D-04a admin can reach users.create scope" "not 403" "$C"
else P "D-04a admin can reach users.create scope (HTTP $C)"; fi

# ==================================================================
echo "=== D-03  Store() actually inserts (and assigns an ID) ==="
BEFORE=$(dbf count)
LEFT=$(python3 -c "
d=open('data/users.dbf','rb').read()
n=int.from_bytes(d[4:8],'little'); s=int.from_bytes(d[8:10],'little'); l=int.from_bytes(d[10:12],'little')
print(sum(1 for r in range(1,n+1) if d[s+(r-1)*l+11:s+(r-1)*l+51].decode().strip().startswith('zverify')))")
if [ "$LEFT" -gt 0 ]; then
   echo "  note: $LEFT leftover zverify* row(s) in users.dbf - harmless (the test name is unique),"
   echo "        run 'hbmk2 regenerate_users.hbp && ./regenerate_users' with the server stopped to reset the seed data"
fi
LOC=$(post users/store "name=$TESTNAME&pass=abcd&roles=customers:search&_csrf=$(csrf)")
AFTER=$(dbf count)
chk "D-03a POST /users/store persists a new row" "$((BEFORE+1))" "$AFTER"
case "$LOC" in
  *"/users/grid") P "D-03b store success redirects to users.grid";;
  *)              F "D-03b store success redirect" "/users/grid" "$LOC";;
esac
LOC=$(post users/store "name=&pass=&roles=&_csrf=$(csrf)")
case "$LOC" in
  *"/users/create") P "D-03c store validation failure redirects back to users.create";;
  *)                F "D-03c store validation failure redirect" "/users/create" "$LOC";;
esac
chk "D-03d failed validation did not insert" "$AFTER" "$(dbf count)"
if page "users/$AFTER" | grep -q "$TESTNAME"; then P "D-03e inserted row is readable through users.show"
else F "D-03e inserted row readable" "$TESTNAME present" "absent"; fi
NEWID=$(dbf row "$AFTER" | sed -n 1p)
if [ "$NEWID" != "0" ] && [ -n "$NEWID" ]; then P "D-03f new record gets an ID (ID=$NEWID, was 0)"
else F "D-03f new record gets an ID" "non-zero ID" "${NEWID:-empty}"; fi

# ==================================================================
echo "=== N-01  every users write form carries a CSRF token (browser path) ==="
# The 09:22 suite harvested the token from GET /login and posted it by hand, so
# it passed even though no form ever rendered one.  These checks use the token
# the form itself renders, which is what a browser actually sends.
for V in users/create users/1/edit users/1/delete_confirm; do
   chk "N-01a GET /$V renders a _csrf input" "1" "$(page "$V" | grep -c 'name="_csrf"')"
done
for V in customer/create customer/1/edit customer/1/delete_confirm; do
   chk "N-01b GET /$V still renders a _csrf input (customer parity)" "1" "$(page "$V" | grep -c 'name="_csrf"')"
done
# The grid delete forms are built in JS: '@CSRF' inside a JS string literal is
# not a directive, so the token must be injected server-side instead.
chk "N-01c users grid injects a server-side token for its JS form" "1" "$(page users/grid | grep -c 'data-csrf=')"
chk "N-01d customer grid injects a server-side token for its JS form" "1" "$(page customer/grid | grep -c 'data-csrf=')"
chk "N-01e no unexpanded '@CSRF' left inside a JS string in any view" "0" "$(grep -rF "'@CSRF'" www/views/ | wc -l)"
# Accept the token the form rendered (the row created by D-03 is the subject).
FT=$(form_csrf "users/$AFTER/edit")
if [ -n "$FT" ]; then P "N-01f edit form of the new row exposes a token (${#FT} chars)"
else F "N-01f edit form exposes a token" "token present" "empty"; fi
LOC=$(post "users/$AFTER/update" "name=$TESTNAME&pass=&roles=customers:search&_csrf=$FT")
case "$LOC" in
  *"/users/$AFTER") P "N-01g POST /users/$AFTER/update with the form's own token is accepted";;
  *)                F "N-01g update with the form's own token accepted" "/users/$AFTER" "$LOC";;
esac
LOC=$(post "users/$AFTER/update" "name=$TESTNAME&pass=&roles=customers:search")
case "$LOC" in
  *"/login") P "N-01h the same POST with no token is still rejected (302 -> /login)";;
  *)         F "N-01h tokenless update rejected" "/login" "$LOC";;
esac

# ==================================================================
echo "=== D-02  delete form posts to a routed URL ==="
N=$(dbf count)
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
if dbf flag "$N"; then P "D-02c record $N soft-deleted ('*' flag set)"
else F "D-02c soft-delete flag" "'*' set" "not set"; fi
if ! page users/grid | grep -q "$TESTNAME"; then P "D-02d soft-deleted record is not listed in the grid"
else F "D-02d soft-deleted record hidden" "absent from grid" "still listed"; fi

# ==================================================================
echo "=== D-15  views render (raw hash subscript removed) ==="
chk "D-15a no raw hMessage[]/hErrors[] subscript left in users views" "0" \
    "$(grep -l "hMessage\[ '\|hErrors\[ '" www/views/masters/users/*.html 2>/dev/null | wc -l)"
for R in users/grid users/search users/create users/1 users/1/edit users/1/delete_confirm; do
   chk "D-15b GET /$R renders" "200" "$(code $R)"
done
chk "D-15c non-existent record still renders (not-found path)" "200" "$(code users/999)"

post users/1/update "name=&pass=&roles=&_csrf=$(csrf)" >/dev/null
ED=$(page users/1/edit)
chk "D-15d edit re-render after failed update" "200" "$(code users/1/edit)"
chk "D-15e edit re-render marks the 2 required invalid fields" "2" "$(echo "$ED" | grep -c 'is-invalid')"
if echo "$ED" | grep -q 'is-invalid' && echo "$ED" | grep -q 'The field name is required'; then
   P "D-15f edit re-render shows field error messages"
else F "D-15f edit re-render shows field error messages" "messages present" "absent"; fi
post users/store "name=&pass=&roles=&_csrf=$(csrf)" >/dev/null
CR=$(page users/create)
if echo "$CR" | grep -q 'is-invalid' && echo "$CR" | grep -q 'The field roles is required'; then
   P "D-15g create re-render shows field error messages"
else F "D-15g create re-render shows field error messages" "messages present" "absent"; fi

# ==================================================================
echo "=== D-05  credentials never reach the UI or the session ==="
chk "D-05a grid view has no 'pass' reference" "0" "$(grep -c "'pass'" www/views/masters/users/grid.html)"
chk "D-05b show view has no 'pass' reference" "0" "$(grep -c "'pass'" www/views/masters/users/show.html)"
chk "D-05c ModelUser does not put the credential in the session hash" "0" \
    "$(grep -c 'hEntry\[ "pass" \]' www/models/modeluser.prg)"
chk "D-05d DAL hides PASS and SALT from Row()" "1" \
    "$(grep -c "Hide( { 'pass', 'salt' } )" www/models/tusers.prg)"
G=$(page users/grid); S=$(page users/1); E=$(page users/1/edit)
chk "D-05e rendered grid contains no 'Password' column" "0" "$(echo "$G" | grep -ci 'password')"
chk "D-05f rendered show page contains no 'Password' row" "0" "$(echo "$S" | grep -ci 'password')"
# N-01 made every write form carry an HMAC token whose signature half is itself 64
# hex chars, so the tokens are stripped before looking for a stored credential.
chk "D-05g no 64-hex digest is rendered anywhere" "0" \
    "$(echo "$G$S$E" | sed -E 's/<input[^>]*_csrf[^>]*>//g; s/data-csrf="[^"]*"//g' | grep -oE '[0-9a-f]{64}' | wc -l)"
chk "D-05h edit password input is type=password" "1" "$(echo "$E" | grep -c 'name="pass"[^>]*type="password"\|type="password"[^>]*name="pass"')"
chk "D-05i edit password input is never pre-filled" "1" "$(echo "$E" | grep -c 'name="pass"[^>]*value=""')"

# ==================================================================
echo "=== D-06  free-text search is restricted to an allow-list ==="
chk "D-06a controller search block never touches 'pass' or 'salt'" "0" \
    "$(grep -cE "aGrid\[ nI \], '(pass|salt)'" www/controllers/masters/users.prg)"
DIG=$(dbf digest 1)
FRAG=${DIG:0:10}
if [ -z "$FRAG" ]; then
   F "D-06 precondition: could not read a stored digest" "64-hex digest" "empty"
fi
if page "users/grid?q=$FRAG" | grep -q 'title="Show"'; then
   F "D-06b searching by a digest fragment matches a row" "no match" "matched"
else P "D-06b searching by digest fragment '$FRAG' matches nothing"; fi
if page "users/grid?q=1234" | grep -q 'title="Show"'; then
   F "D-06c searching by a former plaintext password matches a row" "no match" "matched"
else P "D-06c searching by '1234' matches nothing"; fi

# ==================================================================
echo "=== D-07  passwords stored as salted iterated SHA-256 ==="
chk "D-07a users.dbf contains no plaintext seed password" "" \
    "$(dbf plaintext 1234 5678 9012abcd)"
chk "D-07b PASS column widened to C(128)" "C 128" "$(dbf col PASS)"
chk "D-07c SALT column present" "C 32" "$(dbf col SALT)"
chk "D-07d stored PASS is a 64-hex digest" "1" "$(dbf digest 1 | grep -cE '^[0-9a-f]{64}$')"
chk "D-07e stored SALT is 32-hex" "1" "$(dbf row 1 | sed -n 4p | grep -cE '^[0-9a-f]{32}$')"
chk "D-07f hashing helper uses >=10000 rounds" "1" \
    "$(python3 -c "
import re
m=re.search(r'#DEFINE\\s+PW_HASH_ITERATIONS\\s+(\\d+)', open('www/models/hpassword.prg').read())
print(1 if m and int(m.group(1))>=10000 else 0)")"
# The stored digest must be reproducible with the iteration count the code
# declares - it proves the DBF was seeded with the same work factor the server
# uses at login (a stale seed after raising PW_HASH_ITERATIONS fails here).
chk "D-07g stored digest round-trips at the declared iteration count" "1" \
    "$(python3 -c "
import re, hashlib
d=open('data/users.dbf','rb').read()
s=int.from_bytes(d[8:10],'little'); l=int.from_bytes(d[10:12],'little')
rec=d[s+1:s+l]
pw='1234'
n=int(re.search(r'#DEFINE\\s+PW_HASH_ITERATIONS\\s+(\\d+)', open('www/models/hpassword.prg').read()).group(1))
salt=rec[178:210].decode().strip()
h=hashlib.sha256((salt+pw).encode()).hexdigest()
for _ in range(n): h=hashlib.sha256((salt+h).encode()).hexdigest()
print(1 if h==rec[50:178].decode().strip() else 0)")"

# ==================================================================
echo "=== D-08  column sorting actually sorts ==="
ASC=$(page "users/grid?sort=roles&dir=ASC" | grep -oP '<td>\K[^<]+(?=</td>)' | head -1)
DESC=$(page "users/grid?sort=roles&dir=DESC" | grep -oP '<td>\K[^<]+(?=</td>)' | head -1)
if [ -n "$ASC" ] && [ -n "$DESC" ] && [ "$ASC" != "$DESC" ]; then
   P "D-08a sort=roles ASC ('$ASC') differs from DESC ('$DESC')"
else F "D-08a sort=roles changes the row order" "different first row" "'$ASC' vs '$DESC'"; fi
chk "D-08b sort key is lower-cased to match the grid hash keys" "1" \
    "$(grep -c "cSort    := Lower( UGet( 'sort', 'name' ) )" www/controllers/masters/users.prg)"
chk "D-08c sort column is restricted to an allow-list" "1" \
    "$(grep -c "Ascan( aSortOk, cSort )" www/controllers/masters/users.prg)"

# ==================================================================
echo "=== D-09  NAME uniqueness ==="
BEFORE=$(dbf count)
LOC=$(post users/store "name=ADMIN&pass=abcd&roles=customers:search&_csrf=$(csrf)")
case "$LOC" in
  *"/users/create") P "D-09a duplicate name (case-insensitive) is refused";;
  *)                F "D-09a duplicate name refused" "/users/create" "$LOC";;
esac
chk "D-09b duplicate create inserted nothing" "$BEFORE" "$(dbf count)"
if page users/create | grep -qi 'already in use'; then P "D-09c duplicate create reports the collision"
else F "D-09c duplicate create reports the collision" "'already in use'" "absent"; fi
LOC=$(post users/2/update "name=admin&pass=&roles=customers:search&_csrf=$(csrf)")
case "$LOC" in
  *"/users/2/edit") P "D-09d rename to an existing name is refused";;
  *)                F "D-09d rename to an existing name refused" "/users/2/edit" "$LOC";;
esac
if page users/2/edit | grep -qi 'already in use'; then P "D-09e rename collision reported on the edit form"
else F "D-09e rename collision reported" "'already in use'" "absent"; fi
chk "D-09f rejected rename left record 2 unchanged" "carles" "$(dbf row 2 | sed -n 2p)"

# ==================================================================
echo "=== D-10  flash is drained after being consumed ==="
post users/1/update "name=&pass=&roles=&_csrf=$(csrf)" >/dev/null
if page users/1/edit | grep -q 'is-invalid'; then P "D-10a validation flash is shown once"
else F "D-10a validation flash is shown" "is-invalid present" "absent"; fi
if page users/3/edit | grep -q 'is-invalid'; then F "D-10b flash does not leak into a later edit" "clean form" "stale errors"
else P "D-10b flash does not leak into a later edit"; fi
if page users/grid | grep -q 'Error validacion'; then F "D-10c flash does not leak into the grid" "clean grid" "stale message"
else P "D-10c flash does not leak into the grid"; fi

# ==================================================================
echo "=== D-11 / D-13 / D-12 / D-14  hygiene ==="
chk "D-11a users.prg no longer calls dbcloseall()" "0" "$(grep -cE '^[[:space:]]*dbcloseall' www/controllers/masters/users.prg)"
chk "D-11b Destroy() closes only the module's own DAL instance" "1" "$(grep -c '::oUsers:Close()' www/controllers/masters/users.prg)"
chk "D-13a no bare oVal:Get() calls remain" "0" "$(grep -c "oVal:Get()" www/controllers/masters/users.prg)"
chk "D-12a users.create GET uses MyAppAuthRoleEdit" "1" \
    "$(python3 -c "
import json
r=json.load(open('www/routes/web.json'))
print(1 if [x for x in r if x['name']=='users.create'][0]['middleware']=='MyAppAuthRoleEdit' else 0)")"
chk "D-12b users.edit GET uses MyAppAuthRoleEdit" "1" \
    "$(python3 -c "
import json
r=json.load(open('www/routes/web.json'))
print(1 if [x for x in r if x['name']=='users.edit'][0]['middleware']=='MyAppAuthRoleEdit' else 0)")"
chk "D-12c create form still renders through MyAppAuthRoleEdit" "200" "$(code users/create)"
chk "D-14a no orphan artifacts left in data/" "0" \
    "$(ls data/ | grep -cE '\.bak$|\.prettest$|\.ntx$|\.cdb$|\.dbt$|^test_copy|^users_new|check_tag')"

# ==================================================================
echo "=== D-16  login is case-insensitive, exact, and digest-based ==="
# D-16 needs six /auth attempts.  Wait for a clean rate-limit window so the
# block is deterministic regardless of what earlier stages consumed.
echo "  (waiting $((LOGIN_WINDOW+5))s for a fresh /auth rate-limit window)"
sleep $((LOGIN_WINDOW+5))
if grep -q "INDEX ON Lower( field->name ) TAG name" regenerate_users.prg; then
   P "D-16a 'name' CDX tag is keyed on Lower(name)"
else F "D-16a 'name' CDX tag is keyed on Lower(name)" "Lower( field->name )" "raw field->name"; fi
do_login maria 1234
chk "D-04b user without users:create is refused (maria)" "403" "$(code users/create)"
chk "D-16b partial name not accepted (carle)" "302" "$(logged_in carle 1234)"
chk "D-16c wrong password rejected"            "302" "$(logged_in admin 0000)"
chk "D-16d mixed-case seed name logs in as JOHN" "200" "$(logged_in JOHN 5678)"
chk "D-16e password prefix '9012' rejected"       "302" "$(logged_in jane 9012)"
chk "D-16f full password '9012abcd' accepted"     "200" "$(logged_in jane 9012abcd)"

# ==================================================================
echo "=== D-07b  /auth is rate-limited ==="
# Deliberate: this is the stage that consumes the window, so it runs last.
# Expect the block to appear no later than the configured login_max.
BLOCKED=""
for i in $(seq 1 $((LOGIN_MAX+5))); do
   rm -f "$CK"
   T=$(curl -s -k --connect-timeout "$CT" --max-time "$MT" -c "$CK" "$API/login" \
        | grep -oP 'name="_csrf"[^>]*value="\K[^"]+' | head -1)
   C=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout "$CT" --max-time "$MT" \
        -b "$CK" -c "$CK" -X POST "$API/auth" -d "username=admin&password=0000&_csrf=$T")
   if [ "$C" = "429" ]; then BLOCKED="$i"; break; fi
done
if [ -n "$BLOCKED" ]; then P "D-07c /auth returns 429 after repeated attempts (attempt $BLOCKED of limit $LOGIN_MAX/$LOGIN_WINDOW s)"
else F "D-07c /auth rate limiting" "429 within $((LOGIN_MAX+5)) attempts" "never blocked"; fi

# ==================================================================
# The last two groups cover what the status review left as open risks:
# no TLS, non-CSPRNG salts, and signing keys committed to the repository.
# ==================================================================
echo "=== C-009  TLS ==="
case "$API" in
  https://*) P "C-009a suite reaches the app over https";;
  *)         F "C-009a suite reaches the app over https" "https://..." "$API";;
esac
TLSLINE=$($CU -sv -o /dev/null "$API/login" 2>&1 | grep -oE 'SSL connection using [^ |]+' | head -1)
if [ -n "$TLSLINE" ]; then P "C-009b TLS handshake negotiated ($TLSLINE)"
else F "C-009b TLS handshake" "SSL connection using ..." "none reported"; fi
if curl -s --connect-timeout "$CT" --max-time "$MT" -o /dev/null "http://localhost:9090/login"; then
   F "C-009c plain HTTP is refused" "no plaintext answer" "answered over http"
else P "C-009c plain HTTP is refused (the server speaks TLS only)"; fi

# ==================================================================
echo "=== SEC  signing keys and salts are generated, not committed ==="
git check-ignore -q www/config.json
chk "SEC-01a www/config.json is gitignored (it holds this install's keys)" "0" "$?"
chk "SEC-01b the committed template carries no keys section" "0" "$(grep -c '"keys"' www/config.json.example)"
chk "SEC-01c no signing-key literal left in src/app.prg" "0" "$(grep -cE '"[0-9a-f]{32,}"' src/app.prg)"
chk "SEC-01d app.prg installs the keys before the server starts" "1" "$(grep -c '_AppKeysEnsure( HIX_APP_CONFIG )' src/app.prg)"
chk "SEC-01e www/config.json carries a key set after a server run" "5" "$(python3 -c "
import json
print(len(json.load(open('www/config.json')).get('keys',{})))")"
chk "SEC-01f every key is >=32 chars and not a published HIX default" "5" "$(python3 -c "
import json
k=json.load(open('www/config.json'))['keys']
print(sum(1 for v in k.values() if isinstance(v,str) and len(v)>=32 and 'H!x@' not in v))")"
chk "SEC-02a salt comes from the Harbour core CSPRNG (hb_RandStr)" "1" "$(grep -c 'hb_RandStr( 32 )' www/models/hpassword.prg)"
chk "SEC-02b no name/time/record-count salt derivation left behind" "0" "$(grep -cE 'hb_NTOS\( Seconds|hb_NTOS\( RecCount|hb_TToS\( hb_DateTime' www/models/hpassword.prg)"
NSEC=$(dbf count)
chk "SEC-02c every stored salt is 32-hex" "$NSEC" "$(python3 -c "
import re
d=open('data/users.dbf','rb').read()
n=int.from_bytes(d[4:8],'little'); s=int.from_bytes(d[8:10],'little'); l=int.from_bytes(d[10:12],'little')
print(sum(1 for r in range(1,n+1) if re.fullmatch(r'[0-9a-f]{32}', d[s+(r-1)*l+179:s+(r-1)*l+211].decode().strip())))")"
chk "SEC-02d every stored salt is distinct" "$NSEC" "$(python3 -c "
d=open('data/users.dbf','rb').read()
n=int.from_bytes(d[4:8],'little'); s=int.from_bytes(d[8:10],'little'); l=int.from_bytes(d[10:12],'little')
print(len(set(d[s+(r-1)*l+179:s+(r-1)*l+211].decode().strip() for r in range(1,n+1))))")"

# ==================================================================
ERR_AFTER=$(grep -c "Bound error" .logs/errors.log 2>/dev/null || echo 0)
chk "D-15h no new 'Bound error' logged during the run" "$ERR_BEFORE" "$ERR_AFTER"

echo
echo "users module regression (D-01..D-16 + N-01 + C-009 + SEC): PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
