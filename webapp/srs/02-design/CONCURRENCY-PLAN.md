# Concurrency plan — connections and store read/write under load

> **Report only.** No file was changed, no tool built, no server started, no
> request sent. This is a plan and a measurement of the current surface.
>
> Date: 2026-10-08 · Compliance baseline: `01-requirements/DEV-compliance.md`

---

## 1. What is actually there

Measured from `hix.json`, `src/dbf/hix_dbf.prg`, and `www/`.

### The server's concurrency, as configured

| Knob | Value | Meaning |
|---|---|---|
| `server.maxconn` | 1024 | connections the server will hold |
| `server.timeout` | 30 s | connection timeout |
| `server.exec_timeout_ms` | **30 000 ms** | a handler may run 30 s before the dispatcher kills it |
| `pool_http.workers` | **64** | HTTP worker slots — the real ceiling on concurrent handlers |
| `pool_http.queue_size` | 256 | requests queued behind the workers |
| `pool_http.read_timeout_ms` | 2000 | |
| `pool_http.keep_alive_max` | 100 | |
| `pool_ws.workers` | 100 | |
| `pool_rest.workers_sse / longpoll` | 20 / 10 | |
| `pool_hix.workers` | **4** | the pool that serves **HIX-style app handlers** |
| `monitor.alert_pct` | 75 | warns at 75 % pool utilisation |

**The binding number is `pool_hix.workers = 4`, not 64.** The app runs in HIXSTYLE
mode (`hix.json` `hixstyle.enabled: true`, confirmed by the suite at T48), so
handlers come off the **4**-worker pool. Above 4 simultaneous app handlers, requests
queue.

### The store's concurrency

| Fact | Source |
|---|---|
| RDD default is **DBFCDX** | `hix.json` banner prints it; `www/config.json` `"dbf": { "rddname": "DBFCDX" }` |
| Workareas are **thread-local** in Harbour MT | `src/dbf/hix_dbf.prg:690` comment — aliases are prefixed with `hb_threadID()` to remove ambiguity |
| Writes take a lock | `Update()` and `Delete()` call `::Rlock()` (`:393`, `:616`); `RLock` retries for `::nTime` = **3 s** (`:843`) then fails |
| `lExclusive` default | `.F.` (`:37`) — the store is opened **SHARED**, not exclusive |
| `auto_close_dbf` | `true` in `hix.json` — a forgotten handle is logged, not leaked |
| Harbour core exposes **no `umask()`/`chmod()`** | `go_gcc.sh:21` — they fail to link |

### The app's own state, which is where the real contention is

| State | Where | Contention |
|---|---|---|
| Session store | `.sessions/sess_*`, `storage: file`, `crypt: true`, `lifetime: 3600` | one file per session; concurrent logins create files |
| Login limiter | `www/middlewares/myapplogin.prg` via `HIX_MwRateLimitFactory` | **sliding window per client IP**, `login_max: 5` / `login_window: 60` |
| Global limiter | `HIX_MwRateLimit` 60 req/min | per IP, applies to every route |
| Flash | `UFlash('users')` / `UFlash('customer')` | **per-module singleton** — see §3 C-1 |
| DBF | `data/{users,customers,states}.dbf` | one file per table, one writer at a time |

## 2. What the plan tests

Two axes, and they are not the same thing.

**Axis A — connections.** Can the server hold, route, and tear down many
connections without leaking, and does the queue behave when workers are exhausted.

**Axis B — store read/write.** Do concurrent reads and writes to a DBF produce a
consistent store, and does a lost lock show up or silently corrupt.

### A. Connections

