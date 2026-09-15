# AGENTS.md — cho Codex (bản tương đương CLAUDE.md)

Đọc **CLAUDE.md** — toàn bộ luật cứng ở đó và áp dụng nguyên văn cho Codex. Tóm tắt:
- Chỉ ĐỌC Facebook. Không post/comment/like/DM/join. Người dùng gửi mọi tin.
- ≤4 page load/chu kỳ scan, ≤6 cho inbox-triage, chỉ 08–23h Amsterdam, dừng ngay khi thấy checkpoint/captcha/login.
- Match score từ `scripts/match.py`. Mọi tin gửi ra ngoài phải qua `partner-voice`.
- Mọi record có `source_url` + `seen_at`.

## Skills
Cùng bộ với Claude Code, tại `.agents/skills/<name>/SKILL.md` (symlink → `.claude/skills`). Gọi bằng tên: "run the sublet-scan skill".

## Browser
Codex không có Claude in Chrome. Dùng **Chrome DevTools MCP** attach vào một **Chrome profile riêng** đã login Facebook (Chrome ≥136 không cho remote debugging trên profile mặc định):

```
# khởi động Chrome profile riêng, 1 lần, để mở cả ngày
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --user-data-dir="$HOME/.sublet-chrome" --remote-debugging-port=9222 --no-first-run &
```
Không dùng `--headless`, không dùng `--enable-automation`. Login Facebook trong cửa sổ đó 1 lần.

`~/.codex/config.toml`:
```
[mcp_servers.chrome]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
```
Trong skill, các bước "navigate / get_page_text / scroll" map sang tool của chrome-devtools-mcp (`navigate_page`, `take_snapshot`, `evaluate_script` để lấy innerText). Không gọi `Runtime.enable`-heavy tool nếu có lựa chọn snapshot/a11y.

## Database
Supabase project Lamy, bảng `sublet_*`. Codex không có Supabase MCP mặc định → dùng `scripts/db.py` (psycopg2 qua `SUPABASE_DB_URL` trong `~/.sublet-skills.env`, tạo bằng `zsh ops/setup_env.sh`) hoặc cài Supabase MCP theo `ops/codex-config.example.toml`. Mọi chỗ skill viết "execute_sql" → với Codex là `python3 scripts/db.py "<sql>"`.

## Headless run
`ops/run_skill.sh` với `SUBLET_RUNNER=codex` → `codex exec "Run the <skill> skill"`.
