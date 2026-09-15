---
name: sublet-scan
description: Quét post sublet mới trên Facebook qua groups/feed + notifications trong Chrome thật của người dùng (chỉ đọc, ≤4 page load), phân loại offering/seeking, chấm scam, lưu Supabase. Dùng khi người dùng gõ /sublet-scan hoặc trong /loop.
---

# sublet-scan

Đọc CLAUDE.md trước. Skill này **chỉ đọc**. Không click Like/Comment/Join/Send.

## Điều kiện chạy
1. Đọc `data/config.yaml`. Nếu giờ hiện tại (Europe/Amsterdam) ngoài `hours` → dừng, ghi 1 dòng "ngoài giờ".
2. Đếm `sublet_scan_runs` 24h qua: nếu tổng `page_loads` ≥ 350 → dừng, báo "gần ngưỡng volume".
3. Random: 1/12 chu kỳ bỏ qua (giả lập nghỉ). Ghi "skip ngẫu nhiên".

## Các bước
1. `insert into sublet_scan_runs(mode) values ('feed') returning id` — nhớ id.
2. Chrome (Claude in Chrome / mcp__claude-in-chrome): `navigate` tới `https://www.facebook.com/groups/feed/`. **1 page load.**
   - Nếu trang là login / checkpoint / captcha / "unusual activity": cập nhật run `stopped_reason`, báo người dùng qua Telegram, **dừng toàn bộ và không chạy lại 24h**.
3. `get_page_text` (max_chars 30000). Scroll xuống tối đa 3 lần (`computer scroll`), mỗi lần chờ 2–5s, đọc thêm. Dừng sớm khi gặp post đã có trong DB (so `source_url`) 3 lần liên tiếp.
4. `navigate` tới `https://www.facebook.com/notifications` — **page load 2** — đọc tiêu đề notification dạng "X posted in <group>". Lấy link post nếu có.
5. Với mỗi post mới (chưa có `source_url` trong `sublet_listings`):
   - Lấy: group name → map sang `group_key` từ `data/groups.yaml` (fuzzy theo tên); poster display name; thời gian tương đối ("2h") → `posted_at`; text; permalink.
   - Phân loại `kind`: offering / seeking / other, dùng `keywords` trong groups.yaml + đọc hiểu. "Looking for" = seeking. "Available / my room / subletting" = offering.
   - Chỉ với offering: extract area, room_type, rent_eur, deposit_eur, bills_included, available_from/to (ISO date; năm hiện tại nếu thiếu), min_term_days, furnished, registration_allowed, max_people. Không đoán giá trị không có trong text → để null.
   - `scam_score` 0–100 và `scam_flags` theo `config.scam.flags`. ≥60 = nghi ngờ.
   - Insert vào `sublet_listings` (source='fb_feed' hoặc 'fb_notif', source_url, raw_text = text đầy đủ). Insert `sublet_events(entity_type='listing', event='seen', source_url)`.
   - Với seeking: insert vào `sublet_seekers(source='fb_seeking', contact_consent=false, ...)` chỉ khi có ngày + ngân sách rõ. Không lưu contact.
6. Nếu một offering **thiếu ngày hoặc giá** và có vẻ thật: được phép mở permalink để đọc full post — **page load 3–4, tối đa 2 post/chu kỳ**, và ghi vào `mode='group_page'` run riêng. Không mở comment.
7. Cập nhật run: `finished_at`, `page_loads`, `posts_seen`, `new_listings`.
8. Với mỗi offering mới có scam_score < 60: chạy ngay `/sublet-match` cho listing đó, rồi `/sublet-draft` nếu có ≥3 match score ≥ 60.
9. In tóm tắt 3 dòng: mới / nghi scam / đã match. Nếu có listing mới đáng DM → gửi Telegram (chat_id trong config) 1 tin: "🆕 {n} sublet mới. Top: {area} €{rent} {from}→{to} — draft DM sẵn, /sublet-draft để xem."

## Không làm
- Không mở từng group trong groups.yaml. Feed đã gom.
- Không đọc profile poster. Không lưu ảnh.
- Không chạy khi máy vừa wake < 2 phút (kiểm tra bằng `uptime`/thời gian từ run trước).