| # | Test | Method | Expected |
|---|---|---|---|
| A-1 | Hold N connections without completing a request | open N sockets to :9090, send nothing | server holds them; `maxconn` 1024 is the ceiling; no thread explosion below it |
| A-2 | Keep-alive reuse | same socket, sequential requests | `keep_alive_max: 100` bounds it; connections are reused, not re-TLS'd |
| A-3 | **Worker exhaustion** | 4 + k simultaneous app handlers (logged in, hitting `/customer/grid`) | the first 4 served; the rest **queue** (`queue_size: 256`), not 500; past the queue, a clean rejection |
| A-4 | Queue overflow | > 260 simultaneous | a bounded answer, not a crash, not a hang |
| A-5 | Slow handler | a route that sleeps past `exec_timeout_ms` | killed at 30 s, slot returns to the pool, **no zombie** |
| A-6 | TLS teardown | connections closed mid-handshake | the log shows `SSL: handshake error 1001` (observed today) and nothing leaks |
| A-7 | Idle timeout | connections left past `timeout: 30` | closed, slot freed |
| A-8 | Pool accounting | `/hix-status` metrics before/during/after | `busy` returns to 0; `monitor.alert_pct` fires at 75 % of 4 = **3** workers |

### B. Store read/write

| # | Test | Method | Expected |
|---|---|---|---|
| B-1 | Concurrent reads | k sessions GET `/customer/grid` | every response identical; a read never sees a half-written record |
| B-2 | Concurrent writes, **different** records | k sessions POST `/customer/:id/update` on distinct ids | all k land; no record is half-updated |
| B-3 | Concurrent writes, **same** record | k sessions POST `/customer/6/update` | **exactly one** wins; the rest get a clean answer, not a torn record. Today there is no `VERSION` column in `users.dbf`, so this is last-writer-wins — the plan must state which answer is acceptable |
| B-4 | Write during read | a GET and a POST overlapping | the GET shows the record either fully before or fully after |
| B-5 | **Lock failure** | force `Rlock()` to fail (hold a lock past 3 s) | the handler answers, it does not 500 silently; `DBF_ERR_LOCK` is surfaced |
| B-6 | Soft-delete under concurrency | DELETE while a grid scan runs | the grid shows the record or not, never a half-deleted row |
| B-7 | Session file race | k simultaneous logins | k distinct session files, no partial file, modes 0600 under `umask 077` |
| B-8 | Limiter under concurrency | k IPs × m attempts | each IP gets its own window; a shared counter would be a defect |
| B-9 | **Flash race** | two sessions fail validation "simultaneously" | see C-1 — this is a known shared-state defect, the test proves or disproves it |

## 3. Defects the plan expects to find, and why

These are read off the code, not guessed. Each is a hypothesis the tests settle.

| # | Hypothesis | Evidence | Why it matters |
|---|---|---|---|
| **C-1** | `UFlash('users')` is a **per-module singleton**. `Edit()` reads it, `Store()` writes it. Two sessions failing validation "at once" can read each other's `input`/`errors` | `www/controllers/masters/users.prg` reads `UFlash('users'):Get('input')`; the suite's D-10b/D-10c assert the flash is drained | a validation error from session B can render into session A's form. **Cross-session leak** |
| **C-2** | `pool_hix.workers = 4` while `pool_http.workers = 64` — the app's ceiling is 1/16th of what the config suggests | `hix.json`; `hixstyle.enabled: true` | throughput expectations set against 64 are wrong by an order of magnitude |
| **C-3** | `login_max: 5` per 60 s **per IP** makes any concurrency test that logs in fail spuriously | `www/middlewares/config.json`; already observed — the suites need it widened to complete | every B-test needs either one session reused or the limiter widened for the run |
| **C-4** | `lExclusive = .F.` means the DBF is opened SHARED; two handlers can hold the same table at once, and only `Rlock` separates them | `src/dbf/hix_dbf.prg:37`, `:168` | the lock is the only guard; a path that writes without it is unprotected |
| **C-5** | `Update()`'s lock retries for 3 s then **fails**; under k-way contention on one record, most writers get the failure, not a wait | `src/dbf/hix_dbf.prg:843` (`::nTime` = 3) | contention turns into errors, not throughput |
| **C-6** | `exec_timeout_ms` 30 000 vs `read_timeout_ms` 2000 — a handler that blocks on a DBF lock can exceed the read timeout while still inside the exec timeout | `hix.json` | a slot can be considered dead while still running |

## 4. What the plan must NOT do

