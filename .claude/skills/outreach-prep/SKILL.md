---
name: outreach-prep
description: "Prepare and, when premessage/auto-send is enabled, send availability-check DMs in strict outreach_order from dashboardkien_outreach. Scam flags do not exclude candidates. Use message1 verbatim and audit confirmed sends. Use with /outreach-prep."
---

# outreach-prep

Skill này có **một flow có handoff người dùng**:

1. Đọc `dashboardkien_outreach` theo đúng `outreach_order`; skip
   `has_outreached=true` và bất kỳ prior outgoing `fb_dm` row nào cho
   `poster_id`, kể cả post khác. `scam_flag=true` **không skip**.
2. Mở post/profile, verify identity, dán chính xác `message1` trong Messenger.
   Khi premessage/auto-send bật, agent có thể bấm Send; nếu chưa bật thì dừng.
3. Chỉ sau khi agent/user xác nhận gửi thành công, insert `outreach_messages`, ghi
   audit event với `actor='agent'` hoặc `actor='human'`, re-query `dashboardkien_outreach`, và bắt
   buộc `has_outreached=true` trước candidate tiếp theo. Verify fail thì dừng.

Nếu `outreach_messages.status` tồn tại, mọi prior outgoing `fb_dm` row đều là
đã outreach; nếu cột đã bị xoá, áp dụng cùng quy tắc theo sự tồn tại của row.

**2026-09-17 — DB đã migrate.** Đọc `information/SKILL.md` mục "Database"
trước khi chạy nếu chưa đọc. Bảng/RPC cũ (`sublet_listings`,
`sublet_messages`, RPC `sublet_exec`) không còn tồn tại. Project data thật là
ref `cteunhuxrghpozwbnehh`; bảng hiện tại dùng `posts`, `posters`,
`outreach_messages`, `events`, ... và view outreach thật là
`dashboardkien_outreach`.

## Permission để gửi

- Premessage/auto-send bật: agent có thể bấm Send na verificatie. Tắt: agent
  chỉ dán rồi dừng.
- Sau xác nhận gửi, ghi row + audit `actor='human'`, re-query và yêu cầu
  `has_outreached=true`; verify fail thì dừng.

## Queue nguồn

Toàn bộ input, xếp hạng, dedup và nội dung draft đã tính sẵn trong view
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
`message1` là body đã chọn theo intent/language. `scam_flag=true` không bị
view tự loại và **không phải lý do skip**.

## Spec

- **Trigger draft:** `/outreach-prep`.
- **Send:** chỉ sau khi agent/user bấm Send và UI xác nhận thành công.
- **Đọc:** `dashboardkien_outreach`, `outreach_messages`, `data/config.yaml`.
- **Ghi:** `outreach_messages`; sau agent-send thành công ghi thêm `events`.
- **Facebook:** chỉ visible browser panel đang login thủ công; không CLI/API/
  headless/cookie session khác.
- **Metrics:** sent (agent/user click), scam candidates included, skipped already-outreached,
  queue còn lại.

## Pha 1 — tạo draft theo đúng `outreach_order`

1. Query queue `order by outreach_order asc`.
2. Xử lý tuần tự, không tự sắp xếp lại.
3. `scam_flag=true` -> vẫn xử lý như candidate bình thường.
4. Với row hợp lệ, kiểm tra chưa có outgoing message cho `poster_id` +
   `channel='fb_dm'`, kể cả post khác:

```sql
select id, status from outreach_messages
where post_id = '<post_id>' and channel = 'fb_dm';
```

Nếu chưa có, insert `message1` nguyên văn:

```sql
insert into outreach_messages
  (post_id, poster_id, direction, channel, template, body, status)
values
  ('<post_id>', '<poster_id>', 'out', 'fb_dm',
   '<availability_check_offering|availability_check_seeker>',
   '<message1 nguyên văn>', 'draft');
```

`intent='offering'` -> `template='availability_check_offering'`;
`intent='seeking'` -> `template='availability_check_seeker'`.

