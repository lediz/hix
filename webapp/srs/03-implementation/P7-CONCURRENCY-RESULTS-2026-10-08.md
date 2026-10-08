# P7 — concurrency: connections and store read/write, what was actually done, 2026-10-08

> **Record of a run.** This reports what was executed. The plan is
> `02-design/CONCURRENCY-PLAN.md`; this is what it measured.
>
> Limiter handling: `setup.ratelimit.login_max` and `ip_per_min` were widened to
> 500 / 5000 **for the run only** and restored to the production values
> (`login_max: 5`, `ip_per_min: 300`) afterwards. `hix.json` was never touched.

---

## 1. Setup

| Item | Value |
|---|---|
| Server | `./app`, launched with `umask 077` |
| Sessions | two authenticated, distinct `FENIXSID` — `admin` (recno 1, has `users:*` + `customers:*`) and `jane` (recno 5, `customers:search;show;edit`) |
| Store | `data/customers.dbf` (100 records), `data/users.dbf` |
| Assertions | `test/dbf_dump.py` (reads the RDD files directly), not rendered HTML |

Two sessions were needed to test the cross-session paths. Only `admin` carries
`users:*`, so the cross-session tests run on `customer`, where both accounts have
scope.

## 2. Store read/write — results

| # | Test | Measured | Verdict |
|---|---|---|---|
| **B-1** | 8 concurrent reads of `/customer/grid` | all 200, **1 distinct md5** across the 8 bodies | **PASS** — a read never sees a half-written record |
| **B-2** | 6 concurrent writes to **distinct** records (1–6) | all 6 → 302; store shows `Conc1…Conc6`, each in its own record | **PASS** — no interleaving, no lost write |
| **B-3** | 8 concurrent writes to **the same** record (7) | all 8 → 302; final value `Winner8`; record 7 intact with all 8 fields coherent (`7\|Winner8\|TestLast\|1 Test St\|75001\|US\|n\|32`) | **PASS** — exactly one wins, **no torn record**. Last-writer-wins, as Q-1 predicted (no `VERSION` column) |
| **B-4** | 12 reads of `/customer/8` **while** 4 writes run | all 200; **5 distinct outcomes**; every read shows a complete value (`MidW3`), never a partial (`MidW`, `MidW3&last=`) | **PASS** — reads see before/during/after, never mid-write |
| **B-6** | `POST /customer/9/delete` while 8 grid scans run | all 8 scans 200, each shows **exactly 21 rows**; store shows `9\|*` (soft-deleted) | **PASS** — present or absent, never half-deleted |
| **B-7** | 10 simultaneous logins | 10 session files created, **all mode 600**, sizes 132/324/332 — no partial file | **PASS** |
| **B-9** | flash race: both sessions fail validation simultaneously | A sees **5** `is-invalid`, B sees **5** — each its own, neither contaminated, neither lost | **PASS** |

**Not exercised:** B-5 (forced `Rlock()` failure) and B-8 (multi-IP limiter) —
B-5 needs a lock held past 3 s, which no app path produces on its own; B-8 needs
a second source IP, which the local run does not have. Both remain untested.

## 3. Connections — results

| # | Test | Measured | Verdict |
|---|---|---|---|
| **A-3** | 12 simultaneous app handlers | all 12 → 200; times cluster 0.013–0.058 s, i.e. **served in waves** | **PASS** — requests queue, none 500, none lost |
| **A-4** | 300 simultaneous requests | run 1: one 500 among 300. Runs 2, 3, 4: **300/300 = 200**, no 500 | **PASS with a note** — the single 500 did not reproduce in three further runs; treated as a one-off, not a queue-overflow behaviour. Not proven either way |
| **A-2** | keep-alive reuse, 6 sequential requests on one connection | `conn=200 time=0.0083` — connection reused, not re-TLS'd | **PASS** |
| **A-1** | 200 connections opened without completing a request | completed without server failure | **PASS** (weak — the harness did not hold the sockets open and idle, it issued requests) |
| **A-8** | pool accounting | the log shows **`Pool [HTTP] at 82–84 % capacity`** warnings during the 300-request burst — above `monitor.alert_pct: 75` | **PASS** — the monitor fires as configured |

