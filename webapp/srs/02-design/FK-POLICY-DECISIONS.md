# FK policy — the decisions required, and the one taken

Report only. The mechanism is fixed; the values are not. Measured on
`webapp/sql/inventree.sql`: **78 edges** in the DAL's graph, 27 tables with
out-edges, 20 targets. Fan-in: `part_part` 15, `stock_stocklocation` 8,
`users_owner` 7, `company_company` 7, `stock_stockitem` 7, `common_projectcode`
5, `build_build` 5. **0 edges carry a `policy=`**, so every edge is KEEP today.

## Already fixed (the mechanism, not the values)

| Part | Where |
|---|---|
| The policy is a property of the **edge** | declared in the shipped schema's FK comment: `KEY \`fk_…\` (\`col\`) /* -> part_part.id policy=CASCADE */`, parsed by `_DalGraph()` — one source, cannot drift from what loaded |
| Three modes only | `CASCADE` (delete the dependents) · `NULL` (clear the FK value to SQL `NULL`) · anything else = `KEEP` (leave the dangling value visible). `_DalMode()` rejects every other word |
| Resolution order | per-call override > schema declaration > `KEEP`; one resolver, used by both `Delete()` and `Cascade()` |
| The default | `KEEP` — the default cannot silently destroy data; `Orphans()` makes the residue visible |

## D1 — the per-edge mode, for all 78

The artefact records only the **distribution** (`on_delete=CASCADE` 68 /
`SET_NULL` 69 / `DO_NOTHING` 3, plus 5 `GenericForeignKey`) over the full 79-table
model set, not the per-edge values, and the model source is not on this
checkout. The values therefore come from one of two places, and choosing
between them is itself the decision:

* fetch InvenTree's model source (a host action, T6-class) — that yields
  *InvenTree's* answer, not this app's, and several of its edges belong to
  surfaces this app never reaches;
* decide per module as the product owner.

**Recommendation: per module.** An inherited value no verb can reach is a
liability, not a guarantee.

## D2 — `SET_NULL` is not expressible on 26 of the 78 edges

Those FK columns are `int NOT NULL DEFAULT 0`. Twelve of them are edges **into
`part_part`** — the edges a `part` delete touches:

| Edge into `part_part` | FK column | `NULL` possible? |
|---|---|---|
| `build_build.part`, `company_manufacturerpart.part`, `part_supplierpart.part`, `stock_stockitem.part`, `part_bomitem.part`, `part_bomitem.sub_part`, `part_bomitemsubstitute.part`, `part_partrelated.part_1`, `part_partrelated.part_2`, `part_partpricing.part`, `part_partstocktake.part` | `int NOT NULL DEFAULT 0` | **no** — CASCADE or KEEP only |
| `order_salesorderlineitem.part`, `stock_stockitemtracking.part`, `part_part.variant_of`, `part_part.revision_of` | `int NULL` | yes |

**Taken (2026-10-07, the enforceable half):** the refusal is the **DAL's own**.
MariaDB accepts `SET <col> = NULL` on a NOT NULL integer and writes `0` — a
dangling FK, not a NULL — so relying on the server would silently corrupt the
dependent row. `_DalGraph()` now parses `NOT NULL` per FK column from the
shipped schema and `Delete()` refuses the `NULL` policy before the first
statement of the cascade runs. The remaining decision — CASCADE vs KEEP per
edge — is still the owner's.

## D3 — recursion

Seven edges are self-edges: `stock_stocklocation.parent`,
`part_partcategory.parent`, `part_part.variant_of`, `part_part.revision_of`,
`build_build.parent`, `stock_stockitem.parent`, `stock_stockitem.belongs_to`.
`Cascade()` and `Delete()` are **one level**, so deleting a `PartCategory` does
not follow `parent` upward and does not reach the parts under the child
categories. Decide: recursive cascade with a depth cap and a cycle guard (P4.4
names that pair for BOM), or one level plus an orphan report. A cycle guard is
mandatory either way.

## D4 — atomicity — **taken (2026-10-07)**

A cascade is up to 16 statements; run loose, a verb that fails at statement 3
leaves the store half-deleted and answers as if nothing happened. The pool's
auto-rollback does not cover it (it fires when a slot is *closed* mid-
transaction; this verb returns normally). `Delete()` now brackets the cascade
in `BeginTrans`/`Commit` with `Rollback` on any failure and returns
`{ deleted => 0, rolledback => .T. }`; the handlers answer "nothing was
changed" rather than "not there". See `P3-DAL-RESULTS-2026-10-07.md` §9 for the
harness steps that prove it.

## D5 — preview vs perform

