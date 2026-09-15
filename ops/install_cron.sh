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

if [[ "${1:-}" == "uninstall" ]]; then
  for f in "$PLIST_DIR"/com.sublet.*.plist; do launchctl unload "$f" 2>/dev/null || true; rm -f "$f"; done
  echo "gỡ xong"; exit 0
fi

# 1. scan mỗi 12' (run_skill.sh tự bỏ qua ngoài 08–23 và 1/12 lần ngẫu nhiên trong skill)
make_plist scan sublet-scan "<key>StartInterval</key><integer>720</integer>"
# 2. inbox mỗi 20'
make_plist inbox inbox-triage "<key>StartInterval</key><integer>1200</integer>"
# 3. email mỗi 10' (không cần Chrome — sẽ chuyển sang Hetzner)
make_plist email sublet-email "<key>StartInterval</key><integer>600</integer>"
# 4. followup 08:30
make_plist followup sublet-followup "<key>StartCalendarInterval</key><dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>"
# 5. report 18:00
make_plist report sublet-report "<key>StartCalendarInterval</key><dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>"
# 6. groups rank Chủ nhật 10:00
make_plist groups "sublet-groups rank" "<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>"

for f in "$PLIST_DIR"/com.sublet.*.plist; do launchctl unload "$f" 2>/dev/null || true; launchctl load "$f"; done
launchctl list | grep com.sublet || true
echo "đã cài. log: $REPO/ops/logs/"
