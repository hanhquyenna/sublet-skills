#!/bin/zsh
# Backup JSON hàng ngày (free tier không có PITR). Chạy: zsh ops/backup.sh  → ops/backup/YYYY-MM-DD/*.json (gitignored)
set -euo pipefail
cd "$(dirname "$0")/.."
D="ops/backup/$(date +%Y-%m-%d)"; mkdir -p "$D"
for t in sublet_groups sublet_group_metrics sublet_listings sublet_seekers sublet_matches sublet_viewings sublet_fees sublet_messages sublet_ops_state sublet_inbox; do
  python3 scripts/db.py "select * from $t" > "$D/$t.json"
done
python3 scripts/db.py "select * from sublet_events where created_at > now() - interval '7 days'" > "$D/sublet_events_7d.json"
find ops/backup -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
echo "backup → $D"
