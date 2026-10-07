# InvenTree's MySQL schema — the artefact and how it was derived

> **Artefact + provenance.** Nothing in `webapp/` was changed, no branch added, no build run
> against InvenTree. This is a reference document inside the corpus, not something the
> application reads or loads — `DEV-compliance.md` still forbids SQL in the app.
> **Date:** 2026-10-07
> **Files:** `INVENTREE-MYSQL-SCHEMA.sql` (the schema) · `gen-inventree-mysql-schema.py` (what wrote it)

---

## 1. There is no MySQL schema to download

<https://github.com/inventree/InvenTree> contains no `.sql`, no MySQL schema file and no
dump. Measured on the full `git tree` of the default branch (`master`, commit
`575fbdc9072dee89bc5624cb7b2604829826f552`, 2 669 paths) on 2026-10-07: zero paths match
`*.sql`, and the only matches for `mysql` are prose. InvenTree is a Django project — its
own words are *"an open-source inventory management system … which stores data in a
relational database"* — so the column layout is **built by Django's ORM** from the model
classes, and MySQL only sees the result of `migrate` against
`django.db.backends.mysql`. The default backend is SQLite; MySQL/MariaDB is an option.

The schema therefore has to be **derived**, and any derived schema has to say so.

## 2. What the artefact is

`INVENTREE-MYSQL-SCHEMA.sql` — InvenTree's database as ordinary MySQL 8: one
`CREATE TABLE` per model, back-quoted identifiers, `NOT NULL` / `DEFAULT` / `AUTO_INCREMENT`,
`PRIMARY KEY`, `UNIQUE KEY`, `KEY` per foreign key, and a trailing section that lists every
foreign-key relationship as a comment.

| | |
|---|---|
| Tables | **79** — the tables InvenTree's own apps declare |
| Columns | **895** |
| Foreign keys | **165** (each also emitted as a `KEY`, which is what MySQL actually gets) |
| Unique keys | **24**, of which **9** composite (`Meta.unique_together` / `Meta.constraints`) |
| Apps covered | `build 3 · common 19 · company 4 · importer 3 · machine 2 · order 14 · part 17 · plugin 3 · report 4 · scim 1 · stock 5 · users 4` |
| Heaviest tables | `part_part` 46 cols · `stock_stockitem` 32 · `part_partpricing` 41 · `order_salesorder` 24 |

Cross-check against `02-design/INVENTREE-RESEARCH.md`, which counted **≈ 77–85 concrete
tables** and **546 declared fields** in InvenTree's model source: 79 tables sits inside that
range, and 895 columns exceeds 546 because mixin-inherited fields, companion columns and
Django-mptt bookkeeping are counted per table rather than once in the source.

## 3. How it was produced

```
git clone --depth 1 --filter=blob:none --sparse https://github.com/inventree/InvenTree.git
git -C InvenTree sparse-checkout set --no-cone src/backend/InvenTree
./gen-inventree-mysql-schema.py InvenTree/src/backend/InvenTree > INVENTREE-MYSQL-SCHEMA.sql
```

The generator parses the Python with `ast` — **no Django, no database, no InvenTree install**.
It reads every class in `src/backend/InvenTree` (skipping `migrations/`, tests, samples),
keeps the classes that are Django models, drops the ones whose `Meta` says `abstract = True`,
walks each model's mixin bases so an inherited field is counted in every model that mixes it
in, and maps each field to the MySQL column type Django's own `Field.db_type()` returns for
the MySQL backend.

## 4. Django → MySQL mapping used

Django 5.2.17 (the version InvenTree pins at this commit; `requirements.in` says `django<6.0`).

