#!/usr/bin/env python3
"""
gen-inventree-mysql-schema.py — derive InvenTree's MySQL column layout from its Django source.

InvenTree ships no MySQL schema.  It is a Django project: the column layout is whatever
Django's ORM builds from the model classes under `src/backend/InvenTree/<app>/models.py`
(plus mixins, custom field classes and 185 migrations) when Django's MySQL backend is
configured.  This tool reads that source statically — no Django, no database — and
renders the layout as MySQL 8 SQL.

    git clone --depth 1 --filter=blob:none --sparse https://github.com/inventree/InvenTree.git
    git -C InvenTree sparse-checkout set --no-cone src/backend/InvenTree
    ./gen-inventree-mysql-schema.py InvenTree/src/backend/InvenTree > INVENTREE-MYSQL-SCHEMA.sql

Type mapping follows Django's own `Field.db_type()` for the MySQL backend (Django 5.2,
the version InvenTree pins at the time of this run).  See INVENTREE-MYSQL-SCHEMA.md.
"""

from __future__ import annotations

import ast
import glob
import os
from collections import defaultdict

import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "src/backend/InvenTree"
COMMIT = "575fbdc9072dee89bc5624cb7b2604829826f552"
DJANGO = "5.2.17"

SKIP_DIRS = {
    "migrations", "test", "tests", "_testfolder", "management", "samples",
    "fixtures", "templates", "node_modules", "__pycache__",
}

# Django field class -> MySQL column type (Django's db_type() on the MySQL backend)
MYSQL_TYPE = {
    "AutoField": "int",
    "BigAutoField": "bigint",
    "SmallIntegerField": "int",
    "IntegerField": "int",
    "PositiveIntegerField": "int",
    "PositiveSmallIntegerField": "int",
    "BigIntegerField": "bigint",
    "FloatField": "double",
    "BooleanField": "bool",
    "DateField": "date",
    "DateTimeField": "datetime",
    "CharField": "varchar(255)",
    "SlugField": "varchar(50)",
    "EmailField": "varchar(254)",
    "URLField": "varchar(200)",
    "FileField": "varchar(100)",
    "ImageField": "varchar(100)",
    "TextField": "longtext",
    "JSONField": "json",
    "UUIDField": "char(32)",
    "DecimalField": "decimal(19,6)",
    "ForeignKey": "int",
    "OneToOneField": "int",
    "TreeForeignKey": "int",
    "GenericForeignKey": None,   # reads two sibling columns; adds none
    "GenericRelation": None,     # reverse-relation helper; adds no column
    "TaggableManager": None,     # taggit keeps its own tables
}

# fields that expand into several columns
EXPANDED = {
    "MoneyField": [("{name}", "decimal({md},{dp})"), ("{name}_currency", "char(3)")],
    "StdImageField": [
        ("{name}", "varchar(100)"),
        ("{name}_width", "int"),
        ("{name}_height", "int"),
        ("{name}_custom_data", "json"),
    ],
}

# column types MySQL will not give a literal DEFAULT
NO_DEFAULT = {"longtext", "json", "double", "decimal", "datetime", "date"}

MODEL_BASES = {"Model", "AbstractModel", "MPTTModel"}

# bases that are models defined outside InvenTree's source tree
EXTERNAL_MODEL = {
    "AuthToken": "rest_framework.authtoken.Token (djangorestframework)",
    "User": "django.contrib.auth.User",
    "Group": "django.contrib.auth.Group",
    "ContentType": "django.contrib.contenttypes.ContentType",
    "Tag": "taggit.Tag",
    "TaggedItem": "taggit.TaggedItem",
    "EmailAddress": "allauth.account.EmailAddress",
}

# django-mptt's TreeModel adds these three columns to every tree node model
MPTT_COLUMNS = ["tree_id", "lft", "rght"]


