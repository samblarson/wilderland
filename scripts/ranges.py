# Coarse ranges from iNaturalist for species the geomodel doesn't cover.
# Grid: 20 deg lat x 30 deg lon cells, lat -60..80 (7 rows), lon -180..180 (12 cols); cell = row*12+col
import json, sys, time, urllib.request, urllib.parse, os
src, out = sys.argv[1:3]
rows = json.load(open(src))
ids = sorted({r["id"] for r in rows if r["id"] and r["geo"] < 0 and r["g"] != "sound"})
print("taxa", len(ids), flush=True)
res = json.load(open(out)) if os.path.exists(out) else {"done": [], "cells": {}}
B = 200
for row in range(7):
    for col in range(12):
        cell = row * 12 + col
        if cell in res["done"]: continue
        swlat, swlng = -60 + row * 20, -180 + col * 30
        found = []
        for i in range(0, len(ids), B):
            q = urllib.parse.urlencode({"swlat": swlat, "swlng": swlng, "nelat": swlat + 20, "nelng": swlng + 30,
                "taxon_id": ",".join(map(str, ids[i:i+B])), "verifiable": "true", "per_page": 500})
            for attempt in range(5):
                try:
                    req = urllib.request.Request("https://api.inaturalist.org/v1/observations/species_counts?" + q, headers={"User-Agent": "wildlife-range-builder/0.1"})
                    d = json.load(urllib.request.urlopen(req, timeout=60)); break
                except Exception as e:
                    print("retry", e, flush=True); time.sleep(10 * (attempt + 1))
            else: raise SystemExit("failed")
            found += [x["taxon"]["id"] for x in d["results"]]
            time.sleep(1.0)
            if i == 0 and d["total_results"] == 0 and row in (0,) : pass
        res["cells"][str(cell)] = found; res["done"].append(cell)
        json.dump(res, open(out, "w"))
        print("cell", cell, swlat, swlng, len(found), flush=True)
print("ALL DONE", flush=True)
