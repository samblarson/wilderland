import csv, sys, json, collections
csv.field_size_limit(10**9)
dl, out = sys.argv[1:3]
labels = open(f"{dl}/labels.csv").read().split("\n")[1:]
labels = [l for l in labels if l != ""] if len(labels) > 14795 else labels
assert len(labels) == 14795, len(labels)
want = set(labels)
tax = {}
for r in csv.DictReader(open(f"{dl}/inat/taxa.csv", newline="")):
    n = r["scientificName"]
    if n in want and r["kingdom"] == "Animalia" and n not in tax:
        tax[n] = (r["id"], r["class"], r["order"], r["family"])
ids = {v[0]: k for k, v in tax.items()}
vern = {}
for r in csv.DictReader(open(f"{dl}/inat/VernacularNames-english.csv", newline="")):
    if r["id"] in ids and ids[r["id"]] not in vern: vern[ids[r["id"]]] = r["vernacularName"]
geo = {}; geocommon = {}
for i, line in enumerate(open(f"{dl}/BirdNET%2B_Geomodel_V3.0.3_Global_12K_Labels.txt")):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3:
        geo[p[1]] = i
        if p[2] != p[1]: geocommon[p[1]] = p[2]
bn = {}
for line in open(f"{dl}/birdnet-v3.0-preview4-labels-b1.txt"):
    p = line.strip().split("_", 1)
    if len(p) == 2 and p[0] != p[1]: bn[p[0]] = p[1]
G = {"Aves": "bird", "Mammalia": "mammal", "Amphibia": "amphibian", "Insecta": "insect", "Reptilia": "reptile"}
rows = []; stats = collections.Counter(); nogeo = collections.Counter()
for n in labels:
    t = tax.get(n)
    grp = G.get(t[1], "other") if t else ("sound" if " " not in n or not n[0].isupper() or n not in geo else "other")
    if not t and n in geo: grp = "bird" if n in bn else "other"
    common = geocommon.get(n) or bn.get(n) or vern.get(n) or ""
    g = geo.get(n, -1)
    stats[grp] += 1
    if g < 0: nogeo[grp] += 1
    rows.append({"s": n, "c": common, "g": grp, "geo": g, "id": int(t[0]) if t else 0, "o": t[2] if t else "", "f": t[3] if t else ""})
print(stats); print("no geo:", nogeo)
print("untaxed sample:", [r["s"] for r in rows if r["g"] in ("sound", "other")][:60])
print("no common:", collections.Counter(r["g"] for r in rows if not r["c"]))
json.dump(rows, open(out, "w"), ensure_ascii=False, separators=(",", ":"))