class Info:
    def __init__(self, module, name, node):
        self.module, self.name = module, name
        self.qname = f"{module}.{name}" if module else name
        self.bases = [ast.unparse(b) for b in node.bases]
        self.fields = []          # (name, func_src, Call)
        self.meta = {}            # Meta / MPTTMeta assignments
        self.meta_raw = {}        # same, as AST for the non-literal ones
        for stmt in node.body:
            if isinstance(stmt, ast.Assign) and len(stmt.targets) == 1 \
                    and isinstance(stmt.targets[0], ast.Name):
                tgt = stmt.targets[0].id
                if isinstance(stmt.value, ast.Call):
                    self.fields.append((tgt, ast.unparse(stmt.value.func), stmt.value))
                else:
                    try:
                        self.meta[tgt] = ast.literal_eval(stmt.value)
                    except Exception:
                        self.meta[tgt] = ast.unparse(stmt.value)
                        self.meta_raw[tgt] = stmt.value
            elif isinstance(stmt, ast.ClassDef) and stmt.name in ("Meta", "MPTTMeta"):
                for inner in stmt.body:
                    if isinstance(inner, ast.Assign) and len(inner.targets) == 1 \
                            and isinstance(inner.targets[0], ast.Name):
                        try:
                            self.meta[inner.targets[0].id] = ast.literal_eval(inner.value)
                        except Exception:
                            self.meta[inner.targets[0].id] = ast.unparse(inner.value)
                            self.meta_raw[inner.targets[0].id] = inner.value


classes: dict[str, Info] = {}
by_simple: dict[str, list[str]] = defaultdict(list)
by_lower: dict[str, list[str]] = defaultdict(list)

for path in sorted(glob.glob(f"{ROOT}/**/*.py", recursive=True)):
    parts = path[len(ROOT) + 1:].split(os.sep)
    if any(p in SKIP_DIRS for p in parts[:-1]):
        continue
    module = ".".join(parts[:-1] + [parts[-1][:-3]])
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (SyntaxError, UnicodeError):
        continue
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            info = Info(module, node.name, node)
            classes[info.qname] = info
            by_simple[node.name].append(info.qname)
            by_lower[node.name.lower()].append(info.qname)


def resolve(base):
    base = base.split("[")[0]
    if base in classes:
        return base
    simple = base.split(".")[-1]
    cands = by_simple.get(simple, [])
    return cands[0] if len(cands) == 1 else None


def field_class(func_src):
    """Follow a field constructor to the Django field class it ultimately subclasses."""
    seen = set()
    while True:
        simple = func_src.split(".")[-1]
        if simple.endswith("MoneyField") and simple != "CurrencyField":
            return "MoneyField"
        if simple in MYSQL_TYPE or simple in EXPANDED:
            return simple
        if simple in seen or simple not in by_simple:
            return simple
        seen.add(simple)
        info = classes[by_simple[simple][0]]
        nxt = None
        for b in info.bases:
            bs = b.split(".")[-1]
            if bs in MYSQL_TYPE or bs in EXPANDED:
                nxt = bs
                break
        if nxt is None:
            for b in info.bases:
                if b.split(".")[-1] in by_simple:
                    nxt = b
                    break
        if nxt is None:
            return simple
        func_src = nxt


# tables owned by Django / third-party apps, named where an FK points at them
EXTERNAL_TABLE = {
    "User": "auth_user",
    "Group": "auth_group",
    "Permission": "auth_permission",
    "ContentType": "contenttypes_contenttype",
    "Tag": "taggit_tag",
    "TaggedItem": "taggit_taggeditem",
    "Token": "authtoken_token",
    "EmailAddress": "allauth_account_emailaddress",
    "Schedule": "djangoq_schedule",
    "Result": "djangoq_result",
    "Func": "djangoq_func",
    "Task": "djangoq_task",
}


def kw(call):
    out = {}
    for k in call.keywords:
        if k.arg is None:
            continue
        try:
            out[k.arg] = ast.literal_eval(k.value)
        except Exception:
            out[k.arg] = ("nonliteral", ast.unparse(k.value))
    return out


def is_model(qname, seen=frozenset()):
    if qname in seen:
        return False
    seen = seen | {qname}
    for b in classes[qname].bases:
        if b.split(".")[-1] in MODEL_BASES:
            return True
        t = resolve(b)
        if t and is_model(t, seen):
            return True
    return False


def ancestors(qname, seen=frozenset()):
    """Model/mixin bases of qname, parents first (Django contributes them first)."""
    if qname in seen:
        return []
    seen = seen | {qname}
    out = []
    for b in classes[qname].bases:
        t = resolve(b)
        if t and is_model(t, seen):
            out.extend(ancestors(t, seen))
            out.append(t)
    return out


