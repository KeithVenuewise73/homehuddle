#!/usr/bin/env python3
"""Decode a reassembled ledger.b64 (JSON array of {v,n,s}) into one .sql file per migration
and write manifest.csv with md5/sha256. Usage: unpack_ledger.py <project_dir> <expected_count>"""
import sys, json, base64, hashlib, os, csv
d, expected = sys.argv[1], int(sys.argv[2])
raw = open(os.path.join(d, "ledger.b64")).read().strip()
data = json.loads(base64.b64decode(raw).decode("utf-8"))
assert len(data) == expected, f"expected {expected} rows, got {len(data)}"
out = os.path.join(d, "migrations")
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    if f.endswith((".sql", ".b64", ".csv")):
        os.remove(os.path.join(out, f))
rows = []
for r in data:
    v, n, s = r["v"], (r["n"] or "unnamed"), r["s"]
    safe = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in n)
    fn = f"{v}_{safe}.sql"
    with open(os.path.join(out, fn), "w", newline="") as fh:
        fh.write(s)
    b = s.encode("utf-8")
    rows.append([v, n, fn, hashlib.md5(b).hexdigest(), hashlib.sha256(b).hexdigest(), len(b)])
with open(os.path.join(out, "manifest.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["version", "name", "file", "md5", "sha256", "bytes"])
    w.writerows(rows)
print(f"{len(rows)} migrations written to {out}; total bytes {sum(r[5] for r in rows)}")
