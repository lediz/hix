#!/usr/bin/env bash
# ------------------------------------------------------------------
# run.sh - the whole HIX suite, sliced so its stdout fits a context window.
#
#   ./tests/run.sh [options] [slice-id ...]
#
# Options
#   --fw            framework slices only (tests/unit, CLI mode)
#   --no-fw-ref     skip the reference run (the whole unit suite in one
#                   process). Without it, framework failures that only
#                   appear when a group is sliced out cannot be told apart
#                   from real ones, so they stay counted.
#   --wa            webapp slices only (functional + probes + hygiene)
#   --bf            add the 10 brute-force phases (slow, rate-limit aware)
#   --build         compile framework / unit binary / app before running
#   --no-server     never start webapp/app (assume one is already running)
#   --fresh         wipe tests/.out first
#   --list          print the slice plan and exit
#   --full          uncapped index on stdout (ignore --budget)
#   --fail-only     index lists failing cases only
#   --strict        also fail on failures attributed to harness/tool/env
#   --budget N      stdout byte budget            (default 65536)
#   --timeout N     wall clock per slice, seconds (default 900)
#   -h, --help      this header
#
# How the slicing works
#   * every slice writes uncapped evidence to tests/.out/<id>.log and
#     one TSV row per case to tests/.out/<id>.tsv;
#   * lib/classify.awk turns each of those into <id>.cls.tsv, adding the
#     class of every failure and the basis it was decided on;
#   * run.sh aggregates only the slices that ran in this run into
#     tests/.out/index.txt (uncapped);
#   * stdout is index.txt passed through lib/cap.sh, so the run never
#     emits more than --budget bytes;
#   * anything elided is fetched with tests/slice.sh <id> [--log|--cases].
#
# How a failure stops being a defect
#   A failure is counted ("defect") unless something explains it, and the
#   explanation has to be evidence, not a guess:
#     order    the same case passes in the reference run, so it broke only
#              because the framework suite was sliced up
#     harness  the project's own test script is what is wrong
#     tool     an external tool is missing or is Windows-only
#     env      machine, config or leftover-state, not the code
#   Each demotion is a row in lib/rules.tsv and every rule cites a check
#   that slices/s07_harness.sh re-proves on this tree for this run. A rule
#   whose check no longer holds is inert and its failures come back.
#   Anything no rule explains is class "triage": still counted, and
#   listed separately so it cannot be mistaken for noise.
#
# Exit codes: 0 no defect, 1 a defect (or noise, with --strict),
#             2 a slice could not run.
# ------------------------------------------------------------------
set -uo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
. "$HERE/lib/common.sh"

do_fw=1 do_wa=1 do_bf=0 do_build=0 do_server=1 do_fresh=0 do_list=0 do_full=0 fail_only=0 do_fw_ref=1 do_strict=0
only=()

while [ $# -gt 0 ]; do
   case "$1" in
      --fw)        do_fw=1; do_wa=0; shift ;;
      --fw-ref)    do_fw_ref=1; shift ;;
      --no-fw-ref) do_fw_ref=0; shift ;;
      --wa)        do_wa=1; do_fw=0; shift ;;
      --bf)        do_bf=1; shift ;;
      --build)     do_build=1; shift ;;
      --no-server) do_server=0; shift ;;
      --fresh)     do_fresh=1; shift ;;
      --list)      do_list=1; shift ;;
      --full)      do_full=1; shift ;;
      --fail-only) fail_only=1; shift ;;
      --strict)    do_strict=1; shift ;;
      --budget)    HIX_BUDGET=$2; shift 2 ;;
      --timeout)   HIX_TIMEOUT=$2; shift 2 ;;
      -h|--help)   sed -n '2,53p' "$0"; exit 0 ;;
      -*)          echo "run.sh: unknown option: $1" >&2; exit 2 ;;
      *)           only+=("$1"); shift ;;
   esac
done

hix_env_init
mkdir -p "$HIX_OUT"
[ "$do_fresh" = 1 ] && rm -rf "$HIX_OUT"
mkdir -p "$HIX_OUT"
RUN_LOG=$HIX_OUT/run.log
: > "$RUN_LOG"

# ------------------------------------------------------------------
# the plan: id | tag | slice-script [args...]
# ------------------------------------------------------------------
PLAN=()
add() { PLAN+=("$1|$2|$3"); }