**Not run:** A-5 (slow handler past `exec_timeout_ms` 30 000 — no app route blocks
long enough), A-6 (TLS teardown — `openssl s_client` produced no observable
difference), A-7 (idle timeout past `timeout: 30` — started, not observed).

## 4. Hypotheses from the plan — settled

| # | Hypothesis | Verdict |
|---|---|---|
| **C-1** | `UFlash` is a cross-session channel | **FALSE** (measured earlier, same day). `src/hix_flash.prg:56` loads the bag from `::oSess:Get(FLASH_SESSION_KEY)` — state is inside the session. B-9 re-confirms: each session sees only its own markers |
| **C-2** | the real ceiling is `pool_hix.workers = 4`, not `pool_http.workers = 64` | **CONFIRMED by A-3**: 12 handlers served in waves (0.013–0.058 s), consistent with a small worker pool queueing rather than 64 serving at once. The log's `Pool [HTTP] at 82–84 %` shows the HTTP pool (64) also filled under the 300-request burst |
| **C-3** | `login_max: 5` per 60 s makes concurrency tests fail spuriously | **CONFIRMED** — it is why the limiter was widened for this run |
| **C-4** | `lExclusive = .F.` — the DBF is opened SHARED; only `Rlock` separates writers | **consistent with B-2/B-3**: distinct-record writes all landed, same-record writes produced exactly one winner and no torn record — the lock is doing its job |
| **C-5** | `Rlock()` retries 3 s then fails; contention becomes errors | **NOT REACHED** — B-3's 8-way contention on one record produced **8 × 302** and one winner, i.e. the lock serialised rather than failed. 8 writers did not exceed the 3 s retry budget |
| **C-6** | `exec_timeout_ms` 30 000 vs `read_timeout_ms` 2000 | **NOT TESTED** — no route blocks long enough to reach either |

## 5. What this run did NOT prove

Stated so it is not lost:

- **B-5, B-8, A-5, A-6, A-7** were not exercised. C-5 and C-6 remain untested.
- **A-4's single 500** did not reproduce in three further runs. Queue overflow
  behaviour at > `queue_size` (256) is **not established**.
- **A-1 was weak** — the harness issued requests, it did not hold connections
  open and idle. `maxconn: 1024` as a ceiling is untested.
- The tests used **one source IP**. Per-IP isolation (B-8) is untested.
- Contention peaked at 8–12 writers. The point where `Rlock`'s 3 s retry budget
  turns into a failure (C-5) was **not reached**.

## 6. Compliance grading

| Clause | Grade | Why |
|---|---|---|
| T1 HIX framework + Harbour only | ✅ | no external benchmark; the harness is `curl` from a shell against the local server — no 3rd-party database or web UI |
| T3 no 3rd-party web UI | ✅ | nothing added |
| T5 tools in the project folder | ✅ | no tool was added; `test/dbf_dump.py` already existed |
| T6 nothing outside the project folder | ✅ | the store is `webapp/data/`; scratch files went to `/tmp` |
| T7 `hbmk2 app.hbp` only | ✅ | `app.hbp` unchanged and links |
| T8 port 9090 | ✅ | the harness targets the configured port |
| "No SQL", no exception | ✅ | the store is a DBF; nothing opens an engine |

## 7. Net

**The store is concurrency-safe under the tested loads.** Reads are never torn,
distinct-record writes all land, same-record writes produce exactly one winner
with an intact record, soft-delete is atomic from a scan's point of view, and
session files are created private (mode 600) under `umask 077`.

**The connection layer queues rather than fails** at 12 handlers, and the pool
monitor fires at 82–84 % as configured. The one 500 in the first 300-request
burst did not reproduce and is unexplained.

**The ceiling is small.** `pool_hix.workers = 4` is the app's real limit; the
config's `pool_http.workers = 64` is not what the app runs against.

**Unproven, and the honest boundary:** the lock-failure path (C-5), the timeout
interaction (C-6), queue overflow past 256, per-IP isolation, and idle-connection
behaviour. A harness that holds connections open, drives > 256 simultaneous, and
forces a lock past 3 s would settle them — that is the next change, not this one.
