# FR re-score — the DAL SRS's functional requirements against `part` (and the module surface)

Report only. Scored on this checkout, 2026-10-08. The SRS's FR-* checklist was
originally scored against `customer` (`02-design/DAL-CHECKLIST.md` §2); this pass
re-scores it against **`part`**, the module that runs on the MySQL DAL, and notes
where the same shape now holds across the eleven MySQL modules
(`part`, `users`, `stock`, `company`, `supplier`, `bom`, `order`, `orderline`,
`build`, `testresult`, `settings`, `note`, `projectcode`).

Scoring key: ✅ met as written · ⚠️ met with a recorded deviation from the SRS's
wording · ❌ not met.

| FR | Requirement | Verdict | Where / why |
|---|---|---|---|
| FR-CREATE-1 | "Create New Record" button above the grid | ⚠️ | the grid offers `create` through the module's create form link (`/part/create`); it is not a button drawn above the grid table — the audited `customer` module has the same shape, so the deviation is inherited, not new |
| FR-CREATE-2 | dedicated form page with fields for the entity schema | ✅ | `masters/part/edit.html` with `cMode == 'create'`; the fields are the module's declared whitelist, not the form's |
| FR-CREATE-3 | client-side validation before submission | ⚠️ | validation is **server-side** (`UValidatePost` rules: required, type, max length) and the form is re-rendered with the errors. The SRS's "client-side" wording is not met literally; the effect (nothing invalid reaches the DAL) is |
| FR-CREATE-4 | POST to the API invoking the DAL's Insert | ✅ | `POST /part/store` → `Store()` → `TDalMySql:Insert()` |
| FR-CREATE-5 | success notification, form closed, grid refreshed with the new record | ✅ | flash + `302 → /part/grid`; the suite reads the new id out of that flash |
| FR-READ-1 | paginated tabular grid | ✅ | `masters/part/grid.html`, 20 rows/page, page links |
| FR-READ-2 | GET with a default page size via FetchAll/FetchPaged | ✅ | `Grid()` → `FetchPaged(20, offset, …)` |
| FR-READ-3 | search input, global or per column, GET with query params | ✅ | `?q=` is an OR of LIKEs across the rendered columns; `_q_<column>` boxes narrow (AND) — measured: `_q_name=carles&_q_roles=edit` returns 0 rows |
| FR-READ-4 | column sorting by clicking headers | ⚠️ | the sort is a query parameter (`sort`, `dir`), not a clickable header; the allow-list is enforced (`users.prg` D-06/D-08 shape) |
| FR-READ-5 | row → full details via `GET /{id}` | ✅ | `/part/:id` → `Show()` |
| FR-UPDATE-1 | Edit action on each row | ✅ | grid and show link `/part/<id>/edit` |
| FR-UPDATE-2 | form pre-populated from the DAL | ✅ | `Edit()` fetches the row and renders it into the inputs, with the `version` the write must carry back |
| FR-UPDATE-3 | unique id preserved as a hidden, non-editable field | ✅ | hidden `id` and `version` inputs; the id is never taken from the visible fields |
| FR-UPDATE-4 | PUT or PATCH invoking the DAL's Update | ⚠️ | the app uses `POST /part/:id/update` — the audited POST/redirect pattern (a re-played GET cannot re-issue a write). The DAL verb is `Update()` as required |
| FR-UPDATE-5 | form cleared, success toast, record reloaded | ✅ | flash + `302 → /part/:id`; a conflict re-shows the record instead of overwriting (P3.7 / SRS §5.2) |
| FR-DELETE-1 | Delete action on each row | ✅ | `/part/:id/delete_confirm` |
| FR-DELETE-2 | confirmation dialog for the destructive action | ✅ | the confirm page renders the cascade preview — per edge: table, declared policy, rows — "as of this page load" |
| FR-DELETE-3 | DELETE invoking the DAL's Delete | ⚠️ | `POST /part/:id/delete` (same POST/redirect pattern); the verb is `Delete()`, and the cascade is one transaction (D4) |
| FR-DELETE-4 | record removed from the current grid without a full reload | ❌ | the app redirects to the grid, which re-fetches. There is no client state to mutate — the SRS assumes a client-side grid model this app does not have |

## Summary

**13 ✅ · 6 ⚠️ · 1 ❌** of 20. Every ⚠️ is a wording deviation whose effect is met
and recorded; the single ❌ (FR-DELETE-4) is a requirement that does not apply to
this app's shape — it presumes an in-memory grid the UI mutates, and the app
re-renders from the server. That should be answered in the SRS, not in the code.

## What the module surface adds beyond the FRs

| Check | Result |
|---|---|
| FK orphan check (`/hix-fk-check`) | 27 tables, 78 edges, **0 orphans** after every delete test |
| Aggregate reconcile (`/hix-reconcile`) | SQL `SUM` equals the row-summed aggregate on 4 tables, **0 mismatches** (P5.1: aggregates come from SQL, there is no cache to drift) |
| Pool discipline | 200 mixed requests through one slot end at `busy = 0`; no `reclaiming` lines in the log |
| Transaction interruption | a cascade closed mid-transaction leaves the corpus where it started (the pool's auto-rollback) |
| Sliced suite | `40-wa-part` … `45-wa-reconcile` all **ok**; the failures that remain are the DBF-era suites (`31-wa-users`, `32-wa-customer`, `33-wa-verify`) and `38-wa-probe-seek` — B1's known findings, not new ones |