[ "$do_build" = 1 ] && { add 01-build-fw fw "$HERE/slices/s05_build.sh --fw"; add 02-build-unit fw "$HERE/slices/s05_build.sh --unit"; add 03-build-app wa "$HERE/slices/s05_build.sh --app"; }
add 00-preflight env "$HERE/slices/s00_preflight.sh"
add 05-artifacts env "$HERE/slices/s05_build.sh --check"
add 07-harness   env "$HERE/slices/s07_harness.sh"

if [ "$do_fw" = 1 ]; then
   # The reference run: the whole unit suite in one process, exactly what
   # tests/unit/go_gcc.sh --cli does. Some unit tests depend on state an
   # earlier test leaves behind, so a group slice run on its own can report
   # ERROR where the reference run reports ok - lib/classify.awk only calls
   # that artifact "order" when this run recorded the reference. Skip it
   # with --no-fw-ref and every framework failure stays counted.
   [ "$do_fw_ref" = 1 ] && add 09-fw-all ref "$HERE/slices/s10_fw_unit.sh all 09-fw-all"
   add 10-fw-core       fw "$HERE/slices/s10_fw_unit.sh Core 10-fw-core"
   add 11-fw-routing    fw "$HERE/slices/s10_fw_unit.sh Routing 11-fw-routing"
   add 12-fw-hixstyle   fw "$HERE/slices/s10_fw_unit.sh HixStyle 12-fw-hixstyle"
   add 13-fw-auth       fw "$HERE/slices/s10_fw_unit.sh AUTH 13-fw-auth"
   add 14-fw-mw         fw "$HERE/slices/s10_fw_unit.sh Middleware 14-fw-mw"
   add 15-fw-transport  fw "$HERE/slices/s10_fw_unit.sh Transport 15-fw-transport"
   add 16-fw-network    fw "$HERE/slices/s10_fw_unit.sh Network 16-fw-network"
   add 17-fw-views      fw "$HERE/slices/s10_fw_unit.sh Views 17-fw-views"
   add 18-fw-other      fw "$HERE/slices/s10_fw_unit.sh Other 18-fw-other"
   add 19-fw-extras     fw "$HERE/slices/s10_fw_unit.sh Extras 19-fw-extras"
   add 20-fw-audit-a01  fw "$HERE/slices/s10_fw_unit.sh A01 20-fw-audit-a01"
   add 21-fw-audit-a02  fw "$HERE/slices/s10_fw_unit.sh A02 21-fw-audit-a02"
   add 22-fw-audit-a03  fw "$HERE/slices/s10_fw_unit.sh A03 22-fw-audit-a03"
fi

if [ "$do_wa" = 1 ]; then
   add 30-repo            wa "$HERE/slices/s30_repo.sh"
   add 31-wa-users        wa "$HERE/slices/s20_wa_http.sh users"
   add 32-wa-customer     wa "$HERE/slices/s20_wa_http.sh customer"
   add 33-wa-verify       wa "$HERE/slices/s20_wa_http.sh verify"
   add 34-wa-probe-entropy wa "$HERE/slices/s22_wa_probe.sh entropy"
   add 35-wa-probe-hash    wa "$HERE/slices/s22_wa_probe.sh hash"
   add 36-wa-probe-pwcost  wa "$HERE/slices/s22_wa_probe.sh pwcost"
   add 37-wa-probe-fmode   wa "$HERE/slices/s22_wa_probe.sh fmode"
   add 38-wa-probe-seek    wa "$HERE/slices/s22_wa_probe.sh seek"
fi

if [ "$do_bf" = 1 ]; then
   n=40
   for p in bf01 bf02 bf03 bf04 bf05 bf06 bf07 bf08 bf09 bf10; do
      add "$n-wa-$p" bf "$HERE/slices/s21_wa_bf.sh $p"
      n=$((n+1))
   done
fi

