---
name: sublet-scan
description: CAPTURE-ONLY — quét post mới trên Facebook qua groups/feed + notifications trong Chrome thật (chỉ đọc, ≤4 page load), lưu thô (post, link, text, thời gian, group) vào sublet_listings với kind=null, dừng ở cursor của lần trước để không lặp, rồi gọi intent-analyze. Dùng với /sublet-scan hoặc trong /loop.
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
3. `get_page_text` (max_chars 30000). Scroll xuống tối đa 3 lần (`computer scroll`), mỗi lần chờ 2–5s. **Dừng sớm** khi: gặp `cursor` của run trước (`select cursor from sublet_scan_runs where mode='feed' and cursor is not null order by id desc limit 1`), hoặc 3 permalink liên tiếp đã có trong `sublet_listings.source_url`.
4. `navigate` tới `https://www.facebook.com/notifications` — **page load 2** — đọc "X posted in <group>", lấy link post nếu có. Bỏ qua notification cũ hơn `last_post_seen_at` của group đó (trong `sublet_groups`).
5. Với mỗi post chưa có `source_url` trong DB: **chỉ capture, không phân loại**:
   - `source` ('fb_feed' | 'fb_notif'), `source_url` (permalink, bỏ query string), `group_key` (map tên group → `sublet_groups.key`, fuzzy; không map được → key = slug tên, insert group mới tier=null), `poster_name` (display name như hiện), `posted_at` ("2h" → now−2h), `raw_text` (toàn bộ text post, không cắt), `kind = null`.
   - Insert `sublet_listings`; `sublet_events(event='captured', source_url)`.
   - Update `sublet_groups.last_post_seen_at` = max(posted_at).
   - Permalink đầu tiên đọc được ở đầu feed → ghi vào `sublet_scan_runs.cursor` của run này.
6. Nếu một post có `notes='needs_full_read'` (do intent-analyze đánh) : được phép mở permalink để đọc full post — **page load 3–4, tối đa 2 post/chu kỳ**, và ghi vào `mode='group_page'` run riêng. Không mở comment.
7. Cập nhật run: `finished_at`, `page_loads`, `posts_seen`, `new_listings`.
8. Nếu `new_listings > 0`: gọi `/intent-analyze` (phân loại + extract + scam + tự match). Scan không tự phân loại.
9. In tóm tắt 3 dòng: captured / (từ intent-analyze) offering-seeking-scam / đã match. Nếu có listing mới đáng DM → gửi Telegram (chat_id trong config) 1 tin: "🆕 {n} sublet mới. Top: {area} €{rent} {from}→{to} — draft DM sẵn, /sublet-draft để xem."

## Không làm
- Không mở từng group trong groups.yaml. Feed đã gom.
- Không đọc profile poster. Không lưu ảnh.
- Không chạy khi máy vừa wake < 2 phút (kiểm tra bằng `uptime`/thời gian từ run trước).