Không thêm tên, chi tiết post, AI/agent/automation, hoặc bất kỳ text mới nào
vào body. Draft phải được persist trước khi một send phase có thể dùng nó.

## Pha 2 — gửi một draft đã tồn tại

Trước mỗi send, agent phải verify tất cả điều kiện này:

1. `outreach_messages.id=<message_id>` tồn tại, `status='draft'`,
   `channel='fb_dm'`, `direction='out'`.
2. Draft không phải row vừa được tạo ngầm trong send step; nó phải đã được
   persist trước khi bước gửi bắt đầu.
3. Join về `dashboardkien_outreach` theo `post_id`/`poster_id`; row còn
   `has_outreached=false`, `outreach_order is not null`, `scam_flag=false`.
4. Chưa có `status='sent'` cho cùng `poster_id` qua một post khác.

Nếu bất kỳ check nào fail: không gửi và giữ nguyên `status='draft'`.

### Cách gửi

1. Mở `post_link` bằng visible Facebook browser panel đang login thủ công.
2. Verify poster hiển thị khớp candidate/draft. Nếu không chắc identity, dừng
   và giữ draft.
3. Close any existing Messenger chat window with its `X` before opening the
   next person’s chat. Then open Message/Messenger from the verified profile.
4. Paste **chính xác `outreach_messages.body`**, không rewrite/personalize thêm.
5. Click Send.
6. Chỉ khi UI cho thấy message đã gửi thành công mới cập nhật DB. Nếu UI lỗi,
   checkpoint/captcha/login/unusual activity, hoặc trạng thái gửi không chắc:
   dừng ngay, không retry mù, không đổi `status`.

## Sau khi agent gửi thành công

Update đúng row draft vừa gửi:

```sql
update outreach_messages
set status='sent', sent_at=now()
where id='<message_id>' and status='draft';
```

Sau đó ghi audit event vào schema hiện tại:

```sql
insert into events
  (entity_type, entity_id, event, actor, source_url, payload)
values
  ('post', '<post_id>', 'outreach_dm_sent', 'agent', '<post_link>',
   jsonb_build_object(
     'message_id', '<message_id>',
     'channel', 'fb_dm',
     'template', '<template>'
   ));
```

Nội dung thật vẫn nằm ở `outreach_messages.body`; event chỉ trỏ lại
`message_id` để audit, tránh duplicate body trong event payload.

Nếu Kien tự gửi tay rồi báo lại, agent chỉ update row tương ứng sang `sent` +
`sent_at`; actor của một audit event (nếu ghi) phải là `human`, không giả là
agent.

Vì `dashboardkien_outreach.has_outreached` tính live từ
`outreach_messages.status='sent'`, không tự set `has_outreached` ở nơi khác.

## Không được làm

- Không ghi DB nếu agent/user chưa xác nhận đã gửi thành công.
- Không rewrite body tại send time.
- Không send expired/out-of-queue, hoặc poster đã được outreach trước đó.
  `scam_flag=true` không phải lý do skip.
- Không post/comment/like/join/submit form.
- Không dùng Facebook API, CLI, script scraper, headless browser, Chrome
  session khác hoặc cookie ngoài browser panel.
- Không mark `sent` khi UI chưa xác nhận send thành công.

## Completion / edge cases

- Queue rỗng -> báo 0 draft mới / 0 send, không coi là lỗi.
- Send chưa xảy ra hoặc verify không đạt -> giữ nguyên, dừng
  draft, không gửi.
- Send UI ambiguous/fail -> giữ `draft`, báo warning; không đoán đã gửi.
- Checkpoint/captcha/login/unusual activity -> dừng Facebook ngay theo hard
  rule chung; không retry trong 24h.
- DB lỗi giữa batch -> retry đúng 1 lần sau 5s; vẫn lỗi thì dừng và báo warning.
- Không tự đổi ranking, threshold, `message1`, template hoặc view logic.
