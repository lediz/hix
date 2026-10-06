#!/usr/bin/env gawk -f
# ------------------------------------------------------------------
# parse_wa.awk - turn the webapp suites' output into case rows.
#
#   id \t case \t status \t detail
#
# Modes (-v mode=...), matching the format each existing suite prints:
#
#   bracket  "[PASS] T07 - Login page ... (expected 302, got 200)"
#            test_users_module.sh / test_customer_module.sh
#   verify   "  PASS  D-16a 'name' CDX tag is keyed on Lower(name)"
#            "  FAIL  D-16d ...  [expected 200 / got 302]"
#            verify-users-fixes.sh
#   bf       "BF-04a: PASS — 5 requests, no timing signal"
#            bf_harness.sh verdicts.txt
#
# Summary lines of each suite become a "@totals" NOTE row so the index
# can show the suite's own count next to the parsed one.
# ------------------------------------------------------------------
BEGIN {
   id = ENVIRON["HIX_SLICE"]
   mode = ENVIRON["HIX_PARSE_MODE"]
   cls = ENVIRON["HIX_CLASS"]
   DASH = "\xe2\x80\x94"
}

{
   line = $0
   gsub(/\r/, "", line)
   gsub(/\033\[[0-9;:?]*[ -\/]*[0-9;:?]*[a-zA-Z]/, "", line)
   gsub(/\033/, "", line)
}

mode == "bracket" && line ~ /^\[(PASS|FAIL)\][ \t]/ {
   st = (line ~ /^\[PASS\]/) ? "PASS" : "FAIL"
   sub(/^\[(PASS|FAIL)\][ \t]*/, "", line)
   row(line, st, "")
   next
}

mode == "verify" && line ~ /^[ \t]*(PASS|FAIL)[ \t]+[^ \t]/ {
   st = (line ~ /^[ \t]*PASS/) ? "PASS" : "FAIL"
   sub(/^[ \t]*(PASS|FAIL)[ \t]+/, "", line)
   row(line, st, "")
   next
}

mode == "bf" && line ~ /^[A-Za-z][A-Za-z0-9._-]*:[ \t]+(PASS|FAIL|SKIP|SEE NOTES|NOTE|BLOCKED|ERROR)/ {
   cid = line; sub(/:.*/, "", cid)
   rest = line; sub(/^[^:]+:[ \t]*/, "", rest)
   st = rest; sub(/[ \t].*$/, "", st)
   st = (st == "SEE NOTES") ? "NOTE" : st
   det = rest; sub(/^[^ \t]+[ \t]*/, "", det)
   sub("^" DASH "[ \t]*", "", det)
   row(cid, st, det)
   next
}

# --- suite self-reported totals ------------------------------------
line ~ /PASS[ \t]*=[ \t]*[0-9]+[ \t]+FAIL[ \t]*=[ \t]*[0-9]+/ {
   d = line; sub(/^[^A-Za-z]*/, "", d)
   row("@totals", "NOTE", d); next
}
line ~ /^[ \t]*Total[ \t]*:[ \t]*[0-9]+[ \t]+Pass[ \t]*:[ \t]*[0-9]+[ \t]+Fail[ \t]*:[ \t]*[0-9]+/ {
   gsub(/^[ \t]+|[ \t]+$/, "", line); row("@totals", "NOTE", line); next
}
line ~ /^[ \t]*(Total tests|Passed|Failed)[ \t]*:[ \t]*[0-9]+/ {
   gsub(/^[ \t]+|[ \t]+$/, "", line)
   if      (line ~ /^Total tests/) sum_total  = line
   else if (line ~ /^Passed/)      sum_passed = line
   else { row("@totals", "NOTE", sum_total "   " sum_passed "   " line)
          sum_total = sum_passed = "" }
   next
}

function row(name, status, detail) {
   gsub(/\t/, " ", name); gsub(/\t/, " ", detail)
   printf "%s\t%s\t%s\t%s\t%s\n", id, name, status, detail, cls
}
