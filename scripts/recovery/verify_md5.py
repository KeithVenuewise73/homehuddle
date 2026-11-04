#!/usr/bin/env python3
"""Compare DB md5 list (version,md5;...) against local manifest.csv. Usage: verify_md5.py <project_dir> <dbmd5file>"""
import sys, csv, os
d, dbf = sys.argv[1], sys.argv[2]
db = dict(p.split(",") for p in open(dbf).read().strip().split(";"))
local = {r["version"]: r["md5"] for r in csv.DictReader(open(os.path.join(d, "migrations", "manifest.csv")))}
missing = [v for v in db if v not in local]
extra = [v for v in local if v not in db]
mismatch = [v for v in db if v in local and db[v] != local[v]]
print(f"db={len(db)} local={len(local)} missing={missing} extra={extra} mismatch={mismatch}")
print("VERIFIED" if not (missing or extra or mismatch) else "FAILED")
