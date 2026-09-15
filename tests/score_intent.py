#!/usr/bin/env python3
"""So sánh predictions với labels: tests/intent_cases.json (expected) vs tests/intent_predictions.json.
Usage: python3 tests/score_intent.py [--show-errors]
"""
import json, sys, os
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
cases = {c["id"]: c for c in json.load(open(os.path.join(HERE, "intent_cases.json")))}
preds = {p["id"]: p for p in json.load(open(os.path.join(HERE, "intent_predictions.json")))}
show = "--show-errors" in sys.argv

fields = ["kind", "subtype", "poster_type", "dead", "scam_bucket", "confidence", "rent_eur", "available_from", "available_to", "area", "registration_allowed", "create_seeker"]
hits = Counter(); tot = Counter(); errs = defaultdict(list)
conf_kind = Counter()

def norm(v):
    if v in ("", None): return None
    if isinstance(v, str): return v.strip().lower()
    return v

for cid, c in cases.items():
    p = preds.get(cid)
    if not p:
        errs["missing"].append(cid); continue
    e = c["expected"]; pp = p.get("predicted", p)
    for f in fields:
        # only score subtype/poster_type when kind expected != other; only score fields for offering
        if f in ("subtype", "poster_type") and e["kind"] == "other": continue
        if f in ("rent_eur", "available_from", "available_to", "area", "registration_allowed") and e["kind"] != "offering": continue
        if f == "create_seeker" and e["kind"] != "seeking": continue
        tot[f] += 1
        if norm(e.get(f)) == norm(pp.get(f)):
            hits[f] += 1
        else:
            errs[f].append((cid, e.get(f), pp.get(f)))
    conf_kind[(e["kind"], norm(pp.get("kind")))] += 1

print("# Intent eval — %d cases, %d predicted\n" % (len(cases), len(preds)))
print("| field | acc | n |\n|---|---|---|")
for f in fields:
    if tot[f]:
        print(f"| {f} | {100*hits[f]/tot[f]:.0f}% | {tot[f]} |")
print("\n## kind confusion (expected → predicted)")
for (e, p), n in sorted(conf_kind.items()):
    print(f"- {e} → {p}: {n}")
crit = [x for x in errs["kind"]] + [x for x in errs["poster_type"] if x[2] == "agency" or x[1] == "agency"] + [x for x in errs["scam_bucket"] if "high" in (x[1], x[2])]
print(f"\n## critical errors (kind wrong, agency wrong, scam-high wrong): {len(crit)}")
if show:
    for f in fields:
        if errs[f]:
            print(f"\n### {f} errors ({len(errs[f])})")
            for cid, e, p in errs[f]:
                print(f"- {cid}: expected {e!r}, got {p!r} — {cases[cid]['text'][:90]!r}")
if errs["missing"]:
    print("\nmissing predictions:", errs["missing"])
