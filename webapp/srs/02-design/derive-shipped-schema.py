#!/usr/bin/env python3
"""derive-shipped-schema.py -- P1.1 / P1.2 / P1.4 of INVENTREE-MYSQL-PLAN.md.

Reads the reference artefact (INVENTREE-MYSQL-SCHEMA.sql, 79 tables) and writes
the SHIPPED schema (webapp/sql/inventree.sql, the 38 tables the functional flow
touches).  It is a derivation, not a copy: the artefact is the shape, this file
is the deliverable, and every gap the artefact left open is closed here with a
`-- DECISION:` comment so the answer is in the file and not in a plan.

  P1.1  the 38 tables, in FK dependency order (targets before referrers),
        CREATE TABLE + KEY inline (the artefact's ALTER lines are comments)
  P1.2  gaps resolved in the file:
        (a) FK targets that are not shipped -> plain int column, no index
        (b) users_apitoken dropped whole (HIX has JWT + HIX_KEY_TOKEN)
        (c) longtext / json carry no DEFAULT (MySQL rejects one)
        plus the NOT NULL / DEFAULT policy for every other column
  P1.3  the row-width envelope, recomputed over the shipped file
  P1.4  the indexes the flow needs: FULLTEXT on name/description/keywords,
        KEY on IPN / SKU / barcode_hash (exact-match lookup), UNIQUE as declared

Usage:  derive-shipped-schema.py INVENTREE-MYSQL-SCHEMA.sql > webapp/sql/inventree.sql
        derive-shipped-schema.py --report            (envelope + counts to stderr)

Tooling, not shipped code: the shipped artefact of this step is the .sql file,
and what loads it is Harbour (webapp/create_mysql_sql.prg, P1.5).
"""

import re
import sys
import json
from collections import OrderedDict

# ---------------------------------------------------------------------
# The 38 tables of INVENTREE-MYSQL-PLAN.md section 2, verbatim.
# ---------------------------------------------------------------------
KEEP = [
    # inventory core (12)
    "part_part", "part_partcategory", "part_partparametertemplate",
    "part_partparameter", "stock_stocklocation", "stock_stockitem",
    "company_company", "company_contact", "company_address",
    "company_manufacturerpart", "part_supplierpart", "part_supplierpricebreak",
    # bom / pricing (4)
    "part_bomitem", "part_bomitemsubstitute", "part_partrelated",
    "part_partpricing",
    # orders (6)
    "order_purchaseorder", "order_purchaseorderlineitem", "order_salesorder",
    "order_salesorderlineitem", "order_salesordershipment",
    "order_salesorderallocation",
    # build / stocktake / tests (6)
    "build_build", "build_builditem", "build_buildline", "part_partstocktake",
    "stock_stockitemtestresult", "stock_stockitemtracking",
    # support (10)
    "common_inventreesetting", "common_inventreeusersetting", "common_note",
    "common_attachment", "common_projectcode", "common_barcodescanresult",
    "stock_stocklocationtype", "users_owner", "users_userprofile",
    "users_ruleset",
]
KEEP_SET = set(KEEP)

# Django / third-party tables: named in the artefact, never defined by it.
# INVENTREE-MYSQL-PLAN.md section 2 says drop these FKs and use HIX's own
# session / role model instead (www/models/tusers.prg, www/middlewares/
# myappauthrole.prg, www/models/hpassword.prg).
FOREIGN_TARGETS = {"auth_user", "auth_group", "contenttypes_contenttype"}

# P1.4: the search columns the flow needs (FR-READ-2 "search") and the exact-
# match keys it needs (IPN / SKU / barcode_hash lookups).  FULLTEXT is not a
# MySQL default and the artefact does not have it; UNIQUE is only what InvenTree
# itself declares, which the artefact already carries.
FULLTEXT_COLS = ("name", "description", "keywords")
LOOKUP_COLS = ("IPN", "SKU", "barcode_hash")

# P3.7 of INVENTREE-MYSQL-PLAN.md: optimistic concurrency. The plan says
# "add a version int DEFAULT 0 column to the mutable tables (a deliberate
# deviation from the artefact, recorded)". It is applied to EVERY table of
# the shipped subset, not to a judgement of which tables are mutable -
# P4.7 edits the support tables through plain CRUD too, and a per-table
# judgement would be an unrecordled guess. The column is what Update
# matches on: UPDATE ... WHERE id = ? AND version = ? + Affected_Rows().
VERSION_COL = ("version", "int", "NOT NULL DEFAULT 0")

