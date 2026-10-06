#!/usr/bin/env gawk -f
# ------------------------------------------------------------------
# parse_unit.awk - turn "tests/unit/app --cli" output into case rows.
#
# Input shape (the test master's CLI mode):
#     Core/Server ... ok
#     Routing/Request ... [EXCEPTION] Message not found
#     FAIL (1)
#          [FAIL] ERROR -- Message not found
#     1981 total | 1972 passed | 9 failed
#
# The status token is normally on the same line as the test name, but a
# test that writes to stdout pushes it onto the next line, so a pending
# test is kept until the token shows up.
#
# Rows written to stdout:  id \t case \t status \t detail
#   kind "test"   one per test group entry
#   kind "assert" one per failed assertion (the name is prefixed with the test)
#   kind "totals" the run's own totals line
#
# A group's own "FAIL (n)" line is a rollup of the n assertion lines that
# follow it, so it is buffered and only emitted when those n rows did not
# all show up - otherwise the same failure would be counted twice.
# ------------------------------------------------------------------
BEGIN { id = ENVIRON["HIX_SLICE"]; cls = ENVIRON["HIX_CLASS"]; pending = ""; pend_status = ""; pend_detail = "" }

{
   line = $0
   gsub(/\r/, "", line)
   gsub(/\033\[[0-9;:?]*[a-zA-Z]/, "", line)
   gsub(/\033\][^\007]*\007/, "", line)
   gsub(/\033\([A-Z]/, "", line)
   gsub(/\033/, "", line)
}

# --- test line: "  Group/Test ... <status>" -------------------------
line ~ /^[ \t]+[^ \t].*[ \t]\.\.\.[ \t]/ {
   sub(/^[ \t]+/, "", line)
   # cut at the first " ... " - the name may itself contain spaces
   # ("Auth & Security/JWT"), so a pattern anchored at the start of the
   # line would only ever work for names that have none.
   p = index(line, " ... ")
   name = substr(line, 1, p - 1)
   rest = substr(line, p + 5)
   # the test master emits cursor/decset sequences around the status, so a
   # status can arrive as "                    ok"; trim before matching
   gsub(/^[ \t]+|[ \t]+$/, "", rest)
   if (rest ~ /^ok/)                       { row(name, "PASS", "") ; pending = "" }
   else if (rest ~ /^FAIL/)                { rollup(name, rest); pending = "" }
   else if (rest ~ /^\[EXCEPTION\]/)       { row(name, "ERROR", rest); exc[name] = substr(rest, 13); pending = "" }
   else if (rest == "")                    { pending = name }
   else                                    { row(name, "NOTE", rest); pending = "" }
   cur = name
   next
}

# --- bare status line belonging to the pending test -----------------
line ~ /^FAIL[ \t]*\([0-9]+\)[ \t]*$/ || line ~ /^ERROR[ \t]*$/ {
   if (pending != "") { rollup(pending, line); pending = "" }
   next
}

# --- failed assertion detail ---------------------------------------
line ~ /^[ \t]+\[FAIL\][ \t]/ {
   sub(/^[ \t]+\[FAIL\][ \t]*/, "", line)
   d = line
   sub(/^.* -- /, "", d)
   n = line; sub(/ -- .*$/, "", n)
   g = (cur != "" ? cur : n)
   # when a group died on an exception the master re-reports it as an
   # assertion named "ERROR" with the same detail - one failure, not two
   if (n == "ERROR" && exc[g] != "" && exc[g] == d) next
   if (g in roll_n) roll_seen[g]++
   row((cur != "" ? cur " :: " : "") n, "FAIL", d)
   next
}

# --- run totals -----------------------------------------------------
line ~ /^[0-9]+ total \| [0-9]+ passed \| [0-9]+ failed/ {
   row("@totals", "NOTE", line)
   next
}

END {
   if (pending != "") row(pending, "NOTE", "no status token seen")
   for (g in roll_n) if (roll_seen[g] + 0 != roll_n[g]) row(g, "FAIL", roll_d[g])
}

# a "FAIL (n)" status is a count of the assertion rows that follow it
function rollup(name, detail,   n) {
   if (detail ~ /^FAIL[ 	]*\([0-9]+\)[ 	]*$/) {
      n = detail; sub(/^FAIL[ 	]*\(/, "", n); sub(/\)[ 	]*$/, "", n)
      roll_n[name] = n + 0; roll_d[name] = detail
      return
   }
   row(name, "FAIL", detail)
}

function row(name, status, detail) {
   gsub(/\t/, " ", name); gsub(/\t/, " ", detail)
   printf "%s\t%s\t%s\t%s\t%s\n", id, name, status, detail, cls
}
