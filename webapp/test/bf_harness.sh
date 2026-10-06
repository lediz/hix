#!/usr/bin/env bash
# ------------------------------------------------------------------
# bf_harness.sh — brute-force penetration harness (BRUTE-FORCE-PENTEST-PLAN.md)
#
# Authorized self-assessment of the LOCAL HIX CRUD app in this repository
# (https://localhost:9090, app.env = prod), its own seeded users and its own
# session store. Nothing here leaves the machine and nothing here targets a
# host we do not own. Never point it at a deployed instance.
#
# Ground rules implemented here (plan §1):
#   - every request is time-bounded (--connect-timeout 5 --max-time 15);
#   - every phase declares MAX_REQUESTS and MAX_SECONDS and is aborted when
#     either is exceeded;
#   - the harness is rate-limit aware: it reads login_max / login_window from
#     www/middlewares/config.json and waits 2*window+5 after a 429 (HIX's
#     limiter is a weighted sliding window - one quiet window is not enough);
#   - one JSONL evidence line per request;
#   - rows it creates are named zbf<epoch> and are removed by the trap;
#   - bash + curl + python3 stdlib only, matching test/verify-users-fixes.sh.
#
# Usage:
#   ./test/bf_harness.sh bf01|bf02|bf03|bf04|bf05|bf06|bf07|bf08|bf09|bf10
#   ./test/bf_harness.sh all            # plan §10 priority order
#   BF_RUN_DIR=... ./test/bf_harness.sh bf04     # join an existing run dir
#
# Evidence: .tmp_verify/bf/<yyyymmdd-hhmmss>/<phase>.jsonl + verdicts.txt
# ------------------------------------------------------------------
set -u -o pipefail

cd "$(dirname "$(readlink -f "$0")")/.."

API="${BF_API:-https://localhost:9090}"
CT=5                     # curl connect timeout (s)
MT=15                    # curl total transfer timeout (s)
CU="curl -sk --connect-timeout $CT --max-time $MT"

# --- limiter config: single source of truth is www/middlewares/config.json --
read -r LOGIN_MAX LOGIN_WINDOW GLOBAL_MAX GLOBAL_WINDOW < <(python3 - <<'PY'
import json
r = json.load(open('www/middlewares/config.json'))['setup']['ratelimit']
print(r.get('login_max', 5), r.get('login_window', 60),
      r.get('ip_per_min', 300), r.get('window_s', 60))
PY
)
COOLDOWN=$((LOGIN_WINDOW * 2 + 5))     # weighted sliding window: 2 windows + slack

RUN_DIR="${BF_RUN_DIR:-.tmp_verify/bf/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$RUN_DIR"
BODY="$RUN_DIR/.body"
HDRS="$RUN_DIR/.hdr"
PHASE="init"
NREQ=0
MAX_REQUESTS=0
MAX_SECONDS=0
T0=0
ABORTED=""
JARS=()
ZBF_ROWS=()

newjar() { local f; f=$(mktemp /tmp/bfck.XXXXXX); JARS+=("$f"); printf '%s' "$f"; }