# ---------------------------------------------------------------------
# Column types, as the artefact spells them.
# ---------------------------------------------------------------------
NOT_NULLABLE_DEFAULT = {          # explicit DEFAULT added where none is given
    "int": "0", "bigint": "0", "double": "0", "bool": "0", "decimal": "0",
}
LITERAL_EMPTY = ("varchar", "char")
NO_DEFAULT_TYPE = ("longtext", "json")   # MySQL rejects a DEFAULT for these
DATE_TYPES = ("date", "datetime")       # no literal default invented


def parse(sql_text):
    """-> (tables OrderedDict name -> dict, fk list of (src, scol, tgt, tcol))"""
    tables = OrderedDict()
    fk_list = []
    name_re = re.compile(r"^CREATE TABLE `(\w+)` \($")
    fk_re = re.compile(r"^-- (\w+)\.(\w+) -> (\w+)\.(\w+)$")

    lines = sql_text.splitlines()
    i, n = 0, len(lines)
    while i < n:
        m = name_re.match(lines[i])
        if m and m.group(1) not in tables:
            name = m.group(1)
            header = []
            j = i - 1
            while j >= 0 and (lines[j].startswith("--") or lines[j] == ""):
                header.insert(0, lines[j])
                j -= 1
            body = []
            k = i + 1
            while k < n and lines[k] != ");":
                body.append(lines[k])
                k += 1
            tables[name] = {"header": header, "body": body}
            i = k + 1
            continue
        m = fk_re.match(lines[i])
        if m:
            fk_list.append(m.groups())
        i += 1
    return tables, fk_list


def col_re():
    return re.compile(r"^\s+`(\w+)` (\w+)(\([\d,]+\))? (.+?),?$")


def key_re():
    return re.compile(r"^\s+((?:PRIMARY |UNIQUE )?KEY)(?: `([\w]*)`)? ?\(([^)]*)\)(.*)$")


def transform(name, body, dropped_cols):   # dropped_cols: col -> target table
    """-> (out_lines, stats) for one table"""
    out_cols, out_keys = [], []
    stats = {"cols": 0, "defaults_added": 0, "fk_kept": 0, "fk_dropped": 0}
    for line in body:
        if line.strip() == "":
            continue
        m = col_re().match(line)
        k = key_re().match(line)
        if m and not line.lstrip().startswith(("PRIMARY", "UNIQUE", "KEY")):
            col, typ, size, rest = m.group(1), m.group(2), m.group(3) or "", m.group(4)
            comment = ""
            cm = re.search(r"/\*.*?\*/", rest)
            if cm:
                comment = cm.group(0)
                rest = rest[: cm.start()]
            rest = rest.strip().rstrip(",").strip()
            autoinc = "AUTO_INCREMENT" in rest
            notnull = "NOT NULL" in rest
            has_def = "DEFAULT" in rest
            base = typ

            # (c) longtext / json: assert the artefact really carries no DEFAULT
            if base in NO_DEFAULT_TYPE and has_def:
                raise SystemExit(f"{name}.{col}: artefact defaults a longtext/json column")

            notes = []
            if col in dropped_cols:
                notes.append(f"-- DECISION P1.2a: FK -> {dropped_cols[col]}.id is not shipped "
                             "-> plain int column, no index (HIX owns users, roles, scopes)")

            if not autoinc and base not in NO_DEFAULT_TYPE and not has_def:
                if notnull:
                    if base in LITERAL_EMPTY:
                        rest = (rest + " DEFAULT ''").strip()
                    elif base in NOT_NULLABLE_DEFAULT:
                        rest = (rest + " DEFAULT 0").strip()
                    elif base in DATE_TYPES:
                        notes.append("-- DECISION P1.1: NOT NULL date, no DEFAULT invented "
                                     "- the DAL must always supply it")
                    else:
                        raise SystemExit(f"{name}.{col}: unhandled NOT NULL type {base}")
                    stats["defaults_added"] += 1
                else:
                    if notnull is False and "NULL" not in rest:
                        rest = (rest + " NULL").strip()

            txt = f"  `{col}` {base}{size} {rest}".rstrip()
            if comment:
                txt += f"  {comment}"
            for n in notes:
                out_cols.append("  " + n)
            out_cols.append(txt)
            stats["cols"] += 1
            continue

        if k:
            kind, kn, cols, tail = k.group(1), k.group(2), k.group(3), k.group(4)
            tgt = re.search(r"-> (\w+)\.", tail)
            if tgt and tgt.group(1) not in KEEP_SET:
                stats["fk_dropped"] += 1
                continue
            if tgt:
                stats["fk_kept"] += 1
            out_keys.append(line.rstrip().rstrip(","))
            continue

        raise SystemExit(f"{name}: unparsed body line {line!r}")

    # P1.4: the indexes the flow needs, that the artefact does not have.
    have = set()
    for line in out_keys:
        for c in re.findall(r"`(\w+)`", line.split("(", 1)[1]):
            have.add(c)
    real = [c for c in out_cols if not c.lstrip().startswith("--")]
    colnames = [re.match(r"  `(\w+)`", l).group(1) for l in real]
    types = {}
    for line in real:
        mm = re.match(r"  `(\w+)` (\w+)(\([\d,]+\))?", line)
        types[mm.group(1)] = mm.group(2)

    added = []
    for c in FULLTEXT_COLS:
        if c in colnames and types[c] in LITERAL_EMPTY + ("longtext",):
            added.append(f"  FULLTEXT KEY `ft_{c}` (`{c}`)")
    for c in LOOKUP_COLS:
        if c in colnames and c not in have:
            added.append(f"  KEY `ix_{c}` (`{c}`)")
    stats["indexes_added"] = added

    #  P3.7 of INVENTREE-MYSQL-PLAN.md: optimistic concurrency (SRS 5.2).
    #  Added to EVERY table of the shipped subset, not to a judgement of
    #  which tables are mutable - P4.7 edits the support tables through
    #  plain CRUD too, and a per-table judgement would be an unrecorded
    #  guess. Update matches on it: UPDATE ... WHERE id = ? AND version = ?
    #  plus Affected_Rows(), and 0 rows affected is a 409, not an overwrite.
    out_cols.append("  -- DECISION P3.7: optimistic concurrency (SRS 5.2) - not in the artefact")
    out_cols.append(f"  `{VERSION_COL[0]}` {VERSION_COL[1]} {VERSION_COL[2]}")
    stats["version"] = 1

    return out_cols, out_keys, added


