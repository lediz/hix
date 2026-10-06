#!/usr/bin/env gawk -f
# ------------------------------------------------------------------
# count_class.awk - one summary line for a slice's rows, as used by
# tests/slice.sh --list.
#
#   HIX_CLS=<the classified file, if any> awk -F'\t' -f count_class.awk <rows>
#
# The failing rows are broken out by class, because that is the only
# part of a slice's count that says anything about the code under test.
# ------------------------------------------------------------------
BEGIN {
   clsfile = ENVIRON["HIX_CLS"]
   if (clsfile != "") {
      while ((getline l < clsfile) > 0) {
         if (split(l, a, "\t") >= 5 && (a[3] == "FAIL" || a[3] == "ERROR")) kcls[a[2]] = a[5]
      }
      close(clsfile)
   }
}
{
   if ($2 == "@totals") next
   c[$3]++
   if ($3 == "FAIL" || $3 == "ERROR") {
      cl = (NF >= 5 && $5 != "" ? $5 : (kcls[$2] != "" ? kcls[$2] : "triage"))
      k[cl]++
      tot++
   }
}
END {
   out = sprintf("PASS=%d FAIL=%d SKIP=%d ERROR=%d NOTE=%d", c["PASS"], c["FAIL"], c["SKIP"], c["ERROR"], c["NOTE"])
   if (tot > 0) {
      out = out "  failing-by-class:"
      for (cl in k) out = out " " cl "=" k[cl]
   }
   print out
}
