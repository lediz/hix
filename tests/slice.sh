#!/usr/bin/env bash
# ------------------------------------------------------------------
# slice.sh - drill into the evidence of one slice, still capped.
#
#   ./tests/slice.sh <slice-id> [options]
#   ./tests/slice.sh --list
#
# Options
#   --cases        the parsed case rows (default when no view is given)
#   --log          the raw, uncapped evidence of the slice
#   --digest       the slice's own stdout digest as it ran
#   --status S     only rows with this status (PASS|FAIL|SKIP|ERROR|NOTE)
#   --class C      only rows of this class (product|triage|harness|tool|
#                  env|order) - what makes "is this a real failure?" a
#                  one-command question; --defect and --noise are shortcuts
#   --grep PAT     keep lines matching this regex (case-insensitive)
#   --head N       first N lines      --tail N   last N lines
#   --from L       start at line L    --lines N  take N lines from there
#   --budget N     byte budget for this view (default $HIX_BUDGET)
#   --full         no budget at all - you asked for it
#
# Every view goes through lib/cap.sh, so drilling in can never blow the
# window either: it just tells you what is still on disk.
# ------------------------------------------------------------------
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
. "$HERE/lib/common.sh"

view=""; status=""; class=""; grep_pat=""; headn=""; tailn=""; from=""; lines=""; full=0
id=${1:-}
[ $# -gt 0 ] && shift
if [ "$id" = "-h" ] || [ "$id" = "--help" ]; then sed -n '2,24p' "$0"; exit 0; fi

while [ $# -gt 0 ]; do
   case "$1" in
      --cases)  view=cases; shift ;;
      --log)    view=log; shift ;;
      --digest) view=digest; shift ;;
      --status) status=$2; shift 2 ;;
      --class)  class=$2;  shift 2 ;;
      --defect) class=product,triage; shift ;;
      --noise)  class=harness,tool,env,order; shift ;;
      --grep)   grep_pat=$2; shift 2 ;;
      --head)   headn=$2; shift 2 ;;
      --tail)   tailn=$2; shift 2 ;;
      --from)   from=$2; shift 2 ;;
      --lines)  lines=$2; shift 2 ;;
      --budget) HIX_BUDGET=$2; shift 2 ;;
      --full)   full=1; shift ;;
      -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
      *) echo "slice.sh: unknown option: $1" >&2; exit 2 ;;
   esac
done

if [ "$id" = "--list" ] || [ -z "$id" ]; then
   {
      echo "slices recorded in $HIX_OUT"
      for f in "$HIX_OUT"/*.tsv; do
         case "$f" in *.cls.tsv) continue ;; esac
         [ -e "$f" ] || continue
         s=$(basename "$f" .tsv)
         printf '  %-22s rows=%-5s log=%-8s digest=%-8s %s\n' "$s" "$(wc -l < "$f")" \
            "$( [ -f "$HIX_OUT/$s.log" ] && wc -c < "$HIX_OUT/$s.log" || echo 0 )B" \
            "$( [ -f "$HIX_OUT/$s.digest" ] && wc -c < "$HIX_OUT/$s.digest" || echo 0 )B" \
            "$(HIX_CLS="$(hix_cases_file "$s")" awk -F'\t' -f "$HERE/lib/count_class.awk" "$f")"
      done
   } | "$HERE/lib/cap.sh" --budget "$HIX_BUDGET" --cols "$HIX_COLS"
   exit 0
fi

[ -n "$view" ] || view=cases
if [ "$view" = cases ]; then src=$(hix_cases_file "$id"); else src="$HIX_OUT/$id.$( [ "$view" = log ] && echo log || echo digest )"; fi
[ -e "$src" ] || { echo "slice.sh: no $view for slice '$id' ($src missing). Try: tests/slice.sh --list" >&2; exit 2; }

rows() {   # case rows rendered as: STATUS  CLASS  case  detail  [basis]
   # the filters travel through the environment, not -v: awk resolves
   # escape sequences in -v assignments, so a pattern like 'gen\.' would
   # draw a warning and quietly become 'gen.'.
   HIX_STATUS_FILTER=$status HIX_CLASS_FILTER=$class HIX_GREP=$grep_pat awk -F'\t' '
      BEGIN { st = ENVIRON["HIX_STATUS_FILTER"]; cl = ENVIRON["HIX_CLASS_FILTER"]; p = ENVIRON["HIX_GREP"] }
      (st == "" || $3 == st) && (cl == "" || index("," cl ",", "," ($5 ? $5 : "triage") ",") > 0) \
         && (p == "" || $2 ~ p || $4 ~ p) {
         printf "%-6s %-8s %s  %s%s\n", $3, ($5 ? $5 : "-"), $2, $4, (NF >= 6 && $6 != "" ? "   [" $6 "]" : "")
      }' "$1"
}

{
   echo "slice $id - view=$view src=$src ($(wc -c < "$src") bytes, $(wc -l < "$src") lines)"
   if [ "$view" = cases ]; then
      awk -F'\t' '{c[$3]++} END{for(k in c) printf "  %-6s %d\n", k, c[k]}' "$src"
      awk -F'\t' '($3=="FAIL"||$3=="ERROR"){c[($5 ? $5 : "triage")]++} END{for(k in c) printf "  %-8s %d failing row(s)\n", k, c[k]}' "$src"
   fi
   if [ -n "$headn" ]; then { [ "$view" = cases ] && rows "$src" || cat "$src"; } | head -n "$headn"
   elif [ -n "$tailn" ]; then { [ "$view" = cases ] && rows "$src" || cat "$src"; } | tail -n "$tailn"
   elif [ -n "$from" ]; then { [ "$view" = cases ] && rows "$src" || cat "$src"; } | tail -n +"$from" | head -n "${lines:-100000}"
   else { [ "$view" = cases ] && rows "$src" || cat "$src"; }
   fi
} | { [ -n "$grep_pat" ] && grep -iE -- "$grep_pat" || cat; } \
    | "$HERE/lib/cap.sh" --budget "$HIX_BUDGET" --cols "$HIX_COLS" --ansi \
        --marker "uncapped: $src ($(wc -l < "$src") lines) - tests/slice.sh $id --$view --full"
