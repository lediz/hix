# Aesthetics plan — `webapp/` views and CSS

> **Report only.** No file was changed, no view rewritten, no stylesheet added,
> no build run. This is a plan and a measurement of the current surface.
>
> Date: 2026-10-08 · Compliance baseline: `01-requirements/DEV-compliance.md`

---

## 1. What is actually there

Measured, not assumed.

| Surface | Count | Notes |
|---|---|---|
| View files | 15 | `index`, `main`, 3 `common` (`header`/`navbar`/`sidebar`), 5 `customer`, 5 `users`, plus `masters/example.html` and `masters/modules/` |
| Total view bytes | 72 981 | largest: `customer/grid.html` 12 675, `customer/edit.html` 12 289 |
| Stylesheets | 3 | `www/public/css/{crud,main,logo}.css` — 549 / 490 / 706 bytes |
| Framework CSS | Bootstrap 5.3.3 + bootstrap-icons 1.11.3 | loaded from `cdn.jsdelivr.net` |
| JS | `www/public/js/hi.js` | |
| CSP (`app.prg:_CspDefault`) | `script-src`/`style-src`/`font-src` allow `https://cdn.jsdelivr.net` | the CDN is **not** optional under the current policy |

### The three stylesheets, read

`main.css` sets `body { max-width: 600px; margin: 60px auto }` — a **fixed 600 px column** for every page. `crud.css` then fights it: `a { color: black }`, `main { margin-top: 70px }`, `.w-100px { width: 200px !important }` (a class named for 100 px that sets 200), `place-items: center` (**not a real CSS property** — the valid one is `place-items` on grid containers is `place-items`… it is `place-items` on `align`/`justify`; as written it is inert), and `box-shadow: … !important` on `.card`.

So the current look is: Bootstrap defaults, overridden by three small stylesheets that contain one invalid declaration, one self-contradictory class name, and four `!important` overrides, on a 600 px column that ignores the viewport.

## 2. What is wrong, ranked by how much it costs to fix

| # | Defect | Evidence | Cost |
|---|---|---|---|
| A-1 | **600 px fixed column** regardless of viewport | `main.css` `body { max-width:600px }` | one rule |
| A-2 | **No dark mode**, no `prefers-color-scheme` anywhere | grep over the 3 stylesheets | one block |
| A-3 | **No type scale** — sizes are per-element ad hoc (`.title { font-size: 30px }`) | `main.css` | one block |
| A-4 | **`place-items: center` is inert** as written | `crud.css` `.centered-content` | one rule |
| A-5 | **`.w-100px` sets 200 px** with `!important` | `crud.css` | rename + drop `!important` |
| A-6 | **Four `!important`** in 1.7 KB of CSS | `crud.css` | specificity work |
| A-7 | **No design tokens** — colours are literals (`#c4c4c4`, `#dedede`, `#ddd`, `#f4f4f4`) repeated across files | grep | one `:root` block |
| A-8 | **Grid tables have no row rhythm** — `border-collapse: collapse` + 1 px borders on every cell | `main.css` `td,th` | one block |
| A-9 | **Forms are unstyled density** — `edit.html` is 12 KB of Bootstrap form markup with no spacing system | view sizes | one block + view classes |
| A-10 | **Duplicated view chrome** — `sidebar.html` is 5 108 bytes and is `@view`'d by every page, but the breadcrumb block is repeated inside each of the 10 module views | `grep breadcrumb-item` | view refactor |
| A-11 | **No focus/`:hover` state** on the action buttons | grep | one block |
| A-12 | **No reduced-motion / reduced-data** handling; the sidebar is offcanvas on every page | `sidebar.html` | one block |

## 3. What the plan changes, and what it must not

**In scope (HIX style only, no 3rd-party web UI):**

