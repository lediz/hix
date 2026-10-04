#!/usr/bin/env python3
"""DBF inspector for functional tests (users module).
Usage: dbf_dump.py <file.dbf> [--deleted]
Prints: record count, deleted-flagged count, and one line per record.
Adhoc test tool — lives inside the project folder per DEV-compliance.md.
"""
import struct
import sys


def read_dbf(path):
    d = open(path, "rb").read()
    nrec, hlen, rlen = struct.unpack("<IHH", d[4:12])
    nfields = (hlen - 32 - 1) // 32
    fields = []
    for i in range(nfields):
        o = 32 + i * 32
        name = d[o:o + 11].split(b"\x00")[0].decode()
        typ = chr(d[o + 11])
        ln = d[o + 16]
        fields.append((name, typ, ln))
    rows = []
    for r in range(nrec):
        rec = d[hlen + r * rlen:hlen + (r + 1) * rlen]
        if not rec:
            break
        flag = chr(rec[0])
        off = 1
        h = {}
        for name, typ, ln in fields:
            v = rec[off:off + ln].decode("latin1").strip()
            h[name] = v
            off += ln
        rows.append((r + 1, flag, h))
    return nrec, fields, rows


if __name__ == "__main__":
    path = sys.argv[1]
    want_deleted = "--deleted" in sys.argv
    nrec, fields, rows = read_dbf(path)
    live = [r for r in rows if r[1] != "*"]
    dele = [r for r in rows if r[1] == "*"]
    if want_deleted:
        for recno, flag, h in dele:
            print(f"{recno}|{flag}|" + "|".join(h[f] for f, _, _ in fields))
    else:
        print(f"records={nrec} live={len(live)} deleted={len(dele)}")
        for recno, flag, h in rows:
            print(f"{recno}|{flag}|" + "|".join(h[f] for f, _, _ in fields))
