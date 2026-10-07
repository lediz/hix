# P2 (the pool, and the app starting with it) — what was actually done, 2026-10-07

> **Record of a run.** This file reports what was executed on this checkout. It
> implements **P2 only** of `INVENTREE-MYSQL-PLAN.md` (P2.1–P2.5). P0 and P1 are
> green (`P0-MYSQL-HOST-RESULTS-2026-10-07.md`, `P1-MYSQL-SCHEMA-RESULTS-2026-10-07.md`).
> P3 was not started: there is no MySQL DAL, no handler queries the pool, and the
> DBF DAL in `www/models/t*.prg` is what still ships.

---

## 1. What P2 had to prove, and the verdict

| Step | Claim | Result |
|---|---|---|
| **P2.1** | the `mysql` pool exists and is registered | ✅ boot banner: `» WDO Loaded  MariaDB 2.0`, `» RDBMS MariaDB Server 13.0.2-MariaDB`, `» RDBMS MariaDB Client MariaDB 3.4.10`; `/health/db` → `{"ok":true,"driver":"MYSQL","size":8,"busy":0,"free":8,"closed":false}` |
| **P2.2** | `read_timeout_s` above `exec_timeout_ms` | ⚠️ **set, not reproducible.** `read_timeout_s = 45` against `hix.json → server.exec_timeout_ms = 30000`, and `app.prg` raises it if a smaller value is passed. The mechanism the plan warns about did **not** reproduce: `SELECT SLEEP(8)` finished in 8.0 s with `nReadTimeout` set to 3 s (see §3) |
| **P2.3** | the cascade `MySQL max_connections > HIX workers ≥ WDO pool_size` | ✅ WDO `pool_size = 8` (Little's Law: 500 req/s × 10 ms = 5 slots, so 8 is the margin), `hix.json → pool_http.workers = 64`, and the running `mariadbd` carries **`--max-connections=38`** (pool + 30, added to `./gen_mysql_db.sh`). `free` = 8 on every hit, never 0 |
| **P2.4** | startup ordering, decided rather than discovered | ✅ **dev-friendly branch, and it had to be built here.** With the host down the app starts, binds 9090, `/health/db` answers **503** with diagnostics. Neither of the framework's two abort paths is usable: both `Inkey( 0 )` and hang a non-interactive start (§3) |
| **P2.5** | credentials not in the docroot | ✅ `DB_PWD`/`DB_USER`/`DB_NAME`/`DB_HOST`/`DB_PORT`/`DB_DLL` from the environment; `www/config.json` still has **`"databases": {}`**; `curl -k https://localhost:9090/config.json` → **404**, and no response in the run carries a password |

P2 is green. The gate for P3 is: `./gen_mysql_db.sh start` + the app started with
`DB_PWD` set → `/health/db` 200 with `free` never 0; and with the host down → the
app still starts and `/health/db` is 503.

## 2. What was written

| Path | What | Tracked? |
|---|---|---|
| `webapp/src/app.prg` | `_DbPoolEnsure()` (env → `WDO_InitPoolMySqlEx( "mysql", hParams )`), `_DbReachable()` (the TCP preflight), `_EnvOr()`, `_DbDllDefault()`, the `WDO_EndPoolMySql()` on exit, and the header that says where the credentials come from | yes (already tracked; modified) |
| `webapp/www/routes/web.json` | one route: `sys.health_db` → `/health/db`, `controllers/healthdb.prg`, `GET`, middleware `MyAppAuth` | yes |
| `webapp/www/controllers/healthdb.prg` | the controller: `WDO_PoolStats("mysql")`, 200 with `ok/driver/size/busy/free/closed`, 503 with a hint when no pool is registered | new |
| `webapp/gen_mysql_db.sh` | `--max-connections=38` on the `mariadbd` start (P2.3's server side of the cascade) | yes (modified) |
| `webapp/app` | rebuilt with `hbmk2 app.hbp` (T7: `app.hbp` lists exactly `src/app.prg`, so the change is a rebuild, not a new build) | no — `app` is gitignored, it is a build product |

Nothing was added under `www/models/`, `www/views/`, `www/middlewares/`, `data/`,
`src/wdo/` or `resources/`. **The framework was not touched** — every trap found
here was worked around in `app.prg`, which is the one source `app.hbp` builds.

## 3. Facts the plan got wrong, found by running it

| Plan said | Reality on HIX 2.3.10 / Harbour 3.2.1dev / MariaDB 13.0.2 |
|---|---|
| P2.1 "fill the `"databases": {}` block" and P2.5 "read the credentials from the environment and use `WDO_InitPoolMySqlEx()` **instead of** the declarative block" | they are alternatives, not both. P2.5 is the compliant one (`www/config.json` is inside `paths.root`), so the block **stays empty** and `HIX_InitPoolsFromConfig()` logs `WDO_LOG_POOLS_INIT_NONE` ("no `databases` section"). The pool is built in `app.prg` with the same field names `WDO_InitPoolMySqlEx( cKey, hParams )` takes (`src/wdo/mysql/wdo_mysql_pool.prg:88`), which is what makes the two paths interchangeable |
| P2.4 "keep the abort (production-correct)" | **the abort hangs.** `src/wdo/wdo_config.prg:109-110` prints `==> Fatal: database pool ...` then `Inkey( 0 )` then `QUIT`. A container, a supervisor or a test harness never sends that key |
| P2.4 "do not discover this by watching `==> Error: Cannot load MySQL DLL`" | it had to be discovered exactly that way, and there is a **second** one. The WDO driver aborts on its own: `_WdoMySqlReportDown` (`src/wdo/mysql/wdo_mysql.prg:1484-1486`) prints `==> Error: Mysql not running (127.0.0.1:3306)` / `Press any key to exit...` then `Inkey( 0 )`, `ErrorLevel( 1 )`, `QUIT`; `_WdoMySqlReportDllFail` does the same for a bad DLL. So a pool built against a dead server does not fail — **it blocks the start forever and 9090 is never bound**. Fix used here: `_DbReachable()` probes `host:port` with `hb_socketConnect` **before** the driver is asked, mirroring the driver's own `_WdoMySqlTcpProbe` (including the `localhost` → `127.0.0.1` remap) |
| `hix.json → server.exec_timeout_ms = 30000` vs `read_timeout_s: 30` being "the default to beat" | the ordering rule is kept (45 > 30 s, and `app.prg` raises a smaller value with a printed warning), but the **effect** the plan describes is not what this client library does. With `oConn:nReadTimeout := 3`, `SELECT SLEEP( 8 )` still returned one row after 8.0 s. `MYSQL_OPT_READ_TIMEOUT`/`MYSQL_OPT_WRITE_TIMEOUT` are applied (`src/wdo/mysql/wdo_mysql.prg:327-333`) — MariaDB's library retries the read instead of failing it. The zombie-slot risk is recorded as **not reproduced**, not as fixed |
| `WDO_Get("mysql")` vs the framework's `WDO_MYSQL_POOL_KEY "MYSQL"` | not a trap, and it must not be "fixed": `WDO_RegisterPool` uppercases on registration (`src/wdo/wdo_pool.prg:393`) and `WDO_Get`/`WDO_PoolStats` uppercase on lookup. `"mysql"` and `"MYSQL"` are the same pool — declaring both would be the real bug |
| the pool is closed at shutdown | `HIX_EndPoolsFromConfig()` (`src/hix_server.prg:384`) closes **config-declared** pools only. Ours is built in code, so `app.prg` calls `WDO_EndPoolMySql()` after `oServer:Start()` returns — and `WDO_EndPoolMySql()` unregisters only `WDO_MYSQL_POOL_KEY`, so a second pool under another key would never be closed by it |
| Harbour's `Main( aArg )` receives an argument array | it receives the first argument as a string (P1's finding, re-hit) |
| `hb_getEnv()` answers NIL for an unset variable | it answers **`""`**. And `hb_defaultValue( hb_getEnv( "DB_POOL" ), "8" )` does **not** substitute — it substitutes through a by-reference argument, so a temporary gets handed back unchanged. Result on the first run: `pool_size = Val("") = 0`, `connect_timeout_s = 0`, and `dll = ""` → `==> Error: Cannot load MySql DLL` + the `Inkey` above. `_EnvOr()` is explicit about both |
| the driver's compiled-in library default works on Linux | confirmed and worse than the plan says: it resolves to `/usr/lib/x86_64-linux-gnu/libmysqlclient.so` (`src/wdo/mysql/wdo_mysql.prg:1432`), which does not exist on this distro. `_DbDllDefault()` pins `/usr/lib/libmysqlclient.so` and the boot line reports it |
| `/health/db` answers 200 to anyone | it is `MyAppAuth` (SecHeaders + Session + `HIX_MwIsAuth`), so unauthenticated is a **302** to `/login`, not a 401. The response carries pool counters only — no host, user, table name or password |

## 4. Verification actually run

```
$ hbmk2 app.hbp                                   -> no errors, app 6 848 144 B

# host UP, DB_PWD exported from .mysql/credentials (0600, never echoed)
app.prg: MySQL/MariaDB pool 'mysql'
app.prg:   harbour@127.0.0.1:3306/inventree driver=mariadb
app.prg:   pool_size=8 read_timeout_s=45 connect_timeout_s=10
app.prg:   client library pinned: /usr/lib/libmysqlclient.so
» WDO Loaded            MariaDB 2.0
» RDBMS MariaDB Server  13.0.2-MariaDB
» RDBMS MariaDB Client  MariaDB 3.4.10

$ curl -k -s -o /dev/null -w '%{http_code}' https://localhost:9090/config.json
404
$ curl -k -s https://localhost:9090/health/db                       (no session)
302
$ (login admin/1234) curl -k -s -b "$CK" https://localhost:9090/health/db
{"ok":true,"driver":"MYSQL","size":8,"busy":0,"free":8,"closed":false}
$ ... again
{"ok":true,"driver":"MYSQL","size":8,"busy":0,"free":8,"closed":false}

$ ps -o args= -p $(pgrep -f '.mysql/bin/mariadbd') | grep max-connections
--max-connections=38

# DBF DAL not regressed by the change
/main -> 200   /users/grid -> 200   /customer/grid -> 200

# host DOWN (./gen_mysql_db.sh stop first), DB_PWD still set
app.prg: nothing is listening on 127.0.0.1:3306 - no pool is started.
app.prg: the app starts anyway; /health/db answers 503 ...
» Server startup at 07/10/26 15:53:52          (9090 bound, no hang)
$ (login) curl -k -s -b "$CK" https://localhost:9090/health/db
{"ok":false,"error":"no MySQL/MariaDB pool registered",
 "hint":"the pool is started by app.prg from DB_PWD/DB_USER/DB_NAME in the environment, not from www/config.json (that file is inside the document root)"}
```

* **idempotency**: `./gen_mysql_db.sh start` after a stop reproduced the green
  probe block and exited 0; the app was started four times during this step and
  every start either bound 9090 or said why it would not.
* **no hang**: the dead-host run bound 9090 within 9 s. The runs that used to
  hang are the framework's own paths, which are now never reached because
  `_DbReachable()` answers first.

## 4.1 Restart hazards found while cycling this step

| Found | Effect | Handling |
|---|---|---|
| starting the app while a previous one still holds 9090 | two servers, and the checks below hit the older one | `pkill -x app` before each start; `ss -ltnp \| grep :9090` is the check. `pgrep -f` also matched the shell running the command, which killed the harness rather than the server |
| `hb_getEnv` returning `""` for an unset variable | `pool_size = 0` and `dll = ""` → the driver's DLL abort, i.e. a **pool of zero connections** that still reports `RESULT ok` at the tool level | `_EnvOr()`; and `WDO_InitPoolMySqlEx` returns `.F.` when zero connections opened, which `app.prg` now logs instead of swallowing |
| the app was started with `DB_PWD` set and the host down **before** `_DbReachable()` existed | the process printed `Press any key to exit...` and never bound 9090; `ss` showed nothing, which looks like "not started" rather than "hung" | that is why the probe exists; the symptom is indistinguishable from a silent failure, so it is recorded here |
| `WDO_EndPoolMySql()` is called only when `_DbPoolEnsure()` returned `.T.` | closing a pool that was never registered is a no-op, but a pool registered under a **different** key would leak | one key (`HIX_DB_POOL_KEY "mysql"`) for now; P3 must not add a second pool without its own close |

## 5. Compliance of what was done

| Test | Verdict | Where |
|---|---|---|
| **T1** HIX style only | ✅ | the route is `www/routes/web.json` + `www/controllers/healthdb.prg` + `MyAppAuth`, the same MVC shape the audited `customer.*` and `users.*` blocks use; the pool bootstrap sits in `src/app.prg`, the one source `app.hbp` builds |
| **T2** No SQL | ✅ **under the exception recorded 2026-10-07** | P2 runs no SQL at all — it configures a pool and reads its own counters. The exception's scope starts at P1, so it covers this phase; the app still contains no SQL |
| **T4** HIX + Harbour only | ✅ | `WDO_InitPoolMySqlEx` / `WDO_PoolStats` / `WDO_EndPoolMySql` are framework code (`src/wdo/mysql/`, `src/wdo/wdo_pool.prg`); `hb_socketOpen/Connect/Close` are Harbour core RTL. No framework file was edited |
| **T5** tools in the project folder | ✅ | everything changed is under `webapp/` |
| **T6** nothing outside the project folder | ✅ | the only host-side change is an option on the server that already lives under `webapp/.mysql/` |
| **T7** `hbmk2 app.hbp` only | ✅ | `app.hbp` untouched, still lists exactly `src/app.prg`; the rebuild is what P2.5 predicted |
| **T8** port 9090 | ✅ | `hix.json → server.port` untouched; the checks below ran against 9090 over the existing self-signed TLS (`-k`) |

## 6. Ready for P3, and what P3 must not assume

Ready: the app starts with a **registered `mysql` pool of 8 connections** against
MariaDB 13.0.2, `/health/db` reports its counters, the 38 shipped tables are
loaded and seeded (P1), and the app also starts **without** the pool.

P3 must not assume:

1. **that a handler has ever touched the pool.** Nothing in `www/` calls
   `WDO_Get` yet; `/health/db` deliberately does not (it must answer while every
   slot is busy). P3.4's discipline — one `WDO_Get` per handler, `Close()` on
   every exit path — is unverified until P3.1 writes the DAL.
2. **that `read_timeout_s` protects a slot.** It is set to 45 as the plan says,
   and it demonstrably does not interrupt a long query on this library (§3).
   The dispatcher's `exec_timeout_ms = 30000` is the only bound that actually
   fires today.
3. **that the pool survives a dead server by failing.** It is not built at all
   when `_DbReachable()` fails, so `WDO_PoolStats` returns NIL and the answer is
   503. A pool that opened zero connections is a different state (the app logs
   it and continues) and P3.6's error mapping must not confuse the two.
4. **that a second pool key is free.** `WDO_EndPoolMySql()` closes
   `WDO_MYSQL_POOL_KEY` only.
5. **that the DBF DAL went away.** `hix.json → app.auto_close_dbf` is still
   `true`, `data/*.dbf` is still the app's state, and `/main`, `/users/grid`,
   `/customer/grid` still answer 200 from DBF. Step 0.2 (Option A) has still not
   been taken — P3.1 introduces the MySQL DAL object, and the switch is a
   product decision that has to be recorded when it happens, not implied by a
   pool existing.
6. **that `www/config.json` is the place to configure the pool.** It is inside
   `paths.root`; the 404 for `/config.json` is a route in `src/app.prg:125`, not
   a property of the static dispatcher, so a new docroot file is still
   downloadable unless a route says otherwise.
