#!/usr/bin/env bash
# ------------------------------------------------------------------
# s30_repo.sh - repository hygiene. Read-only, report-only.
#
# Every case here is a property of the tracked tree or of the runtime
# files the app leaves behind. Nothing is changed: a FAIL is a finding
# for whoever owns the repository, not something this suite repairs.
#
# Cases: secret.*  tracked/untracked key material
#        ignore.*  .gitignore coverage
#        path.*    machine-specific paths baked into tracked files
#        gen.*     build-generated artifacts that should not be tracked
#        data.*    runtime state of the DBF/CDX files
#        perm.*    modes of the files the app writes at runtime
# ------------------------------------------------------------------
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
hix_slice_init "${SLICE_ID:-30-repo}"
cd "$HIX_ROOT" || exit 2

# A hygiene finding is a defect in the repository, which is part of what
# this suite owns: class product. The one exception is decided by a rule -
# residue in users.dbf is residue of previous test runs, not of the app.
hix_class product

git -C "$HIX_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   || { hix_case "@abort" FAIL "not a git work tree" env; exit 2; }

tracked=$(git ls-files)

# --- secret material --------------------------------------------------------
secret_tracked=$(printf '%s\n' "$tracked" | grep -iE '\.(key|crt|pem|p12|pfx)$' || true)
if [ -z "$secret_tracked" ]; then hix_case "secret.tracked" PASS "no key/cert files tracked"
else hix_case "secret.tracked" FAIL "tracked: $(echo "$secret_tracked" | tr '\n' ' ')"; fi

secret_history=$(git log --all --format=%H --name-only --diff-filter=A 2>/dev/null \
   | grep -iE '\.(key|crt|pem|p12|pfx)$' | sort -u || true)
if [ -z "$secret_history" ]; then hix_case "secret.history" PASS "no key/cert ever added"
else hix_case "secret.history" NOTE "$(echo "$secret_history" | wc -l) path(s) ever added, e.g. $(echo "$secret_history" | head -2 | tr '\n' ' ')"; fi

secret_untracked=$(git status --porcelain --untracked-files=all 2>/dev/null \
   | awk '{print $2}' | grep -iE '\.(key|crt|pem|p12|pfx)$' || true)
if [ -z "$secret_untracked" ]; then hix_case "secret.untracked" PASS "none in the working tree"
else
   hix_case "secret.untracked" FAIL "$(echo "$secret_untracked" | wc -l) private file(s) one 'git add -A' away: $(echo "$secret_untracked" | tr '\n' ' ')"
   for f in $secret_untracked; do
      case "$f" in *.key) m=$(stat -c '%a' "$f" 2>/dev/null)
         if [ "$m" = "600" ]; then hix_case "secret.untracked.mode" NOTE "$f is 0$m but still unignored"
         else hix_case "secret.untracked.mode" FAIL "$f is 0$m and unignored"; fi ;;
      esac
   done
fi

# --- .gitignore coverage ----------------------------------------------------
for pat in 'tests/unit/hix_test.key' 'tests/unit/hix_test.crt' 'webapp/hix.keys.json' 'webapp/www/config.json'; do
   if git check-ignore -q "$pat" 2>/dev/null; then hix_case "ignore.$pat" PASS
   else hix_case "ignore.$pat" FAIL "not matched by .gitignore"; fi
done

# --- machine-specific paths in tracked files --------------------------------
pathhits=$(git grep -nIE '/home/[a-z0-9_-]+/|/Users/[a-z0-9_-]+/|[A-Za-z]:\\\\Users\\\\|[A-Za-z]:\\\\home\\\\' -- . 2>/dev/null \
   | grep -v '^tests/\.out/' | head -20 || true)
if [ -z "$pathhits" ]; then hix_case "path.portable" PASS "no absolute home paths in tracked files"
else hix_case "path.portable" FAIL "$(echo "$pathhits" | wc -l) hit(s): $(echo "$pathhits" | head -3 | tr '\n' ' | ')"; fi

