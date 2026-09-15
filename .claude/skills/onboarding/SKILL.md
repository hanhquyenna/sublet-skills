---
name: onboarding
description: Checklist khởi động cho người vận hành (bạn) — kiểm tra từng điều kiện (Chrome login, group joined, notification, Gmail IMAP, Tally, Supabase, cron) và ghi tiến độ vào sublet_ops_state. Dùng với /onboarding lần đầu và mỗi khi đổi máy. Agent kiểm tra được gì thì tự kiểm, còn lại hỏi bạn từng câu.
---

# onboarding

Mục tiêu: sau khi chạy xong, hệ thống chạy tự động mà bạn chỉ còn 2 việc: **tap gửi** và **báo kết quả**.

## Cách chạy
`/onboarding` → agent đi qua checklist, mỗi mục: tự kiểm nếu có thể, nếu không thì hỏi bạn "xong chưa? (y/n)". Ghi vào `sublet_ops_state(key, value, updated_at)`. Chạy lại bất kỳ lúc nào chỉ hỏi mục chưa xong.

## Checklist (theo thứ tự)

### Ngày 0 — nền
0. `env_file` — tồn tại `~/.sublet-skills.env`. Chưa có → bảo bạn chạy `zsh ops/setup_env.sh` (hỏi 5 thứ, 3 phút) rồi chạy lại /onboarding. **Codex bắt buộc** (cần SUPABASE_DB_URL); Claude Code có Supabase MCP nên chỉ cần IMAP.
1. `supabase_ok` — `select count(*) from sublet_groups` chạy được: Claude Code → Supabase MCP `execute_sql`; Codex → `python3 scripts/db.py "select count(*) from sublet_groups"` (cần `pip3 install psycopg2-binary` + env). Lỗi kết nối → dừng onboarding ở đây, in đúng lỗi, không tick mục nào tiếp.
2. `config_filled` — `data/config.yaml` có `email.imap_user`, `offer.your_first_name`. Agent đọc file kiểm tra.
3. `inbox_ok` — `insert into sublet_inbox(level,title) values ('info','onboarding started')` chạy được.
4. `chrome_fb_login` — Chrome thật đã login Facebook. Agent `navigate` `facebook.com/groups/feed` (1 load) và xác nhận thấy feed, không thấy login. Thấy trang login → ghi `no`, **không thử lại, không tự login**, bảo bạn login tay rồi chạy lại. (Codex: profile riêng cổng 9222, lệnh trong AGENTS.md.)
5. `env_imap` — `source ~/.sublet-skills.env; echo $SUBLET_IMAP_USER` không rỗng. Nếu rỗng: `zsh ops/setup_env.sh`.

### Ngày 0–7 — group (tay, chậm)
6. `groups_join_plan` — `/sublet-groups status` → in danh sách tier 1–2 chưa `joined`. Bạn join **≤5/ngày**. Mỗi ngày /onboarding hỏi lại, bạn tick.
7. `notif_all_posts` — với mỗi group đã joined: Group → Notifications → All posts. Bạn tick từng group; agent update `sublet_groups.notif_all_posts`.
8. `email_test` — `python3 scripts/gmail_pull.py --since-days 2` trả về ≥1 email facebookmail. Nếu 0: chờ 1 ngày sau khi bật notification.

### Ngày 1 — demand
9. `tally_form` — form seeker tạo xong, link điền vào `config.seeker_form.url`. Cột theo README.
10. `seeker_seed` — bạn tự điền form với 3 người quen đang tìm phòng (hoặc chính bạn). `/seeker-intake` chạy → ≥3 seekers active.
11. `whatsapp_channel` — (tuỳ chọn) tạo WhatsApp Community/Telegram channel "Verified sublets Amsterdam", link vào config.

### Ngày 1 — automation
12. `cron_installed` — `ops/install_cron.sh` chạy xong; `launchctl list | grep sublet` có các job. Agent kiểm.
13. `first_scan` — `/sublet-scan` chạy tay 1 lần thành công: có run trong `sublet_scan_runs`, ≥1 listing captured (nếu feed có).
14. `first_analyze` — `/intent-analyze` → ≥1 offering có kind.
15. `voice_reviewed` — bạn đã đọc `partner-voice/SKILL.md` và sửa 2 dòng định vị theo giọng mình. Bạn tick.

### Ngày 2 — deal đầu
16. `first_dm_sent` — có ≥1 `sublet_messages` template='dm_offer' status='sent'.
17. `first_ok` — ≥1 listing status='accepted'.

## Output
Bảng checklist với ✅/⬜ và "việc tiếp theo của bạn" (1 dòng). Khi tất cả ✅: in "Onboarding xong. Từ giờ: sáng /sublet-followup, tối /sublet-report, còn lại tự chạy."
