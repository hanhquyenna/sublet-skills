---
name: outreach-prep
description: "Send availability-check DMs directly, in strict outreach_order from dashboardkien_outreach, to individual posters who aren't scam-flagged and haven't already been outreached. Use message1 verbatim, log every send immediately after Facebook confirms it, and stop on any uncertain state. Use with /outreach-prep."
---

# outreach-prep

**2026-09-18 — bỏ mô hình draft/send 2 pha.** Không còn cờ `auto_dm`, không
còn `outreach_messages.status`. Một pha duy nhất:

1. Đọc `dashboardkien_outreach` theo đúng `outreach_order`, không tự sắp xếp
   lại, không tự viết lại `message1`.
2. Với mỗi người: skip nếu `scam_flag=true`, hoặc `has_outreached=true`
   (đã có ai gửi cho poster này rồi, ở bất kỳ post nào — không chỉ post
   hiện tại).
3. Với người còn hợp lệ: mở `post_link` bằng visible Facebook browser panel
   đang login thủ công, verify đúng người (không chắc identity → dừng,
   không gửi), mở Messenger, paste **chính xác** `message1` — không
   rewrite/personalize thêm, click Send.
4. **Chỉ sau khi UI xác nhận gửi thành công** mới insert 1 row vào
   `outreach_messages` (`post_id`, `poster_id`, `direction='out'`,
   `channel='fb_dm'`, `template`, `body=message1`, `sent_at=now()`) và ghi
   audit `events`. Row này vừa là log gửi vừa là nguồn cho
   `has_outreached` — cột này tính live: **tồn tại bất kỳ row nào** cho
   `poster_id` đó trong `outreach_messages` (không cần lọc theo `status`
   nữa vì cột đó không còn tồn tại — một row tồn tại nghĩa là đã gửi
   thật, không có trạng thái trung gian).
5. Nếu UI lỗi, checkpoint/captcha/login/unusual activity, hoặc không chắc
   đã gửi thành công: dừng ngay, **không insert gì cả**, không đoán, không
   retry mù.

**2026-09-17 — DB đã migrate.** Đọc `information/SKILL.md` mục "Database"
trước khi chạy nếu chưa đọc. Project data thật là ref `cteunhuxrghpozwbnehh`;
bảng hiện tại dùng `posts`, `posters`, `outreach_messages`, `events`, ... và
view outreach thật là `dashboardkien_outreach`.

## Không cần hỏi trước khi gửi

Agent tự xử lý toàn bộ queue theo `outreach_order` trong cùng run, không cần
hỏi lại từng người và không cần Kien yêu cầu rõ từng lần gửi. Agent không
bao giờ post/comment/like/join group/submit form trên Facebook. DM trực
tiếp `message1` cho poster hợp lệ là ngoại lệ ghi duy nhất.

## Queue nguồn

Toàn bộ input, xếp hạng và dedup đã tính sẵn trong view
`dashboardkien_outreach`. Không tự tính lại điều kiện:

```sql
select poster_id, poster_name, post_id, intent, post_link, message1,
       scam_flag, outreach_order, has_outreached
from dashboardkien_outreach
where outreach_order is not null
  and not has_outreached
order by outreach_order asc;
```

`outreach_order` có thể có khoảng trống; chỉ cần giữ đúng thứ tự tăng dần.
`message1` là body đã chọn theo intent/language — copy nguyên văn. `scam_flag`
đã bị lọc ra khỏi kết quả (không có trong queue này vì `where not
has_outreached` không loại scam — vẫn phải tự kiểm `scam_flag=false` trước
khi gửi bất kỳ ai, không dựa vào view tự loại hộ):

```sql
select poster_id, poster_name, post_id, message1, scam_flag
from dashboardkien_outreach
where outreach_order is not null and not has_outreached and scam_flag = true;
-- liệt kê riêng, báo tên, không gửi cho những người này
```

## Spec

- **Trigger:** `/outreach-prep`.
- **Đọc:** `dashboardkien_outreach`, `outreach_messages`, `data/config.yaml`.
- **Ghi:** `outreach_messages` — 1 **insert** cho mỗi lần gửi thành công,
  không update, không có trạng thái trung gian; sau đó ghi thêm `events`.
- **Facebook:** chỉ visible browser panel đang login thủ công; không CLI/API/
  headless/cookie session khác.
- **Metrics:** sent, skipped scam, skipped already-outreached, queue còn lại.

## Cách gửi

1. Mở `post_link` bằng visible Facebook browser panel đang login thủ công.
2. Verify poster hiển thị khớp candidate trong queue. Nếu không chắc
   identity, dừng, không gửi.
3. Mở Message/Messenger từ UI Facebook.
4. Paste **chính xác `message1`**, không rewrite/personalize thêm.
5. Click Send.
6. Chỉ khi UI cho thấy message đã gửi thành công mới ghi DB. Nếu UI lỗi,
   checkpoint/captcha/login/unusual activity, hoặc trạng thái gửi không
   chắc: dừng ngay, không retry mù, **không insert gì**.

## Sau khi gửi thành công

```sql
insert into outreach_messages
  (post_id, poster_id, direction, channel, template, body, sent_at)
values
  ('<post_id>', '<poster_id>', 'out', 'fb_dm',
   '<availability_check_offering|availability_check_seeker>',
   '<message1 nguyên văn>', now());
```

`intent='offering'` -> `template='availability_check_offering'`;
`intent='seeking'` -> `template='availability_check_seeker'`.

Sau đó ghi audit event:

```sql
insert into events
  (entity_type, entity_id, event, actor, source_url, payload)
values
  ('post', '<post_id>', 'outreach_dm_sent', 'agent', '<post_link>',
   jsonb_build_object('channel', 'fb_dm', 'template', '<template>'));
```

Nếu Kien tự gửi tay rồi báo lại, agent chỉ insert row tương ứng (không phải
`agent` mà là `human` cho actor của audit event nếu ghi).

Vì `dashboardkien_outreach.has_outreached` tính live từ việc tồn tại bất kỳ
row nào trong `outreach_messages` cho `poster_id` đó, không cần và không tự
set `has_outreached` ở nơi khác — nó tự đúng ngay khi row trên được insert.

## Không được làm

- Không gửi cho poster có `scam_flag=true` hoặc `has_outreached=true`.
- Không rewrite/personalize `message1`.
- Không insert vào `outreach_messages` trước khi Facebook xác nhận gửi
  thành công — không có draft để "giữ lại" nếu gửi lỗi; nếu gửi lỗi thì
  đơn giản là không insert gì.
- Không post/comment/like/join/submit form.
- Không dùng Facebook API, CLI, script scraper, headless browser, Chrome
  session khác hoặc cookie ngoài browser panel.
- Không mark đã gửi khi UI chưa xác nhận send thành công.
- Không vượt **10 agent-sent DM/24h**.

## Completion / edge cases

- Queue rỗng -> báo 0 sent, không coi là lỗi.
- Send UI ambiguous/fail -> không insert gì, báo warning; không đoán đã gửi.
- Checkpoint/captcha/login/unusual activity -> dừng Facebook ngay theo hard
  rule chung; không retry trong 24h.
- DB lỗi giữa batch -> retry đúng 1 lần sau 5s; vẫn lỗi thì dừng và báo
  warning.
- Đã đạt 10 agent-sent DM/24h -> dừng gửi thêm, báo còn lại bao nhiêu trong
  queue.
- Không tự đổi ranking, threshold, `message1`, template hoặc view logic.
