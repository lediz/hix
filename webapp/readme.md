# Readme !

1.- Adjust the paths of the go.bat compilation file

2.- Copy .\dll\<compiler>\*.dll to server path

3.- Test -> <root>/test/index.html
    You can execute url http://localhost:9090/test/index.html
    Only when hix.json -> app.env = "dev": in production the test harness is
    not served at all (src/app.prg gates AllowDir on the environment).

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
(`hix.json -> admin.enabled = false`); see PENTEST-REPORT.md for the full
remediation record.

## Starting the server

Use `./go_gcc.sh` (build + run).  It sets `umask 077` before exec'ing `app`
and tightens any session store left over from an earlier run.

HIX writes session files with `hb_MemoWrit()` + `FRename()` and never sets a
mode, so they inherit the process umask; Harbour core has no `umask()` or
`chmod()` (they fail to link: `HB_FUN_UMASK` / `HB_FUN_CHMOD`), so the app
cannot tighten them itself.  Under the usual `0022` the store is created 0755
and its records 0644 - world-readable session data (PENTEST-REPORT.md §7).
With the launcher umask the store is 0700 and every session file is 0600,
which `test/verify-users-fixes.sh` checks as H-05a / H-05c.
