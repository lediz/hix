#!/usr/bin/env python3
"""BF-07 sample analysis: is there a known-user vs unknown-user timing oracle?

Input: one line per POST /auth sample, as written by test/bf_harness.sh:
    <user> <pass> <status> [<redirect_url>] <size> <time_total_s>
Prints the two distributions, their medians, and whether the ranges overlap.
Adhoc analysis tool — lives inside the project folder per DEV-compliance.md.
"""
import statistics as st
import sys


def parse(path):
    known, unk, sk, su, codes = [], [], [], [], {}
    skipped = 0
    for line in open(path):
        f = line.split()
        if len(f) < 4:
            continue
        code_i = [i for i, x in enumerate(f) if x.isdigit() and len(x) == 3]
        if not code_i:
            continue
        i = code_i[0]
        code = f[i]
        rest = f[i + 1:]
        nums = [x for x in rest if x.isdigit()]
        flts = [x for x in rest if x.replace('.', '', 1).isdigit() and '.' in x]
        if not nums or not flts:
            continue
        size, t = int(nums[0]), float(flts[0]) * 1000.0
        codes[code] = codes.get(code, 0) + 1
        if code != '302':
            # a rate-limited (429) or otherwise non-gate response is not a
            # credential-gate sample: its cost is the limiter, not the KDF
            skipped += 1
            continue
        is_known = f[0] == 'carles'
        (known if is_known else unk).append(t)
        (sk if is_known else su).append(size)
    return known, unk, sk, su, codes, skipped


def desc(x):
    x = sorted(x)
    return (f"n={len(x)} median={st.median(x):.3f}ms mean={st.mean(x):.3f} "
            f"sd={st.pstdev(x):.3f} min={x[0]:.3f} max={x[-1]:.3f}")


def main():
    known, unk, sk, su, codes, skipped = parse(sys.argv[1])
    if not known or not unk:
        print("no samples parsed")
        return 1
    print("status codes seen:", codes, "| non-302 samples excluded:", skipped)
    print("known-user  ", desc(known))
    print("unknown-user", desc(unk))
    print("median delta ms (known - unknown) =",
          round(st.median(known) - st.median(unk), 3))
    print("sizes known:", sorted(set(sk)), "unknown:", sorted(set(su)))
    print("ranges overlap:", not (max(known) < min(unk) or max(unk) < min(known)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
