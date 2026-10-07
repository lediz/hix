# P0 (MySQL/MariaDB host) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P0 only** of `INVENTREE-MYSQL-PLAN.md`; P1 and later were not
> started. No file under `src/`, `www/`, `data/` or `examples/` was changed, and
> the WebApp was not rebuilt.

---

## 1. What P0 had to prove, and the verdict

| Step | Claim | Result |
|---|---|---|
| **P0.1** | a MySQL/MariaDB client library exists | ✅ `/usr/lib/libmysqlclient.so` → `libmariadb.so.3` (MariaDB's MySQL-compatible library, from `mariadb-libs 13.0.2-2`) |
| **P0.2** | the driver loads it **by explicit override**, not from the compiled-in default | ✅ `probe_mysql` prints `DllSource() = override`, `DllPath() = /usr/lib/libmysqlclient.so` |
| **P0.3** | a MariaDB instance answers on 127.0.0.1:3306, project database + account exist | ✅ `13.0.2-MariaDB`, database `inventree`, account `harbour`@`localhost`, and a **second connection through the project account succeeded** |
| **P0.4** | the character policy of that database, as the server reports it | ✅ `utf8mb4` / `utf8mb4_unicode_ci`, `sql_mode = STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION` |

P0 is green. The gate for P1 is: `./gen_mysql_db.sh start` exits 0 with the probe
block above it.

## 2. Deviation from the plan, and why it matters

`INVENTREE-MYSQL-PLAN.md` graded **P0.3 as ⚠️ against T6** ("No change will be done
outside project folder") and assumed a packaged MariaDB: `pacman -S mariadb`,
`/var/lib/mysql`, `/etc/mysql`, a systemd unit. That assumption turned out to be
unavailable **and** non-compliant:

* `sudo` needs a password here, so a system install was never possible;
* the whole host was therefore moved **inside the project folder**, which makes
  P0.3 ✅ T6 instead of ⚠️ — the server, its data directory, socket, log, pid and
  credentials all live under `webapp/.mysql/`, gitignored.

The server binaries are not vendored: they are the distribution's own package,
unpacked once. Reproduction:

```bash
# 50 300 400 bytes, sha256 a5842f2e2897294ba0695f82f5bbc5b1dfb6d41f8ce78dee1e3deee9fd08053c
curl -sS -O https://archive.archlinux.org/packages/m/mariadb/mariadb-13.0.2-2-x86_64.pkg.tar.zst
mkdir -p .mysql/bin .mysql/data .mysql/share
bsdtar -xf mariadb-13.0.2-2-x86_64.pkg.tar.zst --include='usr/bin/*' --include='etc/*' -C pkg
mv pkg/usr/bin/mariadbd pkg/usr/bin/mariadb-install-db pkg/usr/bin/my_print_defaults \
   pkg/usr/bin/resolveip pkg/usr/bin/mariadb-waitpid .mysql/bin/
mv pkg/usr/share/mysql .mysql/share/          # mariadb-install-db needs share/mysql/*.sql
```

`ldd` on the extracted `mariadbd` resolves every dependency against this system
(`libmariadbd.so.19` comes from `mariadb-libs`), so nothing was compiled here.

## 3. Facts the plan got wrong, found by running it

These are the corrections a later session must not re-discover.

| Plan said | Reality on MariaDB 13.0.2 / Harbour 3.2.1dev |
|---|---|
| `--data-dir` | **`--datadir`** (`-h`). `--data-dir` is not an option in this build at all — `strings` finds no `data-dir` in the binary — and every attempt to pass it was silently ignored, so the server tried `/var/lib/mysql` and aborted. `mariadb-install-db` also derives `bin/` and `share/mysql/` from `--basedir`, which is why `.mysql/` mirrors the package layout |
| `--etc-file`, `--log-file` | **unknown options** in this build; logging goes to stderr, redirected by `gen_mysql_db.sh` |
| `TRY / CATCH / FINALLY` are Harbour syntax | they are **`#xcommand` macros in `src/include/hix_const.ch:13-16`** (`TRY => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }`). Without `#include "hix_const.ch"` the compiler rejects `TRY` with "Incomplete statement", which is why the probe includes that header |
| `oConn:Exec()` for writes | **`Exec()` fails with a DynCall "Argument error" for the account statements** (`CREATE USER`, `GRANT`, `FLUSH PRIVILEGES`); `Query()` + `FetchAll(.F.)` + `Free()` runs them. `probe_mysql` uses `Query()` for everything |
| `CREATE USER 'u' WITH '<pwd>'` (MariaDB 11+ style) | **rejected**; the parser wants the legacy `IDENTIFIED BY '<pwd>'`. The built-in help table (`share/mysql/fill_help_tables.sql`, topic `GRANT`) is what gave the working form |
| account host `127.0.0.1` | the driver dials `127.0.0.1` but **MariaDB reports the peer as `localhost`**; an account bound to `%` was refused by that connection while a `localhost` account was accepted. The account is `harbour`@`localhost` |
| creating an account is idempotent | it is not: `CREATE USER` against an existing account does not reliably set the password, and the probe's green "created" line then still produced a refused connection. The probe **drops both spellings and recreates**, then `FLUSH PRIVILEGES` |
| privileges are live immediately | the **first** account-management statement of a server freshly bootstrapped by `mariadb-install-db` fails ("Operation CREATE USER failed"); `FLUSH PRIVILEGES` first makes it succeed |
| Harbour RTL has `hb_MemoWrite`, `Q()`, `FPutS`, `hb_Chmod` | the RTL exports **`hb_MemoWrit`** (`hix_config.prg:188` uses it); `Q()` and `FPutS` are not linked in, so the probe quotes with a literal and writes with `hb_MemoWrit`; the mode is set by the caller (`chmod 600`, like `gen_keys.sh`'s `umask 077`) |
| a backtick is a safe identifier quote in source | Harbour's preprocessor eats a literal backtick; the probe builds it as `Chr( 96 )` |
| MariaDB's charset is `utf8` | MariaDB 13 reports **`utf8mb4` / `utf8mb4_unicode_ci`** — the plan's P0.4 decision is already the server default, no `SET CHARACTER SET` needed |
| an uncaught Harbour error is harmless | it opens the **interactive "Quit" dialog**, which hung the whole tool call. Every statement in the probe is inside `TRY/CATCH/FINALLY`, and `WDO_MySql():New()` is wrapped too, because a refused connection raises |

## 4. What was written

| Path | What | Tracked? |
|---|---|---|
| `webapp/gen_mysql_db.sh` | P0 lifecycle: install tables if missing, start/reuse the server, run the P0 gate, keep `credentials` at 0600. Mirrors `gen_keys.sh` / `gen_cert.sh` | yes |
| `webapp/probe_mysql.hbp` | build recipe for the probe — same link shape as `app.hbp` (`${hix}/hix_server.hbx`), `hbmk2` only | yes |
| `webapp/test/probe_mysql.prg` | the probe: P0.1–P0.4, creates the database + account idempotently, never echoes the password | no — `webapp/test/` is local tooling, same as the other probes |
| `webapp/.gitignore` | `+ .mysql/` (runtime DB, log, socket, binaries, credentials) `+ probe_mysql` (built binary) | yes |
| `webapp/.mysql/` | the running host: `bin/` `data/` (139 MB, InnoDB preallocated) `share/mysql/` `mariadb.sock` `nohup.out` `credentials` (0600) | no, gitignored |

Nothing was added under `src/`, `www/`, `data/`, `examples/`, `resources/`.

## 5. Verification actually run

```
$ ./gen_mysql_db.sh status      -> not running
$ ./gen_mysql_db.sh stop        -> "not running" (nothing to stop)
$ ./gen_mysql_db.sh start       -> server started, then the probe block:
      P0.2 source: override        P0.2 path: /usr/lib/libmysqlclient.so
      server 13.0.2-MariaDB        client 3.4.10        driver WDO_MYSQL_CONN 2.0
      database inventree (already there)
      user   harbour
      P0.4 charset utf8mb4   collation utf8mb4_unicode_ci
      sql_mode STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

* **idempotency**: a second run with `MYSQL_PWD` taken from `.mysql/credentials`
  reproduced the same green result (database "already there", account recreated,
  connection through the project account accepted) — exit 0 both times.
* **no interactive hang**: the probe was run under `timeout 60` and returned in
  under a second; the failure modes that used to open the "Quit" dialog
  (syntax error, refused connection, bad array index) are all caught now.
* **`git check-ignore`** confirms `webapp/.mysql/credentials` and `webapp/probe_mysql`
  are ignored, and `gen_mysql_db.sh` / `probe_mysql.hbp` are not.

## 5.1 Restart hazards found while cycling the server

| Found | Effect | Handling |
|---|---|---|
| `status` reported "not running" for a server that **was** running | `pgrep -f "$BIN/mariadbd"` matches the absolute path the script starts; a server started by hand with a relative path (`.mysql/bin/mariadbd`) is invisible to it | always go through `gen_mysql_db.sh`; never start `mariadbd` by hand |
| after a `SIGTERM` stop, one restart logged `Plugin 'InnoDB' registration as a STORAGE ENGINE failed` → `Could not open mysql.plugin table: "Unknown storage engine 'Aria'"` → `Failed to initialize plugins` → **Aborting** | the data directory still held `aria_log.00000001` / `aria_log_control` from the aborted first bootstrap, and this build has no Aria plugin | the next stop removed them and the following start reached `ready for connections` cleanly. A killed server must not be restarted over an inconsistent data directory without checking the log first |
| `mariadb-install-db` also created `test`, `performance_schema`, `sys`, `mariadb_upgrade_info` in the data directory | the project database is `inventree`; the others are MariaDB's own | P1 must not treat "the database" as "the only database" |
| the log carries `Aborted connection ... closed normally without authentication` warnings on every probe run | the probe's `Close()` of connections that never authenticated (the expected "already exists" paths) | benign; ignore, but do not mistake them for a leak |
| `.mysql/` is **186 MB** (binaries 26 MB, data 139 MB — InnoDB preallocates `ibdata1` 12 MB + three 10 MB undo files — `share/mysql` 5.6 MB) | disk, not repo: the whole tree is gitignored | keep it out of any commit; `du -sh .mysql` is the check |

## 6. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style | ✅ | the probe is a CLI tool; the app itself is untouched |
| **T2** No SQL | ⚠️ **retroactive** | the probe runs SQL, and at the time P0 ran the clause was still binding — `DEV-compliance.md` had not been touched. The exception was recorded **after** this run, on 2026-10-07, and its scope starts at **P1**: P0's probe is the same WDO pool path the exception licenses, but it is covered by the clause's intent, not by its recorded scope. Nothing in P0 needs redoing; the record just does not claim a green T2 it did not have |
| **T4** HIX + Harbour only | ✅ | driver is framework code (`src/wdo/mysql/*.prg` → `hix_server.hbx`); the probe links `${hix}/hix_server.hbx` and builds with `hbmk2` |
| **T5** tools in the project folder | ✅ | `gen_mysql_db.sh`, `probe_mysql.hbp`, `test/probe_mysql.prg` |
| **T6** nothing outside the project folder | ✅ **improved over the plan** — the server, its data and its credentials are all under `webapp/.mysql/`; the only outside input is the distribution package, downloaded, not installed |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched; the probe has its own `.hbp`, like every other probe here |
| **T8** port 9090 | ✅ | untouched; the MariaDB listens on 3306, which is not the web service |

## 7. Ready for P1, and what P1 must not assume

Ready: a MariaDB 13.0.2 answering on 127.0.0.1:3306, database `inventree`,
account `harbour`@`localhost` with a 32-hex password in `.mysql/credentials`
(0600), `utf8mb4` / `utf8mb4_unicode_ci`, and a proven path from Harbour to it
(`WDO_MySql():New(...)` with the library pinned).

P1 must not assume:

1. **the server is running.** `hix.json` has no MySQL pool yet; `Start()` calls
   `HIX_InitPoolsFromConfig()` and **aborts** if a declared pool fails, so adding
   the `databases.mysql` block (P2.1) without `./gen_mysql_db.sh start` makes the
   app unstartable. That ordering is now a script obligation, not a discovery.
2. **`Exec()` works for writes.** It does not for the account statements; use
   `Query()` + `Free()`.
3. **the account host.** `localhost`, not `%`, not `127.0.0.1`.
4. **`--data-dir`** anywhere in a tool name or option: this build spells it `--datadir`.
5. **that the DBF state went away.** `webapp/data/*.dbf` and
   `hix.json → app.auto_close_dbf` are untouched — Step 0.2 (Option A: MySQL
   replaces DBFCDX) was **not** taken this session.
