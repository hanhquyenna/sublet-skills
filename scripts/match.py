#!/usr/bin/env python3
"""Deterministic match scoring: listing x seekers -> ranked JSON.

Usage:
  python3 scripts/match.py listing.json seekers.json [--top 15]
  (or pipe: echo '{"listing":{...},"seekers":[...]}' | python3 scripts/match.py -)

Score 0-100. Không dùng bất kỳ thuộc tính nhân thân nào ngoài: ngày, ngân sách, khu vực, số người, registration, pets.
"""
import json, sys
from datetime import date, timedelta

def d(s):
    return date.fromisoformat(s) if s else None

def score(listing, s):
    reasons, flags, pts = [], [], 0
    lf, lt = d(listing.get("available_from")), d(listing.get("available_to"))
    mi, mo = d(s.get("move_in")), d(s.get("move_out"))
    flex = timedelta(days=int(s.get("flex_days") or 7))

    # 1. Date window (max 45)
    if lf and mi:
        gap_start = (mi - lf).days
        if abs(gap_start) <= flex.days:
            pts += 25; reasons.append(f"move-in {mi} ~ available {lf}")
        elif 0 < gap_start <= 21:
            pts += 15; reasons.append(f"move-in {gap_start}d after available (landlord loses {gap_start}d)")
        elif -21 <= gap_start < 0:
            pts += 10; reasons.append(f"seeker needs {abs(gap_start)}d earlier"); flags.append("needs_bridge_before")
        else:
            reasons.append("start dates far apart")
    if lt and mo:
        gap_end = (lt - mo).days
        if abs(gap_end) <= flex.days:
            pts += 20; reasons.append(f"move-out {mo} ~ end {lt}")
        elif gap_end > 0:
            pts += 12; reasons.append(f"seeker leaves {gap_end}d before end")
        else:
            pts += 5; reasons.append(f"seeker wants {abs(gap_end)}d longer"); flags.append("needs_bridge_after")
    elif lt is None and mo:
        pts += 10; reasons.append("listing open-ended")

    # 2. Budget (max 25)
    rent, budget = listing.get("rent_eur"), s.get("budget_eur")
    if rent and budget:
        ratio = rent / budget
        if ratio <= 1.0:
            pts += 25; reasons.append(f"rent {rent} within budget {budget}")
        elif ratio <= 1.1:
            pts += 15; reasons.append(f"rent {rent} slightly above budget {budget}")
        elif ratio <= 1.25:
            pts += 5; reasons.append("rent 10-25% over budget"); flags.append("over_budget")
        else:
            reasons.append("rent far over budget"); flags.append("over_budget")

    # 3. Area (max 15)
    area = (listing.get("area") or "").lower()
    areas = [a.lower() for a in (s.get("areas") or [])]
    if not areas:
        pts += 10; reasons.append("seeker flexible on area")
    elif area and any(a in area or area in a for a in areas):
        pts += 15; reasons.append(f"area match: {area}")
    else:
        reasons.append("area not in seeker list")

    # 4. Hard constraints (max 15, can veto)
    people_ok = (listing.get("max_people") or 9) >= (s.get("people") or 1)
    if people_ok:
        pts += 5
    else:
        flags.append("too_many_people"); reasons.append("more people than allowed")
    if s.get("registration_need"):
        ra = listing.get("registration_allowed", "unknown")
        if ra == "yes": pts += 10; reasons.append("registration allowed")
        elif ra == "no": flags.append("registration_blocked"); reasons.append("seeker needs registration, listing says no")
        else: pts += 3; reasons.append("registration unknown — ask")
    else:
        pts += 5
    if s.get("pets"):
        flags.append("pets_ask"); reasons.append("seeker has pets — ask")

    # poster constraints — chỉ điều kiện chỗ ở (people/pets/occupation), không nhân thân
    pc = (listing.get("poster_constraints") or "").lower()
    if pc:
        if "no couple" in pc and (s.get("people") or 1) >= 2:
            flags.append("poster_no_couples"); reasons.append("poster: no couples")
        if "no pet" in pc and s.get("pets"):
            flags.append("poster_no_pets"); reasons.append("poster: no pets")
        if "student" in pc and "only" in pc and (s.get("occupation") or "") not in ("student", ""):
            flags.append("poster_students_only"); reasons.append("poster: students only")

    # vetoes
    if (listing.get("scam_score") or 0) >= 60:
        flags.append("listing_scam_risk")
    if listing.get("poster_type") == "agency":
        flags.append("agency_listing")
    if listing.get("status") == "dead":
        flags.append("listing_dead")

    return max(0, min(100, pts)), reasons, flags

def main():
    args = sys.argv[1:]
    top = 15
    if "--top" in args:
        i = args.index("--top"); top = int(args[i+1]); del args[i:i+2]
    if args and args[0] == "-":
        data = json.load(sys.stdin); listing, seekers = data["listing"], data["seekers"]
    else:
        listing = json.load(open(args[0])); seekers = json.load(open(args[1]))
    out = []
    for s in seekers:
        if s.get("status") not in (None, "active"):
            continue
        sc, reasons, flags = score(listing, s)
        out.append({"seeker_id": s.get("id"), "name": s.get("name"), "score": sc,
                    "reasons": "; ".join(reasons), "risk_flags": flags})
    out.sort(key=lambda x: -x["score"])
    json.dump({"listing_id": listing.get("id"), "matches": out[:top]}, sys.stdout, indent=2, ensure_ascii=False)
    print()

if __name__ == "__main__":
    main()
