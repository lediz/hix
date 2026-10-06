#!/usr/bin/env gawk -f
# ------------------------------------------------------------------
# classify.awk - decide what kind of failure a row is.
#
#   awk -F'\t' -v rules=lib/rules.tsv -v checks=<out>/checks.tsv \
#              -v ref=<out>/09-fw-all.tsv -v refid=09-fw-all \
#        -f lib/classify.awk <out>/<id>.tsv  >  <out>/<id>.cls.tsv
#
# Input  (a slice's own rows):  id \t case \t status \t detail \t asserted-class
# Output:                      id \t case \t status \t detail \t class \t basis
#
# The asserted class is what the slice itself claimed. The final class is
# decided in this order, first match wins:
#
#   1. a rule from rules.tsv whose check s07_harness.sh proved ok this run
#      -> that rule's class          (basis rule:<id>+<check>)
#   2. the same case PASSES in the reference run (whole unit suite in one
#      process) -> "order", an artifact of slicing the framework up. An
#      assertion row ("<group> :: <assertion>") is matched by its group:
#      if the group passed whole in the reference run, none of its
#      assertions failed there, so the failure only exists in isolation.
#   3. the class the slice asserted   (basis asserted)
#   4. nothing explained it -> "triage": still a failure, but flagged as
#      unclassified so it cannot quietly be read as noise
#
# PASS/SKIP/NOTE rows are never reclassified: their class is only a label.
# ------------------------------------------------------------------
BEGIN {
   OFS = "\t"
   while ((getline l < checks) > 0) { if (split(l, a, "\t") >= 2) cok[a[1]] = (a[2] == "ok") }
   if (checks != "") close(checks)

   nr = 0
   while ((getline l < rules) > 0) {
      if (l ~ /^[ \t]*(#|$)/) continue
      n = split(l, a, "\t")
      if (n < 4) continue
      nr++
      rid[nr] = a[1]; rcase[nr] = a[2]; rdet[nr] = a[3]; rcls[nr] = a[4]
      rchk[nr] = (n >= 5 && a[5] != "-" ? a[5] : "")
   }
   if (rules != "") close(rules)

   if (ref != "") {
      while ((getline l < ref) > 0) {
         if (split(l, a, "\t") >= 3 && a[2] != "@totals") refst[a[2]] = a[3]
      }
      close(ref)
   }
}

{
   asserted = (NF >= 5 ? $5 : "")
   cls = ""; basis = ""

   if ($3 == "FAIL" || $3 == "ERROR") {
      for (i = 1; i <= nr; i++)
         if ($2 ~ rcase[i] && ($2 " " $4) ~ rdet[i] && (rchk[i] == "" || cok[rchk[i]] == 1)) {
            cls = rcls[i]; basis = "rule:" rid[i] (rchk[i] != "" ? "+" rchk[i] : "")
            break
         }
      if (cls == "" && $1 != refid && refid != "") {
         grp = $2; sub(/ :: .*$/, "", grp)
         if (($2 in refst) && refst[$2] == "PASS")      { cls = "order"; basis = "ref-pass:" refid }
         else if (grp != $2 && (grp in refst) && refst[grp] == "PASS") {
            cls = "order"; basis = "ref-pass-group:" refid "/" grp
         }
      }
      if (cls == "" && asserted != "") { cls = asserted; basis = "asserted" }
      if (cls == "")                   { cls = "triage"; basis = "unexplained" }
   } else {
      cls   = (asserted != "" ? asserted : "-")
      basis = (asserted != "" ? "asserted" : "")
   }

   print $1, $2, $3, $4, cls, basis
}
