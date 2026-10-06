#!/usr/bin/env bash
# ------------------------------------------------------------------
# cap.sh - bound any stream so it always fits a fixed byte budget.
#
# This is what makes the suite "sliceable": every script's stdout is
# produced through cap.sh, so a run can never overflow the context
# window it is being read from. The full, uncapped evidence always
# stays on disk under tests/.out/ and is fetched with tests/slice.sh.
#
# Usage:  some-command | ./cap.sh [--budget N] [--cols N]
#                                [--head|--tail|--both] [--ansi]
#                                [--marker TEXT]
#
#   --budget N   max bytes written to stdout (default 65536)
#   --cols N     truncate each line to N bytes (default 200, 0 = off)
#   --head       keep the first lines only
#   --tail       keep the last lines only
#   --both       keep a head and a tail slice (default, 70/30)
#   --ansi       strip ANSI/CSI escape sequences from the input
#   --marker T   text appended to the truncation notice (how to drill in)
#
# Byte counting is done with LC_ALL=C so "bytes" really means bytes.
# Everything cap.sh emits goes to stdout - report line first, then the
# body - because a report on stderr races with a block-buffered stdout
# and can splice itself into the middle of the last line when both
# streams are captured together. The truncation notice is part of the
# body and is counted against the budget.
# ------------------------------------------------------------------
set -uo pipefail

budget=65536 cols=200 headpct=70 marker="" strip_ansi=0

while [ $# -gt 0 ]; do
   case "$1" in
      --budget) budget=$2; shift 2 ;;
      --cols)   cols=$2;   shift 2 ;;
      --head)   headpct=100; shift ;;
      --tail)   headpct=0;   shift ;;
      --both)   headpct=70;  shift ;;
      --ansi)   strip_ansi=1; shift ;;
      --marker) marker=$2; shift 2 ;;
      -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
      *) echo "cap.sh: unknown option: $1" >&2; exit 2 ;;
   esac
done

LC_ALL=C awk -v budget="$budget" -v cols="$cols" -v headpct="$headpct" \
             -v marker="$marker" -v sansi="$strip_ansi" '
function clip(s) {
   if (cols > 0 && length(s) > cols) return substr(s, 1, cols - 3) "..."
   return s
}
{ raw[++n] = $0 }
END {
   tot = 0
   for (i = 1; i <= n; i++) {
      s = raw[i]
      gsub(/\r/, "", s)
      if (sansi) { gsub(/\033\[[0-9;:?]*[a-zA-Z]/, "", s)          # CSI ... final byte
                   gsub(/\033\][^\007]*\007/, "", s)               # OSC ... BEL
                   gsub(/\033\([A-Z]/, "", s)                        # charset selection
                   gsub(/\033/, "", s) }
      gsub(/[\000-\010\013\014\016-\037]/, "", s)          # control chars, tabs kept
      s = clip(s)
      L[i] = s; B[i] = length(s) + 1; tot += B[i]
   }
   # the report line is part of stdout, so it is counted too: the promise
   # is that nothing cap.sh emits exceeds --budget, not just the body.
   report = sprintf("[cap] %d lines / %d bytes - within the %d byte budget\n", n, tot, budget)
   if (tot + length(report) <= budget) {
      printf "%s", report
      for (i = 1; i <= n; i++) print L[i]
      exit 0
   }
   note = sprintf(">>> TRUNCATED by cap.sh: %d of %d lines elided (%d of %d bytes).", 0, n, 0, tot)
   if (marker != "") note = note " " marker
   report = sprintf("[cap] %d lines / %d bytes -> capped to %d bytes\n", n, tot, budget)
   if (length(report) + length(note) + 2 > budget) {   # not even the notices fit
      print substr(report, 1, budget - 1)
      exit 0
   }
   reserve = length(note) + length(report) + 10
   avail = budget - reserve; if (avail < 0) avail = 0
   hb = int(avail * headpct / 100); tb = avail - hb

   i = 0;   acc = 0;  while (i < n && acc + B[i+1] <= hb) { i++;   acc += B[i] }
   headend = i
   j = n+1; acc2 = 0; while (j > 1 && acc2 + B[j-1] <= tb) { j--;  acc2 += B[j] }
   tailstart = j

   printf "%s", report
   if (tailstart <= headend + 1) {                        # overlap: head only
      k = 0; acc = 0
      while (k < n && acc + B[k+1] <= budget - reserve) { k++; acc += B[k] }
      for (i = 1; i <= k; i++) print L[i]
      printf ">>> TRUNCATED by cap.sh: %d of %d lines elided (%d of %d bytes).%s\n", \
             n - k, n, tot - acc, tot, (marker != "" ? " " marker : "")
   } else {
      for (i = 1; i <= headend; i++) print L[i]
      printf ">>> TRUNCATED by cap.sh: %d of %d lines elided (%d of %d bytes).%s\n", \
             tailstart - headend - 1, n, tot - acc - acc2, tot, (marker != "" ? " " marker : "")
      for (i = tailstart; i <= n; i++) print L[i]
   }
}'