def main():
    report = "--report" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        raise SystemExit(__doc__)
    art = open(args[0]).read()
    tables, fk_list = parse(art)

    missing = [t for t in KEEP if t not in tables]
    if missing:
        raise SystemExit(f"artefact has no table {missing}")

    # FK edges inside the shipped subset -> dependency order
    deps = {t: set() for t in KEEP}
    dropped_fk, kept_fk = [], []
    for src, scol, tgt, tcol in fk_list:
        if src not in KEEP_SET:
            continue
        if tgt in KEEP_SET:
            if tgt != src:
                deps[src].add(tgt)
            kept_fk.append((src, scol, tgt, tcol))
        else:
            dropped_fk.append((src, scol, tgt, tcol))

    dropped_cols = {c for src, c, tgt, _ in dropped_fk}
    per_table_dropped = {}
    for src, c, tgt, _ in dropped_fk:
        per_table_dropped.setdefault(src, {})[c] = tgt

    order, seen = [], set()

    def visit(t):
        if t in seen:
            return
        seen.add(t)
        for d in sorted(deps[t]):
            visit(d)
        order.append(t)

    for t in KEEP:
        visit(t)

    # P1.3 row-width envelope, over the shipped file
    envelope = {}
    for t in KEEP:
        w = 0
        for line in tables[t]["body"]:
            m = col_re().match(line)
            if m and m.group(2) in LITERAL_EMPTY:
                w += int(re.search(r"\((\d+)", m.group(3)).group(1)) * 4 + 1
        envelope[t] = w

    if report:
        widest = max(envelope, key=envelope.get)
        print(json.dumps({
            "tables": len(KEEP),
            "columns": sum(1 for t in KEEP for l in tables[t]["body"]
                           if col_re().match(l) and not l.lstrip().startswith(("PRIMARY", "UNIQUE", "KEY"))),
            "fk_kept": len(kept_fk),
            "fk_dropped": len(dropped_fk),
            "dropped_targets": sorted({t for _, _, t, _ in dropped_fk}),
            "widest_table": widest, "widest_bytes": envelope[widest],
            "limit_bytes": 65535,
        }, indent=2), file=sys.stderr)

    out = []
    out.append("-- InvenTree -- the SHIPPED MySQL/MariaDB schema (P1 of INVENTREE-MYSQL-PLAN.md)")
    out.append("--")
    out.append("-- derived from   INVENTREE-MYSQL-SCHEMA.sql (the 79-table reference artefact)")
    out.append("--              by derive-shipped-schema.py; provenance in INVENTREE-MYSQL-SCHEMA.md")
    out.append("-- subset        the 38 tables the functional flow touches (SRS-DAL-CRUD-WEB-UI.md)")
    out.append("-- order         FK dependency order: every target table precedes its referrers")
    out.append("-- load with     ./create_mysql_sql   (webapp/create_mysql_sql.prg, P1.5)")
    out.append("-- seed with     ./seed_inventree     (webapp/seed_inventree.prg, P1.6)")
    out.append("--")
    out.append("-- DECISIONS (the gaps the artefact left open, closed here)")
    out.append("--   P1.1  CREATE TABLE + KEY inline. The artefact's ALTER ... ADD CONSTRAINT")
    out.append("--         section is a comment; MySQL 8 / MariaDB 13 do not enforce FKs anyway,")
    out.append("--         so the KEY index is all the DB gets and the DAL enforces the policy")
    out.append("--         (INVENTREE-MYSQL-PLAN.md Step 0.3: CASCADE 68 / SET_NULL 69 /")
    out.append("--         DO_NOTHING 3 are the app's job, not the server's).")
    out.append("--   P1.1  NOT NULL policy: every NOT NULL column that is not an AUTO_INCREMENT")
    out.append("--         PK and carries no DEFAULT gets one - '' for varchar/char, 0 for")
    out.append("--         int/bigint/double/bool. MariaDB runs STRICT_TRANS_TABLES (P0.4), so")
    out.append("--         an INSERT that omits a NOT NULL column with no DEFAULT is an error,")
    out.append("--         not a silent 0. date/datetime keep NOT NULL with NO default: a")
    out.append("--         literal would be invented data, so the DAL must always supply them.")
    out.append("--   P1.2a FK targets that are not shipped (auth_user, auth_group,")
    out.append("--         contenttypes_contenttype, and InvenTree tables outside the 38)")
    out.append("--         -> the column stays, a plain int, with NO index. HIX owns users,")
    out.append("--         roles and scopes; importing Django's auth_user would import its")
    out.append("--         password hashing, which www/models/hpassword.prg already replaced.")
    out.append("--   P1.2b users_apitoken is dropped whole - its columns are inherited from")
    out.append("--         djangorestframework.authtoken, which is not in the corpus, and HIX")
    out.append("--         authenticates with JWT + HIX_KEY_TOKEN instead. It is not one of the 38.")
    out.append("--   P1.2c longtext / json columns carry no DEFAULT: MySQL rejects one. Asserted")
    out.append("--         over the artefact, not assumed.")
    out.append("--   P1.4  FULLTEXT KEY ft_name / ft_description / ft_keywords for global")
    out.append("--         search (FR-READ-2); KEY ix_IPN / ix_SKU / ix_barcode_hash for exact-")
    out.append("--         match lookup. UNIQUE only where InvenTree declares one - it does NOT")
    out.append("--         declare IPN / SKU / barcode_hash unique, so none was invented here.")
    out.append("--         MariaDB FULLTEXT honours min_word_size (default 3): tokens shorter")
    out.append("--         than that are not indexed; the flow's search route uses LIKE ? for")
    out.append("--         those, not MATCH (P4.1).")
    out.append("")

    for t in order:
        hdr = [l for l in tables[t]["header"] if l.strip()]
        out.append("-- ============================================================")
        out.append(f"-- table `{t}`  ({len(KEEP)}-table subset of the artefact's 79)")
        for l in hdr:
            out.append("--   " + l.lstrip("- ").lstrip())
        out.append("-- ============================================================")
        cols, keys, added = transform(t, tables[t]["body"],
                                      per_table_dropped.get(t, {}))
        entries = cols + keys + added
        last = max(i for i, l in enumerate(entries) if not l.lstrip().startswith("--"))
        out.append(f"CREATE TABLE `{t}` (")
        for idx, l in enumerate(entries):
            is_note = l.lstrip().startswith("--")
            out.append(l + ("," if idx < last and not is_note else ""))
        out.append(");")
        out.append("")

    out.append("-- ============================================================")
    out.append("-- foreign keys inside the shipped subset (MySQL does not enforce")
    out.append("-- these; they are the DAL's policy surface - Step 0.3)")
    out.append("-- ============================================================")
    for src, scol, tgt, tcol in kept_fk:
        out.append(f"-- {src}.{scol} -> {tgt}.{tcol}")
    out.append("")
    out.append("-- FKs dropped: the column is shipped, the relation is not.")
    out.append("-- HIX's own user / role ids live in the users module, not here.")
    for src, scol, tgt, tcol in dropped_fk:
        out.append(f"-- {src}.{scol} -> ({tgt}.{tcol}) not shipped")
    out.append("")
    out.append("-- ============================================================")
    out.append("-- index")
    out.append("-- ============================================================")
    for t in order:
        cols, keys, added = transform(t, tables[t]["body"],
                                      per_table_dropped.get(t, {}))
        ncol = len([c for c in cols if not c.lstrip().startswith("--")])
        out.append(f"-- {t:<44} {ncol:>3} cols {len(keys):>3} idx {len(added):>2} added")
    out.append(f"-- {len(KEEP)} tables")

    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
