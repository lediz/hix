#!/usr/bin/env bash
#
# compare-branches.sh — comparative analysis between two refs.
#
# Default comparison: origin/enhance (the unified work) vs origin/main (the
# upstream-tracking branch). Re-runnable; writes a Markdown report.
#
#   ./compare-branches.sh [LEFT] [RIGHT] [OUTPUT]
#   ./compare-branches.sh --no-fetch origin/enhance origin/main COMPARISON.md
#   ./compare-branches.sh --exclude webapp/srs/06-release/COMPARISON-enhance-vs-main.md
#
# The report's own output file is always excluded from the content delta: it
# changes on every run, so counting it would make the numbers self-referential.
# Add more with --exclude <path> (repeatable).
#
# Exit codes: 0 ok · 2 bad usage/ref · 3 substantive divergence found
# (a non-fast-forward relationship), so it can gate CI if wanted.

set -uo pipefail

FETCH=1
EXTRA=()
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --no-fetch) FETCH=0; shift; continue ;;
    --exclude)  EXTRA+=("${2:?--exclude needs a path}"); shift 2; continue ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) break ;;
  esac
done

LEFT="${1:-origin/enhance}"
RIGHT="${2:-origin/main}"
OUT="${3:-webapp/srs/06-release/COMPARISON-enhance-vs-main.md}"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not inside a git repository" >&2; exit 2; }
norm_rel() { case "$1" in /*) realpath -m --relative-to="$ROOT" "$1" ;; *) printf '%s' "${1#./}" ;; esac }
in_repo()  { case "$1" in ""|/*|..|../*) return 1 ;; *) return 0 ;; esac; }

OUTREL=$(norm_rel "$OUT")
XPS=(); EXCLUDED=()
for _p in "$OUTREL" ${EXTRA[@]+"${EXTRA[@]}"}; do
  if in_repo "$_p"; then XPS+=(":(exclude)$_p"); EXCLUDED+=("$_p")
  else echo "warn: not excluding '$_p' — outside the repository" >&2; fi
done
TOPS=(); for _p in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do TOPS+=("${_p%%/*}"); done
if [ ${#EXCLUDED[@]} -gt 0 ]; then EXCL_TXT="${EXCLUDED[*]}"; else EXCL_TXT="nothing"; fi
drop_top() { if [ ${#TOPS[@]} -gt 0 ]; then grep -v -x -F -f <(printf '%s\n' "${TOPS[@]}") || true; else cat; fi; }

for ref in "$LEFT" "$RIGHT"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || {
    echo "error: cannot resolve ref: $ref" >&2; exit 2; }
done

if [ "$FETCH" = 1 ]; then
  git fetch --quiet --prune origin 2>/dev/null || echo "warn: fetch failed; using local refs" >&2
fi

L=$(git rev-parse "$LEFT^{commit}")
R=$(git rev-parse "$RIGHT^{commit}")
MB=$(git merge-base "$L" "$R" || echo "")
LR=$(git rev-list --left-right --count "$L...$R")
AHEAD=$(echo "$LR" | awk '{print $1}')
BEHIND=$(echo "$LR" | awk '{print $2}')

is_anc() { git merge-base --is-ancestor "$1" "$2" 2>/dev/null && echo yes || echo no; }
R_IS_ANC_L=$(is_anc "$R" "$L")   # RIGHT contained in LEFT -> LEFT can fast-forward RIGHT
L_IS_ANC_R=$(is_anc "$L" "$R")

if   [ "$L" = "$R" ];                 then REL="identical"
elif [ "$R_IS_ANC_L" = yes ];         then REL="fast-forward: $LEFT is ahead of $RIGHT by $AHEAD"
elif [ "$L_IS_ANC_R" = yes ];         then REL="fast-forward: $RIGHT is ahead of $LEFT by $BEHIND"
else                                       REL="DIVERGED: $AHEAD unique to $LEFT, $BEHIND unique to $RIGHT (non-fast-forward)"
fi

md_escape() { sed 's/|/\\|/g'; }

# --- content delta (this report's own file excluded; see header) -----------
if ! NUMSTAT=$(git diff --numstat -M "$R" "$L" -- ${XPS[@]+"${XPS[@]}"}); then
  echo "error: git diff failed — check the --exclude pathspecs" >&2; exit 2
fi
SHORTSTAT=$(git diff --shortstat -M "$R" "$L" -- ${XPS[@]+"${XPS[@]}"} | sed 's/^ *//')
NAMESTATUS=$(git diff --name-status -M "$R" "$L" -- ${XPS[@]+"${XPS[@]}"})
ADDED=$(echo   "$NAMESTATUS" | grep -c '^A' || true)
MODIFIED=$(echo "$NAMESTATUS" | grep -c '^M' || true)
DELETED=$(echo  "$NAMESTATUS" | grep -c '^D' || true)
RENAMED=$(echo  "$NAMESTATUS" | grep -c '^R' || true)
BINARY=$(echo   "$NUMSTAT" | awk -F'\t' '$1=="-" && $2=="-"' | grep -c . || true)
INS=$(echo "$NUMSTAT" | awk -F'\t' '$1!="-"{s+=$1} END{print s+0}')
DEL=$(echo "$NUMSTAT" | awk -F'\t' '$2!="-"{s+=$2} END{print s+0}')

tree_files() { git ls-tree -r --name-only "$1" | grep -c . || true; }
tree_bytes() { git ls-tree -r -l "$1" | awk '{s+=$4} END{print s+0}'; }

census() { git log --format="$2" "$1" | sort | uniq -c | sort -rn | sed 's/^ *//'; }

commit_table() {   # commit_table <range> <limit>
  local n; n=$(git rev-list --count "$1" 2>/dev/null || echo 0)
  if [ "$n" = 0 ]; then echo "_(none)_"; return; fi
  git log --format='%ad%x09%an%x09%s' --date=short "$1" | head -"$2" \
    | awk -F'\t' '{ gsub(/\|/, "\\|", $3); gsub(/\|/, "\\|", $2); printf "| %s | %s | %s |\n", $1, $2, $3 }'
}

dir_breakdown() { git diff --name-only -M "$R" "$L" -- ${XPS[@]+"${XPS[@]}"} | awk -F/ 'NF>1{print $1"/"} NF==1{print "(root)"}' | sort | uniq -c | sort -rn | sed 's/^ *//'; }

{
echo "# Comparative analysis: \`$LEFT\` vs \`$RIGHT\`"
echo
echo "Generated: $(date -Is) · by \`$(basename "$0")\`"
echo
echo "| Ref | SHA | Commits | Files | Tree size |"
echo "|---|---|---|---|---|"
echo "| \`$LEFT\` | \`$(git rev-parse --short "$L")\` | $(git rev-list --count "$L") | $(tree_files "$L") | $(tree_bytes "$L") B |"
echo "| \`$RIGHT\` | \`$(git rev-parse --short "$R")\` | $(git rev-list --count "$R") | $(tree_files "$R") | $(tree_bytes "$R") B |"
echo
echo "## 1. Topology"
echo
echo "| Metric | Value |"
echo "|---|---|"
echo "| Relationship | **$REL** |"
echo "| Merge base | \`$( [ -n "$MB" ] && git log -1 --format='%h — %s (%ad)' --date=short "$MB" || echo 'none — unrelated histories')\` |"
echo "| Unique to \`$LEFT\` | $AHEAD |"
echo "| Unique to \`$RIGHT\` | $BEHIND |"
echo "| \`$RIGHT\` ⊆ \`$LEFT\` | $R_IS_ANC_L |"
echo "| \`$LEFT\` ⊆ \`$RIGHT\` | $L_IS_ANC_R |"
echo
echo "## 2. Content delta (\`$RIGHT\` → \`$LEFT\`)"
echo
echo "| Metric | Value |"
echo "|---|---|"
echo "| Files added / modified / deleted / renamed | $ADDED / $MODIFIED / $DELETED / $RENAMED |"
echo "| Lines inserted / deleted | +$INS / -$DEL |"
echo "| Binary files changed | $BINARY |"
echo "| Shortstat | $SHORTSTAT |"
echo "| Excluded from the delta | $EXCL_TXT |"
echo
echo "### Top-level entries only in one side"
echo
ONLY_L=$(comm -23 <(git ls-tree --name-only "$L" | sort) <(git ls-tree --name-only "$R" | sort) | drop_top)
ONLY_R=$(comm -13 <(git ls-tree --name-only "$L" | sort) <(git ls-tree --name-only "$R" | sort) | drop_top)
echo "- only in \`$LEFT\`: $( [ -n "$ONLY_L" ] && echo "$ONLY_L" | tr '\n' ' ' || echo '—' )"
echo "- only in \`$RIGHT\`: $( [ -n "$ONLY_R" ] && echo "$ONLY_R" | tr '\n' ' ' || echo '—' )"
echo
echo "### Largest content changes"
echo
echo '```'
echo "$NUMSTAT" | sort -rn | head -15
echo '```'
echo
echo "### Changes by top-level directory"
echo
echo '```'
dir_breakdown
echo '```'
echo
echo "### Renames"
echo
echo '```'
echo "$NAMESTATUS" | grep '^R' | head -20 || echo "(none)"
echo '```'
echo
echo "## 3. Unique commits"
echo
echo "### Only in \`$LEFT\` ($AHEAD)"
echo
echo '| Date | Author | Subject |'
echo '|---|---|---|'
commit_table "$R..$L" 60
echo
echo "### Only in \`$RIGHT\` ($BEHIND)"
echo
echo '| Date | Author | Subject |'
echo '|---|---|---|'
commit_table "$L..$R" 60
echo
echo "## 4. Attribution"
echo
echo "### Authors — \`$LEFT\`"
echo '```'
census "$L" '%an <%ae>'
echo '```'
echo
echo "### Authors — \`$RIGHT\`"
echo '```'
census "$R" '%an <%ae>'
echo '```'
echo
echo "### Committers — \`$LEFT\`"
echo '```'
census "$L" '%cn <%ce>'
echo '```'
echo
echo "### Email domains unique to one side"
echo
echo '```'
DL=$(git log --format='%ae' "$L" | sed 's/.*@//' | sort -u)
DR=$(git log --format='%ae' "$R" | sed 's/.*@//' | sort -u)
DOM=$( { comm -23 <(echo "$DL") <(echo "$DR") | sed 's/^/only in LEFT:  /'; comm -13 <(echo "$DL") <(echo "$DR") | sed 's/^/only in RIGHT: /'; } )
if [ -n "$DOM" ]; then echo "$DOM"; else echo "(none — both sides share the same author email domains)"; fi
echo '```'
echo
echo "### Signed commits"
echo
SIGNED_L=$(git rev-list "$L" | while read -r c; do git cat-file -p "$c" | grep -q '^gpgsig' && echo x; done | grep -c . || true)
SIGNED_R=$(git rev-list "$R" | while read -r c; do git cat-file -p "$c" | grep -q '^gpgsig' && echo x; done | grep -c . || true)
echo "- \`$LEFT\`: $SIGNED_L signed"
echo "- \`$RIGHT\`: $SIGNED_R signed"
echo
echo "## 5. Tags"
echo
echo '```'
git for-each-ref --format='%(refname:short) -> %(objectname:short)' refs/tags
echo '```'
echo
echo "## 6. Findings"
echo
if [ "$REL" = identical ]; then
  echo "- The two refs are identical."
else
  echo "- $REL"
fi
[ "$R_IS_ANC_L" = yes ] && [ "$L" != "$R" ] && \
  echo "- \`$LEFT\` can be merged into \`$RIGHT\` as a **fast-forward**."
[ "$R_IS_ANC_L" = no ] && [ "$L_IS_ANC_R" = no ] && {
  echo "- Syncing either direction needs a **merge commit** or a **force-push**."
  echo "- A force-push would discard the other side's unique commits; record the current tip before any force:"
  echo "  \`$R\` for \`$RIGHT\`, \`$L\` for \`$LEFT\`."
  echo "- Re-running this script after upstream moves shows whether the gap widened or narrowed."
}
[ "$MB" != "" ] && git merge-base --is-ancestor "$MB" "$R" && git merge-base --is-ancestor "$MB" "$L" && \
  echo "- Shared history below the merge base is common to both; commits there keep identical SHAs unless history is rewritten."
echo "- The content delta excludes $EXCL_TXT. The unique-commit count still includes the commit that carries this report — that one is unavoidable while the report is tracked."
echo
echo "## 7. Machine-readable summary"
echo
echo '```json'
EXJSON=$(for _p in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do printf '"%s",' "$_p"; done | sed 's/,$//')
printf '{\n  "left": "%s",\n  "left_sha": "%s",\n  "right": "%s",\n  "right_sha": "%s",\n  "merge_base": "%s",\n  "left_only": %s,\n  "right_only": %s,\n  "fast_forward_possible": %s,\n  "diverged": %s,\n  "excluded": [%s],\n  "files": {"added": %s, "modified": %s, "deleted": %s, "renamed": %s, "binary": %s},\n  "lines": {"insertions": %s, "deletions": %s}\n}\n' \
  "$LEFT" "$L" "$RIGHT" "$R" "$MB" "$AHEAD" "$BEHIND" \
  "$([ "$R_IS_ANC_L" = yes ] || [ "$L_IS_ANC_R" = yes ] && echo true || echo false)" \
  "$([ "$R_IS_ANC_L" = no ] && [ "$L_IS_ANC_R" = no ] && echo true || echo false)" \
  "$EXJSON" \
  "$ADDED" "$MODIFIED" "$DELETED" "$RENAMED" "$BINARY" "$INS" "$DEL"
echo '```'
} > "$OUT"

echo "report: $OUT"
echo "$LEFT ($(git rev-parse --short "$L")) vs $RIGHT ($(git rev-parse --short "$R")): $REL"
[ "$R_IS_ANC_L" = no ] && [ "$L_IS_ANC_R" = no ] && exit 3
exit 0
