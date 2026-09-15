# AGENTS.md — cho Codex (bản tương đương CLAUDE.md)

Đọc **CLAUDE.md** — toàn bộ luật cứng ở đó và áp dụng nguyên văn cho Codex. Tóm tắt:
- Chỉ ĐỌC Facebook. Không post/comment/like/DM/join/submit form.
- Capture tuần tự tối đa 14 group, cửa sổ 14 ngày; ≤4 page load/run và dừng ngay khi thấy checkpoint/captcha/login.
- Mọi raw record có `source_url` + `seen_at`; resume từ DB cursor và dedupe trước khi ghi.

## Skills
Active sublet scope gồm `.agents/skills/information/SKILL.md`,
`.agents/skills/sublet-scrape-14-groups/SKILL.md` và
`.agents/skills/validate-permalink/SKILL.md` (symlink → `.claude/skills`).
Đọc `information` trước; capture bằng `sublet-scrape-14-groups`, rồi gọi
`validate-permalink` để xử lý queue link theo thứ tự.

## Browser
Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác để thao tác/verify Facebook. Người dùng login thủ công; agent chỉ đọc và phải dừng khi thấy login/checkpoint/captcha/unusual activity.

Trong skill, các bước navigate / get page text / scroll map sang thao tác đọc trong ChatGPT browser panel. DB/SQL là luồng riêng và vẫn dùng `scripts/db.py`; không dùng script đó để điều khiển Facebook.

## Database
Supabase project Lamy hiện tại là ref `cteunhuxrghpozwbnehh`. Secret nằm trong `~/.sublet-skills.env` (chmod 600); không commit/in giá trị. `scripts/db.py` tự đọc `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` và chạy REST RPC `sublet_exec`, nên workflow hiện tại không cần `SUPABASE_DB_URL` hay psycopg2. Supabase MCP database cũng đã cấu hình trong `/Users/ad/.codex/config.toml`; khi skill viết "execute_sql", đường chạy chuẩn là `python3 scripts/db.py "<sql>"`.

## Headless run
`ops/run_skill.sh` với `SUBLET_RUNNER=codex` → `codex exec "Run the <skill> skill"`.
