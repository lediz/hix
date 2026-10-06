#!/usr/bin/env bash
# ------------------------------------------------------------------
# s22_wa_probe.sh - one webapp probe binary, asserted on its own output.
#
#   s22_wa_probe.sh entropy | hash | pwcost | fmode | seek
#
# The probes are Harbour console programs: they paint a full-screen GT,
# so they are run with TERM=dumb and every CSI sequence is stripped
# before anything is matched. The stripped text is kept in the slice log
# (uncapped) - stdout only carries the assertions.
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

which_probe=${1:-}
case "$which_probe" in
   entropy|hash|pwcost|fmode|seek) : ;;
   *) echo "usage: $(basename "$0") entropy|hash|pwcost|fmode|seek" >&2; exit 2 ;;
esac
hix_slice_init "${SLICE_ID:-34-wa-probe-$which_probe}"   # run.sh numbers them 34..38
hix_env_init

bin="$HIX_WEBAPP/probe_$which_probe"
[ -x "$bin" ] || { hix_case "@abort" FAIL "$bin missing - build it with hbmk2 probe_$which_probe.hbp" env; exit 2; }

cd "$HIX_WEBAPP" || exit 2
t0=$(date +%s)
TERM=dumb timeout 120 "./probe_$which_probe" > "$HIX_OUT/$HIX_SLICE.raw" 2>&1
rc=$?
secs=$(( $(date +%s) - t0 ))
LC_ALL=C sed -e 's/\x1b\[[0-9;:?]*[a-zA-Z]//g' -e 's/\x1b([A-Z]//g' -e 's/\x1b//g' -e 's/\r//g' \
   "$HIX_OUT/$HIX_SLICE.raw" | tr -s ' ' > "$HIX_LOG"
hix_log "probe_$which_probe rc=$rc in ${secs}s raw=$(wc -c < "$HIX_OUT/$HIX_SLICE.raw")B stripped=$(wc -c < "$HIX_LOG")B"
hix_case "@probe.rc" NOTE "rc=$rc ${secs}s raw=$(wc -c < "$HIX_OUT/$HIX_SLICE.raw")B stripped=$(wc -c < "$HIX_LOG")B"

want() {   # want <case> <regex>
   if grep -qE "$2" "$HIX_LOG"; then hix_case "$1" PASS "matched /$2/"
   else hix_case "$1" FAIL "no match for /$2/" product; fi
}
tell() {   # tell <case> <regex> - evidence, not a verdict
   local v; v=$(grep -oE "$2" "$HIX_LOG" | head -1)
   hix_case "$1" NOTE "${v:-<no match: $2>}"
}
tellall() { # tellall <case> <regex> - up to 5 matches, one NOTE row
   local v; v=$(grep -oE "$2" "$HIX_LOG" | head -5 | tr '\n' ' ')
   hix_case "$1" NOTE "${v:-<no match: $2>}"
}

case "$which_probe" in
   entropy)
      want  entropy.rndstr_linked   'hb_RandStr linked:[[:space:]]*\.T\.'
      want  entropy.no_malformed    'malformed[[:space:]]*:[[:space:]]*0'
      want  entropy.no_duplicates   'duplicates[[:space:]]*:[[:space:]]*0'
      tell  entropy.seeds           'seeds generated[[:space:]]*:[[:space:]]*[0-9]+'
      tell  entropy.unique          'unique[[:space:]]*:[[:space:]]*[0-9]+'
      tell  entropy.hex_bias        "first-hex '0'[[:space:]]*:[[:space:]]*[0-9]+"
      ;;
   hash)
      want  hash.sha256_len  'sha256 len=[[:space:]]*64'
      want  hash.md5_len     'md5 len=[[:space:]]*32'
      tell  hash.md5_val     'val=[0-9a-f]{32}'
      ;;
   pwcost)
      want  pwcost.table          'iterations'
      tell  pwcost.cheapest       '1000[0-9a-f]{32}[0-9.]+'
      tell  pwcost.priciest       '50000[0-9a-f]{32}[0-9.]+'
      ;;
   fmode)
      tell  fmode.chmod_from_harbour 'change mode from Harbour[^-]*'
      tellall fmode.modes_seen       '\.tmp_probe_fmode/m[0-9]{4}'
      tell  fmode.dir_listing        'no dir entry'
      ;;
   seek)
      want  seek.exact_admin     "seek 'admin' -> NAME='admin'[[:space:]]*exactmatch=YES"
      want  seek.partial_carle   "seek 'carle' -> NAME='carlesX'[[:space:]]*exactmatch=NO"
      want  seek.missing_nobody  "seek 'nobody' -> no record"
      tell  seek.residue_rows    'NAME=(zbf|zverify)[0-9]*'
      ;;
esac

{
   echo "slice $HIX_SLICE - probe_$which_probe rc=$rc ${secs}s"
   awk -F'\t' '$2!~/^@/{printf "  %-6s %-24s %s\n", $3, $2, $4}' "$HIX_TSV"
   echo "  --- stripped probe output, first 400 bytes (full: tests/slice.sh $HIX_SLICE --log) ---"
   head -c 400 "$HIX_LOG"; echo
} | hix_digest

awk -F'\t' '$3=="FAIL"{n++} END{exit (n>0?1:0)}' "$HIX_TSV"