def table_of(qname):
    info = classes[qname]
    return info.meta.get("db_table") or (
        f"{info.module.split('.')[0]}_{info.name}".lower() if info.module else info.name.lower()
    )


def pk_of(qname):
    """Primary-key column name for a model (Django's pk, not the FK target's)."""
    info = classes[qname]
    for name, _, call in info.fields:
        if kw(call).get("primary_key") is True:
            d = kw(call).get("db_column")
            return d if isinstance(d, str) else name
    for a in ancestors(qname):
        for name, _, call in classes[a].fields:
            if kw(call).get("primary_key") is True:
                d = kw(call).get("db_column")
                return d if isinstance(d, str) else name
    return "id"


def lookup(to):
    """Resolve a Django model reference ('app.Model', a bare name, an imported alias).

    Django's own reference lookup is case-insensitive on the model name, so
    'part.part' and 'part.Part' both resolve to part.models.Part.
    """
    if to in classes:
        return classes[to]
    if to == "settings.AUTH_USER_MODEL":
        to = "auth.User"
    app = to.split(".")[0] if "." in to else None
    simple = to.split(".")[-1]
    cands = by_simple.get(simple) or by_lower.get(simple.lower()) or []
    if len(cands) == 1:
        return classes[cands[0]]
    for q in cands:
        mod = q[: q.rindex(".")]
        if app and mod == f"{app}.models":
            return classes[q]
    for q in cands:
        if q[: q.rindex(".")].endswith(".models"):
            return classes[q]
    return None


def fk_target(call, owner):
    """Target of a ForeignKey -> (table, column, why)."""
    to = None
    if call.args:
        first = call.args[0]
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            to = first.value
        else:
            to = ast.unparse(first)
    k = kw(call)
    if to is None and isinstance(k.get("to"), str):
        to = k["to"]
    if to is None:
        return None, None, "no target"
    if to in ("self", "InvenTreeTree", "InvenTreeModel"):
        return table_of(owner), pk_of(owner), "self"
    target = lookup(to)
    if target is None:
        simple = "User" if to == "settings.AUTH_USER_MODEL" else to.split(".")[-1]
        if simple in EXTERNAL_TABLE:
            return EXTERNAL_TABLE[simple], "id", f"external app table {simple}"
        return None, None, f"external model {to}"
    if target.meta.get("abstract") is True:
        return table_of(owner), pk_of(owner), "abstract base -> self"
    return table_of(target.qname), pk_of(target.qname), "declared"


# --------------------------------------------------------------------------
# render
# --------------------------------------------------------------------------
out = []
emit = out.append

emit(f"""-- InvenTree -- MySQL 8 column layout, derived from the Django models
--
-- upstream    github.com/inventree/InvenTree @ {COMMIT}
-- backend     Django {DJANGO}, django.db.backends.mysql (MySQL 8 / MariaDB)
-- generated   gen-inventree-mysql-schema.py   (provenance: INVENTREE-MYSQL-SCHEMA.md)
--
-- InvenTree declares no MySQL schema of its own.  Django's ORM builds one from the
-- model classes in src/backend/InvenTree/<app>/models.py; this file is that layout
-- rendered as ordinary MySQL 8.  It is a reference artefact: the only correct way to
-- create InvenTree's database is InvenTree's own `inventree migrate`.
--
-- Conventions
--   * identifiers are back-quoted (MySQL reserved words: key, status, default, ...)
--   * int = 32-bit (IntegerField / AutoField / ForeignKey to an int PK)
--   * bigint = BigIntegerField / BigAutoField
--   * FK columns are an ordinary column + KEY + a trailing comment naming the target;
--     MySQL has no FK declaration, so the equivalent ALTER TABLE lines are grouped at
--     the foot of the file, commented out
--   * longtext / json columns carry no DEFAULT (MySQL cannot default those types)
--   * column order is mixin-first-then-own; Django orders by a global registration
--     counter, so order here is indicative, not byte-exact
--   * tables owned by Django / third-party apps (auth.*, sessions, admin, taggit,
--     django-q2, allauth, ...) are named where an FK points at them, not defined here
""")

unknown_kinds: set[str] = set()

models = {}
for qname, info in classes.items():
    if is_model(qname) and info.meta.get("abstract") is not True:
        models[qname] = info

summary = []
fk_alters = []
taggable_models = []