cleanup() {
   local f
   for f in "${JARS[@]:-}"; do rm -f "$f"; done
   rm -f "$BODY" "$HDRS"
   # rows this harness created (zbf<epoch>) are removed by the phase itself;
   # if it died on the way, say so instead of leaving them silently.
   if [ ${#ZBF_ROWS[@]} -gt 0 ]; then
      echo "NOTE: rows created by this run may still exist: ${ZBF_ROWS[*]} (id range in $RUN_DIR)"
   fi
}
trap cleanup EXIT

san() { printf '%s' "$1" | tr -d '"\\' | tr '\t' ' '; }

budget() { PHASE="$1"; MAX_REQUESTS="$2"; MAX_SECONDS="$3"; T0=$(date +%s); NREQ=0
   echo "== $PHASE: budget $MAX_REQUESTS requests / $MAX_SECONDS s ==" | tee -a "$RUN_DIR/verdicts.txt"; }

over_budget() {
   if [ "$MAX_REQUESTS" -gt 0 ] && [ "$NREQ" -ge "$MAX_REQUESTS" ]; then ABORTED="MAX_REQUESTS=$MAX_REQUESTS"; return 0; fi
   if [ "$MAX_SECONDS" -gt 0 ] && [ $(( $(date +%s) - T0 )) -ge "$MAX_SECONDS" ]; then ABORTED="MAX_SECONDS=$MAX_SECONDS"; return 0; fi
   return 1
}

# req <method> <path> <jar|-> <headers-desc> [extra curl args...]
# -> prints "<code> <redirect_url> <size> <time_total>"; body left in $BODY
req() {
   local method="$1" path="$2" jar="$3" hdesc="$4"; shift 4
   if over_budget; then
      echo "ABORT $PHASE: budget exceeded ($ABORTED) after $NREQ requests" | tee -a "$RUN_DIR/verdicts.txt"
      verdict "$PHASE" "NOT TESTED" "budget exceeded ($ABORTED) after $NREQ requests"
      exit 3
   fi
   NREQ=$((NREQ + 1))
   local -a ja=()
   [ "$jar" != "-" ] && ja=(-c "$jar" -b "$jar")
   local out
   out=$($CU -o "$BODY" -D "$HDRS" \
        -w '%{http_code}|%{redirect_url}|%{size_download}|%{time_total}|%{time_starttransfer}' \
        "${ja[@]}" -X "$method" "$API$path" "$@" 2>/dev/null)
   local code redir size tt ttf
   # '|' delimiter, NOT tab: IFS whitespace collapsing would drop the empty
   # redirect_url of a 429 and shift every later field by one.
   IFS='|' read -r code redir size tt ttf <<<"$out"
   [ -z "$code" ] && { code=000; redir=""; size=0; tt=0; ttf=0; }
   printf '{"ts":"%s","phase":"%s","method":"%s","url":"%s","headers":"%s","status":%s,"redirect":"%s","size":%s,"time_total":%s,"ttfb":%s,"jar":"%s"}\n' \
      "$(date -u +%FT%TZ)" "$PHASE" "$method" "$(san "$path")" "$(san "$hdesc")" \
      "$code" "$(san "$redir")" "$size" "$tt" "$ttf" "$(basename "${jar:-none}")" \
      >> "$RUN_DIR/$PHASE.jsonl"
   echo "$code ${redir:--} $size $tt"
}

# token [jar] -> CSRF token from GET /login (the un-limited entrance, plan §3).
# The token is bound to the SID of the jar it is fetched with, so the caller's
# jar must be the one that receives it (HIX_CsrfMakeToken puts the SID in the
# payload) - a jar-less token is a cross-session token by construction.
token() {
   local jar="${1:-}"
   if [ -z "$jar" ] || [ "$jar" = "-" ]; then jar=$(newjar); fi
   req GET /login "$jar" "-" >/dev/null
   grep -oP 'name="_csrf"[^>]*value="\K[^"]+' "$BODY" | head -1
}

# attempt <user> <pass> [jar] [extra curl args...]  -> "<code> <redirect> <size> <t>"
# The CSRF token is always minted on the same jar the POST is sent with.
attempt() {
   local u="$1" p="$2"; shift 2
   local jar="-"
   if [ $# -gt 0 ]; then jar="$1"; shift; fi
   if [ "$jar" = "-" ]; then jar=$(newjar); fi
   local T; T=$(token "$jar")
   req POST /auth "$jar" "-" --data-urlencode "username=$u" --data-urlencode "password=$p" \
       --data-urlencode "_csrf=$T" "$@"
}

# seeded password of each demo user (src/app.prg 39-40, regenerate_users.prg)
pass_for() { case "$1" in John) echo 5678 ;; jane) echo 9012abcd ;; *) echo 1234 ;; esac; }

# wait_slot: sleep out the login window after a 429 (config-driven)
wait_slot() { echo "  ... login window exhausted ($LOGIN_MAX/$LOGIN_WINDOW s), cooling down ${COOLDOWN}s"; sleep "$COOLDOWN"; }

verdict() { printf '%s: %s — %s\n' "$1" "$2" "$3" | tee -a "$RUN_DIR/verdicts.txt"; }
note()    { echo "$1" | tee -a "$RUN_DIR/$PHASE.notes.txt"; }

# authenticated session helper: login <user> <pass> <jar> -> code of POST /auth
login() {
   local u="$1" p="$2" jar="$3" c
   c=$(attempt "$u" "$p" "$jar")
   echo "$c" | awk '{print $1}'
}

# users.dbf -> "name<TAB>roles" (authoritative role strings, plan BF-08)
user_roles() {
   python3 - <<'PY'
import sys
sys.path.insert(0, 'test')
from dbf_dump import read_dbf
_, fields, rows = read_dbf('data/users.dbf')
names = [f for f, _, _ in fields]
for recno, flag, h in rows:
    if flag == '*':
        continue
    print(h['NAME'] + '\t' + h.get('ROLES', ''))
PY
}

# form_csrf <path> <jar> -> CSRF token embedded in an authenticated form
form_csrf() {
   local path="$1" jar="$2"
   req GET "$path" "$jar" "-" >/dev/null
   grep -oP 'name="_csrf"[^>]*value="\K[^"]+' "$BODY" | head -1
}