| Temptation | Why not |
|---|---|
| Use a 3rd-party HTTP benchmark (`ab`, `wrk`, `siege`) | T1/T3: only the HIX framework and Harbour. The harness is a **Harbour tool in `webapp/test/`**, like the existing `probe_*.prg` and `bf_harness.sh` |
| Add a database to test store contention | there is no engine; the store is a DBF. Introducing one breaks "No SQL" with no exception |
| Raise `pool_hix.workers` to make tests pass | that changes the shipped configuration. If a test needs more workers, the **run** sets it and the record says so; `hix.json` keeps its production value |
| Widen `login_max` permanently | same rule: widen for the run, restore after. The shipped value is 5/60 s |
| Test by hand in a browser | not reproducible, not recordable |

## 5. How it would be built (not built now)

One Harbour tool, `webapp/test/concurrency_harness.prg` + `.hbp`, in the shape the
existing tools already use:

- **Client side:** `hb_socketConnect` (`hbsocket.ch`, already used by the pool probe
  that was removed — the primitive is Harbour core, not framework) or `hbcurl`
  multi-handle. Threads via Harbour MT (`hb_threadID` is already in the framework's
  own code at `src/dbf/hix_dbf.prg:696`).
- **Assertions against the store, not the HTML:** `test/dbf_dump.py` already exists
  and prints `records=N live=N deleted=N` plus one line per record. That is the
  right primitive for B-1..B-6 — it reads the RDD files directly.
- **Pool accounting:** `/hix-status` metrics (the framework's own route).
- **Output:** a results table, and a `RESULT : ok` / `RESULT : failed` line,
  matching the convention every existing tool prints.

The `.hbp` follows `probe_seek.hbp`'s shape (`-n`, `-iwww`, `${hix}/hix_server.hbx`,
`${hix}/hix_server.hbc`) — that link shape is already proven to work for a tool
that needs the framework.

## 6. Compliance grading of the plan

| Clause | Grade | Why |
|---|---|---|
| T1 HIX framework + Harbour only | ✅ | the harness is a Harbour tool; no external benchmark |
| T3 no 3rd-party web UI | ✅ | no new dependency |
| T5 tools in the project folder | ✅ | `webapp/test/` |
| T6 nothing outside the project folder | ✅ | the store is `webapp/data/`; the harness writes only to `webapp/test/.out/` (the pattern `tests/.out/` already shows) |
| T7 `hbmk2 app.hbp` only | ✅ | the harness has its own `.hbp`, like every other adhoc tool here; `app.hbp` is untouched |
| T8 port 9090 | ✅ | the harness targets the configured port |
| "No SQL", no exception | ✅ | the store is a DBF; nothing opens an engine |

## 7. What the results would show, and the trap

The suites are **serial**. `test_users_module.sh` reaches 60/60 today with one
session at a time. Nothing in the tree has ever sent two simultaneous requests.
So every hypothesis in §3 is **untested**, and C-1 in particular is a security
claim (cross-session flash leak) that has never been checked.

Two traps the plan must not fall into:

1. **A concurrency test that logs in per request hits C-3** and reports 429
   cascades that look like app defects. This already bit the existing suites —
   they need `login_max` widened to complete. The harness must either reuse one
   session or widen for the run and say so.
2. **A concurrency test that asserts on rendered HTML is markup-coupled** — the
   aesthetics plan changes markup, and these suites grep it. The B-tests assert
   against `dbf_dump.py` output instead, which is markup-independent.

## 8. Open decisions (owner, before any harness is built)

| # | Decision | Why it blocks | Recommendation |
|---|---|---|---|
| Q-1 | Is B-3 (same-record contention) last-writer-wins or refused? | `users.dbf` has no `VERSION` column; the contract was dropped, not faked | **last-writer-wins**, and the test asserts "exactly one wins, no torn record" |
| Q-2 | Widen `login_max` for the run, or reuse one session? | the shipped value is 5/60 s | **reuse one session** for B-tests; widen only for A-3/A-4 |
| Q-3 | Raise `pool_hix.workers` for the run to exercise the queue? | the shipped ceiling is 4 | **no** — 4 is the interesting case; the queue is exercised at 5+ |
| Q-4 | Is C-1 (flash leak) a defect to fix or to record? | it is a cross-session state channel | **record first**, fix in a separate change once measured |
| Q-5 | How many concurrent connections is "enough"? | A-3/A-4 need > queue_size (256) to prove overflow | **300** for the overflow test, 8 for the exhaustion test |