for qname in sorted(models, key=lambda q: (classes[q].module.split(".")[0], classes[q].name)):
    info = classes[qname]
    app = info.module.split(".")[0] if info.module else "?"
    table = table_of(qname)
    chain = ancestors(qname) + [qname]

    fields = []
    externals = []
    mptt = False
    for q in chain:
        fields.extend(classes[q].fields)
        for b in classes[q].bases:
            simple = b.split(".")[-1]
            if simple in EXTERNAL_MODEL:
                externals.append(EXTERNAL_MODEL[simple])
            if simple == "MPTTModel":
                mptt = True

    cols = []          # (colname, type, nullable, default, note)
    keys = []          # (kind, name, [cols])
    fks = []           # (colname, table, column)
    declared_pk = None

    for name, func_src, call in fields:
        if name == "objects":          # models.Manager: not a column
            continue
        k = kw(call)
        dbcol = k.get("db_column")
        col = dbcol if isinstance(dbcol, str) else name
        kind = field_class(func_src)
        raw = func_src.split(".")[-1]
        if kind not in MYSQL_TYPE and kind not in EXPANDED:
            unknown_kinds.add(f"{info.name}.{name} = {raw} -> {kind}")
            continue          # not a field: class-level constant, manager, Q object

        if kind in ("GenericForeignKey", "GenericRelation", "TaggableManager"):
            if raw == "TaggableManager":
                taggable_models.append(table)
            continue

        if kind in ("ForeignKey", "OneToOneField", "TreeForeignKey"):
            tgt, tcol, why = fk_target(call, qname)
            fks.append((col, tgt, tcol, why))
            cols.append((col, "int", True if k.get("null") else False, None,
                         f"FK -> {tgt}.{tcol}" if tgt else why))
            if k.get("unique") is True:
                keys.append(("UNIQUE KEY", f"u_{table}_{col}", [col]))
            continue

        if kind in EXPANDED:
            md, dp = k.get("max_digits", 19), k.get("decimal_places", 6)
            if not isinstance(md, int):
                md = 19
            if not isinstance(dp, int):
                dp = 6
            for pat, typ in EXPANDED[kind]:
                cname = pat.format(name=col)
                typ = typ.format(md=md, dp=dp)
                cols.append((cname, typ, k.get("null") is True, None, ""))
            continue

        typ = MYSQL_TYPE.get(kind, "varchar(255)")
        if kind == "CharField" and isinstance(k.get("max_length"), int):
            typ = f"varchar({k['max_length']})"
        if kind == "DecimalField" and isinstance(k.get("max_digits"), int) \
                and isinstance(k.get("decimal_places"), int):
            typ = f"decimal({k['max_digits']},{k['decimal_places']})"
        if kind == "URLField" and raw == "InvenTreeURLField":
            typ = "varchar(2000)"
        if kind == "TextField" and raw == "InvenTreeNotesField":
            typ = "longtext"

        if k.get("primary_key") is True:
            declared_pk = col

        default = None
        d = k.get("default")
        if isinstance(d, bool):
            default = "1" if d else "0"
        elif isinstance(d, (int, float)):
            default = str(d)
        elif isinstance(d, str):
            default = f"'{d}'"
        elif isinstance(d, tuple):
            default = None  # callable / computed default: no DB default
        nullable = k.get("null") is True
        note = ""
        if k.get("auto_now_add") is True:
            note = "auto_now_add"
        elif k.get("auto_now") is True:
            note = "auto_now"
        cols.append((col, typ, nullable, default, note))

        if k.get("unique") is True:
            keys.append(("UNIQUE KEY", f"u_{table}_{col}", [col]))
        if k.get("index") is True:
            keys.append(("KEY", f"i_{table}_{col}", [col]))

        # InvenTreeCustomStatusModelField adds a companion *_custom_key column
        if raw == "InvenTreeCustomStatusModelField":
            cols.append((f"{col}_custom_key", "int", True, None,
                         "added by InvenTreeCustomStatusModelField"))

    if mptt:
        for c in MPTT_COLUMNS:
            cols.append((c, "int", False, "0", "django-mptt TreeModel"))

    pk = declared_pk or "id"
    if not declared_pk:
        cols.insert(0, ("id", "int", False, None, "AutoField, AUTO_INCREMENT"))

    summary.append((app, info.name, table, len(cols), len(fks)))

    emit("")
    emit(f"-- {'=' * 66}")
    emit(f"-- app {app} | model {info.name} | table `{table}`")
    for src in dict.fromkeys(externals):
        emit(f"--   inherits columns from {src} (outside this source tree)")
    if table in taggable_models:
        emit("--   TaggableManager -> taggit's own tables (taggit_tag, taggit_taggeditem)")
    emit(f"-- {'=' * 66}")

    body = []
    used = set()
    for colname, typ, nullable, default, note in cols:
        if colname in used:
            continue
        used.add(colname)
        parts = [f"`{colname}` {typ}"]
        parts.append("NULL" if nullable else "NOT NULL")
        base = typ.split("(")[0]
        if default is not None and base not in NO_DEFAULT:
            parts.append(f"DEFAULT {default}")
        if note == "AutoField, AUTO_INCREMENT":
            parts.append("AUTO_INCREMENT")
        line = "  " + " ".join(parts)
        if note and note != "AutoField, AUTO_INCREMENT":
            line += f"  /* {note} */"
        body.append(line)

    # Meta.unique_together / Meta.constraints -> composite UNIQUE KEY columns
    for q in chain:
        ut = classes[q].meta.get("unique_together")
        if isinstance(ut, list):
            for grp in ut:
                grp = list(grp) if isinstance(grp, tuple) else [grp]
                want = [c for c in grp if any(c == x[0] for x in cols)]
                if len(want) > 1:
                    keys.append(("UNIQUE KEY", f"u_{table}_{'_'.join(want)}", want))
        cons = getattr(classes[q], "meta_raw", {}).get("constraints")
        if isinstance(cons, ast.List):
            for node in cons.elts:
                if not isinstance(node, ast.Call):
                    continue
                if ast.unparse(node.func).split(".")[-1] != "UniqueConstraint":
                    continue
                fields, cname = [], None
                for k2 in node.keywords:
                    if k2.arg == "fields" and isinstance(k2.value, ast.List):
                        fields = [ast.unparse(e) for e in k2.value.elts]
                    elif k2.arg == "name" and isinstance(k2.value, ast.Constant):
                        cname = k2.value.value
                want = [c for c in fields if any(c == x[0] for x in cols)]
                if len(want) > 1:
                    keys.append(("UNIQUE KEY",
                                 f"u_{table}_{cname}" if cname else
                                 f"u_{table}_{'_'.join(want)}", want))

    tail = [f"  PRIMARY KEY (`{pk}`)"]
    for kind, kname, kcols in keys:
        tail.append(f"  {kind} `{kname}` ({', '.join('`%s`' % c for c in kcols)})")
    for colname, tgt, tcol, why in fks:
        if tgt:
            tail.append(f"  KEY `fk_{table}_{colname}` (`{colname}`)  /* -> {tgt}.{tcol} */")
        else:
            tail.append(f"  KEY `fk_{table}_{colname}` (`{colname}`)  /* {why} */")

    emit(f"CREATE TABLE `{table}` (")
    emit(",\n".join(body + tail))
    emit(");")
    for colname, tgt, tcol, why in fks:
        if tgt:
            fk_alters.append(
                f"-- {table}.{colname} -> {tgt}.{tcol}"
            )

emit("")
emit("-- " + "=" * 66)
emit("-- Foreign-key relationships, one line each (commented out)")
emit("-- MySQL 8 does not enforce foreign keys: the FKs above are backed only by the")
emit("-- KEY indexes, and InvenTree checks them in Django's ORM.  These lines state the")
emit("-- same facts as source.column -> target.column, for a reader who wants to declare")
emit("-- real constraints on a DB that does enforce them.")
emit("-- " + "=" * 66)
out.extend(fk_alters)

emit("")
emit("-- " + "=" * 66)
emit("-- index")
emit("-- " + "=" * 66)
for app, name, table, ncols, nfks in summary:
    emit(f"-- {app:<12} {name:<34} {table:<34} {ncols:>3} cols {nfks:>2} fk")
emit(f"-- {len(summary)} tables owned by InvenTree's own apps")

print("\n".join(out))
if unknown_kinds:
    import sys
    print("\n".join(f"-- unresolved field class: {u}" for u in sorted(unknown_kinds)), file=sys.stderr)