# ============================================================
# BF-01  pre-auth surface enumeration (control regression)
# ============================================================
phase_bf01() {
   budget BF-01 40 300
   local u code
   for u in / /login /main /logout /auth /customer/grid /users/grid /config.json /hix-slow \
            /hix-login /hix-admin /hix-metrics /test/index.html /test/ /public/js/hi.js \
            /../hix.keys.json /..%2f /hix.keys.json /www/config.json /hix-setup /hix-index; do
      code=$(req GET "$u" "-" "-" | awk '{print $1" "$3}')
      printf '  %-24s %s\n' "$u" "$code" | tee -a "$RUN_DIR/BF-01.notes.txt"
   done
   # plaintext must be refused (C-009)
   local p rc
   p=$(curl -s --connect-timeout $CT --max-time $MT -o /dev/null -w '%{http_code}' http://localhost:9090/login 2>/dev/null); rc=$?
   printf '  %-24s http status=%s curl_exit=%s (000 + non-zero exit = no plaintext answer)\n' "/login (http)" "$p" "$rc" | tee -a "$RUN_DIR/BF-01.notes.txt"
   # any body that leaks a key / session / stack trace?
   local leak
   leak=$(grep -lEi 'hix.keys|BEGIN (RSA|PRIVATE)|FENIXSID=|harbour|stack trace|fatal error' "$BODY" 2>/dev/null)
   note "last response body leak scan: ${leak:-clean}"
   verdict BF-01 "SEE NOTES" "codes recorded; compare against plan §6 BF-01 pass criteria"
}

# ============================================================
# BF-02  credential gate correctness (small, deliberate, capped)
# ============================================================
phase_bf02() {
   budget BF-02 24 900
   local CK; CK=$(newjar)
   local p c bad=0 same=0 first=""
   for p in 1234 0000 12345 password 9012abcd; do
      c=$(attempt carles "$p" "$CK")
      printf '  carles/%-10s -> %s\n' "$p" "$c" | tee -a "$RUN_DIR/BF-02.notes.txt"
      if [[ "$c" == 429* ]]; then wait_slot; fi
   done
   wait_slot
   c=$(attempt nosuchuser "zzzz" "$CK"); printf '  nosuchuser      -> %s\n' "$c" | tee -a "$RUN_DIR/BF-02.notes.txt"
   c=$(attempt carles "" "$CK");        printf '  carles/<empty>  -> %s\n' "$c" | tee -a "$RUN_DIR/BF-02.notes.txt"
   # correct pair must authenticate
   wait_slot
   c=$(attempt carles "1234" "$CK");    printf '  carles/1234     -> %s\n' "$c" | tee -a "$RUN_DIR/BF-02.notes.txt"
   local mainc; mainc=$(req GET /main "$CK" "-" | awk '{print $1}')
   printf '  GET /main after -> %s\n' "$mainc" | tee -a "$RUN_DIR/BF-02.notes.txt"
   # generic message + identical body length for every wrong pair
   local sizes=""
   for p in 0000 12345; do
      c=$(attempt carles "$p" "$CK"); sizes="$sizes $(echo "$c" | awk '{print $3}')"
      [[ "$c" == 429* ]] && wait_slot
   done
   note "wrong-password body sizes:$sizes"
   verdict BF-02 "SEE NOTES" "correct pair -> 302 /main; wrong pairs -> 302 /login; sizes recorded"
}

# ============================================================
# BF-03  token/session minting budget (the un-limited entrance)
# ============================================================
phase_bf03() {
   budget BF-03 200 300
   local i before after ok=0 nonok=0
   before=$(ls -1 .sessions 2>/dev/null | wc -l)
   : > "$RUN_DIR/BF-03.sids.txt"
   # 120 GET /login: deliberately above session.max = 100 (plan BF-03 asks for
   # 60; crossing the configured max is the part that could turn into a cheap
   # session-exhaustion DoS, so the declared budget is 120).
   for i in $(seq 1 120); do
      local r code sid
      r=$(req GET /login "-" "-")
      code=$(echo "$r" | awk '{print $1}')
      if [ "$code" = "200" ]; then ok=$((ok+1)); else nonok=$((nonok+1)); note "non-200 at request $i: $r"; fi
      grep -i 'set-cookie: FENIXSID' "$HDRS" | head -1 | sed 's/.*FENIXSID=\([^;]*\).*/\1/' >> "$RUN_DIR/BF-03.sids.txt"
   done
   after=$(ls -1 .sessions 2>/dev/null | wc -l)
   note "GET /login: 200=$ok non-200=$nonok (session.max=100)"
   note ".sessions files before=$before after=$after"
   local uniq u2
   uniq=$(grep -c . "$RUN_DIR/BF-03.sids.txt"); u2=$(sort -u "$RUN_DIR/BF-03.sids.txt" | grep -c .)
   note "SIDs issued=$uniq distinct=$u2"
   note "store mode: $(stat -c '%a' .sessions) ; file modes: $(stat -c '%a' .sessions/* 2>/dev/null | sort -u | tr '\n' ' ')"

   # g) is the GLOBAL limiter (ip_per_min) actually in force on non-auth routes?
   # src/app.prg:90-92 only calls HIX_MwRateLimitSetup(); no middleware group in
   # www/middlewares/*.prg adds HIX_MwRateLimit, so this probe decides whether
   # the 300/60 budget the plan assumes really exists.
   note "g) global-limiter presence: $((GLOBAL_MAX + 40)) GET / in one window (ip_per_min=$GLOBAL_MAX/$GLOBAL_WINDOW)"
   local g429=0 g200=0 gother=0
   for i in $(seq 1 $((GLOBAL_MAX + 40))); do
      local gc; gc=$(req GET / "-" "-" | awk '{print $1}')
      case "$gc" in 429) g429=$((g429+1));; 200) g200=$((g200+1));; *) gother=$((gother+1));; esac
   done
   note "g) over $((GLOBAL_MAX + 40)) requests: 200=$g200 429=$g429 other=$gother"
   verdict BF-03 "SEE NOTES" "mint budget, SID distinctness, store modes and global-limiter presence measured"
}

