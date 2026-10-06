#!/usr/bin/env bash
# ------------------------------------------------------------------
# s21_wa_bf.sh - one brute-force / penetration phase, run unmodified.
#
#   s21_wa_bf.sh bf01|bf02|...|bf10
#
# webapp/test/bf_harness.sh is the project's own harness; it is already
# phase-sliced and rate-limit aware, so one phase is one slice. Verdicts
# are read from the harness's own verdicts.txt (its stdout is noisier).
#
# These phases are slow (they wait out the login rate-limit window) and
# they write rows into the app's data files, so they are opt-in: run.sh
# only plans them with --bf.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

phase=${1:-}
case "$phase" in
   bf01|bf02|bf03|bf04|bf05|bf06|bf07|bf08|bf09|bf10) : ;;
   *) echo "usage: $(basename "$0") bf01..bf10" >&2; exit 2 ;;
esac
hix_slice_init "${SLICE_ID:-40-wa-$phase}"   # run.sh numbers them 40..49
hix_env_init
hix_curl_trust || true

cd "$HIX_WEBAPP" || { hix_case "@abort" FAIL "cannot cd $HIX_WEBAPP" env; exit 2; }
url=$(hix_api_url)
hix_server_up "$url" || { hix_case "@abort" FAIL "no HIX app answering on $url" env; exit 2; }

run_dir=".tmp_verify/bf/$(date +%Y%m%d-%H%M%S)-$HIX_SLICE"
export BF_API="$url"
export BF_RUN_DIR="$run_dir"

t0=$(date +%s)
hix_log "bf_harness.sh $phase (BF_RUN_DIR=$run_dir)"
timeout "$HIX_TIMEOUT" bash test/bf_harness.sh "$phase" > "$HIX_OUT/$HIX_SLICE.raw" 2>&1
rc=$?
secs=$(( $(date +%s) - t0 ))
cp "$HIX_OUT/$HIX_SLICE.raw" "$HIX_LOG"
hix_log "rc=$rc in ${secs}s raw=$(wc -c < "$HIX_LOG") bytes"

[ "$rc" = 124 ] && { hix_case "@abort" FAIL "timeout after ${HIX_TIMEOUT}s" env; exit 2; }

verdicts="$HIX_WEBAPP/$run_dir/verdicts.txt"
hix_class env
if [ -f "$verdicts" ]; then
   hix_class ""
   HIX_SLICE=$HIX_SLICE HIX_PARSE_MODE=bf hix_parse parse_wa.awk "$verdicts"
   njsonl=$(cat "$HIX_WEBAPP/$run_dir"/*.jsonl 2>/dev/null | wc -l)
   hix_case "@evidence" NOTE "verdicts=$(wc -l < "$verdicts") request_jsonl=$njsonl dir=$run_dir"
else
   hix_case "@abort" FAIL "harness produced no verdicts.txt (rc=$rc)" env
   hix_class ""
   HIX_SLICE=$HIX_SLICE HIX_PARSE_MODE=bf hix_parse parse_wa.awk "$HIX_LOG"
fi

{
   echo "slice $HIX_SLICE - brute-force phase $phase rc=$rc ${secs}s"
   echo "  verdicts: $(awk -F'\t' '$2!~/^@/{c++} END{print c+0}' "$HIX_TSV")" \
        "| PASS $(awk -F'\t' '$3=="PASS"{c++} END{print c+0}' "$HIX_TSV")" \
        "| FAIL $(awk -F'\t' '$3=="FAIL"{c++} END{print c+0}' "$HIX_TSV")" \
        "| NOTE $(awk -F'\t' '$3=="NOTE"{c++} END{print c+0}' "$HIX_TSV")"
   awk -F'\t' '$2!~/^@/{printf "  %-9s %s  %s\n", $3, $2, $4}' "$HIX_TSV"
} | hix_digest

awk -F'\t' '$3=="FAIL"{n++} END{exit (n>0?1:0)}' "$HIX_TSV"
