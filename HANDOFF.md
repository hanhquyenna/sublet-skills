# HANDOFF — prompt cho Codex (hoặc bất kỳ agent nào) tiếp quản repo này

> **Active scope:** bộ sublet hiện có `information`, `sublet-scrape-14-groups`, `validate-permalink`, `data-engineer` và `analyze-insights`. Các tên skill/workflow cũ còn trong phần lịch sử bên dưới không được gọi hoặc khôi phục.

Copy nguyên khối dưới đây làm tin nhắn đầu tiên cho Codex khi mở `~/sublet-skills`.

---

```
Bạn tiếp quản dự án `sublet-skills` — bộ skill vận hành dịch vụ ghép sublet ở Amsterdam. Agent là mắt + trí nhớ + người soạn; người vận hành (tôi) là tay + tên. Mục tiêu 30 ngày (Phase 0): đo 5 số — offering thật/ngày theo group, DM→ok %, accepted→3 viewing/72h %, show-up %, fee thu %.

ĐỌC THEO THỨ TỰ, KHÔNG BỎ QUA:
1. `.agents/skills/information/SKILL.md` — context/runtime snapshot và vị trí mọi thành phần
2. AGENTS.md  — luật cho Codex (trỏ sang CLAUDE.md, áp dụng nguyên văn)
3. CLAUDE.md  — luật cứng: CHỈ ĐỌC Facebook, không post/comment/like/DM/join; ≤4 page load/chu kỳ scan, ≤6 cho inbox-triage; chỉ 08–23h Amsterdam; thấy checkpoint/captcha/login → dừng, ghi sublet_inbox(level='stop'), không chạy lại 24h. Mọi tin gửi ra do tôi gửi.
4. PLAN.md    — logic từng skill, bảng đọc/ghi, state machine, cron, cách cập nhật rule (phần H)
5. README.md  — setup + daily loop
6. `.agents/skills/information/SKILL.md`, `.agents/skills/sublet-scrape-14-groups/SKILL.md`, `.agents/skills/validate-permalink/SKILL.md`, `.agents/skills/analyze-insights/SKILL.md` và `.agents/skills/data-engineer/SKILL.md` — năm skill active
7. db/schema.sql — 11 bảng sublet_* trên Supabase (đã apply; RLS bật, không policy)

TRẠNG THÁI HIỆN TẠI (2026-09-16):
- Code + schema xong. Supabase canonical là project ref `cteunhuxrghpozwbnehh`; `scripts/db.py` dùng `~/.sublet-skills.env` + REST RPC `sublet_exec`. Snapshot DB mới nhất: 103 `sublet_groups`, 152 metrics, 48 listings, 62 events, 6 scan runs, 10 ops_state; validation queue có 45 `unvalidated`, 2 `validated`, 1 `inaccessible`. Schema có `link_validation_status`, `link_validated_url`, attempts/note và view `sublet_v_link_validation_queue`. Config `your_first_name=Kien`; `email.imap_user` và `seeker_form.url` còn trống. Chưa có cron.
- Kiến trúc active: `information` → `sublet-scrape-14-groups` → `validate-permalink` qua ChatGPT browser panel; `data-engineer` QA/normalize/aggregate DB-only; `analyze-insights` tạo insight heuristic và candidate signal. Capture lưu post + public context raw với `kind=null`, giữ cả share URL chưa resolve; validation tuần tự ghi `validated`/`inaccessible`/`needs_review`. Match chính thức và outreach vẫn là future scope.
- Run group activity cao nhất là `sublet_scan_runs.id=7`; boundary đã chạm card **31/08 lúc 23:40**, DB ghi `posts_seen=54`, `new_listings=42`, `posts_verified=46`, `unresolved_cards=15`, `page_loads=4/4`, `finished_at=NULL`, `posts_14d_complete=false`. Không báo đủ 14 ngày và không chuyển group khi run/capture còn incomplete.
- Không có Telegram/notification và không có outreach trong active scope.
- Offer: €49 khi người tôi giới thiệu dọn vào (config.offer.fee_trigger=move_in). Miễn phí cho người tìm nhà. Định vị: broker nhỏ, không phải agency, không nhắc AI trong tin nhắn.

MÔI TRƯỜNG CỦA BẠN (Codex):
- Env: **đã có** `~/.sublet-skills.env` (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, chmod 600). `scripts/db.py` tự đọc file đó và đi qua REST RPC `sublet_exec`; không cần source, psycopg2 hay postgres password. IMAP/email không thuộc active scope. Không tự bịa giá trị, không hỏi tôi paste secret vào chat.
- DB: mọi chỗ skill viết "execute_sql" → `python3 scripts/db.py "<sql>"`. Supabase MCP database đã cấu hình trong `/Users/ad/.codex/config.toml` với project ref hiện tại. Tables: sublet_listings, sublet_seekers, sublet_matches, sublet_viewings, sublet_fees, sublet_messages, sublet_events, sublet_scan_runs, sublet_groups, sublet_ops_state, sublet_inbox.
- Browser hard rule: mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác. Thấy trang login/checkpoint/captcha/unusual activity → ghi ops_state phù hợp, bảo tôi xử lý thủ công, KHÔNG tự login và KHÔNG thử lại trong session đó.
- Headless run: ops/run_skill.sh <skill> với SUBLET_RUNNER=codex.

VIỆC ĐẦU TIÊN CỦA BẠN, THEO THỨ TỰ:
1. Chạy `python3 scripts/db.py "select count(*) from sublet_groups"`, đọc `sublet_ops_state`/run mở và `select * from sublet_v_link_validation_queue` trước khi mở browser.
2. Đọc `/information`, chạy `/sublet-scrape-14-groups` để capture raw bằng DOM/a11y; với card không lộ permalink dùng Share → Copy link, lưu share URL và để `unvalidated`, không mở từng link trong capture pass.
3. Chạy `/validate-permalink` theo `seen_at asc, id asc`: mở từng link trong ChatGPT browser panel, xác nhận group/poster/content; nếu inaccessible thì thử recovery đúng một lần bằng group + poster/anonymous + timestamp + text/media fingerprint. Chỉ match duy nhất mới ghi `link_validated_url`; không overwrite `source_url` gốc.
4. Sau mỗi record/batch xác nhận listing/event/run/cursor đã ghi. `inaccessible` chỉ dành cho Facebook xác nhận unavailable sau recovery; checkpoint/login/timeout/ambiguous là `needs_review`. Không chuyển group và không claim đủ 14 ngày khi còn unresolved/partial.

LUẬT KHI SỬA LOGIC (PLAN.md phần H): rule phân loại ở docs/intent-logic.md (sửa xong chạy `intent-analyze --all` và kiểm lại 10 ví dụ mục 12 + tests/intent_cases.json nếu có); trọng số match ở scripts/match.py; giọng ở partner-voice/SKILL.md; template ở templates/; ngưỡng volume/giờ ở data/config.yaml. Commit message "rule: <gì> vì <lý do>". Không sửa CLAUDE.md phần "Không bao giờ".

KHÔNG LÀM DÙ TÔI CÓ BẢO: tự gửi DM/comment/post trên Facebook; chạy headless hoặc dán cookie vào máy khác; mở từng group để scan (dùng groups/feed); thu tiền hộ, giữ deposit; ghi listing filled / match signed khi chưa có xác nhận từ subletter hoặc seeker; xếp hạng theo quốc tịch/giới tính.

Khi xong bước 1, in checklist onboarding với ✅/⬜ và 1 dòng "việc tiếp theo của bạn".
```

---

## Ghi chú cho người vận hành

- Prompt trên tự đủ; Codex không cần lịch sử chat này.
- Nếu dùng Claude Code thay vì Codex: mở `claude` trong repo và gõ `/onboarding` — CLAUDE.md và skills tự load, không cần prompt này.
- Thứ chưa quyết, để dữ liệu quyết sau 30 ngày: fee trigger (move_in vs 3 viewings), promise 72h vs 24h, có thêm `outreach-prep` (agent điền sẵn draft vào ô Messenger, bạn Enter) hay không.