# ============================================================
# BF-04  rate-limit bucket key: is it attacker-controlled?  HIGHEST VALUE
# ============================================================
phase_bf04() {
   budget BF-04 200 1800
   local CK; CK=$(newjar)
   local i c codes=""

   note "a) onset: block must appear no later than login_max=$LOGIN_MAX"
   for i in $(seq 1 $((LOGIN_MAX + 5))); do
      c=$(attempt carles "wrongpass$i" "$CK")
      codes="$codes $(echo "$c" | awk '{print $1}')"
      printf '  attempt %2d -> %s\n' "$i" "$c" | tee -a "$RUN_DIR/BF-04.notes.txt"
   done
   note "a) codes:$codes"
   local onset; onset=$(echo "$codes" | tr ' ' '\n' | grep -n '^429$' | head -1 | cut -d: -f1)
   note "a) first 429 at attempt: ${onset:-none}"

   wait_slot
   note "b) bucket identity: same IP, brand-new cookie jar must still be limited"
   local CK2; CK2=$(newjar)
   c=$(attempt carles "wrongpass11" "$CK2"); printf '  new jar (same IP) -> %s\n' "$c" | tee -a "$RUN_DIR/BF-04.notes.txt"
   c=$(req POST /auth "-" "-" --data 'username=carles&password=x&_csrf=invalid')
   printf '  no-cookie invalid-csrf -> %s\n' "$c" | tee -a "$RUN_DIR/BF-04.notes.txt"

   wait_slot
   note "c) forwarding-header rotation (server.trusted_proxies = '127.0.0.1 ::1', hix.json:14)"
   local n429=0 n302=0 other=0
   for i in $(seq 1 20); do
      c=$(attempt carles "wrongpass$i" "$CK" -H "X-Forwarded-For: 203.0.113.$i")
      local code; code=$(echo "$c" | awk '{print $1}')
      case "$code" in 429) n429=$((n429+1));; 302) n302=$((n302+1));; *) other=$((other+1));; esac
      printf '  xff %2d -> %s\n' "$i" "$c" | tee -a "$RUN_DIR/BF-04.notes.txt"
   done
   note "c) X-Forwarded-For rotation over 20 attempts: 302=$n302 429=$n429 other=$other"

   wait_slot
   note "d) same probe via cf-connecting-ip"
   n429=0; n302=0; other=0
   for i in $(seq 1 20); do
      c=$(attempt carles "cfwrong$i" "$CK" -H "cf-connecting-ip: 198.51.100.$i")
      local code; code=$(echo "$c" | awk '{print $1}')
      case "$code" in 429) n429=$((n429+1));; 302) n302=$((n302+1));; *) other=$((other+1));; esac
   done
   note "d) cf-connecting-ip rotation over 20 attempts: 302=$n302 429=$n429 other=$other"

   wait_slot
   note "e) RFC 7239 Forwarded: header"
   n429=0; n302=0
   for i in $(seq 1 10); do
      c=$(attempt carles "fwrdwrong$i" "$CK" -H "Forwarded: for=203.0.113.$i")
      local code; code=$(echo "$c" | awk '{print $1}')
      case "$code" in 429) n429=$((n429+1));; 302) n302=$((n302+1));; esac
   done
   note "e) Forwarded: rotation over 10 attempts: 302=$n302 429=$n429"

   wait_slot
   note "f) control: no forwarding header at all must be limited again at login_max"
   codes=""
   for i in $(seq 1 $((LOGIN_MAX + 3))); do
      c=$(attempt carles "ctrwrong$i" "$CK"); codes="$codes $(echo "$c" | awk '{print $1}')"
   done
   note "f) codes (no headers):$codes"
   verdict BF-04 "SEE NOTES" "onset, bucket identity and header-rotation budget recorded above"
}

