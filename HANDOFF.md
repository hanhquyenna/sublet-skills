# HANDOFF — prompt cho Codex (hoặc bất kỳ agent nào) tiếp quản repo này

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
6. `.agents/skills/*/SKILL.md` — toàn bộ skill (symlink tới `.claude/skills`)
7. db/schema.sql — 11 bảng sublet_* trên Supabase (đã apply; RLS bật, không policy)
8. docs/intent-logic.md — cách hiểu một post, bằng lời; intent-analyze phải theo file này

TRẠNG THÁI HIỆN TẠI (2026-09-15):
- Code + schema xong. Supabase canonical là project ref `cteunhuxrghpozwbnehh`; `scripts/db.py` dùng `~/.sublet-skills.env` + REST RPC `sublet_exec`. Snapshot DB ngày 2026-09-15: 103 `sublet_groups`, 152 metrics, 10 raw listings/context events, 0 seekers, 9 ops_state; 75 group có cờ `joined=true`. Run group activity cao nhất đã chạm boundary 14 ngày nhưng chưa đủ chứng cứ mọi card, nên `posts_14d_complete=false`; không coi 8/10 listings là tổng 14 ngày. Config `your_first_name=Kien`; `email.imap_user` và `seeker_form.url` còn trống. Chưa có cron.
- Kiến trúc: KNOW (sublet-groups) → CAPTURE (sublet-scan/backfill qua ChatGPT browser panel, sublet-email qua IMAP, lưu post + public context raw với kind=null) → ANALYZE (intent-analyze theo docs/intent-logic.md) → MATCH (scripts/match.py deterministic) → VOICE/RUN (partner-voice; sublet-draft; inbox-triage; viewing-coordinate; sublet-followup). Backfill là một group mỗi lần, cửa sổ 14 ngày, resumable và ghi DB sau từng batch. Ops: onboarding, sublet-report, sublet-diagnose, seeker-intake.
- Không có Telegram/notification. Mọi thứ tôi cần biết → bảng sublet_inbox. /sublet-followup là nơi tôi đọc.
- Offer: €49 khi người tôi giới thiệu dọn vào (config.offer.fee_trigger=move_in). Miễn phí cho người tìm nhà. Định vị: broker nhỏ, không phải agency, không nhắc AI trong tin nhắn.

MÔI TRƯỜNG CỦA BẠN (Codex):
- Env: **đã có** `~/.sublet-skills.env` (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, chmod 600). `scripts/db.py` tự đọc file đó và đi qua REST RPC `sublet_exec`; không cần source, psycopg2 hay postgres password. Thiếu IMAP → chỉ ảnh hưởng `sublet-email`; bảo tôi thêm bằng `zsh ops/setup_env.sh` khi cần. Không tự bịa giá trị, không hỏi tôi paste secret vào chat.
- DB: mọi chỗ skill viết "execute_sql" → `python3 scripts/db.py "<sql>"`. Supabase MCP database đã cấu hình trong `/Users/ad/.codex/config.toml` với project ref hiện tại. Tables: sublet_listings, sublet_seekers, sublet_matches, sublet_viewings, sublet_fees, sublet_messages, sublet_events, sublet_scan_runs, sublet_groups, sublet_ops_state, sublet_inbox.
- Browser hard rule: mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác. Thấy trang login/checkpoint/captcha/unusual activity → ghi ops_state phù hợp, bảo tôi xử lý thủ công, KHÔNG tự login và KHÔNG thử lại trong session đó.
- Headless run: ops/run_skill.sh <skill> với SUBLET_RUNNER=codex.

VIỆC ĐẦU TIÊN CỦA BẠN, THEO THỨ TỰ:
1. Chạy `python3 scripts/db.py "select count(*) from sublet_groups"` → project hiện tại phải ra 92 theo snapshot (nếu khác, kiểm tra nguyên nhân trước). Rồi chạy skill `onboarding`: đọc `sublet_ops_state` trước, chỉ hỏi mục chưa ✅, ghi kết quả.
2. Chạy `sublet-groups status` → in group tier 1–2 chưa joined → nhắc tôi join ≤5/ngày và bật Notifications → All posts.
3. Khi tôi báo đã join ≥1 group và Facebook đã login trong ChatGPT browser panel: chọn group đã joined có `posts_per_day` cao nhất rồi chạy `/sublet-backfill <group_key> 14` theo từng chunk. Capture phải lưu raw post + poster + visible public comments/replies + public context giới hạn, cập nhật DB sau từng batch, và chỉ đánh dấu complete khi thật sự qua boundary 14 ngày và xử lý hết card có permalink. Sau đó mới chạy `intent-analyze` riêng; không DM ai trước QA.
4. Khi có ≥3 seeker (`seeker-intake`): `sublet-match` cho offering deal_score cao nhất → `sublet-draft` → in draft DM để tôi gửi.
5. Từ đó, mỗi session: `sublet-followup` trước — in hàng đợi sublet_inbox + draft; chờ tôi gửi; tôi gõ `sublet-draft sent <id>`.

LUẬT KHI SỬA LOGIC (PLAN.md phần H): rule phân loại ở docs/intent-logic.md (sửa xong chạy `intent-analyze --all` và kiểm lại 10 ví dụ mục 12 + tests/intent_cases.json nếu có); trọng số match ở scripts/match.py; giọng ở partner-voice/SKILL.md; template ở templates/; ngưỡng volume/giờ ở data/config.yaml. Commit message "rule: <gì> vì <lý do>". Không sửa CLAUDE.md phần "Không bao giờ".

KHÔNG LÀM DÙ TÔI CÓ BẢO: tự gửi DM/comment/post trên Facebook; chạy headless hoặc dán cookie vào máy khác; mở từng group để scan (dùng groups/feed); thu tiền hộ, giữ deposit; ghi listing filled / match signed khi chưa có xác nhận từ subletter hoặc seeker; xếp hạng theo quốc tịch/giới tính.

Khi xong bước 1, in checklist onboarding với ✅/⬜ và 1 dòng "việc tiếp theo của bạn".
```

---

## Ghi chú cho người vận hành

- Prompt trên tự đủ; Codex không cần lịch sử chat này.
- Nếu dùng Claude Code thay vì Codex: mở `claude` trong repo và gõ `/onboarding` — CLAUDE.md và skills tự load, không cần prompt này.
- Thứ chưa quyết, để dữ liệu quyết sau 30 ngày: fee trigger (move_in vs 3 viewings), promise 72h vs 24h, có thêm `outreach-prep` (agent điền sẵn draft vào ô Messenger, bạn Enter) hay không.
