#!/usr/bin/env bash
# ------------------------------------------------------------------
# gen_keys.sh - create hix.keys.json, this installation's HIX signing
#               keys (csrf / jwt / session / token / resource).
#
# WHY NOT www/config.json:  paths.root is www/ and HIX serves root-level
# files of the document root, so "GET /config.json" used to hand out all
# five HMAC secrets (PENTEST-REPORT.md §1).  Keys now live OUTSIDE the
# docroot, are 0600, and are gitignored.  src/app.prg reads them and
# registers them with HIX_KeySet() before Start(); /config.json is
# answered 404 by a route.
#
# Precedence in src/app.prg:
#   HIX_KEY_CSRF / HIX_KEY_JWT / HIX_KEY_SESSION / HIX_KEY_TOKEN /
#   HIX_KEY_RESOURCE   >   hix.keys.json   >   generated on startup
#
# Rotating a key invalidates every CSRF token, session id and resource id
# issued before it - that is the point when a key has been exposed.
# Delete the file (or one key inside it) and restart to rotate.
# ------------------------------------------------------------------
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$DIR/hix.keys.json"

NAMES=(csrf jwt session token resource)

if [ -f "$FILE" ]; then
   echo "hix.keys.json already exists - nothing to do."
   chmod 600 "$FILE"
   exit 0
fi

umask 077

{
   echo '{'
   echo '  "keys": {'
   for i in "${!NAMES[@]}"; do
      sep=','
      [ "$i" = "$(( ${#NAMES[@]} - 1 ))" ] && sep=''
      printf '    "%s": "%s"%s\n' "${NAMES[$i]}" "$(openssl rand -hex 32)" "$sep"
   done
   echo '  }'
   echo '}'
} > "$FILE"

chmod 600 "$FILE"

echo "created:"
echo "  $FILE  (0600, gitignored, outside paths.root)"
for n in "${NAMES[@]}"; do
   echo "    $n  $(python3 -c "import json,sys;print(json.load(open('$FILE'))['keys']['$n'][:8]+'...')" 2>/dev/null || echo '-')"
done
