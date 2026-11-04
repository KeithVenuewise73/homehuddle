#!/usr/bin/env python3
"""Extract the 'c' chunk from a persisted execute_sql tool-result file and append it to a target .b64 file."""
import sys, json
src, dst = sys.argv[1], sys.argv[2]
r = json.loads(open(src).read())["result"]
# find the JSON array that follows the opening untrusted-data tag
start = r.find("\n[{", r.find("<untrusted-data-"))
end = r.rfind("}]") + 2
arr = json.loads(r[start + 1:end])
c = arr[0]["c"] or ""
with open(dst, "a") as f:
    f.write(c)
print(len(c))
