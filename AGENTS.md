# AGENTS.md — cho Codex (bản tương đương CLAUDE.md)

Đọc **CLAUDE.md** — toàn bộ luật cứng ở đó và áp dụng nguyên văn cho Codex. Tóm tắt:
- Chỉ ĐỌC Facebook. Không post/comment/like/DM/join. Người dùng gửi mọi tin.
- ≤4 page load/chu kỳ scan, ≤6 cho inbox-triage, chỉ 08–23h Amsterdam, dừng ngay khi thấy checkpoint/captcha/login.
- Match score từ `scripts/match.py`. Mọi tin gửi ra ngoài phải qua `partner-voice`.
- Mọi record có `source_url` + `seen_at`.

## Skills
Cùng bộ với Claude Code, tại `.agents/skills/<name>/SKILL.md` (symlink → `.claude/skills`). Gọi bằng tên: "run the sublet-scan skill".
Skill `information` là bản đồ context/runtime; đọc trước khi onboarding hoặc khi cần khôi phục trạng thái dự án.

## Browser
Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác để thao tác/verify Facebook. Người dùng login thủ công; agent chỉ đọc và phải dừng khi thấy login/checkpoint/captcha/unusual activity.

Trong skill, các bước navigate / get page text / scroll map sang thao tác đọc trong ChatGPT browser panel. DB/SQL là luồng riêng và vẫn dùng `scripts/db.py`; không dùng script đó để điều khiển Facebook.

## Database
Supabase project Lamy hiện tại là ref `cteunhuxrghpozwbnehh`. Secret nằm trong `~/.sublet-skills.env` (chmod 600); không commit/in giá trị. `scripts/db.py` tự đọc `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` và chạy REST RPC `sublet_exec`, nên workflow hiện tại không cần `SUPABASE_DB_URL` hay psycopg2. Supabase MCP database cũng đã cấu hình trong `/Users/ad/.codex/config.toml`; khi skill viết "execute_sql", đường chạy chuẩn là `python3 scripts/db.py "<sql>"`.

## Headless run
`ops/run_skill.sh` với `SUBLET_RUNNER=codex` → `codex exec "Run the <skill> skill"`.
