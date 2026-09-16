#!/bin/zsh
# Cài launchd jobs trên Mac (chạy khi user đăng nhập, máy thức). Chạy 1 lần: zsh ops/install_cron.sh
# Gỡ: zsh ops/install_cron.sh uninstall
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR" "$REPO/ops/logs"

make_plist() { # name interval_seconds skill [StartCalendarInterval hour minute]
  local name="$1" skill="$2" sched="$3"
  cat > "$PLIST_DIR/com.sublet.$name.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.sublet.$name</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>$REPO/ops/run_skill.sh</string><string>$skill</string>
  </array>
  $sched
  <key>StandardOutPath</key><string>$REPO/ops/logs/launchd.$name.out</string>
  <key>StandardErrorPath</key><string>$REPO/ops/logs/launchd.$name.err</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
</dict></plist>
EOF
}

# Biến thể gọi 1 script tuỳ ý thay vì run_skill.sh <skill> (dùng cho wrapper nối skill).
make_plist_script() { # name interval_seconds script_path
  local name="$1" script="$2" sched="$3"
  cat > "$PLIST_DIR/com.sublet.$name.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.sublet.$name</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>$REPO/$script</string>
  </array>
  $sched
  <key>StandardOutPath</key><string>$REPO/ops/logs/launchd.$name.out</string>
  <key>StandardErrorPath</key><string>$REPO/ops/logs/launchd.$name.err</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
</dict></plist>
EOF
}

if [[ "${1:-}" == "uninstall" ]]; then
  for f in "$PLIST_DIR"/com.sublet.*.plist; do launchctl unload "$f" 2>/dev/null || true; rm -f "$f"; done
  echo "gỡ xong"; exit 0
fi

# Backup: non-Facebook maintenance task, chạy 23:30 hàng ngày.
make_plist backup "backup" "<key>StartCalendarInterval</key><dict><key>Hour</key><integer>23</integer><key>Minute</key><integer>30</integer></dict>"

# scrape_and_validate: mỗi 20' (1200s) chạy sublet-scrape-14-groups rồi validate-permalink
# nối tiếp (ops/run_scrape_and_validate.sh). Bật theo yêu cầu Kien 2026-09-16. Mỗi lệnh con
# tự gate giờ/wake/login/pause/page-load-budget qua run_skill.sh; hours=24/7 trong
# data/config.yaml nên không còn chặn theo giờ trong ngày.
make_plist_script scrape_and_validate "ops/run_scrape_and_validate.sh" "<key>StartInterval</key><integer>1200</integer>"

for f in "$PLIST_DIR"/com.sublet.*.plist; do launchctl unload "$f" 2>/dev/null || true; launchctl load "$f"; done
launchctl list | grep com.sublet || true
echo "đã cài. log: $REPO/ops/logs/"
