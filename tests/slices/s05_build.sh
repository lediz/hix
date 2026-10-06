#!/usr/bin/env bash
# ------------------------------------------------------------------
# s05_build.sh - build (or only check) the three artifacts the suite runs.
#
#   s05_build.sh --check          verify presence + staleness, no compiling
#   s05_build.sh --fw             go_lib_gcc.sh        (hix_server.hbx + libhix_server.a)
#   s05_build.sh --unit           tests/unit/go_gcc.sh (the unit-test binary)
#   s05_build.sh --app            webapp/go_gcc.sh     (the CRUD app)
#   s05_build.sh --all            fw, then unit, then app
#
# Compiling is deliberately opt-in: it is slow, and a build failure must
# not be confused with a test failure. Evidence goes to the slice log.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
hix_slice_init "${SLICE_ID:-05-build}"
hix_env_init
hix_class env        # a build or artifact problem is the state of the tree,
                     # never a verdict on the code under test

what=${1:---check}
rc_total=0

build_one() {   # build_one <label> <dir> <cmd...>
   local label=$1 dir=$2; shift 2
   local t0=$(date +%s) rc
   hix_log "building $label in $dir: $*"
   ( cd "$dir" && "$@" ) >> "$HIX_LOG" 2>&1
   rc=$?
   local errs; errs=$(grep -ciE '^Error|error E[0-9]+|undefined reference' "$HIX_LOG" 2>/dev/null || echo 0)
   if [ "$rc" = 0 ] && [ "$errs" = 0 ]; then
      hix_case "build.$label" PASS "rc=0 in $(( $(date +%s) - t0 ))s"
   else
      hix_case "build.$label" FAIL "rc=$rc errors=$errs in $(( $(date +%s) - t0 ))s"
      rc_total=1
   fi
}

case "$what" in
   --check)
      [ -f "$HIX_ROOT/hix_server.hbx" ] && hix_case "art.fw.hbx" PASS || hix_case "art.fw.hbx" FAIL "missing"
      ls "$HIX_ROOT"/lib/*/libhix_server.a >/dev/null 2>&1 && hix_case "art.fw.lib" PASS || hix_case "art.fw.lib" FAIL "missing"
      [ -x "$HIX_UNIT/app" ] && hix_case "art.unit.bin" PASS || hix_case "art.unit.bin" FAIL "missing"
      # The framework is stale when a source is newer than the newest of the
      # two artifacts go_lib_gcc.sh produces (an incremental build refreshes
      # the .a but not the .hbx).
      ref=$(ls -t "$HIX_ROOT/hix_server.hbx" "$HIX_ROOT"/lib/*/libhix_server.a 2>/dev/null | head -1)
      n=$(find "$HIX_ROOT/src" -name '*.prg' -newer "${ref:-$HIX_ROOT/hix_server.hbx}" 2>/dev/null | wc -l)
      [ "$n" = 0 ] && hix_case "art.fw.stale" PASS "reference $(basename "${ref:-none}")" \
                   || hix_case "art.fw.stale" FAIL "$n src/*.prg newer than $(basename "${ref:-hix_server.hbx}")"
      n=$(find "$HIX_UNIT/src" -name '*.prg' -newer "$HIX_UNIT/app" 2>/dev/null | wc -l)
      [ "$n" = 0 ] && hix_case "art.unit.stale" PASS || hix_case "art.unit.stale" FAIL "$n tests/unit/src/*.prg newer than the binary"
      n=$(find "$HIX_WEBAPP/src" "$HIX_WEBAPP/www" -name '*.prg' -newer "$HIX_WEBAPP/app" 2>/dev/null | wc -l)
      [ "$n" = 0 ] && hix_case "art.app.stale" PASS || hix_case "art.app.stale" FAIL "$n app .prg newer than webapp/app"
      ;;
   # The compile step of each project's own go_*.sh, without the "then run
   # it" half: go_gcc.sh execs the server, and the unit go_gcc.sh would run
   # the whole unit suite. hbmk2 is on PATH from hix_env_init.
   --fw)   build_one fw   "$HIX_ROOT"   ./go_lib_gcc.sh ;;
   --unit) build_one unit "$HIX_UNIT"  hbmk2 app.hbp ;;
   --app)  build_one app  "$HIX_WEBAPP" hbmk2 app.hbp ;;
   --all)
      build_one fw   "$HIX_ROOT"   ./go_lib_gcc.sh
      build_one unit "$HIX_UNIT"  hbmk2 app.hbp
      build_one app  "$HIX_WEBAPP" hbmk2 app.hbp
      ;;
   *) hix_case "build.usage" FAIL "unknown mode: $what"; rc_total=2 ;;
esac

{
   echo "slice $HIX_SLICE - build ($what)"
   cat "$HIX_TSV" | awk -F'\t' '{printf "  %-6s %s  %s\n", $3, $2, $4}'
   if [ -s "$HIX_LOG" ]; then
      echo "--- build log tail (full: tests/slice.sh $HIX_SLICE --log) ---"
      tail -25 "$HIX_LOG"
   fi
} | hix_digest

exit $rc_total
