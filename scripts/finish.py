# Merge coarse iNaturalist ranges into the species catalog.
import json, sys
raw, ranges, out = sys.argv[1:4]
rows = json.load(open(raw))
try: res = json.load(open(ranges))
except FileNotFoundError: res = {"done": [], "cells": {}}
complete = len(res["done"]) == 84
by = {}
for cell, ids in res["cells"].items():
    for i in ids: by.setdefault(i, []).append(int(cell))
n = 0
for r in rows:
    if complete and r["geo"] < 0 and r["id"] and r["g"] != "sound" and r["id"] in by:
        r["r"] = sorted(by[r["id"]]); n += 1
json.dump(rows, open(out, "w"), ensure_ascii=False, separators=(",", ":"))
print("ranges complete:", complete, "species with grid range:", n)
