---
name: sublet-draft
description: Soạn (không gửi) DM offer €49/72h cho subletter và tin push cho seekers đã match, từ templates/, lưu sublet_messages status='draft' để người dùng gửi tay. Dùng sau sublet-match hoặc khi gõ /sublet-draft.
---

# sublet-draft

> **Đọc `partner-voice` trước khi soạn bất kỳ tin nào.** Định vị, giọng, giới hạn 90/40 từ, minh bạch ai trả phí — đều ở đó.

Agent soạn. **Người dùng gửi.** Không có ngoại lệ.

## Input
Listing id, hoặc `select * from sublet_v_deal_queue limit 1` (đã lọc deal_score ≥60, scam <60, confidence ≠ low, không agency, không cross-post). Kiểm `sublet_seekers.push_count` hôm nay của mỗi seeker ≤ 3 trước khi draft push; update `push_count`, `last_pushed_at` khi bạn báo sent. Đọc `data/config.yaml` (offer, language_out) và template tương ứng.

## DM offer cho subletter
1. Điền `templates/dm_offer.md` (EN hoặc NL theo config). Viết lại câu đầu theo chi tiết thật của post (khu, ngày, 1 chi tiết đặc trưng) — không copy nguyên template.
2. `offer_link`: nếu config có link intake thì dùng; chưa có → "forward me the replies".
3. Insert `sublet_messages(entity_type='listing', entity_id, direction='out', channel='fb_dm', template='dm_offer', body, status='draft')`.
4. Kiểm tra: hôm nay đã có bao nhiêu `fb_dm` status='sent'? Nếu ≥10 → in cảnh báo "đủ 10 DM hôm nay, để mai".

## Push cho seekers
1. Lấy `sublet_matches` của listing, score ≥ 60, `contact_consent=true`, chưa có message. Tối đa 15.
2. Điền `templates/seeker_push.md` cho từng người. Không địa chỉ chính xác, không tên poster.
3. Insert `sublet_messages(entity_type='match', ..., channel theo contact, template='seeker_push', status='draft')`.

## Output cho người dùng
In từng draft trong code block, kèm: người nhận, kênh, link post (để mở đúng DM). Cuối cùng hỏi: "Gửi xong thì gõ `/sublet-draft sent <message_id...>` để mình đánh dấu." Khi người dùng báo đã gửi: update `status='sent', sent_at=now()`, `sublet_listings.status='contacted', contacted_at`, hoặc `sublet_matches.status='pushed'`.

## Không
- Không nhắc "AI/agent/automation" trong tin.
- Không gửi qua bất kỳ MCP nào.
