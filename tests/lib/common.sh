# ------------------------------------------------------------------
# lib/common.sh - shared harness for the HIX test suite.
#
# Contract every slice follows:
#
#   raw evidence   $HIX_OUT/<id>.log      uncapped, on disk only
#   case rows      $HIX_OUT/<id>.tsv      id \t case \t status \t detail \t class
#   classified     $HIX_OUT/<id>.cls.tsv  ... \t class \t basis   (lib/classify.awk)
#   stdout         a capped digest, never more than $HIX_SLICE_BUDGET
#
# The 5th column of a slice's own rows is the class the slice *asserts*
# for it (product|env|tool|harness|order, empty = no claim). It is only a
# claim: lib/classify.awk has the final say, and a failure is moved out of
# the counted classes only when a check in tests/.out/checks.tsv proves
# the noise cause for this run.
#
# Nothing in this library writes to the repository: it only reads the
# tree, builds into the places the project's own build scripts build
# into, and puts everything it produces under tests/.out/.
#
# Source it from a slice:  . "$(dirname "$0")/../lib/common.sh"
# ------------------------------------------------------------------

HIX_TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HIX_ROOT=$(cd "$HIX_TESTS_DIR/.." && pwd)
HIX_WEBAPP="$HIX_ROOT/webapp"
HIX_UNIT="$HIX_ROOT/tests/unit"
HIX_OUT=${HIX_OUT_DIR:-$HIX_TESTS_DIR/.out}

HIX_BUDGET=${HIX_BUDGET:-65536}          # run.sh stdout budget
HIX_SLICE_BUDGET=${HIX_SLICE_BUDGET:-16384}   # one slice's own stdout budget
HIX_COLS=${HIX_COLS:-200}
HIX_TIMEOUT=${HIX_SLICE_TIMEOUT:-900}    # wall clock per slice (s)
HIX_CURL_CT=5
HIX_CURL_MT=20

HIX_SLICE="" HIX_LOG="" HIX_TSV="" HIX_SERVER_PID="" HIX_SERVER_OWNED=0
HIX_CLASS=""                       # class asserted by the slice for its next rows
HIX_REF_ID=09-fw-all               # the framework run everything is sliced from

# ------------------------------------------------------------------
# toolchain / environment
# ------------------------------------------------------------------
hix_env_init() {
   # Idempotent: run.sh and every slice call this, and the environment it
   # exports is inherited, so the path additions below are guarded against
   # being appended more than once (a doubled HB_INCLUDE is not a search
   # path any more, it is a broken one).
   [ -n "${HIX_ENV_INIT:-}" ] && return 0
   # Same resolution order as webapp/go_gcc.sh: HB_ROOT, then PATH, then
   # the usual build locations. Nothing here names a machine.
   : "${HB_ROOT:=$HOME/harbour-core}"
   if [ ! -x "$HB_ROOT/bin/linux/gcc/hbmk2" ] && command -v hbmk2 >/dev/null 2>&1; then
      local d
      d=$(cd "$(dirname "$(command -v hbmk2)")/../../.." 2>/dev/null && pwd)
      [ -x "$d/bin/linux/gcc/hbmk2" ] && HB_ROOT="$d"
   fi
   if [ ! -x "$HB_ROOT/bin/linux/gcc/hbmk2" ]; then
      local cand
      for cand in "$HOME/Projects/harbour" "$HOME/harbour" /opt/harbour; do
         if [ -x "$cand/bin/linux/gcc/hbmk2" ]; then HB_ROOT="$cand"; break; fi
      done
   fi
   export HB_ROOT
   case ":$PATH:" in *":$HB_ROOT/bin/linux/gcc:"*) : ;; *) export PATH="$HB_ROOT/bin/linux/gcc:$PATH" ;; esac
   case ":${HB_INCLUDE:-}:" in *":$HB_ROOT/include:"*) : ;; *) export HB_INCLUDE="$HB_ROOT/include${HB_INCLUDE:+:$HB_INCLUDE}" ;; esac
   # ${hix} in the .hbp files expands from this; the framework root is the repo root.
   if [ -z "${hix:-}" ] || [ ! -f "${hix:-/nonexistent}/hix_server.hbx" ]; then
      hix="$HIX_ROOT"
   fi
   export hix
   export HIX_ENV_INIT=1
}

