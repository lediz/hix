#!/usr/bin/env gawk -f
# ------------------------------------------------------------------
# index.awk - aggregate the per-slice case rows into the suite index.
#
#   awk -v fail_only=0 -v rules=lib/rules.tsv -f lib/index.awk <out>/rc.txt <rows>...
#
# Input:
#   rc.txt    slice \t tag \t rc \t secs
#   rows      slice \t case \t status \t detail \t class [\t basis]
#             (the .cls.tsv files when classify has run, the .tsv ones when not)
#
# What makes the index readable is that a failure is never just a
# failure: it carries the class it was decided to be.
#
#   defect = product + triage   -> the suite failed, exit 1
#   noise   = harness + tool + env + order -> reported, not counted
#
# Nothing is dropped: every failure appears in exactly one of the three
# lists at the bottom, and a noise row cites the rule and the check that
# justified moving it out of the counted classes.
#
# Output (uncapped - run.sh caps it): one row per slice, a TOTAL row, the
# reference run separately (its assertions are the group slices' ones a
# second time), the slices' exit codes, the suites' own self-reported
# totals, and the three failure lists.
# ------------------------------------------------------------------
BEGIN {
   FS = "\t"
   while ((getline l < rules) > 0) {
      if (l ~ /^[ \t]*(#|$)/) continue
      if (split(l, a, "\t") >= 6) why[a[1]] = a[6]
   }
   if (rules != "") close(rules)
}

FILENAME ~ /rc\.txt$/ { secs[$1] = $4; rcs[$1] = $3; tag[$1] = $2; next }

{
   slice = $1
   if ($2 == "@totals") { assert_note[slice] = $4; next }
   n[slice]++
   if      ($3 == "PASS")  p[slice]++
   else if ($3 == "FAIL")  f[slice]++
   else if ($3 == "SKIP")  s[slice]++
   else if ($3 == "ERROR") e[slice]++
   else                     o[slice]++

   if ($3 == "FAIL" || $3 == "ERROR") {
      cl = (NF >= 5 && $5 != "" ? $5 : "triage"); bs = (NF >= 6 && $6 != "" ? $6 : "unclassified")
      if (cl == "product" || cl == "triage") {
         d[slice]++
         if (cl == "triage") t[slice]++
         dlist = dlist sprintf("  %s / %s  %s   [%s]\n", slice, $2, $4, bs)
         if (cl == "triage") tlist = tlist sprintf("  %s / %s  %s\n", slice, $2, $4)
      } else if (cl == "harness" || cl == "tool" || cl == "env" || cl == "order") {
         x[slice]++
         ncl[cl]++
         rid = bs; sub(/^rule:/, "", rid); sub(/\+.*$/, "", rid)
         xlist = xlist sprintf("  %-7s %s / %s\n          %s\n          (%s)\n", \
                               cl, slice, $2, $4, (why[rid] != "" ? rid ": " why[rid] : bs))
      }
   }
}

END {
   m = 0
   for (k in n) if (tag[k] != "ref") order[++m] = k
   for (k in n) if (tag[k] == "ref") rorder[++rm] = k
   for (i = 1; i <= m; i++) for (j = i+1; j <= m; j++)
      if (order[j] < order[i]) { z = order[i]; order[i] = order[j]; order[j] = z }

   printf "%-22s %5s %5s %5s %5s %5s %5s %6s %5s %6s  %s\n", \
          "slice", "cases", "pass", "fail", "skip", "err", "note", "defect", "noise", "secs", "verdict"
   for (i = 1; i <= m; i++) {
      k = order[i]
      printf "%-22s %5d %5d %5d %5d %5d %5d %6d %5d %6s  %s\n", k, n[k], p[k]+0, f[k]+0, s[k]+0, e[k]+0, o[k]+0, \
             d[k]+0, x[k]+0, secs[k]+0, verdict(k)
      tn += n[k]; tp += p[k]+0; tf += f[k]+0; ts += s[k]+0; te += e[k]+0; to += o[k]+0
      td += d[k]+0; tx += x[k]+0; tt += t[k]+0
   }
   printf "%-22s %5d %5d %5d %5d %5d %5d %6d %5d %6s\n", "TOTAL", tn, tp, tf, ts, te, to, td, tx, ""

   if (rm > 0) {
      print ""
      print "reference run - the same framework assertions in one process, not counted in TOTAL"
      printf "%-22s %5s %5s %5s %5s %5s %5s %6s %5s %6s  %s\n", \
             "slice", "cases", "pass", "fail", "skip", "err", "note", "defect", "noise", "secs", "verdict"
      for (i = 1; i <= rm; i++) { k = rorder[i]
         printf "%-22s %5d %5d %5d %5d %5d %5d %6d %5d %6s  %s\n", k, n[k], p[k]+0, f[k]+0, s[k]+0, e[k]+0, o[k]+0, \
                d[k]+0, x[k]+0, secs[k]+0, verdict(k) }
   }

   print ""
   printf "verdict  %s\n", (td > 0 ? sprintf("%d DEFECT(S) in the code under test (%d of them unexplained)", td, tt) \
                                   : (tx > 0 ? sprintf("clean: %d failure(s), all attributed to harness/tool/env/slice-order", tx) : "clean"))
   printf "classes  defect = product + triage (counts)   noise = %s (does not count)\n", \
          join_classes()

   for (k in rcs) if (rcs[k] + 0 != 0) printf "rc %-19s %s\n", k, rcs[k]
   for (k in assert_note) printf "assertions %-18s %s\n", k, assert_note[k]

   if (dlist != "") { print ""; print "--- defects: the code under test is wrong ---"; printf "%s", dlist }
   if (tlist != "") { print ""; print "--- unexplained: no rule matched, so still counted (tests/slice.sh <id> --cases) ---"; printf "%s", tlist }
   if (xlist != "" && fail_only != 1) {
      print ""
      print "--- not defects: harness / tool / environment / slice order ---"
      printf "%s", xlist
   }
}

function verdict(k) {
   if (d[k] > 0) return "FAIL"
   if (x[k] > 0) return "NOISE"
   return "ok"
}

function join_classes(   c, out) {
   out = ""
   for (c in ncl) out = out (out == "" ? "" : " + ") c "=" ncl[c]
   return (out == "" ? "harness + tool + env + order" : out)
}
