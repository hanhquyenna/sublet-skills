#!/bin/zsh
# Chạy 1 skill headless. Dùng bởi launchd (Mac) hoặc cron (Hetzner).
# Usage: ops/run_skill.sh <skill> [args]   ví dụ: ops/run_skill.sh sublet-scrape-14-groups
# Env: SUBLET_RUNNER=claude|codex (mặc định claude)
set -euo pipefail
cd "$(dirname "$0")/.."
source ~/.zshrc 2>/dev/null || true
[ -f ~/.sublet-skills.env ] && source ~/.sublet-skills.env

export TZ=Europe/Amsterdam
SKILL="$1"; shift || true
case "$SKILL" in
  information|sublet-scrape-14-groups|validate-permalink|backup) ;;
  *) echo "unsupported skill in active scope: $SKILL" >&2; exit 2 ;;
esac
# Skill nào cần Chrome thật (Facebook) — dùng để gate giờ/wake/login/pause bên dưới.
case "$SKILL" in
  sublet-scrape-14-groups|validate-permalink) NEEDS_CHROME=1 ;;
  *) NEEDS_CHROME=0 ;;
esac
# R20: 1 skill 1 instance
mkdir -p ops/locks; exec 9>"ops/locks/$SKILL.lock"; if ! flock -n 9; then echo "$(date +%T) skip $SKILL (locked)" >> "ops/logs/$(date +%Y-%m-%d).log"; exit 0; fi
ARGS="$*"
RUNNER="${SUBLET_RUNNER:-claude}"
LOG="ops/logs/$(date +%Y-%m-%d).log"
mkdir -p ops/logs

# Giờ chạy đọc trực tiếp từ data/config.yaml (hours.start/hours.end), không hardcode.
# Từ 2026-09-16 config đặt 00:00–23:59 (24/7) theo yêu cầu Kien; đổi lại config nếu cần thu hẹp giờ.
NOWMIN=$(( 10#$(TZ=Europe/Amsterdam date +%H) * 60 + 10#$(TZ=Europe/Amsterdam date +%M) ))
STARTSTR=$(grep -A2 '^hours:' data/config.yaml | grep 'start:' | sed -E 's/.*"([0-9]{2}):([0-9]{2})".*/\1 \2/')
ENDSTR=$(grep -A2 '^hours:' data/config.yaml | grep 'end:' | sed -E 's/.*"([0-9]{2}):([0-9]{2})".*/\1 \2/')
STARTMIN=$(( 10#$(echo $STARTSTR | awk '{print $1}') * 60 + 10#$(echo $STARTSTR | awk '{print $2}') ))
ENDMIN=$(( 10#$(echo $ENDSTR | awk '{print $1}') * 60 + 10#$(echo $ENDSTR | awk '{print $2}') ))
# start=00:00 và end=23:59 (hoặc lớn hơn) nghĩa là 24/7, không chặn giờ nào.
if [[ "$NEEDS_CHROME" == "1" && ! ( $STARTMIN -eq 0 && $ENDMIN -ge 1439 ) && ( $NOWMIN -lt $STARTMIN || $NOWMIN -ge $ENDMIN ) ]]; then
  echo "$(date +%T) skip $SKILL (ngoài giờ config: ${STARTSTR// /:}-${ENDSTR// /:})" >> "$LOG"; exit 0
fi

# Skill cần Chrome thật chỉ chạy khi máy thức > 2 phút và có màn hình mở
if [[ "$NEEDS_CHROME" == "1" ]]; then
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

# Watchdog thủ công (máy này không có timeout/gtimeout sẵn). Nếu claude/codex treo
# (chờ page load mãi, model kẹt...), lock ở dòng flock phía trên sẽ giữ mãi và mọi
# tick cron sau chỉ thấy "locked" rồi bỏ qua vô thời hạn — không tự phục hồi.
# Mặc định 900s (15') để luôn xong trước tick kế tiếp (1200s); đổi qua
# SUBLET_SKILL_TIMEOUT nếu cần.
TIMEOUT_SECS="${SUBLET_SKILL_TIMEOUT:-900}"
case "$RUNNER" in
  claude) CMD=(claude -p "/$SKILL $ARGS" --permission-mode acceptEdits) ;;
  codex)  CMD=(codex exec "Run the $SKILL skill. $ARGS") ;;
esac
"${CMD[@]}" >> "$LOG" 2>&1 &
CPID=$!
(
  sleep "$TIMEOUT_SECS"
  if kill -0 "$CPID" 2>/dev/null; then
    echo "$(date +%T) TIMEOUT $SKILL sau ${TIMEOUT_SECS}s — gửi TERM" >> "$LOG"
    kill -TERM "$CPID" 2>/dev/null
    sleep 10
    if kill -0 "$CPID" 2>/dev/null; then
      echo "$(date +%T) TIMEOUT $SKILL vẫn sống — gửi KILL" >> "$LOG"
      kill -KILL "$CPID" 2>/dev/null
    fi
  fi
) &
WATCHDOG=$!
set +e
wait "$CPID"
STATUS=$?
set -e
kill "$WATCHDOG" 2>/dev/null || true
wait "$WATCHDOG" 2>/dev/null || true

if [[ $STATUS -ne 0 ]]; then
  echo "$(date +%T) done $SKILL (exit=$STATUS — có thể bị timeout/kill)" >> "$LOG"
else
  echo "$(date +%T) done $SKILL" >> "$LOG"
fi
