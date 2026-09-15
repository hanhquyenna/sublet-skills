#!/bin/zsh
# Thiết lập env + config 1 lần, tương tác. Chạy: zsh ops/setup_env.sh
# Ghi vào: ~/.sublet-skills.env (được source bởi run_skill.sh và bởi bạn), data/config.yaml (3 ô trống).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ENVF="$HOME/.sublet-skills.env"
touch "$ENVF"; chmod 600 "$ENVF"

ask() { # var prompt [secret]
  local var="$1" prompt="$2" secret="${3:-}" cur val
  cur=$(grep -E "^export $var=" "$ENVF" 2>/dev/null | sed -E 's/^export [A-Z_]+="?([^"]*)"?$/\1/' || true)
  if [[ -n "$cur" ]]; then echo "  $var: đã có ($( [[ -n "$secret" ]] && echo '***' || echo "$cur")) — Enter để giữ"; fi
  if [[ -n "$secret" ]]; then read -rs "val?  $prompt: "; echo; else read -r "val?  $prompt: "; fi
  [[ -z "$val" ]] && val="$cur"
  if [[ -n "$val" ]]; then
    grep -vE "^export $var=" "$ENVF" > "$ENVF.tmp" || true; mv "$ENVF.tmp" "$ENVF"
    echo "export $var=\"$val\"" >> "$ENVF"
  fi
}

echo "== Supabase (Codex/Hetzner dùng psql; Claude Code có MCP nên có thể bỏ trống) =="
echo "  Lấy ở: Supabase dashboard → Project Settings → Database → Connection string (URI), dùng pooler 'session' nếu có."
ask SUPABASE_DB_URL "SUPABASE_DB_URL (postgresql://postgres.<ref>:<pw>@aws-0-eu-west-2.pooler.supabase.com:5432/postgres)" secret

echo "== Gmail nhận notification Facebook =="
echo "  App Password: Google Account → Security → 2-Step Verification → App passwords."
ask SUBLET_IMAP_USER "SUBLET_IMAP_USER (Gmail)"
ask SUBLET_IMAP_PASS "SUBLET_IMAP_PASS (App Password 16 ký tự)" secret

echo "== Config =="
read -r "name?  Tên bạn dùng trong tin nhắn (offer.your_first_name): "
read -r "form?  Link Tally form seeker (seeker_form.url, Enter nếu chưa có): "
python3 - "$REPO/data/config.yaml" "${name:-}" "${form:-}" "$(grep -E '^export SUBLET_IMAP_USER=' "$ENVF" | sed -E 's/^export [A-Z_]+="?([^"]*)"?$/\1/')" <<'PY'
import sys,re
p,name,form,imap=sys.argv[1:5]; s=open(p).read()
if name: s=re.sub(r'your_first_name: ""', f'your_first_name: "{name}"', s)
if form: s=re.sub(r'url: ""(\s+#[^\n]*)?', f'url: "{form}"\\1', s, count=1)
if imap: s=re.sub(r'imap_user: ""', f'imap_user: "{imap}"', s)
open(p,'w').write(s)
PY

# source tự động trong shell
grep -q 'sublet-skills.env' ~/.zshrc 2>/dev/null || echo '[ -f ~/.sublet-skills.env ] && source ~/.sublet-skills.env' >> ~/.zshrc
echo
echo "Xong. Env: $ENVF (chmod 600, không commit). Mở shell mới hoặc: source $ENVF"
echo "Kiểm: python3 scripts/db.py \"select count(*) from sublet_groups\""
