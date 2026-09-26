#!/usr/bin/env python3
"""Fills post_details property fields (room_type, bills_included, max_people,
registration_allowed, sublet_permission, furnished) using the JEV API
(typesafe.ai), for posts already classified intent='offering' but still
missing them.

Why a separate pass from `intent-analyze`: that skill's read query is
`where p.intent is null`, so once a post has an intent it is never revisited
-- even if post_details fields under its own documented scope (§11 of
docs/intent-logic.md) were left null. As of 2026-09-26, 1017/1017 offering
posts in the live pool have sublet_permission still at its untouched
'unknown' default and 758/1017 have no room_type at all. This script targets
exactly that backlog. `furnished` is a new field: docs/intent-logic.md never
defined it (Kien decision, 2026-09-26), added here because Roomie needs it
for a filter and the column has existed, unused, since the schema was cut.

Rules, kept identical to docs/intent-logic.md §11 so this does not invent a
second, drifting source of truth:
  - room_type: room / studio / apartment / other -- "studio"/"apartment"
    only when the post says so (matches the CHECK constraint exactly).
  - registration_allowed / sublet_permission: yes / no / unknown -- yes/no
    only on an explicit statement, per docs/intent-logic.md.
  - bills_included: intent-logic.md's 'all' / 'none' / '+N' scheme needs
    exact amount extraction JEV cannot do (it returns typed decisions, not
    free text), so this script only ever writes the unambiguous ends: 'all'
    or 'none', gated on high confidence, and never touches a '+N' row.
  - max_people: intent-logic.md's own worked examples are exactly 1 or 2;
    anything else is left null rather than guessed.
  - furnished: boolean, gated on high confidence both ways.

Never overwrites a value that is not the column's untouched default
(room_type/bills_included/max_people/furnished NULL; registration_allowed/
sublet_permission 'unknown') -- same "do not silently reclassify" rule
intent-analyze/SKILL.md states for `intent` itself, applied here.

Env: ~/.sublet-skills.env (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, same as
scripts/db.py) and ~/.jev.env (TYPESAFE_API_KEY). Neither file is read from
or written to any repo.

Usage:
  python3 scripts/classify_properties_jev.py            # classify + write
  python3 scripts/classify_properties_jev.py --dry-run  # classify, print, no writes
  python3 scripts/classify_properties_jev.py --limit 20 # smoke test on a few posts
"""
import concurrent.futures as cf
import json
import os
import sys
import time
import urllib.error
import urllib.request

JEV_URL = "https://api.typesafe.ai/v1/systemone"
JEV_MODEL = "jev-latest"
WORKERS = 8
CHOICE_CONF = 0.75  # below this, a Choice answer is treated as "not sure enough to write"
NOUL_HIGH = 0.85    # >= this -> true
NOUL_LOW = 0.15      # <= this -> false


def load_env_file(path):
    p = os.path.expanduser(path)
    if not os.path.exists(p):
        sys.exit(f"missing {p}")
    for line in open(p):
        line = line.strip()
        if line.startswith("export "):
            line = line[7:]
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            os.environ.setdefault(k, v.strip().strip('"'))


