---
name: outreach-prep
description: "Create availability-check DM drafts in strict outreach_order from dashboardkien_outreach, and send only pre-existing approved drafts through the visible Facebook browser when explicitly requested or when outreach.auto_dm=true. Use message bodies verbatim and audit every send. Use with /outreach-prep."
---

# outreach-prep

Skill này có **2 pha tách biệt**:

1. **Draft:** đọc `dashboardkien_outreach`, copy `message1` nguyên văn vào
   `outreach_messages` với `status='draft'`.
2. **Send:** agent được phép gửi DM **chỉ khi row draft đã tồn tại từ trước**.
   Agent lấy `outreach_messages.body` nguyên văn, gửi qua visible Facebook
   browser panel, rồi chỉ sau khi UI xác nhận gửi thành công mới đổi đúng row đó
   sang `status='sent'` và ghi audit event.

Draft tồn tại là điều kiện bắt buộc trước khi agent được gửi. Không được tạo câu
mới rồi gửi ngay trong cùng bước send, không được sửa body lúc gửi, và không
được gửi một message chưa có row `status='draft'` trong DB.

**2026-09-17 — DB đã migrate.** Đọc `information/SKILL.md` mục "Database"
trước khi chạy nếu chưa đọc. Bảng/RPC cũ (`sublet_listings`,
`sublet_messages`, RPC `sublet_exec`) không còn tồn tại. Project data thật là
ref `cteunhuxrghpozwbnehh`; bảng hiện tại dùng `posts`, `posters`,
`outreach_messages`, `events`, ... và view outreach thật là
`dashboardkien_outreach`.

## Permission để gửi

- `outreach.auto_dm: false` (mặc định): `/outreach-prep` chỉ tạo draft. Agent
  chỉ được gửi khi Kien yêu cầu rõ một send action, ví dụ
  `/outreach-prep send <message_id>` hoặc một câu tương đương chỉ rõ draft cần
  gửi.
- `outreach.auto_dm: true`: agent được xử lý các **draft đã tồn tại** theo
  `outreach_order` mà không phải hỏi lại từng message. Việc bật cờ này không
  cho phép bỏ qua các check bên dưới và không cho phép draft+send trong cùng
  một bước không có row draft trung gian.
- Dù cờ nào, agent không bao giờ post/comment/like/join group/submit form trên
  Facebook. DM từ draft là ngoại lệ ghi duy nhất.

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
`message1` là body draft đã chọn theo intent/language. `scam_flag=true` không bị
view tự loại nhưng agent phải skip: không draft, không send, và báo riêng.

## Spec

- **Trigger draft:** `/outreach-prep`.
- **Trigger send khi `auto_dm=false`:** `/outreach-prep send <message_id>` hoặc
  yêu cầu rõ tương đương.
- **Trigger send khi `auto_dm=true`:** có thể gửi các draft ready theo thứ tự
  mà không hỏi lại từng tin trong một run outreach đã được yêu cầu.
- **Đọc:** `dashboardkien_outreach`, `outreach_messages`, `data/config.yaml`.
- **Ghi:** `outreach_messages`; sau agent-send thành công ghi thêm `events`.
- **Facebook:** chỉ visible browser panel đang login thủ công; không CLI/API/
  headless/cookie session khác.
- **Metrics:** draft mới, draft chờ, sent, agent-send audit, skipped scam,
  queue còn lại.

## Pha 1 — tạo draft theo đúng `outreach_order`

1. Query queue `order by outreach_order asc`.
2. Xử lý tuần tự, không tự sắp xếp lại.
3. `scam_flag=true` -> skip và báo tên, không insert draft.
4. Với row hợp lệ, kiểm tra chưa có message cho `post_id` + `channel='fb_dm'`:

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
5. Chưa đạt giới hạn **10 agent-sent DM trong 24h**. Nếu đã đạt, giữ draft và
   dừng gửi thêm.

Nếu bất kỳ check nào fail: không gửi và giữ nguyên `status='draft'`.

### Cách gửi

1. Mở `post_link` bằng visible Facebook browser panel đang login thủ công.
2. Verify poster hiển thị khớp candidate/draft. Nếu không chắc identity, dừng
   và giữ draft.
3. Mở Message/Messenger từ UI Facebook.
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

- Không gửi nếu không có pre-existing `status='draft'` row.
- Không rewrite body tại send time.
- Không send row `scam_flag=true`, expired/out-of-queue, hoặc poster đã được
  outreach trước đó.
- Không post/comment/like/join/submit form.
- Không dùng Facebook API, CLI, script scraper, headless browser, Chrome
  session khác hoặc cookie ngoài browser panel.
- Không mark `sent` khi UI chưa xác nhận send thành công.
- Không vượt 10 agent-sent DM/24h.

## Completion / edge cases

- Queue rỗng -> báo 0 draft mới / 0 send, không coi là lỗi.
- Draft tồn tại nhưng `auto_dm=false` và chưa có explicit send request -> giữ
  draft, không gửi.
- Send UI ambiguous/fail -> giữ `draft`, báo warning; không đoán đã gửi.
- Checkpoint/captcha/login/unusual activity -> dừng Facebook ngay theo hard
  rule chung; không retry trong 24h.
- DB lỗi giữa batch -> retry đúng 1 lần sau 5s; vẫn lỗi thì dừng và báo warning.
- Không tự đổi ranking, threshold, `message1`, template hoặc view logic.
