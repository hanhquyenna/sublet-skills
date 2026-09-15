# HANDOFF — prompt cho Codex (hoặc bất kỳ agent nào) tiếp quản repo này

Copy nguyên khối dưới đây làm tin nhắn đầu tiên cho Codex khi mở `~/sublet-skills`.

---

```
Bạn tiếp quản dự án `sublet-skills` — bộ skill vận hành dịch vụ ghép sublet ở Amsterdam. Agent là mắt + trí nhớ + người soạn; người vận hành (tôi) là tay + tên. Mục tiêu 30 ngày (Phase 0): đo 5 số — offering thật/ngày theo group, DM→ok %, accepted→3 viewing/72h %, show-up %, fee thu %.

ĐỌC THEO THỨ TỰ, KHÔNG BỎ QUA:
1. AGENTS.md  — luật cho Codex (trỏ sang CLAUDE.md, áp dụng nguyên văn)
2. CLAUDE.md  — luật cứng: CHỈ ĐỌC Facebook, không post/comment/like/DM/join; ≤4 page load/chu kỳ scan, ≤6 cho inbox-triage; chỉ 08–23h Amsterdam; thấy checkpoint/captcha/login → dừng, ghi sublet_inbox(level='stop'), không chạy lại 24h. Mọi tin gửi ra do tôi gửi.
3. PLAN.md    — logic từng skill, bảng đọc/ghi, state machine, cron, cách cập nhật rule (phần H)
4. README.md  — setup + daily loop
5. .agents/skills/*/SKILL.md — 14 skill (symlink tới .claude/skills)
6. db/schema.sql — 11 bảng sublet_* trên Supabase (đã apply; RLS bật, không policy)
7. docs/intent-logic.md — cách hiểu một post, bằng lời; intent-analyze phải theo file này

TRẠNG THÁI HIỆN TẠI (2026-09-15):
- Code + schema xong. Onboarding: env_file ✅, supabase_ok ✅ (db.py trả 7 groups), inbox_ok ✅, config your_first_name=Kien ✅. Còn ⬜: chrome_fb_login (Chrome đang ở trang login), env_imap, seeker_form.url, groups (0/6 joined), cron. Chưa có seeker.
- Kiến trúc: KNOW (sublet-groups) → CAPTURE (sublet-scan qua Chrome thật / sublet-email qua IMAP, lưu thô kind=null) → ANALYZE (intent-analyze theo docs/intent-logic.md: kind, subtype, poster_type, fields, scam_score, deal_score, confidence) → MATCH (scripts/match.py deterministic) → VOICE/RUN (partner-voice; sublet-draft; inbox-triage; viewing-coordinate; sublet-followup). Ops: onboarding, sublet-report, sublet-diagnose, seeker-intake.
- Không có Telegram/notification. Mọi thứ tôi cần biết → bảng sublet_inbox. /sublet-followup là nơi tôi đọc.
- Offer: €49 khi người tôi giới thiệu dọn vào (config.offer.fee_trigger=move_in). Miễn phí cho người tìm nhà. Định vị: broker nhỏ, không phải agency, không nhắc AI trong tin nhắn.

MÔI TRƯỜNG CỦA BẠN (Codex):
- Env: **đã có** `~/.sublet-skills.env` (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, chmod 600). `scripts/db.py` tự đọc file đó — không cần source, không cần psycopg2, không cần postgres password (đi qua REST rpc `sublet_exec`). Thiếu IMAP (SUBLET_IMAP_USER/PASS) → chỉ ảnh hưởng `sublet-email`; bảo tôi thêm bằng `zsh ops/setup_env.sh` khi cần. Không tự bịa giá trị, không hỏi tôi paste secret vào chat.
- DB: mọi chỗ skill viết "execute_sql" → `python3 scripts/db.py "<sql>"` (cần `pip3 install psycopg2-binary`). Hoặc Supabase MCP theo ops/codex-config.example.toml. Tables: sublet_listings, sublet_seekers, sublet_matches, sublet_viewings, sublet_fees, sublet_messages, sublet_events, sublet_scan_runs, sublet_groups, sublet_ops_state, sublet_inbox.
- Browser: Chrome DevTools MCP attach vào Chrome profile riêng đã login Facebook, cổng 9222, KHÔNG headless, KHÔNG --enable-automation (lệnh trong AGENTS.md). Thấy trang login → ghi ops_state chrome_fb_login=no, bảo tôi login tay, KHÔNG tự login, KHÔNG thử lại trong session đó.
- Headless run: ops/run_skill.sh <skill> với SUBLET_RUNNER=codex.

VIỆC ĐẦU TIÊN CỦA BẠN, THEO THỨ TỰ:
1. Chạy `python3 scripts/db.py "select count(*) from sublet_groups"` → phải ra 7 (env đã có sẵn). Rồi chạy skill `onboarding`: đọc `sublet_ops_state` trước, chỉ hỏi mục chưa ✅, ghi kết quả.
2. Chạy `sublet-groups status` → in group tier 1–2 chưa joined → nhắc tôi join ≤5/ngày và bật Notifications → All posts.
3. Khi tôi báo đã join ≥1 group và Chrome đã login: chạy `sublet-backfill <group_key>` cho group đó (1 lần, 60 ngày, human pace) → `intent-analyze` hết corpus → in thống kê kind × subtype × poster_type, top 10 deal_score, 10 low-confidence, 10 scam. Rồi QA 20 post cùng tôi, sửa docs/intent-logic.md §12, chạy `intent-analyze --all`. Chưa DM ai cho đến khi kind ≥95% và không có agency lọt vào deal_score ≥60.
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