selected() {
   local id=$1 tag=$2
   # the environment slices are never optional: preflight says what the run
   # can trust at all, and 07-harness is what any demotion rests on
   [ "$tag" = env ] && return 0
   [ ${#only[@]} -eq 0 ] && return 0
   local o
   for o in "${only[@]}"; do [ "$o" = "$id" ] && return 0; done
   return 1
}

# a requested id that is not in the plan is a typo, not an empty selection
for o in ${only[@]+"${only[@]}"}; do
   hit=0
   for entry in "${PLAN[@]}"; do [ "${entry%%|*}" = "$o" ] && hit=1; done
   [ "$hit" = 1 ] || echo "run.sh: no such slice id: $o  (tests/run.sh --list)" >&2
done

if [ "$do_list" = 1 ]; then
   {
      echo "slice plan (${#PLAN[@]} entries) - stdout budget $HIX_BUDGET bytes, per-slice timeout ${HIX_TIMEOUT}s"
      printf '%s\n' "${PLAN[@]}" | awk -F'|' '{printf "  %-20s %-4s %s\n", $1, $2, $3}'
      echo "  run one:  tests/run.sh <slice-id>      drill in:  tests/slice.sh <slice-id> --log"
   } | "$HERE/lib/cap.sh" --budget "$HIX_BUDGET" --cols "$HIX_COLS"
   exit 0
fi

# ------------------------------------------------------------------
# server lifecycle
# ------------------------------------------------------------------
cleanup() { hix_server_stop; }
trap cleanup EXIT INT TERM

if [ "$do_wa" = 1 ] || [ "$do_bf" = 1 ]; then
   hix_curl_trust || true
   if [ "$do_server" = 1 ]; then
      if hix_server_up; then
         echo "reusing the HIX app already answering on $(hix_api_url)" >> "$RUN_LOG"
      elif hix_server_start; then
         echo "started webapp/app pid $HIX_SERVER_PID on $(hix_api_url)" >> "$RUN_LOG"
      else
         echo "could not start webapp/app on $(hix_api_url) - webapp slices will abort" >> "$RUN_LOG"
      fi
   fi
fi

# ------------------------------------------------------------------
# run the slices
# ------------------------------------------------------------------
t_run0=$(date +%s)
: > "$HIX_OUT/rc.txt"
for entry in "${PLAN[@]}"; do
   id=${entry%%|*}
   rest=${entry#*|}
   tag=${rest%%|*}
   cmd=${rest#*|}
   selected "$id" "$tag" || continue
   printf '%s' "$(date +%H:%M:%S) RUN $id ($tag): $cmd" >> "$RUN_LOG"; echo >> "$RUN_LOG"
   t0=$(date +%s)
   script=${cmd%% *}
   args=${cmd#* }
   [ "$args" = "$cmd" ] && args=""
   SLICE_ID=$id HIX_TIMEOUT=$HIX_TIMEOUT HIX_OUT_DIR="$HIX_OUT" \
      timeout $((HIX_TIMEOUT + 60)) bash "$script" $args > "$HIX_OUT/$id.digest" 2>&1
   rc=$?
   secs=$(( $(date +%s) - t0 ))
   echo "  -> rc=$rc ${secs}s digest=$(wc -c < "$HIX_OUT/$id.digest")B" >> "$RUN_LOG"
   printf '%s\t%s\t%s\t%s\n' "$id" "$tag" "$rc" "$secs" >> "$HIX_OUT/rc.txt"
done

# ------------------------------------------------------------------
# classify, then aggregate
#
# Only the slices that ran in this run are aggregated: a stale .tsv from
# an earlier run in the same tests/.out is noise of exactly the kind this
# suite is about, so it is never folded into the index.
# ------------------------------------------------------------------
ids=()
while IFS=$'\t' read -r id tag rc secs; do ids+=("$id"); done < "$HIX_OUT/rc.txt"

hix_classify "${ids[@]}"

tsvs=()
for id in "${ids[@]}"; do
   f=$(hix_cases_file "$id")
   [ -e "$f" ] && tsvs+=("$f")
done
[ ${#tsvs[@]} -gt 0 ] || { echo "no slice produced any case row - see $RUN_LOG" > "$HIX_OUT/index.body"; tsvs=( "$HIX_OUT/rc.txt" ); }

awk -F'\t' -v fail_only="$fail_only" -v rules="$HERE/lib/rules.tsv" \
    -f "$HERE/lib/index.awk" "$HIX_OUT/rc.txt" "${tsvs[@]}" > "$HIX_OUT/index.body" 2>> "$RUN_LOG"

# slices that produced no case rows at all: their digest is the only evidence
: > "$HIX_OUT/index.empty"
for id in "${ids[@]}"; do
   [ -s "$HIX_OUT/$id.tsv" ] && continue
   [ -s "$HIX_OUT/$id.digest" ] && { echo "[$id]"; tail -6 "$HIX_OUT/$id.digest"; } >> "$HIX_OUT/index.empty"
done

{
   echo "HIX TEST SUITE - index"
   echo "run    $(date -Is)   tree $(git -C "$HIX_ROOT" rev-parse --short HEAD 2>/dev/null) branch $(git -C "$HIX_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
   echo "budget ${HIX_BUDGET} bytes   evidence ${HIX_OUT}   elapsed $(( $(date +%s) - t_run0 ))s"
   echo "drill  tests/slice.sh <slice-id> [--cases|--log] [--grep PAT] [--budget N] [--full]"
   echo "class  tests/slice.sh <slice-id> --cases --class triage|harness|tool|env|order|product"
   echo ""
   cat "$HIX_OUT/index.body"
   if [ -s "$HIX_OUT/index.empty" ]; then
      echo ""
      echo "--- slices with no case rows (digest tail) ---"
      cat "$HIX_OUT/index.empty"
   fi
} > "$HIX_OUT/index.txt"

python3 - "$HIX_OUT" "${ids[@]}" <<'PY' > "$HIX_OUT/summary.json" 2>/dev/null || true
import json, os, sys
out = sys.argv[1]
DEFECT = {"product", "triage"}
NOISE  = {"harness", "tool", "env", "order"}
res = []
for sid in sys.argv[2:]:
    for ext in (".cls.tsv", ".tsv"):
        f = os.path.join(out, sid + ext)
        if os.path.exists(f):
            break
    else:
        continue
    c = {"PASS": 0, "FAIL": 0, "SKIP": 0, "ERROR": 0, "NOTE": 0}
    k = {"defect": 0, "noise": 0, "triage": 0, "by_class": {}}
    for line in open(f, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or parts[1] == "@totals":
            continue
        if parts[2] in c:
            c[parts[2]] += 1
        if parts[2] in ("FAIL", "ERROR"):
            cl = parts[4] if len(parts) > 4 and parts[4] else "triage"
            k["by_class"][cl] = k["by_class"].get(cl, 0) + 1
            if cl in DEFECT:
                k["defect"] += 1
                if cl == "triage":
                    k["triage"] += 1
            elif cl in NOISE:
                k["noise"] += 1
    res.append({"slice": sid, **c, **k})
print(json.dumps({"slices": res}, indent=1))
PY

if [ "$do_full" = 1 ]; then
   cat "$HIX_OUT/index.txt"
else
   "$HERE/lib/cap.sh" --budget "$HIX_BUDGET" --cols "$HIX_COLS" \
      --marker "full index: $HIX_OUT/index.txt - drill in with tests/slice.sh <slice-id>" \
      < "$HIX_OUT/index.txt"
fi

# ------------------------------------------------------------------
# exit status: only a defect decides it
# ------------------------------------------------------------------
read -r n_defect n_noise < <(awk -F'\t' 'FILENAME ~ /rc\.txt$/ {next}
   $2 == "@totals" { next }
   ($3 == "FAIL" || $3 == "ERROR") {
      cl = (NF >= 5 ? $5 : "triage")
      if (cl == "product" || cl == "triage") d++
      else if (cl == "harness" || cl == "tool" || cl == "env" || cl == "order") x++
   }
   END { print d+0, x+0 }' "$HIX_OUT/rc.txt" "${tsvs[@]}" 2>/dev/null || echo "0 0")

# a slice that could not run at all (timeout, missing binary) is an abort;
# one that ran and recorded rows has already been classified, so its own
# exit code no longer overrides the classes
rc_abort=0
while IFS=$'\t' read -r id tag rc secs; do
   if [ "$rc" != "0" ] && [ "$rc" != "1" ] && [ ! -s "$HIX_OUT/$id.tsv" ]; then rc_abort=1; break; fi
done < "$HIX_OUT/rc.txt"

if [ "$rc_abort" = 1 ]; then exit 2; fi
if [ "${n_defect:-0}" != "0" ]; then exit 1; fi
if [ "$do_strict" = 1 ] && [ "${n_noise:-0}" != "0" ]; then exit 1; fi
exit 0