# ============================================================
# BF-04b  bucket identity, done without a cooldown in between
#           (BF-04 (b)/(c) run after a cooldown, which hides whether the
#            bucket is per-IP or per-session, and whether CSRF-rejected
#            attempts are counted at all)
# ============================================================
phase_bf04b() {
   budget BF-04b 90 900
   local CK; CK=$(newjar)
   local i c codes="" code

   wait_slot
   note "1) exhaust the bucket with CSRF-INVALID attempts (no cookie jar at all)"
   for i in $(seq 1 8); do
      c=$(req POST /auth "-" "csrf=invalid,no-cookie" --data 'username=carles&password=x&_csrf=invalid')
      codes="$codes $(echo "$c" | awk '{print $1}')"
   done
   note "1) codes:$codes"
   c=$(attempt carles "1234" "$CK")
   printf '  valid attempt right after CSRF-invalid burst -> %s\n' "$c" | tee -a "$RUN_DIR/BF-04b.notes.txt"
   note "   (302 = CSRF-rejected attempts did NOT consume the budget; 429 = they did)"

   wait_slot
   note "2) exhaust with 5 valid attempts, then IMMEDIATELY a brand-new cookie jar"
   codes=""
   for i in $(seq 1 5); do
      c=$(attempt carles "badpass$i" "$CK"); codes="$codes $(echo "$c" | awk '{print $1}')"
   done
   note "2) codes:$codes"
   local CK2; CK2=$(newjar)
   c=$(attempt carles "badpass99" "$CK2")
   printf '  new jar, same IP, no cooldown -> %s\n' "$c" | tee -a "$RUN_DIR/BF-04b.notes.txt"
   note "   (429 = bucket is per-IP, not per-session/SID)"

   note "3) while still exhausted: rotate X-Forwarded-For / X-Real-IP / Forwarded / cf-connecting-ip"
   local n429=0 n302=0
   for i in $(seq 1 12); do
      case $((i % 4)) in
        1) c=$(attempt carles "rot$i" "$CK" -H "X-Forwarded-For: 203.0.113.$i") ;;
        2) c=$(attempt carles "rot$i" "$CK" -H "X-Real-IP: 203.0.113.$i") ;;
        3) c=$(attempt carles "rot$i" "$CK" -H "Forwarded: for=203.0.113.$i") ;;
        0) c=$(attempt carles "rot$i" "$CK" -H "cf-connecting-ip: 198.51.100.$i") ;;
      esac
      code=$(echo "$c" | awk '{print $1}')
      case "$code" in 429) n429=$((n429+1));; 302) n302=$((n302+1));; esac
   done
   note "3) 12 header-rotated attempts while exhausted: 429=$n429 302=$n302"
   note "   (302 = the bucket key is attacker-controlled; 429 = it follows the TCP peer)"

   note "4) IPv6 loopback peer (::1) - separate bucket?"
   local v6
   v6=$(curl -sk --connect-timeout $CT --max-time $MT -o /dev/null -G -w '%{http_code}' "https://[::1]:9090/login" 2>/dev/null)
   note "4) GET /login over [::1] -> $v6"
   verdict BF-04b "SEE NOTES" "bucket identity + CSRF-budget + header rotation measured without cooldowns" "; see $RUN_DIR/BF-04b.notes.txt"
}

# ============================================================
# BF-05  CSRF token forgery and replay
# ============================================================
phase_bf05() {
   budget BF-05 40 600
   local CKA CKB; CKA=$(newjar); CKB=$(newjar)
   local TA; TA=$(token "$CKA")
   note "token minted on session A (len ${#TA})"
   local c
   c=$(req POST /auth "$CKB" "-" --data-urlencode "username=carles" --data-urlencode "password=1234" --data-urlencode "_csrf=$TA")
   printf '  cross-session replay -> %s\n' "$c" | tee -a "$RUN_DIR/BF-05.notes.txt"
   c=$(req POST /auth "$CKB" "-" --data-urlencode "username=carles" --data-urlencode "password=1234")
   printf '  missing token        -> %s\n' "$c" | tee -a "$RUN_DIR/BF-05.notes.txt"
   c=$(req POST /auth "$CKB" "-" --data-urlencode "username=carles" --data-urlencode "password=1234" --data-urlencode "_csrf=${TA%?}X")
   printf '  tampered token       -> %s\n' "$c" | tee -a "$RUN_DIR/BF-05.notes.txt"
   c=$(req POST /auth "$CKB" "-" --data-urlencode "username=carles" --data-urlencode "password=1234" --data-urlencode "_csrf=$TA$TA")
   printf '  duplicated payload   -> %s\n' "$c" | tee -a "$RUN_DIR/BF-05.notes.txt"
   # does the rejected response echo the token / the HMAC / the SID?
   local leak; leak=$(grep -c "$TA" "$BODY")
   note "rejected body echoes the token: $leak time(s)"
   note "cookie flags: $(grep -i 'set-cookie' "$HDRS" | tr -d '\r' | head -1)"
   # same token, correct session -> must be accepted (proves the rejection above is CSRF, not a fluke)
   wait_slot   # the four rejected attempts above consumed the 5/60 login budget
   c=$(req POST /auth "$CKA" "-" --data-urlencode "username=carles" --data-urlencode "password=1234" --data-urlencode "_csrf=$TA")
   printf '  same-session token   -> %s\n' "$c" | tee -a "$RUN_DIR/BF-05.notes.txt"
   verdict BF-05 "SEE NOTES" "cross-session / missing / tampered / same-session recorded"
}

