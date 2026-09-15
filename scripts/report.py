#!/usr/bin/env python3
"""Tính metrics Phase 0 từ JSON rows (agent kéo từ Supabase rồi pipe vào).

stdin: {"listings":[...], "seekers":[...], "matches":[...], "viewings":[...], "fees":[...], "scan_runs":[...], "messages":[...]}
stdout: markdown report
"""
import json, sys
from collections import Counter
from datetime import datetime, timedelta

def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")) if ts else None

def main():
    d = json.load(sys.stdin)
    L, S, M, V, F, R, MS = (d.get(k, []) for k in ("listings","seekers","matches","viewings","fees","scan_runs","messages"))
    now = datetime.now().astimezone(); day = now - timedelta(days=1); week = now - timedelta(days=7)
    new24 = [l for l in L if parse(l["seen_at"]) and parse(l["seen_at"]) > day]
    offering = [l for l in L if l.get("kind") == "offering"]
    by_group = Counter(l.get("group_key") or "?" for l in offering if parse(l["seen_at"]) > week)
    scam = [l for l in offering if (l.get("scam_score") or 0) >= 60]
    contacted = [l for l in offering if l.get("contacted_at")]
    accepted = [l for l in offering if l.get("accepted_at")]
    filled = [l for l in offering if l.get("filled_at")]
    showed = [v for v in V if v.get("attendance") == "showed"]; noshow = [v for v in V if v.get("attendance") == "no_show"]
    paid = [f for f in F if f.get("invoice_status") == "paid"]; sent = [f for f in F if f.get("invoice_status") in ("sent","paid")]
    loads24 = sum(r.get("page_loads", 0) for r in R if parse(r["started_at"]) > day)
    drafts = [m for m in MS if m.get("status") == "draft"]
    def pct(a, b): return f"{(100*len(a)/len(b)):.0f}%" if b else "—"
    print(f"# Sublet report {now:%Y-%m-%d %H:%M}\n")
    print(f"- Listings mới 24h: **{len(new24)}** (offering {sum(1 for l in new24 if l.get('kind')=='offering')}, seeking {sum(1 for l in new24 if l.get('kind')=='seeking')})")
    print(f"- Offering 7 ngày theo group: " + ", ".join(f"{k}={v}" for k, v in by_group.most_common()) if by_group else "- Offering 7 ngày: 0")
    print(f"- Scam rate (offering, score≥60): {pct(scam, offering)}")
    print(f"- Seekers active: **{sum(1 for s in S if s.get('status')=='active')}** / {len(S)}")
    print(f"- DM: contacted {len(contacted)} → accepted {len(accepted)} ({pct(accepted, contacted)})")
    print(f"- Filled: {len(filled)} / accepted {len(accepted)} ({pct(filled, accepted)})")
    print(f"- Viewings: showed {len(showed)}, no-show {len(noshow)} (show-up {pct(showed, showed+noshow)})")
    print(f"- Fees: sent {len(sent)}, paid {len(paid)} ({pct(paid, sent)}), €{sum(f.get('amount_eur',0) for f in paid)}")
    print(f"- FB page loads 24h: {loads24}  (ngưỡng an toàn ~400)")
    print(f"- Drafts chờ bạn gửi: **{len(drafts)}**")
    if "--metrics-json" in sys.argv:
        def r(a,b): return round(100*len(a)/len(b),1) if b else None
        m = [
          ("capture","posts_captured_24h",len(new24),10),("capture","page_loads_24h",loads24,350),
          ("capture","dedupe_ratio", round(sum(1 for l in offering if l.get("canonical_id"))/len(offering),3) if offering else None, None),
          ("capture","stops_24h", sum(1 for x in R if parse(x["started_at"])>day and (x.get("stopped_reason") or "") in ("checkpoint","volume")), 0),
          ("analyze","offering_7d",len(offering),None),("analyze","scam_high_rate",r(scam,offering),None),
          ("demand","seekers_active",sum(1 for s in S if s.get("status")=="active"),50),
          ("outreach","dm_sent_24h", sum(1 for x in MS if x.get("status")=="sent" and (x.get("template") or "").startswith("offer_") and parse(x.get("sent_at") or x["created_at"])>day), 10),
          ("outreach","dm_yes_rate_7d", r(accepted,contacted), 30),("outreach","draft_backlog",len(drafts),5),
          ("viewing","showup_rate", r(showed, showed+noshow), 70),
          ("fee","collection_rate", r(paid, sent), 70),("fee","revenue_eur_30d", sum(f.get("amount_eur",0) for f in paid), None),
        ]
        print("\n<!-- metrics-json -->")
        print(json.dumps([{"workflow":w,"metric":k,"value":v,"target":t} for w,k,v,t in m]))

if __name__ == "__main__":
    main()
