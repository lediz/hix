# Readme !

1.- Adjust the paths of the go.bat compilation file

2.- Copy .\dll\<compiler>\*.dll to server path

3.- Test -> <root>/test/index.html
    You can execute url http://localhost:9090/test/index.html
    Only when hix.json -> app.env = "dev": in production the test harness is
    not served at all (src/app.prg gates AllowDir on the environment).

## Where the framework lives

This app sits **inside the HIX framework checkout**, one level below its root
(`../src`, `../hix_server.hbp`, `../lib/gcc/libhix_server.a`). Build the framework first:

```bash
cd .. && HB_ROOT=/path/to/harbour bash go_lib_gcc.sh && cd webapp
./go_gcc.sh --port 9090
```

`go_gcc.sh` resolves `${hix}` (used by `app.hbp` for the `.hbx`, the `.hbc` libpaths and
`incpaths`) from its own location: the **parent directory** — this layout — then the `../../..`
depth the upstream `examples/web/crud/` layout needs. `HB_ROOT` is yours to set; if it is wrong or
unset the script derives the Harbour build from `PATH`. Nothing in the build names a particular
machine or checkout. `app.hbp` needs no path edits.

## Secrets and local files

| File | What it is | Created by |
|---|---|---|
| `certs/hix.key` / `certs/hix.crt` | TLS pair (server.ssl = true) | `./gen_cert.sh` (0600) |
| `hix.keys.json` | The five HIX signing keys: csrf, jwt, session, token, resource | `./gen_keys.sh` (0600) |
| `www/config.json` | App config (sets/dbf). **Never holds keys** | HIX |

Signing keys are resolved by `src/app.prg` in this order:

```bash
export HIX_KEY_CSRF=...      # environment wins
export HIX_KEY_JWT=...       # (container / CI deployments)
export HIX_KEY_SESSION=...
export HIX_KEY_TOKEN=...
export HIX_KEY_RESOURCE=...
# then hix.keys.json, then generated once with the Harbour CSPRNG
```

They live OUTSIDE `paths.root` (www/) because HIX serves root-level docroot
files: a key inside `www/` is downloadable with a plain `GET`.  `GET
/config.json` is answered 404 by a route as well.  Rotating a key invalidates
every CSRF token, session id and resource id issued before it - delete
`hix.keys.json` (or one key inside it) and restart to rotate.

All three files are gitignored.  The HIX admin panel is disabled
(`hix.json -> admin.enabled = false`); see `srs/PENTEST-REPORT.md` for the full
remediation record.

## Starting the server

Use `./go_gcc.sh` (build + run).  It sets `umask 077` before exec'ing `app`
and tightens any session store left over from an earlier run.

HIX writes session files with `hb_MemoWrit()` + `FRename()` and never sets a
mode, so they inherit the process umask; Harbour core has no `umask()` or
`chmod()` (they fail to link: `HB_FUN_UMASK` / `HB_FUN_CHMOD`), so the app
cannot tighten them itself.  Under the usual `0022` the store is created 0755
and its records 0644 - world-readable session data (`srs/PENTEST-REPORT.md` §7).
With the launcher umask the store is 0700 and every session file is 0600,
which `test/verify-users-fixes.sh` checks as H-05a / H-05c.

## Running the test suites

The suites need **two different server modes** - start the app twice:

| Suite | Needs | Command |
|---|---|---|
| `test/test_users_module.sh` | plain HTTP on 9090 (`hix.json -> server.ssl: false`); `API` is hardcoded, no override | `./test/test_users_module.sh` |
| `test/test_customer_module.sh` | plain HTTP; honours `TEST_API=` but its `curl` has no `-k`, so it cannot reach the self-signed TLS server | `TEST_API=http://localhost:9090 ./test/test_customer_module.sh` |
| `test/verify-users-fixes.sh` | TLS (`server.ssl: true`); asserts block C-009 | `./test/verify-users-fixes.sh` |
| `test/bf_harness.sh` | TLS, `app.env = prod`; brute-force / timing probe against **this** local app only - never a deployed instance | see `srs/BRUTE-FORCE-PENTEST-PLAN.md` |

Restore `server.ssl: true` afterwards. Current results (identical before and after the repo
unification): users 55/60, customer 20/50, verify 125/0. The customer failures are mostly `/auth`
rate-limit (429) cascades - the suites share the per-IP login budget in
`www/middlewares/config.json` (`ratelimit.login_max` / `login_window`).

The suites write into `data/*.dbf` and generate `u_check.c`; both are gitignored.