def sublet_exec(sql):
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/sublet_exec"
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    req = urllib.request.Request(
        url,
        data=json.dumps({"q": sql}).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


QUESTIONS = {
    "room_type": {
        "type": "choice",
        "instructions": "What kind of listing is this Amsterdam housing post advertising?",
        "criteria": {
            "room": "A single room in a shared house/apartment; roommates or flatmates present",
            "studio": "A self-contained studio: one open space, no separate bedroom, no roommates",
            "apartment": "A whole self-contained apartment with one or more separate bedrooms, no roommates",
            "other": "Anything that is not clearly one of the above (a house, a boat, unclear, etc.)",
        },
    },
    "bills_included": {
        "type": "noul",
        "instructions": "Does the post say the stated rent already includes ALL utility bills (gas/water/electricity, sometimes internet) -- e.g. 'all-in', 'incl.', 'bills included', 'inclusief'?",
        "criteria": {
            "true": "Explicitly all-in / incl. / bills included, for all utilities",
            "false": "Explicitly excl. / bills not included / rent is on top of utilities",
        },
    },
    "max_people": {
        "type": "choice",
        "instructions": "How many people does the post say may live in the place?",
        "criteria": {
            "one": "Single occupant only ('single only', '1 person')",
            "two": "A couple or two people explicitly allowed ('couples ok', '2 people')",
            "unstated": "Not mentioned, or more than 2, or unclear",
        },
    },
    "registration_allowed": {
        "type": "choice",
        "instructions": "Does the post say whether municipal registration (inschrijving) at the address is possible?",
        "criteria": {
            "yes": "Explicitly says registration/inschrijving IS possible",
            "no": "Explicitly says registration/inschrijving is NOT possible",
            "unknown": "Not mentioned either way",
        },
    },
    "sublet_permission": {
        "type": "choice",
        "instructions": "Does the post say whether the landlord/hoofdhuurder has approved this sublet?",
        "criteria": {
            "yes": "Explicitly says the landlord approved/allowed/knows about it",
            "no": "Explicitly says the landlord does not know, or asks to keep it quiet",
            "unknown": "Not mentioned either way",
        },
    },
    "furnished": {
        "type": "noul",
        "instructions": "Is the place furnished (comes with a bed and furniture already in place)?",
        "criteria": {
            "true": "Explicitly furnished / gemeubileerd / lists furniture as included",
            "false": "Explicitly unfurnished, or furniture is never mentioned at all",
        },
    },
}


def classify_one(row):
    payload = {"state": row["state_text"][:6000], "model": JEV_MODEL, "questions": QUESTIONS}
    req = urllib.request.Request(
        JEV_URL,
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {os.environ['TYPESAFE_API_KEY']}",
            "Content-Type": "application/json",
        },
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                answers = json.loads(r.read().decode())["answers"]
            break
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                return row["id"], None, str(e)
            time.sleep(2 * (attempt + 1))

    out = {}

    rt = answers["room_type"]
    if row["room_type"] is None and rt["confidence"] >= CHOICE_CONF:
        out["room_type"] = rt["choice"]

    bi = answers["bills_included"]["noul"]
    if row["bills_included"] is None:
        if bi >= NOUL_HIGH:
            out["bills_included"] = "all"
        elif bi <= NOUL_LOW:
            out["bills_included"] = "none"

    mp = answers["max_people"]
    if row["max_people"] is None and mp["confidence"] >= CHOICE_CONF and mp["choice"] != "unstated":
        out["max_people"] = 1 if mp["choice"] == "one" else 2

    ra = answers["registration_allowed"]
    if row["registration_allowed"] == "unknown" and ra["confidence"] >= CHOICE_CONF and ra["choice"] != "unknown":
        out["registration_allowed"] = ra["choice"]

    sp = answers["sublet_permission"]
    if row["sublet_permission"] == "unknown" and sp["confidence"] >= CHOICE_CONF and sp["choice"] != "unknown":
        out["sublet_permission"] = sp["choice"]

    fu = answers["furnished"]["noul"]
    if row["furnished"] is None:
        if fu >= NOUL_HIGH:
            out["furnished"] = True
        elif fu <= NOUL_LOW:
            out["furnished"] = False

    return row["id"], out, None


def sql_literal(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    # No single quotes or the word "returning" can appear in written values here
    # (none of our enums/booleans do), but escape defensively anyway.
    return "'" + str(v).replace("'", "''") + "'"


def main():
    load_env_file("~/.sublet-skills.env")
    load_env_file("~/.jev.env")
    dry_run = "--dry-run" in sys.argv
    limit = 100000
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])

    rows = sublet_exec(
        """
        select p.id, p.poster_id,
          coalesce(nullif(btrim(d.description), ''), nullif(btrim(p.body), '')) as state_text,
          d.room_type, d.bills_included, d.max_people,
          d.registration_allowed, d.sublet_permission, d.furnished
        from posts p join post_details d on d.post_id = p.id
        where p.intent = 'offering' and p.canonical_post_id is null and p.status = 'new'
          and coalesce(nullif(btrim(d.description), ''), nullif(btrim(p.body), '')) is not null
          and (d.room_type is null or d.bills_included is null or d.max_people is null
               or d.registration_allowed = 'unknown' or d.sublet_permission = 'unknown'
               or d.furnished is null)
        order by p.id
        """
    )
    rows = rows[:limit]
    print(f"candidates: {len(rows)}", file=sys.stderr)

    written = {"room_type": 0, "bills_included": 0, "max_people": 0,
               "registration_allowed": 0, "sublet_permission": 0, "furnished": 0}
    errors = []
    updates = []

    with cf.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i, (post_id, out, err) in enumerate(pool.map(classify_one, rows)):
            if err:
                errors.append((post_id, err))
                continue
            if out:
                for k in out:
                    written[k] += 1
                sets = ", ".join(f"{k} = {sql_literal(v)}" for k, v in out.items())
                updates.append(f"update post_details set {sets}, updated_at = now() where post_id = '{post_id}'")
            if (i + 1) % 100 == 0:
                print(f"  ...{i + 1}/{len(rows)}", file=sys.stderr)

    print("fields written:", json.dumps(written), file=sys.stderr)
    print(f"errors: {len(errors)}", file=sys.stderr)
    for post_id, err in errors[:10]:
        print(f"  {post_id}: {err}", file=sys.stderr)

    if dry_run:
        print(f"[dry run] would run {len(updates)} updates", file=sys.stderr)
        return

    # sublet_exec runs one statement at a time (a multi-statement ";"-joined
    # or begin/commit-wrapped string 400s -- found running this for real), so
    # one RPC call per row. Never lets the word "returning" slip into the
    # payload (scripts/db.py's documented sublet_exec gotcha) -- none of our
    # enum/boolean values contain it.
    write_errors = []

    def apply_update(sql):
        try:
            sublet_exec(sql)
            return None
        except Exception as e:  # noqa: BLE001 -- report and keep going
            return str(e)

    with cf.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i, err in enumerate(pool.map(apply_update, updates)):
            if err:
                write_errors.append((updates[i], err))
            if (i + 1) % 100 == 0:
                print(f"  wrote {i + 1}/{len(updates)}", file=sys.stderr)

    print(f"write errors: {len(write_errors)}", file=sys.stderr)
    for sql, err in write_errors[:10]:
        print(f"  {sql}: {err}", file=sys.stderr)
    print("done.", file=sys.stderr)


if __name__ == "__main__":
    main()