hix_have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------
# slice bookkeeping
# ------------------------------------------------------------------
hix_slice_init() {
   HIX_SLICE=$1
   mkdir -p "$HIX_OUT"
   HIX_LOG=$HIX_OUT/$HIX_SLICE.log
   HIX_TSV=$HIX_OUT/$HIX_SLICE.tsv
   : > "$HIX_LOG"
   : > "$HIX_TSV"
}

# hix_case <case> <PASS|FAIL|SKIP|ERROR|NOTE> [detail] [class]
#   class defaults to $HIX_CLASS, so a slice can claim a class for a whole
#   block with hix_class and override it row by row.
hix_case() {
   local detail=${3-} cls=${4-${HIX_CLASS:-}}
   detail=${detail//$'\t'/ }
   detail=${detail//$'\n'/ }
   cls=${cls//$'\t'/ }
   cls=${cls//$'\n'/ }
   printf '%s\t%s\t%s\t%s\t%s\n' "$HIX_SLICE" "$1" "$2" "$detail" "$cls" >> "$HIX_TSV"
   return 0
}

# hix_class <product|env|tool|harness|order|''> - claim for later rows.
# Exported, so the parsers in lib/ can pick it up for whole suites.
hix_class() { HIX_CLASS=$1; export HIX_CLASS; }

# hix_check <check-id> <ok|fail> [evidence]
#   The evidence lib/classify.awk needs before a rule in lib/rules.tsv may
#   reclassify a failure as noise. Written for this run only.
hix_check() {
   local ev=${3-}
   ev=${ev//$'\t'/ }; ev=${ev//$'\n'/ }
   printf '%s\t%s\t%s\n' "$1" "$2" "$ev" >> "$HIX_OUT/checks.tsv"
   return 0
}

hix_log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$HIX_LOG"; }

# hix_run <label> <cmd...>  - time-bounded, evidence to the slice log
hix_run() {
   local label=$1; shift
   local t0=$(date +%s) rc=0
   hix_log "RUN $label: $*"
   if hix_have timeout; then
      timeout "$HIX_TIMEOUT" "$@" >> "$HIX_LOG" 2>&1
      rc=$?
   else
      "$@" >> "$HIX_LOG" 2>&1
      rc=$?
   fi
   hix_log "END $label: rc=$rc in $(( $(date +%s) - t0 ))s"
   return $rc
}

# capped digest for a slice's own stdout
hix_digest() {
   "$HIX_TESTS_DIR/lib/cap.sh" --budget "$HIX_SLICE_BUDGET" --cols "$HIX_COLS" \
      --marker "full evidence: $HIX_LOG (tests/slice.sh $HIX_SLICE --log)"
}

# ------------------------------------------------------------------
# reading the project's own config (hix.json is JSON-with-comments,
# so no JSON parser may be used on it)
# ------------------------------------------------------------------
hix_cfg() {   # hix_cfg <file> <key>  -> first scalar value for "key"
   grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[^],}]*" "$1" 2>/dev/null \
      | head -1 | sed -E "s/\"$2\"[[:space:]]*:[[:space:]]*//" | tr -d '"' | tr -d ' '
}

hix_app_port() { local p; p=$(hix_cfg "$HIX_WEBAPP/hix.json" port); echo "${p:-9090}"; }
hix_app_ssl()  { hix_cfg "$HIX_WEBAPP/hix.json" ssl; }

hix_api_url() {
   if [ -n "${HIX_API:-}" ]; then printf '%s' "$HIX_API"; return; fi
   local scheme=http
   [ "$(hix_app_ssl)" = "true" ] && scheme=https
   printf '%s://localhost:%s' "$scheme" "$(hix_app_port)"
}

# The app's own certificate is the trust anchor, so the pre-existing
# suites (which call curl without -k) work against the TLS-only server
# without being edited: curl reads CURL_CA_BUNDLE from the environment.
hix_curl_trust() {
   local c
   for c in "$HIX_WEBAPP/certs/hix.crt" "$HIX_WEBAPP/certs/hix.pem"; do
      [ -f "$c" ] && { export CURL_CA_BUNDLE="$c"; return 0; }
   done
   return 1
}

hix_server_up() {
   local url=${1:-$(hix_api_url)}
   curl -s --connect-timeout "$HIX_CURL_CT" --max-time "$HIX_CURL_MT" -o /dev/null "$url/login" 2>/dev/null
}

# Start webapp/app if nothing answers yet. Never kills a server it did
# not start; a foreign listener on the app's port is reused and noted.
hix_server_start() {
   local url; url=$(hix_api_url)
   if hix_server_up "$url"; then
      HIX_SERVER_OWNED=0
      return 0
   fi
   [ -x "$HIX_WEBAPP/app" ] || return 1
   ( cd "$HIX_WEBAPP" && umask 077 && exec ./app ) >> "$HIX_OUT/server.log" 2>&1 &
   HIX_SERVER_PID=$!
   HIX_SERVER_OWNED=1
   local i
   for i in $(seq 1 30); do
      hix_server_up "$url" && return 0
      sleep 1
   done
   return 1
}

hix_server_stop() {
   [ "${HIX_SERVER_OWNED:-0}" = "1" ] || return 0
   [ -n "${HIX_SERVER_PID:-}" ] || return 0
   kill "$HIX_SERVER_PID" 2>/dev/null
   sleep 1
   kill -9 "$HIX_SERVER_PID" 2>/dev/null
   HIX_SERVER_PID=""
}

# ------------------------------------------------------------------
# shared parsers (lib/*.awk)
# ------------------------------------------------------------------
hix_parse() {   # hix_parse <parser.awk> <raw-file>
   awk -F'\t' -f "$HIX_TESTS_DIR/lib/$1" "$2" >> "$HIX_TSV"
}

# ------------------------------------------------------------------
# classification
# ------------------------------------------------------------------
# hix_classify <slice-id>...  - turn <id>.tsv into <id>.cls.tsv, which
# carries the final class plus the basis it was decided on. The reference
# run ($HIX_REF_ID) is what lets a group-slice failure be called an
# artifact of slicing rather than a defect.
hix_classify() {
   local id src out ref="$HIX_OUT/$HIX_REF_ID.tsv" saw_ref=0
   # the reference only counts when it ran in *this* run: a .tsv left over
   # from an earlier one would let a group-slice failure be called "order"
   # on evidence this run never recorded
   for id in "$@"; do [ "$id" = "$HIX_REF_ID" ] && saw_ref=1; done
   { [ "$saw_ref" = 1 ] && [ -f "$ref" ]; } || ref=""
   for id in "$@"; do
      src=$HIX_OUT/$id.tsv
      [ -f "$src" ] || continue
      out=$HIX_OUT/$id.cls.tsv
      awk -F'\t' -v rules="$HIX_TESTS_DIR/lib/rules.tsv" -v checks="$HIX_OUT/checks.tsv" \
              -v ref="$ref" -v refid="$HIX_REF_ID" \
          -f "$HIX_TESTS_DIR/lib/classify.awk" "$src" > "$out.tmp" \
         && mv "$out.tmp" "$out" \
         || rm -f "$out.tmp"
   done
}

# hix_cases_file <slice-id> - the rows to read: classified when available
hix_cases_file() {
   local f="$HIX_OUT/$1.cls.tsv"
   [ -f "$f" ] || f="$HIX_OUT/$1.tsv"
   printf '%s' "$f"
}
