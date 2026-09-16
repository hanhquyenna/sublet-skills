#!/bin/zsh
# 1 cron tick = chạy sublet-scrape-14-groups rồi validate-permalink nối tiếp.
# Mỗi skill tự gate giờ/wake/login/pause/page-load-budget riêng trong run_skill.sh;
# nếu scrape bị skip (ngoài giờ/paused/chưa login) thì validate vẫn thử chạy độc lập.
set -uo pipefail
cd "$(dirname "$0")/.."
zsh ops/run_skill.sh sublet-scrape-14-groups
zsh ops/run_skill.sh validate-permalink
