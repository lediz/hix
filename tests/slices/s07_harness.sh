#!/usr/bin/env bash
# ------------------------------------------------------------------
# s07_harness.sh - prove why a failure may be treated as noise.
#
#   s07_harness.sh
#
# lib/rules.tsv is what lets the suite tell a defect in HIX apart from a
# defect in a test script, a missing tool or a leftover of an earlier
# run. A rule must not be trusted on its own: each one cites a check id,
# and this slice is what decides whether that check holds *right now*,
# against the tree as it stands. It writes one row per check to
#
#   tests/.out/checks.tsv      check-id \t ok|fail \t evidence
#
# which lib/classify.awk reads. If a check says "fail" the rule citing it
# is inert and the rows it used to explain come back as class "triage" -
# a stale rule can never keep hiding a real failure.
#
# Every check is a fact about the harness or the machine, never about
# HIX: this slice reports, it does not fix.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
hix_slice_init "${SLICE_ID:-07-harness}"

: > "$HIX_OUT/checks.tsv"

# check <id> <ok?> <evidence>  - records the verdict and mirrors it into
# the slice's own rows so the evidence is drillable with tests/slice.sh.
check() {   # check <id> <ok?> <what> <evidence>
   if [ "$2" = "0" ]; then
      hix_check "$1" ok "$4"
      hix_case "check.$1" NOTE "JUSTIFIED - $3 is noise, not a defect: $4"
   else
      hix_check "$1" fail "$4"
      hix_case "check.$1" NOTE "NOT JUSTIFIED - $3 will be counted as a defect"
   fi
}

# --- mock.io.stale ---------------------------------------------------------
# Which messages does the framework send to its IO object, and does the
# unit suite's mock implement them? A message the mock does not answer
# kills the whole test group with "[EXCEPTION] Message not found" before
# a single assertion runs, so those groups say nothing about HIX.
io_msgs=$(grep -rhoE 'oIO:[A-Za-z_][A-Za-z0-9_]*' --include='*.prg' "$HIX_ROOT/src" 2>/dev/null \
            | sed 's/^oIO://' | sort -u)
mock_methods=$(awk '/^CLASS TMockIO/,/^ENDCLASS/' "$HIX_UNIT/src/hix_test_utils.prg" 2>/dev/null \
            | grep -oE '^[[:space:]]*METHOD[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
            | sed 's/^[[:space:]]*METHOD[[:space:]]*//' | sort -u)
mock_data=$(awk '/^CLASS TMockIO/,/^ENDCLASS/' "$HIX_UNIT/src/hix_test_utils.prg" 2>/dev/null \
            | grep -oE '^[[:space:]]*DATA[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
            | sed 's/^[[:space:]]*DATA[[:space:]]*//' | sort -u)
mock_have=$(printf '%s\n%s\n' "$mock_methods" "$mock_data" | grep -v '^[[:space:]]*$' | sort -u)
mock_missing=$(comm -23 <(printf '%s\n' "$io_msgs") <(printf '%s\n' "$mock_have") | grep -v '^[[:space:]]*$' | tr '\n' ' ')
if [ -n "$mock_missing" ]; then
   check mock.io.stale 0 "the Message-not-found unit groups" "TMockIO does not answer: $mock_missing"
else
   check mock.io.stale 1 "the Message-not-found unit groups" "TMockIO answers every message src/ sends to oIO"
fi

# --- curl.exe.windows ------------------------------------------------------
# The unit suite skips its HTTPS cases by looking for curl.exe, which
# only exists on Windows. On Linux it reports that as a FAIL.
if grep -rlq 'curl\.exe' --include='*.prg' "$HIX_UNIT/src" 2>/dev/null && ! hix_have curl.exe; then
   check curl.exe.windows 0 "the Transport/SSL case" "tests/unit asks for curl.exe; this is $(uname -s)"