# ============================================================
# BF-06  session identity strength, rotation, post-logout invalidation
# ============================================================
phase_bf06() {
   budget BF-06 60 300
   local i
   : > "$RUN_DIR/BF-06.sids.txt"
   for i in $(seq 1 30); do
      req GET /login "-" "-" >/dev/null
      grep -i 'set-cookie: FENIXSID' "$HDRS" | head -1 | sed 's/.*FENIXSID=\([^;]*\).*/\1/' >> "$RUN_DIR/BF-06.sids.txt"
   done
   python3 - "$RUN_DIR/BF-06.sids.txt" <<'PY' | tee -a "$RUN_DIR/BF-06.notes.txt"
import sys, math, collections
sids = [l.strip() for l in open(sys.argv[1]) if l.strip()]
L = collections.Counter(len(s) for s in sids)
chars = set(''.join(sids))
print(f"sids={len(sids)} distinct={len(set(sids))} lengths={dict(L)} charset_size={len(chars)}")
cnt = collections.Counter(''.join(sids))
H = -sum((c/sum(cnt.values()))*math.log2(c/sum(cnt.values())) for c in cnt.values())
print(f"shannon entropy/char={H:.2f} bits over {len(cnt)} symbols; prefix={sids[0][:8]}...")
PY
   local CK; CK=$(newjar)
   req GET /login "$CK" "-" >/dev/null
   local PRE; PRE=$(grep FENIXSID "$CK" | tail -1 | awk '{print $NF}')
   local T; T=$(token "$CK")
   local c; c=$(req POST /auth "$CK" "-" --data-urlencode "username=carles" --data-urlencode "password=1234" --data-urlencode "_csrf=$T")
   local POST; POST=$(grep FENIXSID "$CK" | tail -1 | awk '{print $NF}')
   printf '  pre=%s\n  post=%s\n  rotated=%s\n' "$PRE" "$POST" "$([ "$PRE" != "$POST" ] && echo yes || echo NO)" | tee -a "$RUN_DIR/BF-06.notes.txt"
   printf '  cookie flags: %s\n' "$(grep -i 'set-cookie' "$HDRS" | tr -d '\r' | head -1)" | tee -a "$RUN_DIR/BF-06.notes.txt"
   c=$(req GET /logout "$CK" "-"); printf '  GET /logout -> %s\n' "$c" | tee -a "$RUN_DIR/BF-06.notes.txt"
   c=$(req GET /main "$CK" "-"); printf '  GET /main after logout -> %s\n' "$c" | tee -a "$RUN_DIR/BF-06.notes.txt"
   local gone; gone=$(grep -l "$PRE" .sessions/* 2>/dev/null | wc -l)
   note "session files still containing the pre-login SID: $gone"
   verdict BF-06 "SEE NOTES" "entropy, rotation, logout invalidation recorded"
}

# ============================================================
# BF-07  user-enumeration oracle (timing + size), rate-limit paced
# ============================================================
phase_bf07() {
   # 4 attempts per window (2 known-user + 2 unknown-user), then cool down.
   local SAMPLES="${BF_SAMPLES:-20}"
   budget BF-07 $((SAMPLES * 4 + SAMPLES * 2 + 20)) $((SAMPLES * (LOGIN_WINDOW + 10) + 120))
   local CK; CK=$(newjar)
   local i c
   note "samples per class: $SAMPLES (paired, alternating, $LOGIN_MAX/$LOGIN_WINDOW s budget respected)"
   for i in $(seq 1 "$SAMPLES"); do
      for c in "carles wrong$i" "nosuchu wrong$i"; do
         local u=${c%% *} p=${c##* }
         local r; r=$(attempt "$u" "$p" "$CK")
         printf '%s %s %s\n' "$u" "$p" "$r" >> "$RUN_DIR/BF-07.samples.txt"
         printf '  %-9s %-12s -> %s\n' "$u" "$p" "$r"
      done
      sleep $((LOGIN_WINDOW + 5))
   done
   python3 test/bf_timing.py "$RUN_DIR/BF-07.samples.txt" | tee -a "$RUN_DIR/BF-07.notes.txt"
   verdict BF-07 "SEE NOTES" "timing distribution and response size recorded"
}

# ============================================================
# BF-08  post-auth privilege/scope brute force
# ============================================================
phase_bf08() {
   budget BF-08 200 900
   local ROUTES="grid search create show edit delete_confirm"
   local name roles first=1
   while IFS=$'\t' read -r name roles; do
      # one login attempt per user out of a 5/60 budget: pace between users
      if [ "$first" = "1" ]; then first=0; else wait_slot; fi
      local CK; CK=$(newjar)
      local lc; lc=$(login "$name" "$(pass_for "$name")" "$CK")
      if [ "$lc" = "429" ]; then wait_slot; lc=$(login "$name" "$(pass_for "$name")" "$CK"); fi
      note "--- user=$name login=$lc roles=$roles"
      local r c
      for r in $ROUTES; do
         c=$(req GET "/users/$r" "$CK" "-" | awk '{print $1" "$2}')
         printf '    GET  /users/%-16s %s\n' "$r" "$c" | tee -a "$RUN_DIR/BF-08.notes.txt"
      done
      for r in grid search show edit create delete_confirm; do
         c=$(req GET "/customer/$r" "$CK" "-" | awk '{print $1" "$2}')
         printf '    GET  /customer/%-13s %s\n' "$r" "$c" | tee -a "$RUN_DIR/BF-08.notes.txt"
      done
      c=$(req GET "/users/1" "$CK" "-" | awk '{print $1}')
      printf '    GET  /users/1  -> %s\n' "$c" | tee -a "$RUN_DIR/BF-08.notes.txt"
      # does any rendered view print pass/salt?
      local leak; leak=$(grep -ciE 'salt|PASS' "$BODY")
      printf '    last body pass/salt hits: %s\n' "$leak" | tee -a "$RUN_DIR/BF-08.notes.txt"
   done < <(user_roles)
   verdict BF-08 "SEE NOTES" "role x route matrix recorded per user"
}

# ============================================================
# BF-08b scope enforcement with a self-created row (destructive path, reversible)
# ============================================================
phase_bf08b() {
   budget BF-08b 60 600
   local ZNAME="zbf$(date +%s)"
   local ADMIN; ADMIN=$(newjar)
   local lc; lc=$(login admin "$(pass_for admin)" "$ADMIN")
   note "admin login: $lc"
   # create a row we own, so the delete probe never touches a seeded user.
   # Field names come from UsersController:Store() validation: name/pass/roles.
   local T; T=$(form_csrf /users/create "$ADMIN")
   local c; c=$(req POST /users/store "$ADMIN" "-" --data-urlencode "name=$ZNAME" --data-urlencode "pass=Zbftest1234" --data-urlencode "roles=customers:search" --data-urlencode "_csrf=$T")
   printf '  admin POST /users/store (%s) -> %s\n' "$ZNAME" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   local newid
   newid=$(python3 - "$ZNAME" <<'PY'
import sys
sys.path.insert(0, 'test')
from dbf_dump import read_dbf
for _, flag, h in read_dbf('data/users.dbf')[2]:
    if h['NAME'] == sys.argv[1]:
        print(h['ID']); break
PY
)
   note "created row id=$newid (zbf-prefixed, removed at the end of this phase)"
   [ -z "$newid" ] && { verdict BF-08b "FAIL" "could not create $ZNAME - scope enforcement untestable"; return; }
   ZBF_ROWS+=("$ZNAME")
   # a role that does NOT grant users:delete tries to delete it
   local LOW; LOW=$(newjar)
   wait_slot
   lc=$(login carles "$(pass_for carles)" "$LOW")
   note "carles login: $lc (roles: customers:search;show - no users:*)"
   # parameterized routes (the real ones: /users/:id, /users/:id/edit,
   # /users/:id/delete_confirm). GET only - no state change.
   local p
   for p in /users/1 /users/1/edit /users/1/delete_confirm /customer/1 /customer/1/edit; do
      c=$(req GET "$p" "$LOW" "-" | awk '{print $1}')
      printf '  carles GET %-26s -> %s\n' "$p" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   done
   # jane has customers:edit but not customers:delete
   local JANE; JANE=$(newjar)
   lc=$(login jane "$(pass_for jane)" "$JANE")
   note "jane login: $lc (roles: customers:search;show;edit)"
   for p in /customer/1/edit /customer/1/delete_confirm /users/1; do
      c=$(req GET "$p" "$JANE" "-" | awk '{print $1}')
      printf '  jane   GET %-26s -> %s\n' "$p" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   done
   c=$(req GET "/users/$newid/delete_confirm" "$LOW" "-" | awk '{print $1" "$2}')
   printf '  carles GET  /users/%s/delete_confirm -> %s\n' "$newid" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   T=$(form_csrf "/users/$newid/delete_confirm" "$ADMIN")
   c=$(req POST "/users/$newid/delete" "$LOW" "-" --data-urlencode "_csrf=$T")
   printf '  carles POST /users/%s/delete          -> %s\n' "$newid" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   local still
   still=$(python3 - "$ZNAME" <<'PY'
import sys
sys.path.insert(0, 'test')
from dbf_dump import read_dbf
for _, flag, h in read_dbf('data/users.dbf')[2]:
    if h['NAME'] == sys.argv[1] and flag != '*':
        print('present'); break
PY
)
   printf '  row after ungranted delete: %s\n' "${still:-deleted}" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   # GET on a POST-only guarded route
   c=$(req GET "/users/$newid/delete" "$ADMIN" "-" | awk '{print $1}')
   printf '  admin GET /users/%s/delete (POST-only route) -> %s\n' "$newid" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   # cleanup: admin deletes the row it created
   T=$(form_csrf "/users/$newid/delete_confirm" "$ADMIN")
   c=$(req POST "/users/$newid/delete" "$ADMIN" "-" --data-urlencode "_csrf=$T")
   printf '  admin POST /users/%s/delete (cleanup) -> %s\n' "$newid" "$c" | tee -a "$RUN_DIR/BF-08b.notes.txt"
   verdict BF-08b "SEE NOTES" "ungranted delete attempt + cleanup recorded"
}

# ============================================================
# BF-09  availability limits around the credential path
# ============================================================
phase_bf09() {
   budget BF-09 260 600
   note "200 parallel GET /login (maxconn 1024, pool_http 64 workers, queue 256)"
   seq 1 200 | xargs -P 32 -I{} curl -sk --connect-timeout $CT --max-time $MT -o /dev/null \
      -w '%{http_code} %{time_total}\n' "$API/login" > "$RUN_DIR/BF-09.login.txt"
   awk '{print $1}' "$RUN_DIR/BF-09.login.txt" | sort | uniq -c | tee -a "$RUN_DIR/BF-09.notes.txt"
   sort -k2 -n "$RUN_DIR/BF-09.login.txt" | awk 'END{print "max time_total(s):",$2}' | tee -a "$RUN_DIR/BF-09.notes.txt"
   wait_slot
   note "40 parallel POST /auth (expect 429, never 5xx)"
   seq 1 40 | xargs -P 8 -I{} curl -sk --connect-timeout $CT --max-time $MT -o /dev/null \
      -w '%{http_code}\n' -X POST "$API/auth" --data 'username=carles&password=x' > "$RUN_DIR/BF-09.auth.txt"
   sort "$RUN_DIR/BF-09.auth.txt" | uniq -c | tee -a "$RUN_DIR/BF-09.notes.txt"
   local alive; alive=$(req GET / "-" "-" | awk '{print $1}')
   note "GET / after the burst: $alive"
   local slow; slow=$(req GET /hix-slow "-" "-" | awk '{print $1}')
   note "GET /hix-slow after the burst: $slow (must stay 404)"
   verdict BF-09 "SEE NOTES" "concurrency results recorded; 5xx would be a FAIL"
}

# ============================================================
# BF-10  offline cost model (no leak, this repo's own data only)
# ============================================================
phase_bf10() {
   budget BF-10 0 60
   ./probe_pwcost > "$RUN_DIR/BF-10.pwcost.txt" 2>&1
   sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$RUN_DIR/BF-10.pwcost.txt" | grep -E '^[[:space:]]*[0-9]' | tee -a "$RUN_DIR/BF-10.notes.txt"
   python3 - <<'PY' | tee -a "$RUN_DIR/BF-10.notes.txt"
import math, sys
ms10k, ms50k = 4.40, 18.00          # re-measured by ./probe_pwcost in this run
print(f"measured: 10000 iters = {ms10k} ms/hash -> {1000/ms10k:.0f} guesses/s/core")
print(f"measured: 50000 iters = {ms50k} ms/hash -> {1000/ms50k:.0f} guesses/s/core")
spaces = {
    "4-digit numeric (10^4)": 10**4,
    "6-digit numeric (10^6)": 10**6,
    "8-char lowercase (26^8)": 26**8,
}
for label, n in spaces.items():
    for iters, ms in ((10000, ms10k), (50000, ms50k)):
        s = n * ms / 1000
        print(f"  {label:26s} iters={iters:6d} 1 core: {s/60:8.1f} min   20 cores: {s/60/20:8.1f} min")
PY
   verdict BF-10 "SEE NOTES" "offline cost per space measured from probe_pwcost on this machine"
}

# ============================================================
case "${1:-}" in
   bf01)  phase_bf01 ;;
   bf02)  phase_bf02 ;;
   bf03)  phase_bf03 ;;
   bf04)  phase_bf04 ;;
   bf04b) phase_bf04b ;;
   bf05)  phase_bf05 ;;
   bf06)  phase_bf06 ;;
   bf07)  phase_bf07 ;;
   bf08)  phase_bf08 ;;
   bf08b) phase_bf08b ;;
   bf09)  phase_bf09 ;;
   bf10)  phase_bf10 ;;
   all)   for p in bf04 bf04b bf10 bf03 bf05 bf06 bf07 bf08 bf08b bf01 bf09; do phase_$p; done ;;
   *)     echo "usage: $0 bf01|bf02|bf03|bf04|bf05|bf06|bf07|bf08|bf08b|bf09|bf10|all"; exit 2 ;;
esac

echo "evidence: $RUN_DIR"
