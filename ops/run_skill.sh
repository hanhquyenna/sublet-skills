#!/bin/zsh
# Chạy 1 skill headless. Dùng bởi launchd (Mac) hoặc cron (Hetzner).
# Usage: ops/run_skill.sh <skill> [args]   ví dụ: ops/run_skill.sh sublet-scan
# Env: SUBLET_RUNNER=claude|codex (mặc định claude)
set -euo pipefail
cd "$(dirname "$0")/.."
source ~/.zshrc 2>/dev/null || true
[ -f ~/.sublet-skills.env ] && source ~/.sublet-skills.env

SKILL="$1"; shift || true
ARGS="$*"
RUNNER="${SUBLET_RUNNER:-claude}"
LOG="ops/logs/$(date +%Y-%m-%d).log"
mkdir -p ops/logs

# Giờ chạy theo config (08–23 Amsterdam). Ngoài giờ → thoát im lặng.
H=$(TZ=Europe/Amsterdam date +%H)
if [[ "$SKILL" != "sublet-report" && ( $H -lt 8 || $H -ge 23 ) ]]; then
  echo "$(date +%T) skip $SKILL (ngoài giờ)" >> "$LOG"; exit 0
fi

# Skill cần Chrome thật chỉ chạy khi máy thức > 2 phút và có màn hình mở
if [[ "$SKILL" == "sublet-scan" || "$SKILL" == "inbox-triage" || "$SKILL" == "sublet-groups" ]]; then
  BOOT=$(sysctl -n kern.boottime | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
  NOW=$(date +%s)
  if (( NOW - BOOT < 120 )); then echo "$(date +%T) skip $SKILL (vừa wake)" >> "$LOG"; exit 0; fi
  # Chưa login Facebook (ops_state) → không tốn page load
  FB=$(python3 scripts/db.py "select value from sublet_ops_state where key='chrome_fb_login'" 2>/dev/null | grep -o '"value": "[^"]*' | cut -d'"' -f4)
  if [[ "${FB:-no}" != yes* ]]; then echo "$(date +%T) skip $SKILL (chrome_fb_login=${FB:-unset})" >> "$LOG"; exit 0; fi
  # Tạm dừng 24h sau checkpoint
  PAUSE=$(python3 scripts/db.py "select value from sublet_ops_state where key='scan_paused_until' and value::timestamptz > now()" 2>/dev/null | grep -c '"value"' || true)
  if [[ "$PAUSE" != "0" ]]; then echo "$(date +%T) skip $SKILL (paused)" >> "$LOG"; exit 0; fi
fi

echo "$(date +%T) run $SKILL $ARGS" >> "$LOG"
if [[ "$SKILL" == "backup" ]]; then zsh ops/backup.sh >> "$LOG" 2>&1; echo "$(date +%T) done backup" >> "$LOG"; exit 0; fi
case "$RUNNER" in
  claude) claude -p "/$SKILL $ARGS" --permission-mode acceptEdits >> "$LOG" 2>&1 ;;
  codex)  codex exec "Run the $SKILL skill. $ARGS" >> "$LOG" 2>&1 ;;
esac
echo "$(date +%T) done $SKILL" >> "$LOG"
