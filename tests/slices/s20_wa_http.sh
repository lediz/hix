#!/usr/bin/env bash
# ------------------------------------------------------------------
# s20_wa_http.sh - one webapp functional suite, run unmodified.
#
#   s20_wa_http.sh users | customer | verify
#
# The three suites in webapp/test are the project's own; this slice only
# supplies the environment they expect and parses their stdout:
#
#   users     webapp/test/test_users_module.sh     (TEST_API)
#   customer  webapp/test/test_customer_module.sh  (TEST_API)
#   verify    webapp/test/verify-users-fixes.sh    (VERIFY_API)
#
# CURL_CA_BUNDLE is pointed at the app's own certificate so the suites
# that call curl without -k still work against the TLS-only server.
# The suites default to http:// while hix.json has ssl=true: that
# mismatch is reported as a case, not patched.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

which_suite=${1:-}
case "$which_suite" in
   users)    script=test/test_users_module.sh;     mode=bracket; apivar=TEST_API;    id=31-wa-users    ;;
   customer) script=test/test_customer_module.sh;  mode=bracket; apivar=TEST_API;    id=32-wa-customer ;;
   verify)   script=test/verify-users-fixes.sh;    mode=verify;  apivar=VERIFY_API;  id=33-wa-verify   ;;
   *) echo "usage: $(basename "$0") users|customer|verify" >&2; exit 2 ;;
esac
hix_slice_init "${SLICE_ID:-$id}"
hix_env_init
hix_curl_trust || true

cd "$HIX_WEBAPP" || { hix_case "@abort" FAIL "cannot cd $HIX_WEBAPP"; exit 2; }
[ -f "$script" ] || { hix_case "@abort" FAIL "missing $script"; exit 2; }

url=$(hix_api_url)
hix_class env          # this slice's own rows describe the run, not HIX
if ! hix_server_up "$url"; then
   hix_case "@abort" FAIL "no HIX app answering on $url - start webapp/app first"
   echo "slice $HIX_SLICE - ABORT: no server on $url" | hix_digest
   exit 2
fi
hix_case "preflight.server" PASS "$url"

# What the suite would use if left to its own default - read out of the
# script rather than assumed: verify-users-fixes.sh already defaults to
# https, the other two to http, and only test_users_module.sh ignores an
# environment variable entirely.
default_api=$(awk 'match($0,/^[ \t]*(API|BASE)="?\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]*\}/) {
   s = substr($0, RSTART, RLENGTH); sub(/^[^:-]*:-/, "", s); sub(/\}$/, "", s); print s; exit }' "$script")
[ -n "$default_api" ] || default_api=$(awk 'match($0,/^[ \t]*(API|BASE)="[^"]*"/) {
   s = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); print s; exit }' "$script")
grep -q "\${$apivar" "$script" 2>/dev/null && honours=yes || honours=no

if [ -z "$default_api" ]; then
   hix_case "preflight.suite_default" NOTE "no API=/BASE= assignment found in $script"
elif [ "${default_api#https://}" != "$default_api" ]; then
   hix_case "preflight.suite_default" PASS \
      "$script defaults to $default_api, which suits the TLS-only server (honours $apivar: $honours)"
else
   code=$(curl -s --connect-timeout 3 --max-time 8 -o /dev/null -w '%{http_code}' "$default_api/login" 2>/dev/null)
   [ -n "$code" ] || code=000
   if [ "$code" = "000" ]; then
      hix_case "preflight.suite_default" NOTE \
         "$script defaults to $default_api, which the TLS-only server refuses; exporting $apivar=$url"
   else
      hix_case "preflight.suite_default" PASS "$default_api answers $code (honours $apivar: $honours)"
   fi
fi

export "$apivar=$url"
t0=$(date +%s)
hix_log "$script with $apivar=$url"
timeout "$HIX_TIMEOUT" bash "$script" > "$HIX_OUT/$HIX_SLICE.raw" 2>&1
rc=$?
secs=$(( $(date +%s) - t0 ))
cp "$HIX_OUT/$HIX_SLICE.raw" "$HIX_LOG"
hix_log "rc=$rc in ${secs}s raw=$(wc -c < "$HIX_LOG") bytes"

if [ "$rc" = 124 ]; then hix_case "@abort" FAIL "timeout after ${HIX_TIMEOUT}s"; exit 2; fi
if [ "$rc" = 2 ];  then hix_case "@abort" FAIL "$script aborted (rc=2) - see the log"; fi

hix_class ""           # the suite's own rows carry no claim of their own:
                       # only a rule with a proved check may call one noise
HIX_SLICE=$HIX_SLICE HIX_PARSE_MODE=$mode hix_parse parse_wa.awk "$HIX_LOG"

{
   echo "slice $HIX_SLICE - webapp $which_suite suite ($script) rc=$rc ${secs}s"
   grep $'\t@totals\t' "$HIX_TSV" | cut -f4 | sed 's/^/  suite says: /'
   echo "  parsed rows: $(awk -F'\t' '$2!~/^@/{c++} END{print c+0}' "$HIX_TSV")" \
        "| PASS $(awk -F'\t' '$3=="PASS"{c++} END{print c+0}' "$HIX_TSV")" \
        "| FAIL $(awk -F'\t' '$3=="FAIL"{c++} END{print c+0}' "$HIX_TSV")" \
        "| raw $(wc -c < "$HIX_LOG") bytes"
   echo "  --- failures ---"
   awk -F'\t' '$3=="FAIL"{printf "  FAIL %s  %s\n", $2, $4}' "$HIX_TSV"
   echo "  --- section headers seen (uncapped list in the log) ---"
   grep -oE '^=== [^=]+===' "$HIX_LOG" | head -40
} | hix_digest

awk -F'\t' '$3=="FAIL"{n++} END{exit (n>0?1:0)}' "$HIX_TSV"
