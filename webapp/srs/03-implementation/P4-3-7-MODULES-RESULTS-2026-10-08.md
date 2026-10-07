# P4.3–P4.7 and P7.1/P7.3/P7.4/P7.5 — what was actually done, 2026-10-08

> **Record of a run.** This file reports what was executed on this checkout. It
> completes the module phases (**P4.3 `company`, P4.4 `bom`, P4.5 `order`,
> P4.6 `build`/test results, P4.7 settings/notes/project codes**) and the
> verification phases **P7.3, P7.4, P7.5** and the P7.1 wiring. M3, M4 and M5
> are therefore reached; **P5.1 is met by construction** (aggregates come from
> SQL) and **P5.5 stays open on purpose** (the `customer` RDDCDX POC is still in
> the app).

---

## 1. What was built

| Phase | Surface |
|---|---|
| P4.3 | `company` (`company_company`), `supplier` (`part_supplierpart`) |
| P4.4 | `bom` (`part_bomitem`) — one level, tree edges carry `policy=KEEP`, so no recursion behind a click |
| P4.5 | `order` (`order_salesorder`), `orderline` (`order_salesorderlineitem`) |
| P4.6 | `build` (`build_build`), `testresult` (`stock_stockitemtestresult`) |
| P4.7 | `settings` (`common_inventreesetting`), `note` (`common_note`), `projectcode` (`common_projectcode`) |
| P5.1 | `SumOf()` / `AvgOf()` in the DAL — `COALESCE(SUM(col),0)` / `AVG` over the FK indexes; no counter tables exist |
| P7.3 | `/hix-reconcile` (scope `sys:reconcile`) — SQL aggregate vs the aggregate summed from the rows the DAL returns |
| P7.4 | harness step 21 — 200 mixed requests through one slot, `WDO_PoolStats` ends `busy = 0` |
| P7.5 | harness step 22 — a cascade closed mid-transaction, no `Commit`: the pool's auto-rollback leaves the corpus where it started |
| P7.1 | `tests/slices/s24_wa_state.sh` + six slices `40-wa-part` … `45-wa-reconcile` in `tests/run.sh` |

Each module is the same nine verbs, the same middleware pair
(`MyAppAuthRole` / `MyAppAuthRoleEdit`), the same scope format
(`<prefix>:search|show|create|edit|delete`), the same write rules (the form is
validated, the DAL binds every value, the write carries the version it read).

## 2. Facts found by running it

| Assumed | Reality |
|---|---|
| Column names can be inferred from the model names | they cannot. `company_company` has no `address` (address is its own table), `part_supplierpart` has no `name` (it is `SKU`), `common_inventreesetting` is `key`/`value` not `name`/`type`, `common_projectcode` is `code`/`responsible`. Every spec was validated against `sql/inventree.sql` before generating |
| NOT NULL columns can be omitted from an insert | MariaDB answers `Field 'creation_date' doesn't have a default value` and `Field 'date' doesn't have a default value` — `build_build.creation_date` and `stock_stockitemtestresult.date` are required with no default, so they are write columns |
| enum-ish columns are strings | `order_salesorder.status` and `stock_stockitemtestresult.result` are integers: `Incorrect integer value: 'STARTED'`. The write rules say so |
| a module can be generated from a Python template | the first attempt failed four times over (Harbour's `{ => }` vs `str.format`, Mambo's `{{ }}` vs the same, `hb_ASort` does not exist, `Val()` of `Get()`). The working approach transforms `stock.prg` — a file known to compile — instead of writing Harbour from a template |
| the admin can be granted every module scope in one string | the roles column had to be widened (506 characters), and `sys:fkcheck` collides with a `sys:search;…` entry in the roles hash — `_ParseRoles` keys by the text before `:`, so the second silently overwrites the first. The settings module's prefix is `prefs` |
| the suites run inside the sliced suite as they do standalone | they do not. `/auth` is rate limited (`login_max` 5 / `login_window` 60) and earlier slices consume the window, so every suite now retries until the limiter answers something other than 429 — it waits for a free slot, it does not guess one |
| a slice can reuse the webapp suites' parser | it cannot: the state suites print one summary line, so `s24_wa_state.sh` parses the summary and reports one case per suite, and **a suite that reports fewer assertions than its floor is a failure** — B1's lesson encoded |

## 3. Verification

```
$ timeout 1500 ./tests/run.sh --wa --no-fw-ref --fresh
  40-wa-part        2/0   ok        43-wa-modules     2/0   ok
  41-wa-users-mysql 2/0   ok        44-wa-fkcheck     2/0   ok
  42-wa-stock       2/0   ok        45-wa-reconcile   2/0   ok
  (remaining failures are the DBF-era suites 31/32/33 and 38-wa-probe-seek -
    B1's known findings, not new ones)

$ ./probe_dalmysql                       PASS 31  FAIL 0
    21 pool after 200 mixed requests: busy = 0, free = 4
    22 interrupted delete: rows before 15, after 15 (auto-rollback)
$ ./test/test_part_module.sh             PASS 38  FAIL 0
$ ./test/test_users_mysql.sh             PASS 39  FAIL 0
$ ./test/test_stock_module.sh            PASS 18  FAIL 0
$ ./test/test_modules_mysql.sh           PASS 112 FAIL 0   (10 modules x 11 assertions)
$ ./test/test_fkcheck.sh                 PASS 2   FAIL 0   (0 orphans / 78 edges)
$ ./test/test_reconcile.sh               PASS 2   FAIL 0   (0 mismatches / 4 tables)
$ ./seed_inventree verify                RESULT : ok
```

## 4. Compliance

T1 HIX MVC shape unchanged · T2 SQL only under the exception recorded 2026-10-07,
scoped to this plan (the `customer` module still contains no SQL, which is the
point of keeping it as the RDDCDX POC) · T4 HIX + Harbour only · T5 every tool and
generated file under `webapp/` · T6 nothing outside it · T7 `app.hbp` untouched
(the modules are runtime-loaded) · T8 port 9090 untouched.

## 5. Still open

1. **P5.5** — `hix.json → app.auto_close_dbf` stays `true` while the `customer`
   POC is in the app. Retiring the POC is a separate decision.
2. **P6** — the seven things MySQL does not replace are carried forward; the
   product description must still say so.
3. The DBF-era suites (`31-wa-users`, `32-wa-customer`, `33-wa-verify`) and
   `38-wa-probe-seek` still fail in the sliced run — B1's findings, untouched by
   this pass.
4. FR-DELETE-4 (remove the row from the current grid without a reload) is scored
   ❌: it presumes a client-side grid model this app does not have. The answer
   belongs in the SRS, not in the code — see `04-verification/FR-RESCORE-PART-2026-10-08.md`.
