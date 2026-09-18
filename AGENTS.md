# AGENTS.md — cho Codex (bản tương đương CLAUDE.md)

Đọc **CLAUDE.md** — toàn bộ luật cứng ở đó và áp dụng nguyên văn cho Codex. Tóm tắt:
- Facebook mặc định chỉ ĐỌC. Không post/comment/like/join/submit form. DM là ngoại lệ duy nhất: `outreach-prep` được gửi **pre-existing** `outreach_messages.status='draft'` qua visible browser panel theo `CLAUDE.md` — agent tự gửi ready drafts theo `outreach_order`, không cần hỏi lại từng tin.
- Capture tuần tự tối đa 14 group, cửa sổ 14 ngày; ≤4 page load/run và dừng ngay khi thấy checkpoint/captcha/login.
- Mọi raw record có `source_url` + `seen_at`; resume từ DB cursor và dedupe trước khi ghi.

## Skills
Active sublet scope gồm `information`, `sublet-scrape-14-groups`,
`validate-permalink`, `analyze-insights`, `data-engineer`, `intent-analyze` và
`outreach-prep` trong `.agents/skills/` (symlink → `.claude/skills`).
Đọc `information` trước; capture bằng `sublet-scrape-14-groups`, rồi gọi
`validate-permalink` để xử lý queue link theo thứ tự. `analyze-insights` là
skill đọc-only trên DB (không mở Facebook), chạy bất kỳ lúc nào sau capture để
tóm tắt insight — không thay thế `validate-permalink` và không phải pipeline
`intent-analyze` chính thức.

## Browser
Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác để thao tác/verify Facebook. Người dùng login thủ công; agent chỉ đọc trừ DM send đã được phép bởi `outreach-prep`, và luôn phải dừng khi thấy login/checkpoint/captcha/unusual activity.

Trong skill, mọi bước navigate / get page text / scroll / click đọc map sang **Chrome-panel browser automation có UI**, ưu tiên DOM/accessibility tree của panel. DB/SQL là luồng riêng và vẫn dùng `scripts/db.py`; không dùng script đó để điều khiển Facebook.

## Database
Supabase project Lamy hiện tại là ref `cteunhuxrghpozwbnehh`. Secret nằm trong `~/.sublet-skills.env` (chmod 600); không commit/in giá trị. `scripts/db.py` tự đọc `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` và chạy REST RPC `sublet_exec`, nên workflow hiện tại không cần `SUPABASE_DB_URL` hay psycopg2. Supabase MCP database cũng đã cấu hình trong `/Users/ad/.codex/config.toml`; khi skill viết "execute_sql", đường chạy chuẩn là `python3 scripts/db.py "<sql>"`.

## Headless run
`ops/run_skill.sh` với `SUBLET_RUNNER=codex` → `codex exec "Run the <skill> skill"`.