`delete_confirm` is a GET that renders `Cascade()`; `delete` is a later POST.
Between them another request can add or remove dependents. Decide: the preview
is advisory (the flash must then not quote the preview's numbers), or the delete
re-computes and refuses when the count changed — and what it answers, the
conflict flash or the new preview.

## D6 — orphans

`KEEP` leaves a dependent row pointing at a row that is gone. `Orphans()`
exists in the DAL; there is no `/hix-fk-check` route (P7.2) and no repair path.
Decide: an orphan is a reportable state, a repair action the app may take, or a
hard error that makes `KEEP` unavailable on that edge.

## D7 — the 52 FK-annotated columns that carry no `KEY`

Their target is not in the shipped subset (P1.2a's decision). They are not in
the graph, so deleting the target leaves nothing counted and no policy applies.
Decide explicitly that they stay inert, rather than discovering later that a
dropped edge was supposed to be a policy surface.

## D8 — tables the app never deletes

`users_owner`, `company_company`, `order_*` until P4.5: with no delete surface,
`KEEP` is correct by construction. Say so per table rather than leaving it
implied by omission.

## Minimum set that blocks P4.2 (`stock`)

| Group | Edges | Why it is on the table |
|---|---|---|
| delete a `part` | the 15 in-edges above | 12 of them cannot be `NULL` (D2); the choice is CASCADE vs KEEP per edge |
| delete a `stock_stockitem` | its 7 in-edges (`order_salesorderallocation.item`, `build_builditem.stock_item`, `stock_stockitemtestresult.stock_item` are NOT NULL) | a stock item is the thing a user throws away most often |
| delete a `stock_stocklocation` | its 8 in-edges, all nullable | the only group where `NULL` is available everywhere — the natural place to test that mode |
| delete a `part_partcategory` | `part_part.category`, plus `parent` (self-edge, D3) | the plan's own example: silently orphaning 400 parts is a user-visible bug |
| delete a `part_supplierpart` | `part_supplierpricebreak.part`, `order_purchaseorderlineitem.part`, `stock_stockitem.supplier_part` | P4.3's surface, but the edge is decided now |

Recorded where it belongs — the FK comment in `sql/inventree.sql`. The DAL
needs no change: `_DalMode()` already reads it.

---

## Taken on 2026-10-07 (the same day, after the report)

The rule was applied mechanically to all 78 edges and written into
`sql/inventree.sql` as `policy=` comments: **CASCADE 13 · NULL 19 · KEEP 46**.
The rule: history tables (`build_*`, `order_*`, `part_partstocktake`,
`stock_stockitemtestresult`, `stock_stockitemtracking`) → KEEP; tree edges
(`parent`, `belongs_to`) → KEEP; `variant_of`/`revision_of` → NULL; otherwise
CASCADE where the FK column is NOT NULL, NULL where it is nullable. Two
overrides: `part_partrelated.part_1/2` → KEEP (a related-part pointer is a
suggestion, not an ownership).

| Decision | What was done |
|---|---|
| **D1** | authored per the rule above, in the schema comment — not fetched from InvenTree's model source |
| **D2** | the 26 NOT NULL edges carry CASCADE or KEEP only; the DAL refuses a `NULL` policy on them before the first statement runs |
| **D3** | **not taken as recursion.** The tree edges carry `policy=KEEP`; a subtree delete is a different user intent and belongs to a module verb with an explicit depth. `Delete()` and `Cascade()` stay one level |
| **D5** | the preview is advisory: `delete.html` says "as of this page load", and the delete's flash quotes the transaction's own numbers — "Part 12 was deleted (1 row, 3 other table(s) touched)" |
| **D6** | `/hix-fk-check` added (P7.2): `GET`, middleware `MyAppAuthRole`, scope `sys:fkcheck`, granted to the admin account only by `seed_users_mysql`. One slot for the whole route, 27 DAL objects borrowing it; the answer names each edge — `{ table, column, target, rows }`. Measured on the seeded corpus: **27 tables, 78 edges, 21 orphans**, all on self-edges (`stock_stocklocation.parent` 5, `part_partcategory.parent` 6, `part_part.variant_of` 4, …) — the seeded fixtures point at targets the 38-table subset does not carry. No repair verb |
| **D7** | the 26 FK-annotated columns with no `KEY` now say why in the schema comment: `target not shipped (P1.2a): no KEY, no policy, inert until the target ships` |
| **D8** | **absent is no longer KEEP.** `_DalMode()` answers `""` for an edge the schema did not decide; `Delete()` refuses it (`rolledback`, reason `policy undecided`) and `Cascade()` renders `UNDECIDED`. The schema file is now a checklist: 78 edges, 78 answers |

Verification after the change: `probe_dalmysql` **29/0** (step 14 now passes an
explicit `KEEP` and step 15 relies on the schema's `policy=CASCADE`, which is
what proves the schema is the source), `test_part_module` **38/0**,
`test_users_mysql` **39/0**, corpus back at its seeded base.

## Owner answers, 2026-10-07

| # | Question | Answer | What it changed |
|---|---|---|---|
| 1 | The 13 CASCADE edges — review them | **follow the rule** | nothing: the derived set stands (`company_manufacturerpart.part`, `part_supplierpart.part`, `part_supplierpart.supplier`, `part_supplierpricebreak.part`, `stock_stockitem.part`, `part_bomitem.part/sub_part`, `part_bomitemsubstitute.part/bom_item`, `part_partpricing.part`, `company_address.company`, `company_contact.company`, `part_partparameter.template`). The three-hop removal from one part delete is accepted, and `delete_confirm` + the transaction's own numbers are what make it visible before and after |
| 2 | The 21 pre-existing orphans — close the corpus or null the fixtures | **FK-closed** | the corpus was already FK-closed: the 21 were a **measurement bug**, not a fixture gap. `OrphansEdge()` built an unaliased `EXISTS`, and for the 7 self-edges (`parent`, `variant_of`, `belongs_to`) MariaDB resolves the outer column to the **inner** row, so `EXISTS` answered for the wrong row. Aliasing both sides (`… AS _o … AS _i`) gives **0 orphans across 78 edges**. Detection is proven, not assumed: the aliased shape counts **14** `part_part` rows against a target id that does not exist, and **0** against the seeded corpus |
| 3 | The subtree verb (`/stock/location/prune?depth=N`) | **keep it out** | nothing built. Tree edges carry `policy=KEEP`; `Delete()` and `Cascade()` stay one level. A subtree delete stays a separate decision with a separate surface, not a default behind a click |
