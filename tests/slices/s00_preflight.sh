#!/usr/bin/env bash
# ------------------------------------------------------------------
# s00_preflight.sh - environment, build artifacts and app configuration.
#
# Reports only: a FAIL here means the machine or the tree is not in the
# state the rest of the suite assumes, never a defect in HIX itself.
# Cases are named env.* / fw.* / unit.* / app.* / srv.* / cfg.*
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
hix_slice_init "${1:-00-preflight}"
hix_env_init

# Nothing in this slice can be a defect in HIX: it describes the machine,
# the toolchain and the build artifacts. Its failures are class env - they
# say the rest of the run is not trustworthy. The exceptions are the
# invariants of the running app itself (key material modes, certificate
# validity, sessions not plaintext, TLS-only listener), which are class
# product because they are properties of what HIX does.
hix_class env

ck()   { # ck <case> <ok?> <detail>
   if [ "$2" = "0" ]; then hix_case "$1" PASS "$3"; else hix_case "$1" FAIL "$3"; fi
}
mode_of() { stat -c '%a' "$1" 2>/dev/null || echo missing; }

# --- toolchain --------------------------------------------------------------
for t in bash curl python3 openssl git awk grep sed stat timeout; do
   if hix_have "$t"; then hix_case "env.$t" PASS "$(command -v "$t")"
   else hix_case "env.$t" FAIL "not on PATH"; fi
done
hix_case "env.bash" NOTE "${BASH_VERSION}"

# --- Harbour ----------------------------------------------------------------
if [ -x "$HB_ROOT/bin/linux/gcc/hbmk2" ]; then
   hix_case "env.HB_ROOT" PASS "$HB_ROOT"
   hix_case "env.hbmk2"   PASS "$("$HB_ROOT/bin/linux/gcc/hbmk2" -version 2>&1 | head -1)"
else
   hix_case "env.HB_ROOT" FAIL "no hbmk2 under $HB_ROOT (set HB_ROOT)"
   hix_case "env.hbmk2"   SKIP "unreachable without HB_ROOT"
fi
[ -f "$HB_ROOT/include/harbour.hbx" ] && hix_case "env.harbour.hbx" PASS || hix_case "env.harbour.hbx" FAIL "missing"
[ -d "${HB_INCLUDE%%:*}" ]            && hix_case "env.HB_INCLUDE"  PASS "${HB_INCLUDE%%:*} (HB_INCLUDE=$HB_INCLUDE)" \
                                       || hix_case "env.HB_INCLUDE"  FAIL "first entry missing: $HB_INCLUDE"

# --- framework artifacts ----------------------------------------------------
[ -f "$HIX_ROOT/hix_server.hbx" ] && hix_case "fw.hbx" PASS "$(ls -la "$HIX_ROOT/hix_server.hbx" | awk '{print $5" bytes "$6" "$7" "$8}')" \
                                  || hix_case "fw.hbx" FAIL "missing - run go_lib_gcc.sh"
