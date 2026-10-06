#!/usr/bin/env bash
# ------------------------------------------------------------------
# s10_fw_unit.sh - one slice of the HIX framework unit suite.
#
#   s10_fw_unit.sh <filter> [slice-id]
#
# Runs tests/unit/app in CLI mode with the test master's own substring
# filter (matched case-insensitively against "<Group>/<Test>"), so each
# invocation is one slice of the framework: Core, Routing, HixStyle,
# AUTH, Middleware, Transport, Network, Views, Other, Extras, and the
# three audit families A01 / A02 / A03.
#
# Raw CLI output -> $HIX_OUT/<id>.log ; parsed rows -> <id>.tsv.
# stdout is a capped digest.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

filter=${1:-}
[ -n "$filter" ] || { echo "usage: $(basename "$0") <filter> [slice-id]" >&2; exit 2; }

id=${2:-10-fw-$(printf '%s' "$filter" | tr -cs 'A-Za-z0-9' '-' | tr 'A-Z' 'a-z' | sed 's/^-*//;s/-*$//')}
hix_slice_init "$id"
hix_env_init

[ -x "$HIX_UNIT/app" ] || { hix_case "@abort" FAIL "tests/unit/app missing - run s05_build.sh --unit" env; exit 2; }

cd "$HIX_UNIT" || { hix_case "@abort" FAIL "cannot cd $HIX_UNIT" env; exit 2; }

# "all" means no filter argument: the test master treats an empty filter as
# "run everything", and a literal "*" matches nothing.
app_filter=$filter
[ "$filter" = "all" ] && app_filter=""

t0=$(date +%s)
hix_log "unit CLI filter='$filter' (substring match on Group/Test)"
timeout "$HIX_TIMEOUT" ./app --cli "$app_filter" > "$HIX_OUT/$id.raw" 2>&1
rc=$?
secs=$(( $(date +%s) - t0 ))
cp "$HIX_OUT/$id.raw" "$HIX_LOG"
hix_log "rc=$rc in ${secs}s raw=$(wc -c < "$HIX_LOG") bytes"

if [ "$rc" = 124 ]; then hix_case "@abort" FAIL "timeout after ${HIX_TIMEOUT}s" env; exit 2; fi

HIX_SLICE=$id hix_parse parse_unit.awk "$HIX_LOG"

if ! grep -q $'\t@totals\t' "$HIX_TSV"; then
   hix_case "@totals" ERROR "no totals line parsed - rc=$rc, see the log"
fi

n_tests=$(grep -cE $'\t(PASS|FAIL|ERROR|NOTE)\t' "$HIX_TSV" || true)
n_fail=$(awk -F'\t' '$3=="FAIL"' "$HIX_TSV" | wc -l)
n_err=$(awk -F'\t' '$3=="ERROR"' "$HIX_TSV" | wc -l)

{
   echo "slice $id - framework unit tests (filter=$filter) rc=$rc ${secs}s"
   grep $'\t@totals\t' "$HIX_TSV" | cut -f4 | sed 's/^/  totals: /'
   echo "  test rows: $(awk -F'\t' '$2!~/^@/{c++} END{print c+0}' "$HIX_TSV")" \
        "| failing rows: $n_fail | errors: $n_err | raw $(wc -c < "$HIX_LOG") bytes"
   echo "  --- per test ---"
   awk -F'\t' '$2!~/^@/{printf "  %-6s %s%s\n", $3, $2, ($4?"  ["$4"]":"")}' "$HIX_TSV"
} | hix_digest

[ "$n_fail" = 0 ] && [ "$n_err" = 0 ] && [ "$rc" = 0 ] && exit 0
exit 1
