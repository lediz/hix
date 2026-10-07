# Can InvenTree be built on Harbour + DBFCDX + HIX only? — research report

> **Report only.** No code was changed, no branch added, no build run against InvenTree.
> **Date:** 2026-10-07
> **Question:** how would one build <https://github.com/inventree/InvenTree> using **Harbour** (language/runtime),
> **DBFCDX** (the Harbour RDD for DBF + CDX), and **HIX** (this repository's web server) **only** —
> no Python, no Django, no SQL, no third-party web framework, no external database.
> **Constraint baseline:** `01-requirements/DEV-compliance.md` (HIX style only, no SQL, no 3rd-party web UI,
> `hbmk2 app.hbp` build only, port 9090) and `01-requirements/SRS-Harbour-HIX.md` (C-001…C-010).

---

## 0. Verdict

| | |
|---|---|
| **Port InvenTree 1:1** | **Not achievable.** ~15 of its features have no representation inside the envelope (see §5). |
| **Port the inventory domain** (parts, categories, locations, stock, suppliers, BOM, orders) | **Achievable**, and it is the honest target. Roughly **12–18 DBF tables, 60–90 routes, 40–55 k lines of Harbour** plus Mambo templates. |
| **Reproduce the InvenTree UX** (the 98 k-LOC React SPA, 269 API endpoints) | **Not achievable at comparable cost.** Mambo views are a different product, not the same one. |
| **Recommended shape** | Build an **InvenTree-shaped inventory application** on the proven `webapp/` DAL pattern — same nouns, same verbs, deliberately smaller verbs-set and UX. |

The envelope is strong where InvenTree is strong (record-oriented data, CRUD, forms, sessions, CSRF, RBAC,
pagination, JSON API, static serving, gzip, ETag) and absent exactly where InvenTree's *machinery* is strong
(ORM, joins, aggregation, schema migration, permissions graph, template/PDF pipeline, plugin VM, SPA toolchain).

---

## 1. What InvenTree actually is — measured

Measured on a `--depth 1` clone of `inventree/InvenTree` (default branch `master`) taken 2026-10-07.

| Fact | Value |
|---|---|
| Description (their own words) | *"an open-source inventory management system … a Python and Django application which stores data in a relational database"* |
| Language / license / stars | Python / MIT / 7 674 |
| Backend | **172 421 LOC Python** (646 `.py` in the repo) under `src/backend/InvenTree/` |
| Frontend | **97 816 LOC TS/TSX** (578 files) — PatternLab, a React SPA, 41 locales, pre-built and served as static files |
| Django HTML templates | **46** — almost all email / label / report bodies, not the UI |
| Django model classes in `models.py` | **97** matched, **20** `abstract = True` → **≈ 77–85 concrete DB tables** in InvenTree's own apps |
| Declared fields | **546** across those tables |
| `ForeignKey` / `TreeForeignKey` declarations | **130** |
| Named API endpoints (`name='api-…'`) | **269** (part 30, stock 27, order 49, common 49, build 19, company 12, users 15, plugin 15, report 10, machine 8, importer 9) |
| Django migrations | **185** |
| Test functions / test modules | **1 787** / **66** |
| Signal receivers (`post_save`/`post_delete`) | **101** — auto-computed stock/pricing/notification side effects |
| ORM aggregation (`annotate`/`Sum`/`Count`/`Avg`/`Coalesce`) | **91 + 118 = 209** call sites |
| API version counter | `INVENTREE_API_VERSION = 553` — 553 documented API changes |
| Direct dependency pins (`src/backend/requirements.in`) | **74** |
| Django apps | `InvenTree part stock order company build common plugin report importer machine scim users generic web data_exporter` |
| DB backend | SQLite by default (`settings.py` → `DATABASES['default']`); Redis optional; Q2 workers optional |

The 74 dependency pins are the single most useful list for this question: they name, one line each,
every capability InvenTree assumes it has. Grouped:

| Group | Pins | Consequence for a Harbour build |
|---|---|---|
| Web/HTTP | `django`, `djangorestframework`, `drf-spectacular`, `gunicorn`, `whitewhite/whitenoise`, `django-xforwardedfor-middleware`, `django-cors-headers`, `django-sslserver`, `whitenoise` | **covered by HIX** (server, dispatcher, CORS, `X-Forwarded-*`, static, gzip, ETag) |
| Data | `django-mptt`, `django-money`, `django-taggit`, `django-stdimage`, `django-filter`, `django-sql-utils`, `django-dbbackup`, `django-storages[s3,sftp]` | **no equivalent** — must be hand-coded on DBF/CDX |
| Tasks/cache | `django-q2`, `django-redis`, `django-flags`, `django-maintenance-mode` | partial: HIX pools (`HIX_Pool*`) + `HIX_MwMaintenance`; **no persisted task queue** |
| Auth | `django-allauth[saml,openid,social,mfa]`, `django-oauth-toolkit`, `django-sesame`, `django-otp`, `django-anymail`, `django-mailbox` | HIX has session + JWT(HS256) + roles/scopes; **no SSO/SAML/MFA/LDAP** |
| Rendering | `jinja2`, `nh3`, `django-markdownify`, `weasyprint`, `pdf2image`, `pypdf` | Mambo replaces Jinja2; **PDF pipeline must be rebuilt on `hbhpdf`** |
| Imaging | `pillow`, `django-stdimage` | partial: `hbgd` (libgd), `hbfimage` |
| Barcodes | `python-barcode`, `qrcode[pil]`, `ppf.datamatrix` | partial: `hbgd/GDBarCode` = Code 128/39/25/Codabar; **no QR, no DataMatrix** |
| Units/currency | `pint`, `django-money` | hand-code a unit + FX table in DBF |
| Search | `rapidfuzz` | hand-code; CDX is prefix-key only |
| Plugin VM | `importlib` (in-tree) | HIX's on-the-fly `.prg` compiler is the analogue — see §6 |
| Telemetry | `sentry-sdk`, OpenTelemetry × 11 | HIX logger + `/hix-status` metrics; **no OTel wire format** |
| Misc | `dulwich`, `feedparser`, `tablib[xls,xlsx]`, `pyyaml`, `dotenv`, `docutils`, `tqdm`, `blessed` | YAML/DOTENV → HIX JSON config; XLS import → **blocked** (no reader); RSS → `hbcurl` + hand-parsed |

---

## 2. What the envelope actually gives you — measured

| Side | Measured |
|---|---|
| HIX framework | **38 131 LOC Harbour**, 67 `.prg` in `src/`, `src/mw/` 19 middlewares, `src/dbf/hix_dbf.prg`, `src/curl/` |
| Version | **HIX v2.2 Audit Edition**, branch `enhance`; 87 audit points closed, 2 105 tests passing (Windows + Linux) |
| Audited application | `webapp/` — the CRUD DAL app: `app.prg` 434 LOC + `www/{routes,controllers,models,views,middlewares,loaders,public}` |
| Harbour toolchain on this machine | `hbmk2 3.2.1dev (r2026-09-18)` at `~/Projects/harbour/bin/linux/gcc/` |
| RDD in use | `DBFCDX` (`rddSetDefault("DBFCDX")` in `www/config.json`; `UDbf:cRdd` default `"DBFCDX"`) |
| Harbour DBF/CDX constants | `CDX_MAXKEY 240`, `CDX_MAXTAGNAMELEN 10`, `CDX_MAX_REC_NUM 0xFFFFFFFF`, char field width clamped to **255** (`src/rdd/dbf1.c:3409`) |
| `HIX_DBF` API | `Open/Close/Count/CountDeleted/FieldPos/FieldName/FieldGet/FieldPut/Next/Prev/First/Last/Focus/Seek/SoftSeek/Rlock/Unlock/Zap/Pack/Append/Delete/Recall/Insert/Update/Blank/Row/Normalize/RecCount/Recno/Bof/Eof/Skip/Goto/SetFields/Hide/Visible`, `nTime` default **3 s** |
| `UDbf` API | `cPath/cDbf/cCdx/cTag/cRdd/lExclusive/lToUtf8`, `Open/Close`, `First/Last/Next/Prev/Skip/Goto`, `Seek/Focus`, `Row/Blank`, `Insert/GetRecno/GetId/Update/Delete/Recall/Pack/Zap`, `LoadAll` (with `OrdScope` + codeblock filter), `Page(nPage,nRows,aFields,@nTotal)` |
| Request helpers | `UMethod/UPath/UQuery/UGet/UPost/UParam/UHeader/UCookie/UBody/UJson/UContentType/UFiles` (multipart upload), `UIsGet/…/UWantsJson`, `UIP/UHost/UPort`, `UContext` |
| Response helpers | `USendJson/USendHtml/USendText/USendView/USendEmpty/USendError/URedirect`, `UWrite/USetStatus/USetMime/USetHeader/UFlush` (chunked streaming) |
| Routes | JSON-driven `routes/*.json` `{name,url,method,action,middleware,scope}`; methods `GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS`; specificity scoring; `:id([0-9]+)` capture; `*` wildcard |
| Middleware | `HIX_MwSession`, `HIX_MwAuth`, `HIX_MwJwt(+Scope)`, `HIX_MwCsrf/Check`, `HIX_MwHasRole`, `HIX_MwIsAuth`, `HIX_MwRequireAuth`, `HIX_MwCors`, `HIX_MwRateLimit`, `HIX_MwBodyLimit`, `HIX_MwSecHeaders`, `HIX_MwMethodFilter`, `HIX_MwMaintenance`, `HIX_MwReqLog`, `HIX_MwApiKey`, factory variants per route |
| Security | CSRF bound to session (enhanced), JWT HS256, IP firewall by CIDR, rate limit, body limit, HSTS/CSP/XFO, signed resource IDs (`UGetResource`) so HTML cannot retarget a record id |
| Real-time | worker pools `pool_http` 64 / `pool_ws` 100 / `pool_rest` (SSE 20, long-poll 10); SSE, WS, long-polling |
| Static/HTTP | dispatcher serves `public/` with **ETag + gzip + chunked**, ACL dir rules; **no `Range` support** (grep: only `ETag`/`Cache-Control`) |
| Observability | logger w/ rotation, CLF access log, boot log, `/hix-status` metrics, `/hix-monitor` dashboard, `/hix-trace`, `/hix-bench-*` |
| Extensibility | `loaders/*.prg` precompiled at start; `controllers/*.prg` compiled on the fly by the dispatcher (`ExecutePrg(cPath,oReq,hClass,nTimeoutMs)`); `/hix-routes/add\|delete\|reload` |
| Harbour contrib available for the job | `hbssl` (HMAC/SHA), `hbcurl` (HTTP client), `hbhpdf` (libharu → PDF), `hbgd` (libgd + `GDBarCode`: Code128/39/I25/Codabar + `gdchart`, `gdimage`), `hbtinymt` (raster), `hbfimage`, `hbxpp`, `hbfoxpro`, `hbmagic`, `hbnf`, `hbmzip`, `hbexpat`, `hbcups` (printing) |

---

## 3. The translation: Django model → DBF + CDX

This is the mechanical part, and it is mostly **not** the hard part.

| Django concept | DBF/CDX rendering | Cost |
|---|---|---|
| One model = one table | one `.dbf` + one or more `.cdx` | free |
| `id` PK | **do not use recno as the public id.** `Pack()`/deletion renumbers recnos. Keep a `pk` numeric field fed by a persisted counter, plus a CDX tag on a character `pkid` field (`CDX_MAXTAGNAMELEN 10` is enough) | small, but **mandatory** |
| `ForeignKey` (130 of them) | a numeric field holding the target's `pk`; resolve with `GetId()`/`Seek()` on the target's CDX | mechanical, ~1 helper `URef()` |
| `TreeForeignKey` / django-mptt (`PartCategory`, `StockLocation`) | **drop MPTT.** Store `parent` + `lft/rght/tree_id` as plain numeric fields and maintain them in the controller on insert/move, or drop the fields and do parent-pointer walks with a depth cap | **medium** — MPTT is what makes InvenTree's subtree queries O(1); a hand-maintained copy is the single most bug-prone piece here |
| `CharField(max_length=n)` | `C` field of that width | free |
| field **names** | DBF names are **≤ 10 chars**; **168 of 546 InvenTree field names (30.8 %) are longer** (`availability_updated`, `pack_quantity_native`, `supplier_reference`, …) → a rename table is required, and it must be applied consistently in models, views and API output | **tedious, error-prone** |
| `TextField` / long text | `M` (memo) field | free |
| `JSONField` (18) | `C`/`M` field holding JSON text; `hb_jsonEncode`/`hb_jsonDecode` at the boundary | free |
| `DecimalField` / `InvenTreeModelMoneyField` (27) | `N` with `dec`, plus a `C` currency code; FX table in its own DBF refreshed with `hbcurl` | small |
| `DateField`/`DateTimeField` (37) | `D` (+ separate `C`/`N` time, since DBF `D` is date-only) | small |
| `BooleanField` (47) | `L` | free |
| `NULL` | **does not exist** — DBF has typed blanks; every "is not set" test must be rewritten as `= "" / = 0 / = .F. / IS EMPTY` | **pervasive** |
| `abstract = True` mixins (`InvenTreeModel`, `MetadataMixin`, `InvenTreeNoteMixin`, `InvenTreeAttachmentMixin`, `InvenTreeParameterMixin`, `InvenTreeBarcodeMixin`, `InvenTreeTagsMixin`, `PathStringMixin`, `ReferenceIndexingMixin`) | mixins are **not tables** in Django; in DBF they are *columns duplicated into every table that mixes them in* — the `Note`/`Attachment` generic models already point at a shared table, so keep those two as standalone DBFs keyed by `(content_type, object_pk)` | small |
| `django-taggit` `Tag`/`TaggedItem`, `GenericForeignKey` (5) | a `tags.dbf` with `(tag, table, pk)` and a CDX on `tag` | small |
| `unique` / `check_unique` / `validate_unique` constraints | CDX uniqueness on insert is the only enforced one; everything else needs a controller check | small |
| `check_duplicate` (e.g. duplicate IPN), `UniqueConstraint` | hand-written `Seek()` probe before `Insert()` | small |
| `annotate`/`Sum`/`Count`/`Avg` (209 call sites) | **no aggregation engine.** Either scan-with-`OrdScope` per request, or maintain counter DBFs (`part_stock.dbf`: `pk, in_stock, allocated, variant_children`) updated by the same code paths that mutate stock | **the real design work** |
| `post_save`/`post_delete` signals (101) | explicit calls in the controller — HIX has no signal bus; the DAL's `Insert/Update/Delete` are the hook points | medium |
| schema migration (185 migrations) | **no migration tool.** `webapp/` already shows the pattern: ad-hoc Harbour tools (`create_dbf_ntx.prg`, `create_cdx.prg`, `regenerate_data.prg`, `migrate_users.prg`) that rebuild the table set. Every schema change = a new tool + a data dir swap | medium |
| concurrency | DBF is single-writer: `Rlock()` with `nTime = 3 s`, `DbCommit`, `DbUnlock`. HIX is **one process** with thread pools. Two users editing the same part = one waits or fails. No cross-file transactions: a multi-table mutation (order receive = allocate stock + decrement supplier + notify) is **not atomic** | **the hard structural limit** |
| encoding | DBF is byte/codepage; `UDbf:lToUtf8` converts on read. Non-ASCII part names need the flag set consistently everywhere | small but easy to get wrong |

---

## 4. Feature-by-feature feasibility

Legend: 🟩 direct · 🟨 buildable with hand-written code · 🟧 degraded semantics · 🟥 not inside the envelope

| InvenTree feature | Envelope | Verdict |
|---|---|---|
| Parts, categories, parameters | `UDbf` + CDX on `name`/`IPN` | 🟩 |
| Stock items, locations, serial numbers | `StockItem`/`StockLocation` DBFs, CDX on `serial` | 🟩 |
| Suppliers, supplier parts, price breaks | DBFs + FK fields | 🟩 |
| CRUD web UI (grid/search/create/edit/delete, pagination, flash) | exactly the audited `webapp/` pattern (`Page()`, `UValidatePost`, `UFlash`, `@RESOURCE`, CSRF, roles) | 🟩 |
| REST API (JSON) | `USendJson`, `PUT/DELETE/PATCH` routes, JWT scopes | 🟩 mechanism; 🟨 269 endpoints is the volume |
| RBAC (roles/scopes) | `HIX_MwHasRole` + `scope` per route | 🟩 coarse; 🟧 no per-object permission graph (`RuleSet`, `Owner`) |
| BOM (bill of materials), substitutes, variants | `BomItem` DBF + recursive resolve | 🟨 recursion depth + cycle guard hand-written |
| Build orders, allocate/consume/finish/scrap | multi-table mutation | 🟧 no atomicity across `build.dbf`/`stockitem.dbf` |
| Purchase/sales/return/transfer orders + line items + shipments | DBFs + status FSM (`InvenTreeCustomStatusModelField`) | 🟨 FSM hand-coded |
| Pricing (purchase/sale/internal, price breaks, FX) | `N` fields + FX DBF + `hbcurl` | 🟨 |
| Global search / `icontains` across 85 tables | CDX is **prefix-key only** → substring search = full scan per table | 🟧 O(n) per query; needs a hand-built token DBF |
| Filters (`gt/gte/lt/lte/ne/icontains`, `common/filters.py`) | validator + hand-coded predicates | 🟨 |
| Reports (stock/location/BOM/order/test reports) | Mambo views + `hbhpdf` | 🟨 different PDF engine, no WeasyPrint/CSS |
| Labels (Code128, QR, DataMatrix) | `hbgd/GDBarCode` = Code128/39/I25/Codabar; **QR + DataMatrix absent**; `hbcups` for printing | 🟧 QR must be hand-rolled or done client-side in JS |
| Attachments, image upload, thumbnails | `UFiles()` multipart + `HIX_SafePathAllowed` + `hbgd`/`hbfimage` | 🟨 no Pillow pipeline; **no HTTP `Range`** for large downloads |
| Notes / markdown | `Note` DBF + Mambo escaping | 🟨 markdown renderer absent (nh3/markdownify) |
| Notifications, email | no SMTP in Harbour core; `hbcurl` → an HTTP mail API | 🟧 |
| Background tasks (Q2 + Redis) | `HIX_Pool*` in-memory; SSE/long-poll for progress | 🟧 no persisted, restart-durable task queue |
| Cache | `HIX_Pool*` (mutex-guarded) | 🟩 |
| Barcode scan endpoints (`/api/barcode/*`) | routes + `BarcodeScanResult` DBF | 🟩 server side; camera capture is browser JS |
| Plugin system | HIX compiles `controllers/*.prg` on the fly (`ExecutePrg`, `exec_timeout_ms`) and `/hix-routes/add` | 🟨 **surprising fit** — a Harbour plugin = a `.prg` dropped in a watched dir; but no Python API, so existing InvenTree plugins are unusable |
| SCIM provisioning | plain routes | 🟨 |
| Webhooks | `hbcurl` outbound | 🟨 |
| i18n (41 locales) | `hbi18n` + codepage/UTF-8 discipline | 🟧 |
| SSO / SAML / OIDC / MFA / LDAP / magic links | absent | 🟥 |
| 3D STEP viewer, `pdf2image` previews | absent | 🟥 |
| XLS/XLSX import (`tablib`) | absent | 🟥 (CSV only) |
| Sentry / OpenTelemetry | absent (HIX logger/metrics only) | 🟥 |
| Redis-backed storage (S3/SFTP via `django-storages`) | `hbcurl` + `hbssl` HMAC could sign S3 | 🟧 |
| The React SPA frontend (98 k LOC, 41 locales, tables/settings panels/preview drawers) | Mambo views + `public/{css,js}` | 🟥 at comparable cost — a different UX, not a port |

---

## 5. Hard blockers (why a 1:1 port is impossible)

1. **No aggregation engine.** 209 ORM aggregation call sites are the *reason* InvenTree's stock counters
   are always right. On DBF they become hand-maintained counter tables — a correctness surface with no
   safety net.
2. **No atomic multi-table mutation.** "Receive purchase order" writes across 4–6 DBFs. DBF gives per-record
   `Rlock()` only. A crash mid-sequence leaves inconsistent inventory. This is a data-integrity regression,
   not a performance one.
3. **No schema/migration machinery** against 185 migrations of history; every schema change is a bespoke
   Harbour tool in the project folder (the `webapp/` pattern already does this).
4. **No permissions graph.** InvenTree's `RuleSet`/`Owner`/`django-allauth` layer has no HIX analogue beyond
   role + scope.
5. **No template/PDF/imaging/markdown pipeline** equivalent to Jinja2 + WeasyPrint + Pillow + nh3 + markdownify.
6. **No QR / DataMatrix generator** (the two barcode types InvenTree's label templates actually emit).
7. **No plugin VM compatible with InvenTree's plugins** (`importlib`-based Python).
8. **No SPA toolchain.** The frontend is 98 k LOC of TypeScript; "HIX only" means Mambo templates.
9. **No `Range` requests** in HIX's static dispatcher → large attachment downloads are whole-file.
10. **Single-process, single-writer DBF.** InvenTree's stated deployment (reverse proxy → gunicorn → N Django
    processes → SQL DB → Redis → Q2 workers) has no multi-process equivalent here; `hix.json` is one process
    with thread pools, and `SRS-Harbour-HIX.md` A-04 already names this assumption.

---

## 6. How the build would be laid out (HixStyle, per C-003)

```
<repo>/webapp-inventree/
├── app.hbp  go_gcc.sh  hix.json  gen_keys.sh          # same build shape as webapp/
├── src/app.prg                                        # bootstrap: keys, config, Start()
├── www/
│   ├── config.json                                    # Harbour sets + rddname "DBFCDX"
│   ├── routes/{core.json,part.json,stock.json,order.json,build.json,api.json}
│   ├── models/                                       # Fenix pattern: one per DBF
│   │     tpart.prg tcategory.prg tlocation.prg tstockitem.prg tbomitem.prg
│   │     tsupplier.prg tsupplierpart.prg torder.prg tlineitem.prg tbuild.prg
│   │     tcounter.prg  (maintained aggregates)  tsettings.prg tnote.prg tattach.prg
│   ├── controllers/  grid@part.prg  search@part.prg  show@part.prg  edit@part.prg
│   │                 update@part.prg store@part.prg delete_action@part.prg
│   │                 allocate@build.prg receive@order.prg …   # one per verb
│   ├── middlewares/{config.json, invauth.prg invauthedit.prg invrole.prg invpublic.prg}
│   ├── views/  index.html grid.html edit.html …      # Mambo: {{ }}, @if, @foreach, @args
│   ├── loaders/prelude.prg
│   └── public/{css,js,img}
└── data/   part.dbf part.cdx  stockitem.dbf stockitem.cdx …   # runtime state, gitignored
```

Route shape (mirrors the audited `webapp/www/routes/web.json`, which is the pattern to copy):

```json
{ "name":"part.grid",   "url":"/part/grid",                 "action":"controllers/masters/grid@part.prg",  "method":"GET",  "middleware":"InvAuthRole",     "scope":"parts:search" },
{ "name":"part.show",   "url":"/part/:id([0-9]+)",          "action":"controllers/masters/show@part.prg",  "method":"GET",  "middleware":"InvAuthRole",     "scope":"parts:show" },
{ "name":"part.update", "url":"/part/:id([0-9]+)/update",   "action":"controllers/masters/update@part.prg","method":"POST", "middleware":"InvAuthRoleEdit", "scope":"parts:edit" }
```

Data-model decisions that must be made **before** the first line of Harbour:

1. **Stable ids.** `pk` numeric + `pkid` character CDX tag; never expose recno. (The audited app already
   exposes recno via `@RESOURCE` — that is fine for one table, wrong once `Pack()` is used.)
2. **Rename table** for the 168 field names > 10 chars, kept in one place and applied by the models layer
   so the JSON API can still emit the long names.
3. **Counter tables** for the aggregates InvenTree guarantees: `in_stock`, `allocated`, `builds`,
   `variant_children`, `category` part counts, `stock_value`. Written in the same controller that mutates
   stock, never recomputed on read.
4. **Tree maintenance** for `PartCategory`/`StockLocation` (`parent`, `lft`, `rght`, `tree_id`) with a
   `MoveRecno`-style renumber routine and a cycle guard.
5. **Status FSMs** (part active, order status, build status) as `C` fields + a transition table in a DBF,
   mirroring `django-fsm-2`.
6. **Atomicity discipline**: order mutations get a mutex from `HIX_PoolLock()` over a named pool, plus
   a journal DBF so an interrupted sequence can be replayed.

---

## 7. Effort, in work packages

Calibrated against the audited `webapp/`: one full DAL module (customer/users) with grid, search, create,
edit, update, delete-confirm, roles, CSRF, flash, pagination and sorting took **26 commits** and needed a
framework-side fix round (`ENHANCE.md` §1) plus a 5-round test loop before it verified.

| # | Package | Surface | Harbour LOC | Notes |
|---|---|---|---|---|
| P0 | DBF/CDX schema + seeders + rename table + counter tables | 12–18 tables | 2–3 k | tools, like `create_dbf_ntx.prg`/`create_cdx.prg` |
| P1 | Core inventory: Part, Category, Location, StockItem, Supplier, SupplierPart | 6 tables, ~40 routes | 8–12 k | direct extension of the audited DAL |
| P2 | BOM + variants + tree maintenance + aggregates | — | 6–9 k | highest bug risk |
| P3 | Orders (purchase/sales/return/transfer) + FSM + receive/allocate | 8 tables | 8–12 k | atomicity discipline lives here |
| P4 | Build/manufacturing + stocktake + test results | 5 tables | 5–8 k | |
| P5 | Mambo UI (grid/search/detail/forms/settings) | ~30 views | 6–10 k template+CSS | replaces a 98 k-LOC SPA — do not aim for parity |
| P6 | JSON API parity (subset of 269) | ~80 endpoints | 6–10 k | mechanical once controllers exist |
| P7 | Reports + labels (`hbhpdf`, `hbgd`) | — | 3–5 k | QR/DataMatrix unresolved |
| P8 | Settings, notes, attachments, pricing/FX, units | 6 tables | 4–6 k | |
| P9 | Verification harness (sliced suite, functional suites) | — | 3–5 k | the `tests/` suite pattern; **must be built with P1**, not after |
| | **Total** | | **≈ 43–70 k LOC Harbour + templates** | ≈ 25–40 % of InvenTree's 172 k Python LOC, for ≈ 60–70 % of its user-visible inventory behaviour |

At the audited app's per-module cost, that is **not a weekend and not a quarter**: it is a multi-year
surface if pursued to P6, and it is only tractable as P0–P4 + a thin P5.

---

## 8. Risks and what to cut

| Risk | Why it bites | Mitigation |
|---|---|---|
| Aggregate drift | nothing recomputes `in_stock` if a code path forgets to | one `ApplyStockDelta()` choke point; a `/hix-*` reconcile route that rescans and diffs |
| Tree corruption | `lft/rght` renumbering on move/delete | cap depth, refuse moves that create cycles, verify with a `/hix-tree-check` admin route |
| Recno-as-id | `Pack()` renumbers | stable `pk` + CDX from day one |
| 10-char field names | 30.8 % of names must be renamed | single rename table, models layer applies it, API emits long names |
| Blank ≠ NULL | every optional field test changes meaning | a `UBlank()`-style predicate used everywhere |
| Non-atomic multi-table writes | crash mid-sequence | journal DBF + `HIX_PoolLock` + replay |
| Single-writer DBF | two users editing the same part | `Rlock(3)` + explicit 409/429 response; document it |
| Mambo ≠ SPA | users expect InvenTree's UX | state it in the product description; do not promise parity |
| Untested DAL | the audited app's own lesson: two of three functional suites verified nothing (`PRODUCTION-BLOCKERS-2026-10-07.md` B1) | build the sliced suite with P1, and assert on state changes, not HTTP codes |

**Cut list (do not attempt):** SSO/SAML/MFA, SCIM, Sentry/OTel, XLSX import, STEP viewer, QR/DataMatrix
server-side generation, the React SPA, the plugin API, Redis/S3 storage, django-q2 task durability.

---

## 9. Recommendation

1. **Do not frame the task as "build InvenTree".** Frame it as *"an inventory system with InvenTree's
   nouns and verbs, on DBFCDX"*. The nouns translate cleanly; the machinery does not exist and must be
   hand-built, and that is where all the cost and all the bugs are.
2. **Start from `webapp/`, not from InvenTree.** `webapp/` is already an audited DAL + web UI: 35 of its
   tracked files are byte-identical to `examples/web/crud/`, and its DAL checklist (`02-design/DAL-CHECKLIST.md`)
   records which `UDbf` calls actually work — including the known-bad ones (`LoadAll()` crashing through
   `HIX_DBF:Row()/Normalize()` via `HB_HCaseMatch` × `DbStruct()`, `REQ-FUNC-015 ⚠️`). Reusing that
   working subset is the difference between a slow build and a stalled one.
3. **Budget the design decisions in §6 before the code.** Stable ids, the rename table, counter tables,
   tree maintenance, FSMs, and the atomicity discipline are decisions, not discoveries — each one invalidates
   code written before it.
4. **Ship P0–P4 + a thin P5, then stop and measure.** P6 (API parity) and P7 (reports/labels) are only
   worth starting once the inventory core verifies; P5 parity with the SPA is never worth starting.
5. **Write the verification harness with P1**, sliced, asserting on DBF state before/after each verb —
   the failure mode the audited app already recorded (suites that report green while verifying nothing)
   would otherwise be re-introduced at 20× the surface.

---

## 10. Evidence — how every number above was obtained

| Claim | Command |
|---|---|
| InvenTree facts | `git clone --depth 1 https://github.com/inventree/InvenTree.git` (175 MB), then AST over `src/backend/InvenTree/**/models.py` |
| 97 model classes / 20 `abstract = True` / 546 fields / 130 FKs | `ast` walk matching bases ending in `Model`/`Mixin`; `grep -c "abstract = True" */models.py` → 20 |
| 168 names > 10 chars (30.8 %) | same AST, `len(name) > 10` |
| 269 API endpoints | `grep -rhoP "name='api-[a-z0-9-]+'" src/backend/InvenTree --include=*.py \| sort -u \| wc -l` |
| 172 421 Python LOC / 97 816 TS LOC | `find … -name '*.py' \| xargs wc -l`; same for `src/frontend` |
| 185 migrations / 46 templates / 41 locales / 74 dep pins | `find -path "*/migrations/*.py" \| wc -l`; `find -name "*.html"`; `ls src/frontend/src/locales`; `wc -l src/backend/requirements.in` |
| 101 signals / 209 aggregation sites | `grep -rn "post_save\|post_delete\|@receiver"`; `grep -oP "Sum\(\|Count\(\|Avg\(\|Max\(\|Min\(\|Coalesce\("` + `grep -rn "annotate("` |
| DBF/CDX constants | `grep -n define include/hbrddcdx.h` → `CDX_MAXKEY 240`, `CDX_MAXTAGNAMELEN 10`, `CDX_MAX_REC_NUM 0xFFFFFFFF`; `src/rdd/dbf1.c:3409` width clamp 255 |
| HIX LOC / middleware / helpers | `find src -name '*.prg' \| xargs wc -l` → 38 131; `ls src/mw` → 19; `site-docs/en/programacion/mapa-helpers.md`; `site-docs/en/hixstyle/middleware/mw_list.md` |
| No `Range` in HIX | `grep -rn "Range\|If-Modified\|ETag" src/hix_io.prg src/hix_dispatcher.prg src/hix_response.prg` → ETag/gzip/chunked only |
| Barcode coverage | `grep -n "METHOD" contrib/hbgd/gdbarcod.prg` → `Draw128/Draw13/Draw8/DrawI25` (no QR, no DataMatrix) |
| Toolchain | `hbmk2 -??` → `Harbour Make (hbmk2) 3.2.1dev (r2026-09-18)` |
| Deployment topology | `docs/docs/develop/architecture.md` (reverse proxy → gunicorn → Django → SQL DB → Redis → Q2 workers) |
