#!/usr/bin/env bash
# ------------------------------------------------------------------
# gen_mysql_db.sh - P0 of INVENTREE-MYSQL-PLAN.md: the MySQL/MariaDB
#                   host, inside the project folder.
#
# WHY HERE AND NOT SYSTEM-WIDE
#   DEV-compliance T6 says "No change will be done outside project
#   folder". A packaged MariaDB (pacman -S mariadb, /var/lib/mysql,
#   /etc/mysql, a systemd unit) would violate it and needs root, which
#   this checkout does not have. Instead the server runs from .mysql/
#   with its data directory, socket, log and pid all under .mysql/ -
#   gitignored, so the database is state, never source. The client
#   library is the system one (/usr/lib/libmysqlclient.so, MariaDB's
#   MySQL-compatible symlink); the driver is pinned to it by explicit
#   override because its compiled-in default names a Debian multiarch
#   path that does not exist on this distro (probe_mysql prints
#   DllSource() = "override" to prove it).
#
#   The server binaries are NOT vendored here. They come from the
#   distribution's own package (see P0-MYSQL-HOST-RESULTS-2026-10-07.md
#   for the exact extraction), unpacked once into .mysql/bin.
#
# Idempotent: start / reuse / verify. Never prints the password.
#
#   ./gen_mysql_db.sh            start + verify (P0 gate)
#   ./gen_mysql_db.sh stop       shut the server down
#   ./gen_mysql_db.sh status     is it up?
# ------------------------------------------------------------------
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MYSQL_DIR="$DIR/.mysql"
BIN="$MYSQL_DIR/bin"
DATA="$MYSQL_DIR/data"
SOCK="$MYSQL_DIR/mariadb.sock"
PIDF="$MYSQL_DIR/mariadb.pid"
LOG="$MYSQL_DIR/nohup.out"
CRED="$MYSQL_DIR/credentials"
PROBE="$DIR/probe_mysql"

PORT=3306
DB="inventree"
USER="harbour"

die() { echo "gen_mysql_db.sh: $*" >&2; exit 1; }

# ------------------------------------------------------------
# 0600 for the credential file, like gen_keys.sh does for
# hix.keys.json (umask 077 + chmod 600).
# ------------------------------------------------------------
if [ -f "$CRED" ]; then
   chmod 600 "$CRED"
fi

case "${1:-start}" in
   status)
      if pgrep -f "$BIN/mariadbd" >/dev/null 2>&1; then
         echo "running (pid $(pgrep -f "$BIN/mariadbd"))"
         exit 0
      fi
      echo "not running"
      exit 1
      ;;

   stop)
      pkill -f "$BIN/mariadbd" 2>/dev/null || die "not running"
      echo "stopped"
      exit 0
      ;;

   start) : ;;
   *) die "unknown action '$1'" ;;
esac

[ -x "$BIN/mariadbd" ] || die "no server binary at $BIN/mariadbd - unpack the distribution's mariadb package into .mysql/ first (see P0-MYSQL-HOST-RESULTS-2026-10-07.md)"

# ------------------------------------------------------------
# Privilege tables: mariadb-install-db only works on a fresh data
# directory, so it is gated on the table actually being present.
# MariaDB 13 renamed the option to --datadir (not --data-dir), and
# the script derives its paths from --basedir, which is why .mysql/
# mirrors the package layout (bin/, share/mysql/).
# ------------------------------------------------------------
if [ ! -d "$DATA/mysql" ]; then
   echo "installing the system / privilege tables ..."
   mkdir -p "$MYSQL_DIR/tmp"
   "$BIN/mariadb-install-db" \
      --datadir="$DATA" \
      --basedir="$MYSQL_DIR" \
      --tmpdir="$MYSQL_DIR/tmp" \
      --auth-root-authentication-method=normal \
      --user="$(id -un)" >/dev/null
fi

# ------------------------------------------------------------
# Start (or reuse). setsid keeps the daemon alive when this script
# is run from a test harness or an editor that reaps child processes.
# ------------------------------------------------------------
if pgrep -f "$BIN/mariadbd" >/dev/null 2>&1; then
   echo "server already running (pid $(pgrep -f "$BIN/mariadbd"))"
else
    #  P2.3 of INVENTREE-MYSQL-PLAN.md sizes the cascade
   #  MySQL max_connections > HIX pool workers >= WDO pool_size. The WDO
   #  pool is 8 (webapp/src/app.prg -> DB_POOL), so the server gets pool +
   #  30 = 38: the margin is for anything that connects outside the pool.
   #  Little's Law for this app: 500 req/s x 10 ms = 5 active slots.
   #  This is a host option, not a repo change - the whole host lives under
   #  .mysql/, which is gitignored.
   setsid nohup "$BIN/mariadbd" \
      --datadir="$DATA" \
      --pid-file="$PIDF" \
      --socket="$SOCK" \
      --bind-address=127.0.0.1 \
      --port="$PORT" \
      --max-connections=38 \
      --user="$(id -un)" </dev/null >>"$LOG" 2>&1 &
   sleep 6
   pgrep -f "$BIN/mariadbd" >/dev/null 2>&1 || die "server did not start - see $LOG"
   echo "server started"
fi

# ------------------------------------------------------------
# P0 gate: the probe creates the project database + account (idempotent)
# and prints what the server reports about the character policy.
# Timeouts: the probe catches every statement, but a hung server must
# not hang this script either.
# ------------------------------------------------------------
if [ -x "$PROBE" ]; then
   if [ -f "$CRED" ]; then
      MYSQL_PWD="$(sed 's/^MYSQL_PWD=//' "$CRED")" timeout 60 "$PROBE"
   else
      timeout 60 "$PROBE"
   fi
   chmod 600 "$CRED" 2>/dev/null || true
else
   echo "probe_mysql not built - run: hix=<framework root> hbmk2 probe_mysql.hbp"
fi
