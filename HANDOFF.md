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

TRẠNG THÁI HIỆN TẠI:
- Code + schema xong, chưa chạy thật lần nào. Chưa join group nào. Chưa có seeker. data/config.yaml còn trống: email.imap_user, offer.your_first_name, seeker_form.url.
- Kiến trúc: KNOW (sublet-groups) → CAPTURE (sublet-scan qua Chrome thật / sublet-email qua IMAP, lưu thô kind=null) → ANALYZE (intent-analyze: intent, fields, scam) → MATCH (scripts/match.py deterministic) → VOICE/RUN (partner-voice; sublet-draft; inbox-triage; viewing-coordinate; sublet-followup). Ops: onboarding, sublet-report, sublet-diagnose, seeker-intake.
- Không có Telegram/notification nào. Mọi thứ tôi cần biết → bảng sublet_inbox. /sublet-followup là nơi tôi đọc.
- Offer: €49 khi người tôi giới thiệu dọn vào (config.offer.fee_trigger=move_in). Miễn phí cho người tìm nhà. Định vị: broker nhỏ, không phải agency, không AI trong tin nhắn.

MÔI TRƯỜNG CỦA BẠN (Codex):
- Browser: Chrome DevTools MCP attach vào Chrome profile riêng đã login Facebook, cổng 9222, KHÔNG headless, KHÔNG --enable-automation. Lệnh khởi động trong AGENTS.md. Trong skill, "navigate/get_page_text/scroll" = navigate_page / take_snapshot hoặc evaluate_script(innerText) / scroll.
- DB: scripts/db.py với env SUPABASE_DB_URL (psycopg2-binary), hoặc Supabase MCP nếu đã cài. Tables: sublet_listings, sublet_seekers, sublet_matches, sublet_viewings, sublet_fees, sublet_messages, sublet_events, sublet_scan_runs, sublet_groups, sublet_ops_state, sublet_inbox.
- Headless run: ops/run_skill.sh <skill> với SUBLET_RUNNER=codex.

VIỆC ĐẦU TIÊN CỦA BẠN, THEO THỨ TỰ:
1. Chạy skill `onboarding`. Tự kiểm mục nào kiểm được (DB, config, Chrome login, env). Mục cần tôi thì hỏi từng câu, chờ tôi trả lời, ghi sublet_ops_state.
2. Chạy `sublet-groups status` → in danh sách group tier 1–2 chưa joined → nhắc tôi join ≤5/ngày và bật Notifications → All posts.
3. Khi tôi báo đã join ≥1 group: chạy `sublet-scan` 1 lần (≤4 page load) → rồi `intent-analyze` → in bảng: captured / offering / seeking / scam. Đây là bằng chứng pipeline chạy.
4. Khi có ≥3 seeker (tôi điền form hoặc dán text → `seeker-intake`): chạy `sublet-match` cho offering mới nhất → `sublet-draft` → in draft DM để tôi gửi.
5. Từ đó: mỗi lần tôi mở session, chạy `sublet-followup` trước, in hàng đợi sublet_inbox + draft, chờ tôi gửi rồi tôi gõ `sublet-draft sent <id>`.

LUẬT KHI SỬA LOGIC (PLAN.md phần H): rule phân loại ở intent-analyze/SKILL.md (sửa xong chạy `intent-analyze --all`); trọng số match ở scripts/match.py; giọng ở partner-voice/SKILL.md; template ở templates/; ngưỡng volume/giờ ở data/config.yaml. Commit message "rule: <gì> vì <lý do>". Không sửa CLAUDE.md phần "Không bao giờ".

KHÔNG LÀM DÙ TÔI CÓ BẢO: tự gửi DM/comment/post trên Facebook; chạy headless hoặc dán cookie vào máy khác; mở từng group để scan (dùng groups/feed); thu tiền hộ, giữ deposit; ghi listing filled / match signed khi chưa có xác nhận từ subletter hoặc seeker; xếp hạng theo quốc tịch/giới tính.

Khi xong bước 1, in checklist onboarding với ✅/⬜ và 1 dòng "việc tiếp theo của bạn".
```

---

## Ghi chú cho người vận hành

- Prompt trên tự đủ; Codex không cần lịch sử chat này.
- Nếu dùng Claude Code thay vì Codex: mở `claude` trong repo và gõ `/onboarding` — CLAUDE.md và skills tự load, không cần prompt này.
- Thứ chưa quyết, để dữ liệu quyết sau 30 ngày: fee trigger (move_in vs 3 viewings), promise 72h vs 24h, có thêm `outreach-prep` (agent điền sẵn draft vào ô Messenger, bạn Enter) hay không.