lib=$(ls "$HIX_ROOT"/lib/*/libhix_server.a 2>/dev/null | head -1)
[ -n "$lib" ] && hix_case "fw.libstatic" PASS "$lib" || hix_case "fw.libstatic" FAIL "missing - run go_lib_gcc.sh"
hix_case "fw.src.count" NOTE "$(find "$HIX_ROOT/src" -name '*.prg' | wc -l) .prg under src/"

# --- unit-test binary -------------------------------------------------------
if [ -x "$HIX_UNIT/app" ]; then
   hix_case "unit.binary" PASS "$(ls -la "$HIX_UNIT/app" | awk '{print $5" bytes "$6" "$7" "$8}')"
   newest_src=$(find "$HIX_UNIT/src" -name '*.prg' -newer "$HIX_UNIT/app" | wc -l)
   if [ "$newest_src" -gt 0 ]; then hix_case "unit.binary.stale" FAIL "$newest_src .prg newer than the binary - rebuild"
   else hix_case "unit.binary.stale" PASS; fi
else
   hix_case "unit.binary" FAIL "missing - run tests/unit/go_gcc.sh"
fi
[ -f "$HIX_UNIT/hix_test.crt" ] && hix_case "unit.cert" PASS || hix_case "unit.cert" FAIL "missing - tests/unit/make_test_cert.sh"
[ -f "$HIX_UNIT/hix_test.key" ] && hix_case "unit.key"  PASS || hix_case "unit.key"  FAIL "missing"

# --- webapp artifacts and secrets ------------------------------------------
[ -x "$HIX_WEBAPP/app" ] && hix_case "app.binary" PASS "$(ls -la "$HIX_WEBAPP/app" | awk '{print $5" bytes"}')" \
                         || hix_case "app.binary" FAIL "missing - run webapp/go_gcc.sh"
[ -f "$HIX_WEBAPP/www/config.json" ] && hix_case "app.config" PASS || hix_case "app.config" FAIL "missing (copy www/config.json.example)"
[ -f "$HIX_WEBAPP/www/config.json.example" ] && hix_case "app.config.example" PASS || hix_case "app.config.example" FAIL "missing"

if [ -f "$HIX_WEBAPP/hix.keys.json" ]; then
   m=$(mode_of "$HIX_WEBAPP/hix.keys.json")
   if [ "$m" = "600" ]; then hix_case "app.keys.mode" PASS "0600"
   else hix_case "app.keys.mode" FAIL "mode $m, expected 0600" product; fi
   hix_case "app.keys.outside_docroot" PASS "webapp/hix.keys.json is not under www/"
else
   hix_case "app.keys.mode" FAIL "webapp/hix.keys.json missing - run gen_keys.sh"
fi

cert="$HIX_WEBAPP/certs/hix.crt"
if [ -f "$cert" ]; then
   if openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
      hix_case "app.cert.expiry" PASS "$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)" product
   else
      hix_case "app.cert.expiry" FAIL "certificate expired - rerun gen_cert.sh" product
   fi
   m=$(mode_of "$HIX_WEBAPP/certs/hix.key")
   [ "$m" = "600" ] && hix_case "app.key.mode" PASS "0600" || hix_case "app.key.mode" FAIL "mode $m, expected 0600" product
else
   hix_case "app.cert.expiry" FAIL "no certificate - TLS cannot start"
fi

for f in users.dbf users.cdx customers.dbf customers.cdx; do
   [ -f "$HIX_WEBAPP/data/$f" ] && hix_case "app.data.$f" PASS "$(stat -c '%s bytes' "$HIX_WEBAPP/data/$f")" \
                                || hix_case "app.data.$f" FAIL "missing"
done

# --- server reachability ----------------------------------------------------
url=$(hix_api_url)
port=$(hix_app_port); ssl=$(hix_app_ssl)
hix_case "srv.url" NOTE "$url (hix.json: port=$port ssl=$ssl)"
hix_curl_trust || hix_case "srv.trust" NOTE "no app certificate to hand curl (CURL_CA_BUNDLE unset)"
if hix_server_up "$url"; then
   code=$(curl -s --connect-timeout "$HIX_CURL_CT" --max-time "$HIX_CURL_MT" -o /dev/null -w '%{http_code}' "$url/login")
   hix_case "srv.reachable" PASS "GET $url/login -> $code"
   if [ "$ssl" = "true" ]; then
      httpcode=$(curl -s --connect-timeout 3 --max-time 8 -o /dev/null -w '%{http_code}' "http://localhost:$port/login" 2>/dev/null)
      [ -n "$httpcode" ] || httpcode=000
      if [ "$httpcode" = "000" ] || [ "$httpcode" = "400" ] || [ "$httpcode" = "421" ]; then
         hix_case "srv.tls_only" PASS "plain http refused ($httpcode)"
      else
         hix_case "srv.tls_only" FAIL "plain http answered $httpcode" product
      fi
   fi
else
   hix_case "srv.reachable" FAIL "nothing answering on $url - start it with webapp/go_gcc.sh"
fi

# --- app configuration invariants ------------------------------------------
admin=$(hix_cfg "$HIX_WEBAPP/hix.json" enabled)
hix_case "cfg.admin_panel" NOTE "hix.json admin.enabled=$admin"
store=$(hix_cfg "$HIX_WEBAPP/hix.json" storage)
crypt=$(hix_cfg "$HIX_WEBAPP/hix.json" crypt)
hix_case "cfg.session" NOTE "storage=$store crypt=$crypt"
if [ "$crypt" = "true" ]; then hix_case "cfg.session.crypt" PASS "crypt=true"
else hix_case "cfg.session.crypt" FAIL "crypt=$crypt - session payloads are plaintext" product; fi
env_app=$(hix_cfg "$HIX_WEBAPP/hix.json" env)
hix_case "cfg.app.env" NOTE "app.env=$env_app"

# --- digest -----------------------------------------------------------------
{
   echo "slice $HIX_SLICE - preflight"
   awk -F'\t' '{c[$3]++} END{for(k in c) printf "  %-6s %d\n", k, c[k]}' "$HIX_TSV"
   echo "  cases: $(wc -l < "$HIX_TSV")"
   awk -F'\t' '$3=="FAIL"{printf "  FAIL %s  %s\n", $2, $4}' "$HIX_TSV"
} | hix_digest

awk -F'\t' '$3=="FAIL"{n++} END{exit (n>0?1:0)}' "$HIX_TSV"
