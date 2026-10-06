#!/usr/bin/env bash
# ------------------------------------------------------------------
# index.sh - reprint the suite index from the recorded case rows.
#
#   ./tests/index.sh [--fail-only] [--budget N] [--full]
#
# Re-aggregates tests/.out/*.tsv with lib/index.awk, so it reflects the
# slices exactly as they last ran, without running anything.
# ------------------------------------------------------------------
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
. "$HERE/lib/common.sh"

fail_only=0 full=0
while [ $# -gt 0 ]; do
   case "$1" in
      --fail-only) fail_only=1; shift ;;
      --budget)    HIX_BUDGET=$2; shift 2 ;;
      --full)      full=1; shift ;;
      -h|--help)   sed -n '2,9p' "$0"; exit 0 ;;
      *) echo "index.sh: unknown option: $1" >&2; exit 2 ;;
   esac
done

tsvs=()
if [ -f "$HIX_OUT/rc.txt" ]; then
   while IFS=$'\t' read -r id tag rc secs; do
      f=$(hix_cases_file "$id"); [ -e "$f" ] && tsvs+=("$f")
   done < "$HIX_OUT/rc.txt"
fi
[ ${#tsvs[@]} -gt 0 ] || { echo "index.sh: nothing recorded in $HIX_OUT - run tests/run.sh first" >&2; exit 2; }

{
   echo "HIX TEST SUITE - index (recomputed $(date -Is) from $HIX_OUT)"
   echo "drill  tests/slice.sh <slice-id> [--cases|--log|--digest] [--status FAIL] [--class triage] [--budget N] [--full]"
   echo ""
   awk -F'\t' -v fail_only="$fail_only" -v rules="$HERE/lib/rules.tsv" \
       -f "$HERE/lib/index.awk" "$HIX_OUT/rc.txt" "${tsvs[@]}"
} | { [ "$full" = 1 ] && cat || "$HERE/lib/cap.sh" --budget "$HIX_BUDGET" --cols "$HIX_COLS" \
                            --marker "uncapped index: tests/.out/index.txt - or tests/index.sh --full"; }
