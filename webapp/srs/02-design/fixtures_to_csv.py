#!/usr/bin/env python3
"""fixtures_to_csv.py -- P1.6 of INVENTREE-MYSQL-SCHEMA plan: the seed corpus.

InvenTree's own Django fixtures (src/backend/InvenTree/<app>/fixtures/*.yaml)
are the natural seed corpus named by INVENTREE-MYSQL-PLAN.md P1.6. They are
YAML in Django's fixture form (- model: / pk: / fields:), which Harbour does
not read, so this tool renders the CSV equivalent under webapp/sql/fixtures/.
What ships is the CSV (source, tracked) plus the Harbour seeder
(webapp/seed_inventree.prg, P1.6) that bulk-INSERTs it.

  - only fixtures whose model is one of the 38 shipped tables are kept
  - `pk` becomes the `id` column: the fixtures' FK references are pks, so the
    ids must be inserted explicitly, not left to AUTO_INCREMENT
  - fields the shipped schema does not have are reported, not silently dropped
    into a varchar (the artefact's own lesson: StockItem.IN_STOCK_FILTER)
  - True/False -> 1/0 (MySQL bool), None -> empty (NULL)

Usage: fixtures_to_csv.py <fixtures-dir> <schema.sql> <artefact.sql> <out-dir>
"""

import csv
import os
import re
import sys
import yaml
from collections import OrderedDict

KEEP = None  # read from the schema file


def schema_cols(sql):
    """table -> OrderedDict col -> (type, not_null, default_literal)

    The shipped schema is the authority for what a missing value means:
    a NOT NULL column with a DEFAULT takes that DEFAULT, a nullable one
    takes NULL (written as MariaDB's own CSV mark)."""
    out, name, cols = OrderedDict(), None, OrderedDict()
    for line in sql.splitlines():
        m = re.match(r"^CREATE TABLE `(\w+)` \($", line)
        if m:
            name, cols = m.group(1), OrderedDict()
            continue
        if line == ");":
            if name:
                out[name] = cols
            name = None
            continue
        if name and line.strip() and not line.lstrip().startswith("--"):
            if re.match(r"^\s+(PRIMARY|UNIQUE|KEY|FULLTEXT)", line):
                continue
            c = re.match(r"^\s+`(\w+)` (\w+)(\([\d,]+\))?(.*)$", line)
            if c:
                col, typ, size, rest = c.groups()
                rest = rest or ""
                out_notnull = "NOT NULL" in rest
                d = re.search(r"DEFAULT ('[^']*'|\S+)", rest)
                dft = d.group(1).rstrip( "," ) if d else None
                if dft is not None and dft.startswith("'"):
                    dft = dft[1:-1]
                cols[col] = (typ + ( size or "" ), out_notnull, dft)
    return out


def model_to_table(artefact_sql):
    """'part.part' -> 'part_part', honouring the artefact's db_table overrides"""
    pairs = {}
    for m in re.finditer(r"^-- app (\w+) \| model (\w+) \| table `(\w+)`",
                         artefact_sql, re.M):
        app, model, table = m.groups()
        pairs[f"{app}.{model.lower()}"] = table
    return pairs


NUMERIC = ("int", "bigint", "double", "decimal", "bool")
NULL_MARK = "\\N"            # MariaDB's own CSV spelling of NULL


def value(v, typ, notnull, dft, report, where):
    """one fixture field -> one CSV cell, decided by the schema"""
    if isinstance(v, (list, dict)):
        #  e.g. content_type: ['part', 'part'] on a column that is a plain
        #  int once its FK target is not shipped. Not guessed.
        report.add(f"{where} is {type(v).__name__} on a {typ} column")
        v = None

    if v is True:
        v = 1
    elif v is False:
        v = 0

    if v is None or v == "":
        if not notnull:
            return NULL_MARK
        if dft is not None:
            return dft
        report.add(f"{where} not supplied, NOT NULL with no DEFAULT")
        return ""

    s = str(v)
    if typ.split("(")[0] in NUMERIC:
        try:
            float(s)
        except ValueError:
            report.add(f"{where} is {s!r} on a {typ} column")
            if not notnull:
                return NULL_MARK
            return dft if dft is not None else ""
    return s


def main():
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    fx_dir, schema_path, artefact_path, out_dir = sys.argv[1:5]

    tables = schema_cols( open( schema_path ).read() )
    keep = set(tables)

    # artefact header gives app.model -> table; the fixture files use the
    # lowercase model name, which is the same string except for the overrides
    pair = model_to_table( open( artefact_path ).read() )

    rows = {}      # table -> list of dict
    order = {}     # table -> first-seen field order
    unknown = set()
    counts = {}

    for fn in sorted(os.listdir(fx_dir)):
        if not fn.endswith(".yaml"):
            continue
        docs = yaml.safe_load(open(os.path.join(fx_dir, fn))) or []
        for d in docs:
            if not isinstance(d, dict) or "model" not in d:
                continue
            key = str(d["model"]).lower()
            tbl = pair.get(key)
            if tbl is None:
                #  fall back to app_model, then to the shipped name
                tbl = key.replace(".", "_")
                if tbl not in keep:
                    unknown.add(key)
                    continue
            if tbl not in keep:
                continue
            rec = OrderedDict()
            pk = d.get("pk", "")
            rec["id"] = str(pk) if pk != "" else NULL_MARK
            for f, v in (d.get("fields") or {}).items():
                if f not in tables[tbl]:
                    unknown.add(f"{key}.{f}")
                    continue
                typ, notnull, dft = tables[tbl][f]
                rec[f] = value(v, typ, notnull, dft, unknown, f"{key}.{f}")
            rows.setdefault(tbl, []).append(rec)
            order.setdefault(tbl, OrderedDict())
            for f in rec:
                order[tbl][f] = True
            counts[tbl] = len(rows[tbl])

    os.makedirs(out_dir, exist_ok=True)
    for tbl in tables:                      # schema order = FK dependency order
        if tbl not in rows:
            continue
        cols = [c for c in tables[tbl] if c in order[tbl]]
        #  every column of the INSERT, in schema order, gets a cell in
        #  every row: a field the fixture did not supply is decided by
        #  the schema (NOT NULL + DEFAULT -> the DEFAULT, nullable ->
        #  MariaDB's NULL mark), never by an empty string that could
        #  mean either
        for c in cols:
            typ, notnull, dft = tables[tbl][c]
            miss = dft if (notnull and dft is not None) else NULL_MARK
            for r in rows[tbl]:
                r.setdefault(c, miss)
        with open(os.path.join(out_dir, tbl + ".csv"), "w", newline="") as f:
            w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
            w.writerow(cols)
            for r in rows[tbl]:
                w.writerow([r[c] for c in cols])

    print(f"tables written: {len(rows)}  rows: {sum(len(v) for v in rows.values())}")
    for tbl in tables:
        if tbl in rows:
            print(f"  {tbl:<32} {len(rows[tbl]):>3} rows")
    if unknown:
        print("not shipped / not in schema (reported, not guessed):")
        for u in sorted(unknown):
            print(f"  {u}")


if __name__ == "__main__":
    main()