1. **One stylesheet, three layers.** Replace `crud.css` + `main.css` with a single `webapp.css` that declares tokens in `:root`, then a type scale, then components. `logo.css` stays (it is asset-specific).
2. **Fluid layout.** Kill the 600 px column: a content measure (`min(72rem, 100% - 2·gap)`) with a real breakpoint set, so the grid tables get width on wide screens and the forms keep a readable measure on narrow ones.
3. **Tokens.** Every literal colour becomes a custom property, with a `prefers-color-scheme: dark` block re-mapping them. No new colours invented — the existing four are the palette.
4. **Fix the broken rules.** A-4/A-5/A-6 are corrections, not restatements: `place-items` → `place-items` valid form, `.w-100px` renamed to what it does, `!important` removed by raising specificity honestly.
5. **View chrome.** Move the repeated breadcrumb block out of the 10 module views into `common/breadcrumb.html`, `@view`'d with the module name as an argument — the pattern `sidebar.html` already establishes.

**Out of scope, and why:**

| Temptation | Why not |
|---|---|
| Add a CSS framework / component library | T3 "no 3rd-party web UI". Bootstrap 5 is already loaded and is the framework's own example baseline (`examples/web/crud/`) — the plan restyles it, it does not replace it |
| Fetch fonts / add a webfont | CSP allows `cdn.jsdelivr.net` only; a new origin means changing `_CspDefault()` in `src/app.prg`, which is a security surface, not an aesthetic one. Use the existing `system-ui` stack |
| Add JS animation | `hi.js` exists but the app has no motion today; motion without `prefers-reduced-motion` handling is a regression, and A-12 covers the guard |
| Restyle by editing each view's inline `style=` | the views are Mambo templates loaded at runtime; inline styles would reappear on every re-render and cannot be tokenised |

## 4. Compliance grading of the plan itself

| Clause | Grade | Why |
|---|---|---|
| T1 HIX framework + Harbour only | ✅ | the change is CSS and view markup; no new dependency |
| T2 HIX style only | ✅ | restyles Bootstrap 5 as the framework's own example uses it |
| T3 no 3rd-party web UI | ✅ | no new framework, no new origin, no new asset host |
| T5 tools in the project folder | ✅ | stylesheets live in `webapp/www/public/css/` |
| T7 `hbmk2 app.hbp` only | ✅ | views and CSS are loaded at runtime; the build is untouched |
| T8 port 9090 | ✅ | untouched |
| "No SQL" | ✅ | nothing here touches a store |

## 5. How it would be verified (not run)

The corpus convention is that a plan grades itself and a **result record** reports what was executed. Verification would be:

1. **Render check, not assertion.** Screenshot each of the 10 module pages at 3 widths (narrow / 768 / 1440) in both schemes. Aesthetics cannot be asserted by grep the way the security block can — the record must carry the renders.
2. **The assertions that *can* be made** are structural: no `!important` remains; no hex literal outside `:root`; `place-items` is a valid declaration; every view's breadcrumb comes from `common/breadcrumb.html`; the 600 px rule is gone.
3. **The suites must stay green.** `test_customer_module.sh` 50/50 and `test_users_module.sh` 60/60 assert on rendered markup — `grep 'Data Grid'`, `grep 'is-invalid'`, `grep 'name="name"[^>]*value="admin'`. **A restyle that renames a class or drops a marker breaks those assertions.** The plan must keep every class the suites grep, or the suites are updated in the same change and the change to the suite is recorded.

That last point is the real risk: the suites are the only automated check, and they are markup-coupled.

## 6. Open decisions (owner, before any change)

| # | Decision | Why it blocks | Recommendation |
|---|---|---|---|
| O-1 | Keep Bootstrap 5 or drop it | T3 is satisfied either way, but dropping it means the CSP and the CDN go away, which is a security-surface change | **keep** |
| O-2 | Dark mode: `prefers-color-scheme` only, or a user toggle | a toggle is state, and state needs a place in the session | **media query only** |
| O-3 | Rename the classes the suites grep, or restyle in place | renaming forces the suites to change in the same commit | **restyle in place** |
| O-4 | One `webapp.css` or keep three | one file is easier to tokenise; three preserves the current include shape | **one** |
| O-5 | Screenshot the renders into the result record | the record cannot otherwise show an aesthetic change | **yes** |