else
   check curl.exe.windows 1 "the Transport/SSL case" "no curl.exe dependency, or curl.exe is present"
fi

# --- users.api.hardcoded ---------------------------------------------------
# test_users_module.sh pins its target URL instead of honouring TEST_API,
# so it cannot be pointed at the TLS-only server and aborts on its own
# preflight. The abort is a property of the script, not of the app.
uf="$HIX_WEBAPP/test/test_users_module.sh"
if [ -f "$uf" ] && grep -qE '^[[:space:]]*API="https?://' "$uf" && ! grep -q 'TEST_API' "$uf"; then
   check users.api.hardcoded 0 "the users-suite abort" \
      "$(grep -nE '^[[:space:]]*API="https?://' "$uf" | head -1 | tr -s ' ') and no TEST_API in the file"
else
   check users.api.hardcoded 1 "the users-suite abort" "the script honours TEST_API"
fi

# --- customer.cookie.jar ---------------------------------------------------
# The customer suite sends --cookie on the authenticating POST but never
# saves the jar, so the session it authenticated is discarded and every
# later session-dependent request replays the anonymous one.
cf="$HIX_WEBAPP/test/test_customer_module.sh"
if [ -f "$cf" ]; then
   sends=$(grep -c -- '--cookie ' "$cf" 2>/dev/null || echo 0)
   # Walk every "-X POST $API/auth" command (it runs to the line that
   # closes the $( ) the curl call lives in). The one that carries a CSRF
   # token is the one expected to authenticate: does it write the jar?
   read -r auth_csrf auth_saves < <(awk '
      /-X POST "\$API\/auth"/ { f = 1 }
      f { buf = buf " " $0 }
      f && /\)/ {
         if (buf ~ /_csrf=/) { c++; if (buf ~ /--cookie-jar|[[:space:]]-c[[:space:]]/) s++ }
         buf = ""; f = 0
      }
      END { print c+0, s+0 }' "$cf")
   if [ "$sends" -gt 0 ] && [ "${auth_csrf:-0}" -gt 0 ] && [ "${auth_saves:-0}" = "0" ]; then
      check customer.cookie.jar 0 "the customer session cascade" \
         "$auth_csrf authenticating POST(s) send a CSRF token and a cookie, none saves the jar"
   else
      check customer.cookie.jar 1 "the customer session cascade" "$auth_csrf authenticating POST(s), $auth_saves of them save the jar"
   fi
else
   check customer.cookie.jar 1 "the customer session cascade" "$cf missing"
fi

# --- test.rows.are.test.rows ----------------------------------------------
# users.dbf rows whose NAME starts with zbf/zverify are inserted by the
# project's own test scripts. Residue of them is residue of testing.
writers=$(grep -rlE '(zbf|zverify)' --include='*.sh' "$HIX_WEBAPP/test" 2>/dev/null | tr '\n' ' ')
if [ -n "$writers" ]; then
   check test.rows.are.test.rows 0 "users.dbf residue" "written by the suites themselves: $writers"
else
   check test.rows.are.test.rows 1 "users.dbf residue" "no test script writes the zbf*/zverify* rows"
fi

# --- report ----------------------------------------------------------------
{
   echo "slice $HIX_SLICE - noise attribution: which demotion rules hold right now"
   echo "  checks recorded: $(wc -l < "$HIX_OUT/checks.tsv")"
   awk -F'\t' '{printf "  %-24s %-5s %s\n", $1, $2, $3}' "$HIX_OUT/checks.tsv"
   n_ok=$(awk -F'\t' '$2=="ok"' "$HIX_OUT/checks.tsv" | wc -l)
   n_no=$(awk -F'\t' '$2!="ok"' "$HIX_OUT/checks.tsv" | wc -l)
   echo "  justified: $n_ok   not justified: $n_no"
   [ "$n_no" = "0" ] || echo "  a rule that is not justified leaves its failures in class triage (they count)"
} | hix_digest

exit 0
