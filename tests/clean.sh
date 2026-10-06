#!/usr/bin/env bash
# ------------------------------------------------------------------
# clean.sh - remove what the suite itself produced. Nothing else.
#
#   ./tests/clean.sh            wipe tests/.out
#   ./tests/clean.sh --evidence also the harness run dirs the bf phases
#                             leave under webapp/.tmp_verify/bf
#
# It never touches the project's own build outputs, data files or
# certificates.
# ------------------------------------------------------------------
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
. "$HERE/lib/common.sh"

echo "removing $HIX_OUT ($(du -sh "$HIX_OUT" 2>/dev/null | cut -f1 || echo 0))"
rm -rf "$HIX_OUT"

if [ "${1:-}" = "--evidence" ]; then
   for d in "$HIX_WEBAPP/.tmp_verify/bf" "$HIX_WEBAPP/.tmp_verify"; do
      [ -d "$d" ] || continue
      echo "removing $d"
      rm -rf "$d"
   done
   for f in "$HIX_WEBAPP"/.tmp_probe_fmode; do
      [ -e "$f" ] && { echo "removing $f"; rm -rf "$f"; }
   done
fi
echo "done"
