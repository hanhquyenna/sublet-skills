#!/usr/bin/env python3
"""SQL qua psycopg2 khi không có Supabase MCP (Codex / Hetzner).
Env: SUPABASE_DB_URL=postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres
Usage: python3 scripts/db.py "select count(*) from sublet_listings"   -> JSON rows
       echo "insert ..." | python3 scripts/db.py -
Cài: pip3 install psycopg2-binary
"""
import json, os, sys
def main():
    url = os.environ.get("SUPABASE_DB_URL")
    if not url: sys.exit("set SUPABASE_DB_URL")
    try:
        import psycopg2, psycopg2.extras
    except ImportError:
        sys.exit("pip3 install psycopg2-binary")
    sql = sys.stdin.read() if sys.argv[1:] == ["-"] else " ".join(sys.argv[1:])
    with psycopg2.connect(url) as c, c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql)
        if cur.description:
            json.dump(cur.fetchall(), sys.stdout, default=str, indent=2, ensure_ascii=False); print()
        else:
            print(json.dumps({"rowcount": cur.rowcount}))
if __name__ == "__main__": main()