| Django field | MySQL column | |
|---|---|---|
| `AutoField` (InvenTree's `DEFAULT_AUTO_FIELD`) | `int` + `AUTO_INCREMENT` | the `id` PK of most tables |
| `IntegerField` / `PositiveIntegerField` / `SmallIntegerField` | `int` | |
| `BigIntegerField` | `bigint` | e.g. `reference_int`, `PartPricing` counters |
| `FloatField` | `double` | |
| `DecimalField` | `decimal(max_digits,decimal_places)` | `decimal(19,6)` for money, `decimal(15,5)` for pricing ratios |
| `BooleanField` | `bool` | MySQL synonym of `tinyint(1)` |
| `CharField(max_length=n)` | `varchar(n)` | |
| `TextField` | `longtext` | Django's MySQL backend picks `longtext`, not `text` |
| `JSONField` | `json` | 62 of them — InvenTree stores plugin metadata, pricing, deltas as JSON |
| `DateField` / `DateTimeField` | `date` / `datetime` | |
| `ForeignKey` / `OneToOneField` / `TreeForeignKey` | `int` + `KEY` | column type follows the target's PK type |
| `GenericForeignKey` | — | reads two sibling columns that the model declares itself; adds none |
| `GenericRelation` / `TaggableManager` | — | reverse-relation helpers; taggit keeps its own tables |

## 5. Fields that are not one column

| Source field | Columns |
|---|---|
| `InvenTreeModelMoneyField` (djmoney `MoneyField`) | `<name>` `decimal(19,6)` **and** `<name>_currency` `char(3)` — 30 currency columns across the schema |
| `StdImageField` (django-stdimage) | `<name>` `varchar(100)` + `_width` `int` + `_height` `int` + `_custom_data` `json` |
| `InvenTreeCustomStatusModelField` (django-fsm-2 FSM status) | `<name>` `int` **and** `<name>_custom_key` `int`, the companion added by the field's own `contribute_to_class` |
| `InvenTreeTree` / django-mptt `MPTTModel` bases | `tree_id` `int`, `lft` `int`, `rght` `int` on every tree node model (`PartCategory`, `StockLocation`, `Build`) |

InvenTree also fixes its own storage, in its own words:

- `InvenTreeUUIDField.db_type()` returns **`char(32)`** on MySQL — the class docstring says
  MariaDB 10.7+ maps `UUIDField` to a native `uuid` column and writes 36 hyphenated
  characters, while databases migrated under older versions keep `char(32)` columns that a
  36-character value does not fit. InvenTree forces the legacy form.
- `InvenTreeURLField` forces `max_length = 2000` → `varchar(2000)`.
- `InvenTreeNotesField` forces `max_length = 50000` → `longtext`.

## 6. What is **not** in the file

| Gap | Why |
|---|---|
| Django's own tables — `auth_user`, `auth_group`, `auth_permission`, `contenttypes_contenttype`, `django_sessions`, `django_admin_log`, `taggit_tag`, `taggit_taggeditem`, `djangoq_*`, `allauth_account_*`, `django_otp_*` | they belong to installed apps, not to InvenTree's source. They are **named** wherever an InvenTree FK points at one (e.g. `bom_checked_by` → `auth_user.id`), but not defined here |
| `users_apitoken`'s inherited columns | `ApiToken` subclasses `rest_framework.authtoken.Token`, defined in djangorestframework. The table header in the `.sql` says so; only the fields InvenTree itself adds are listed |
| column **order** | Django orders columns by a global registration counter, not by inheritance order. The file is mixin-first-then-own, so order is indicative, not byte-exact |
| `CHECK`-style invariants | Django enforces `choices`, validators and `UniqueConstraint` semantics in the ORM; only the ones that become a real `UNIQUE KEY` are emitted |
| the 185 migrations | the file is the **end state**, not the history |

## 7. Verification actually done

- Every `CREATE TABLE` block parses structurally: 79 blocks, balanced parentheses, no empty
  entry, no trailing comma, every column type inside the MySQL keyword set, no `DEFAULT` on a
  `longtext` / `json` column (MySQL cannot default those), no duplicate key name.
- Foreign-key targets resolve to a named table in 165 of 165 cases; the only unresolved
  reference form is `settings.AUTH_USER_MODEL`, mapped to `auth_user`.
- `db_table` overrides in the source are honoured — `common.Parameter` → `part_partparameter`,
  `company.SupplierPart` → `part_supplierpart`.
- Companion columns confirmed against InvenTree's own migrations, not guessed: `price_currency`
  appears as `CurrencyField(max_length=3)`, `lft` / `rght` / `tree_id` appear as `add_field`
  names in `part/migrations`.
- One class-level constant is deliberately not a column: `StockItem.IN_STOCK_FILTER = Q(...)`,
  reported on stderr rather than silently rendered as a `varchar(255)` column.

## 8. Reading it against the Harbour question

`INVENTREE-RESEARCH.md` asks whether InvenTree can be built on Harbour + `DBFCDX` + HIX only.
This file is the noun half of that answer: 79 record types, 895 fields, 165 relations, and
the 62 JSON columns that would have to become side tables or serialized strings. The
`int`-keyed FK graph is what a DBF/CDX port has to reproduce with keys and side files; the
`longtext`/`json` columns are where the DBF record-length envelope runs out first.
