#!/usr/bin/env bash
# --------------------------------------------------------------
# go_gcc.sh - Build and run HIX example CRUD app on Linux/gcc
#
# Linux equivalent of go_msvc64.bat / go_mingw64.bat. Compiles
# examples/web/crud/app.hbp against libhix_server.a and (if compile
# succeeds) executes the resulting binary.
#
# Usage:
#   ./go_gcc.sh                          build + run
#   ./go_gcc.sh --port 8080              build + run with args
#   HB_ROOT=/opt/harbour ./go_gcc.sh
# --------------------------------------------------------------

set -e
cd "$(dirname "$(readlink -f "$0")")"

# File creation mask for everything this process and the server it execs
# create: session store directory, session files, compiled views, logs.
# HIX writes session files with hb_MemoWrit() + FRename() and never sets a
# mode, and Harbour core exposes no umask()/chmod() (they fail to link:
# HB_FUN_UMASK / HB_FUN_CHMOD), so the application cannot tighten them from
# Harbour code - the launcher is the only place inside the project folder
# that can.  Under the usual 0022 the store lands 0755 and its files 0644,
# i.e. world-readable session records (PENTEST-REPORT.md §7).
umask 077

: "${HB_ROOT:=$HOME/harbour-core}"
export HB_ROOT   # needed if app.hbp references ${HB_ROOT}/... paths

HBMK2="$HB_ROOT/bin/linux/gcc/hbmk2"
if [ ! -x "$HBMK2" ]; then
    for cand in "$HOME/Projects/harbour" "$HOME/harbour" "/home/jack/Projects/harbour"; do
        if [ -x "$cand/bin/linux/gcc/hbmk2" ]; then
            export HB_ROOT="$cand"
            HBMK2="$HB_ROOT/bin/linux/gcc/hbmk2"
            break
        fi
    done
fi
if [ ! -x "$HBMK2" ]; then
    echo "ERROR: hbmk2 not found at $HBMK2" >&2
    echo "Set HB_ROOT to your Harbour build directory." >&2
    exit 1
fi

export PATH="$HB_ROOT/bin/linux/gcc:$PATH"

# ${hix} in app.hbp expands from this env var (-L${hix}, -i${hix}/src/include).
export hix="$(cd ../../.. && pwd)"
# If hix dir not found (e.g., this script is in pi-agent/webapp, not examples/web/crud),
# try one more level up.
if [ ! -f "$hix/hix_server.hbx" ]; then
    export hix="$(cd ../../../.. && pwd)"
fi

# HIX compiles www/controllers, www/middlewares and www/loaders at
# runtime via hb_CompileFromBuf. The preprocessor (src/hix_prepro.prg)
# looks up standard Harbour headers via $HB_INCLUDE — without it,
# dynamic .prg files that use hbclass.ch / hbmemory.ch / etc. fail to
# compile silently and the router returns 403 for their routes.
export HB_INCLUDE="$HB_ROOT/include${HB_INCLUDE:+:$HB_INCLUDE}"

# ${hix} in app.hbp expands from this env var.  The upstream script assumes
# examples/web/crud/; this app lives in pi-agent/webapp/, so fall back to
# sibling checkouts before giving up.
if [ ! -f "$hix/hix_server.hbx" ]; then
    for cand in "$HOME/Projects/hix" "$(cd ../../.. 2>/dev/null && pwd)/hix" "$(cd ../../../.. 2>/dev/null && pwd)/hix"; do
        if [ -f "$cand/hix_server.hbx" ]; then
            export hix="$cand"
            break
        fi
    done
fi

# ------------------------------------------------------------
# It is very important to validate the HBX files, otherwise it
# will produce silent errors.
# ------------------------------------------------------------

if [ ! -f "$hix/hix_server.hbx" ]; then
    echo "*** ERROR: $hix/hix_server.hbx not found." >&2
    echo "    ../../../go_lib_gcc.sh" >&2
    exit 1
fi
if [ ! -f "$HB_ROOT/include/harbour.hbx" ]; then
    echo "*** ERROR: $HB_ROOT/include/harbour.hbx not found." >&2
    echo "    Check your Harbour installation at $HB_ROOT." >&2
    exit 1
fi
if [ ! -f "$hix/lib/gcc/libhix_server.a" ]; then
    echo "*** ERROR: $hix/lib/gcc/libhix_server.a not found." >&2
    exit 1
fi

# ------------------------------------------------------------

# Remove previous binary so a link failure doesn't silently re-run stale.
rm -f app

"$HBMK2" app.hbp

# Windows-only intermediate artifacts (harmless if absent).
rm -f app.exp app.lib app.res

BIN="./app"
if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not produced." >&2
    exit 1
fi

# hix.json has server.ssl = true, and HIX only builds the SSL context per
# connection: without the certificate the server starts and then fails every
# request.  gen_cert.sh is idempotent - it only renews a missing or
# near-expiry certificate.
if [ -x ./gen_cert.sh ]; then
    ./gen_cert.sh
fi

# Signing keys live outside the document root (www/) with 0600 perms.
# Idempotent: it only creates hix.keys.json when it is missing.
if [ -x ./gen_keys.sh ]; then
    ./gen_keys.sh
fi

# Session store: tighten what an earlier, looser umask already created.  New
# files inherit 0700/0600 from the umask above, but a store created before
# this line stays 0755 with 0644 records inside it, and umask cannot fix an
# existing file.
for d in .sessions sessions; do
   if [ -d "$d" ]; then
      chmod 700 "$d"
      find "$d" -maxdepth 1 -type f -exec chmod 600 {} +
   fi
done

echo
"$BIN" "$@"