# --- generated artifacts that must stay untracked ---------------------------
# Harbour writes a .c beside every .prg it compiles, plus link output. A
# tracked .c only counts as compiler output when the .prg it came from sits
# next to it: src/wdo/legacy_func.c is hand-written framework source and is
# not output of anything.
gen_ext=$(printf '%s\n' "$tracked" | grep -E '\.(o|obj|exe|exp|lib|res|hbx|a)$' | grep -v '^resources/' || true)
gen_c=""
while IFS= read -r f; do
   [ -n "$f" ] || continue
   d=${f%/*}; b=${f%.*}
   [ "$d" = "$f" ] && d=""
   git ls-files --error-unmatch "$d/$b.prg" >/dev/null 2>&1 && gen_c+="$f"$'\n'
done <<< "$(printf '%s\n' "$tracked" | grep -E '\.c$' | grep -v '^resources/')"
gen_tracked=$(printf '%s\n%s' "$gen_ext" "$gen_c" | grep -v '^[[:space:]]*$' || true)
if [ -z "$gen_tracked" ]; then hix_case "gen.tracked" PASS "no compiler output tracked"
else hix_case "gen.tracked" FAIL "tracked: $(echo "$gen_tracked" | tr '\n' ' ')"; fi

printf '%s\n' "$tracked" | grep -q '^webapp/data/' \
   && hix_case "gen.data.tracked" FAIL "webapp/data is tracked - DBF/CDX are runtime state" \
   || hix_case "gen.data.tracked" PASS "webapp/data untracked"

printf '%s\n' "$tracked" | grep -q '^webapp/www/config\.json$' \
   && hix_case "gen.config.tracked" FAIL "www/config.json tracked - the original key leak" \
   || hix_case "gen.config.tracked" PASS "www/config.json untracked"

# --- runtime state and permissions -----------------------------------------
perm_case() {   # perm_case <case> <path> <expected-mode> <missing-status>
   if [ -e "$2" ]; then
      m=$(stat -c '%a' "$2")
      [ "$m" = "$3" ] && hix_case "$1" PASS "$2 is 0$m" || hix_case "$1" FAIL "$2 is 0$m, expected 0$3"
   else
      hix_case "$1" "$4" "$2 does not exist yet (created on first server start)"
   fi
}
perm_case "perm.keys"      "$HIX_WEBAPP/hix.keys.json" 600 FAIL
perm_case "perm.appkey"    "$HIX_WEBAPP/certs/hix.key" 600 FAIL
for d in "$HIX_WEBAPP/.sessions" "$HIX_WEBAPP/sessions"; do
   [ -d "$d" ] || continue
   perm_case "perm.session_dir" "$d" 700 FAIL
   loose=$(find "$d" -maxdepth 1 -type f ! -perm 600 | head -5)
   if [ -n "$loose" ]; then hix_case "perm.session_files" FAIL "not 0600: $(echo "$loose" | tr '\n' ' ')"
   else hix_case "perm.session_files" PASS "$(find "$d" -maxdepth 1 -type f | wc -l) files, all 0600"; fi
done

# --- data residue from earlier runs ----------------------------------------
if [ -f "$HIX_WEBAPP/data/users.dbf" ] && [ -f "$HIX_WEBAPP/test/dbf_dump.py" ]; then
   res=$( cd "$HIX_WEBAPP" && python3 - <<'PY' 2>>"$HIX_LOG"
import sys
sys.path.insert(0, 'test')
from dbf_dump import read_dbf
try:
    _, fields, rows = read_dbf('data/users.dbf')
except Exception as e:
    print("READ-ERROR %s" % e); raise SystemExit(0)
names = [f for f, _, _ in fields].index('NAME') if 'NAME' in [f for f, _, _ in fields] else -1
z = []
for recno, flag, h in rows:
    try:
        n = (h[names] if names >= 0 else '').strip()
    except Exception:
        continue
    if n.startswith('zbf') or n.startswith('zverify'):
        z.append(n)
print("rows=%d residue=%d %s" % (len(rows), len(z), ' '.join(z[:6])))
PY
)
   nres=$(printf '%s' "$res" | sed -n 's/.*residue=\([0-9]*\).*/\1/p')
   if [ -z "$nres" ]; then hix_case "data.residue" ERROR "could not read users.dbf: $res"
   elif [ "$nres" = 0 ]; then hix_case "data.residue" PASS "$res"
   else hix_case "data.residue" FAIL "$res - test rows left behind by earlier runs"; fi
   hix_case "data.users_rows" NOTE "$res"
fi

# --- report -----------------------------------------------------------------
{
   echo "slice $HIX_SLICE - repository hygiene"
   awk -F'\t' '{c[$3]++} END{for(k in c) printf "  %-6s %d\n", k, c[k]}' "$HIX_TSV"
   awk -F'\t' '$3=="FAIL"||$3=="ERROR"{printf "  %s %s  %s\n", $3, $2, $4}' "$HIX_TSV"
   echo "  --- git identity of the tree ---"
   echo "  HEAD $(git rev-parse --short HEAD) branch $(git rev-parse --abbrev-ref HEAD)"
} | hix_digest

awk -F'\t' '$3=="FAIL"{n++} END{exit (n>0?1:0)}' "$HIX_TSV"
