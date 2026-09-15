#!/usr/bin/env python3
"""SQL cho Codex / Hetzner (khi không có Supabase MCP). Stdlib-only.

Ưu tiên 1: REST RPC `sublet_exec` với SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (không cần postgres password).
Ưu tiên 2: SUPABASE_DB_URL qua psycopg2 (nếu cài).
Env nằm trong ~/.sublet-skills.env (source trước, hoặc script tự đọc file đó).

Usage: python3 scripts/db.py "select count(*) from sublet_groups"   -> JSON rows
       echo "insert ..." | python3 scripts/db.py -
"""
import json, os, sys, urllib.request, urllib.error

def load_env_file():
    p = os.path.expanduser("~/.sublet-skills.env")
    if not os.path.exists(p): return
    for line in open(p):
        line = line.strip()
        if line.startswith("export "): line = line[7:]
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1); os.environ.setdefault(k, v.strip().strip('"'))

def via_rest(sql):
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/rpc/sublet_exec"
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    req = urllib.request.Request(url, data=json.dumps({"q": sql}).encode(), method="POST",
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:500]}")

def via_pg(sql):
    import psycopg2, psycopg2.extras
    with psycopg2.connect(os.environ["SUPABASE_DB_URL"]) as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql)
        return cur.fetchall() if cur.description else {"rowcount": cur.rowcount}

def main():
    load_env_file()
    sql = sys.stdin.read() if sys.argv[1:] == ["-"] else " ".join(sys.argv[1:])
    if not sql.strip(): sys.exit("no sql")
    if os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        out = via_rest(sql)
    elif os.environ.get("SUPABASE_DB_URL"):
        out = via_pg(sql)
    else:
        sys.exit("set SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_DB_URL) in ~/.sublet-skills.env")
    json.dump(out, sys.stdout, default=str, indent=2, ensure_ascii=False); print()

if __name__ == "__main__":
    main()
