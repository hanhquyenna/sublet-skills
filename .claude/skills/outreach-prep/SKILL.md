---
name: outreach-prep
description: "Prepare availability-check DMs directly, in strict outreach_order from dashboardkien_outreach, to individual posters who aren't scam-flagged and haven't already been outreached. Agent opens the post, verifies identity, opens Messenger, and pastes message1 verbatim — then stops. Kien clicks Send himself; the agent never does. Only after Kien confirms the send does the agent log it. Use with /outreach-prep."
---

# outreach-prep

**2026-09-18 — agent prepares, Kien sends.** The agent never clicks Send.
It does everything up to having the message sitting in the Messenger box,
then stops and hands off. No `auto_dm` flag, no "agent sends autonomously"
mode of any kind — that idea is retired. This is the definitive flow.

1. Đọc `dashboardkien_outreach` theo đúng `outreach_order`, không tự sắp xếp
   lại, không tự viết lại `message1`.
2. Với mỗi người: skip nếu `scam_flag=true`, hoặc `has_outreached=true`,
   **hoặc đã tồn tại bất kỳ outgoing Facebook DM row nào trong
   `outreach_messages` cho cùng `poster_id`**, kể cả row thuộc post khác.
   Nếu schema hiện tại còn cột `status`, mọi trạng thái đều tính là đã có
   outreach row (ví dụ `draft` hoặc `sent`) — không chuẩn bị DM thêm.
3. Với người còn hợp lệ: mở `post_link` bằng visible Facebook browser panel
   đang login thủ công, verify đúng người (không chắc identity → dừng, báo,
   không làm gì thêm với candidate này). Mở Messenger, paste **chính xác**
   `message1` — không rewrite/personalize thêm.
4. **Dừng ngay tại đây.** Báo cho Kien: "Ready to send to `<poster_name>` —
   message is pasted, click Send when ready." Agent không click Send,
   không giả định Kien sẽ click, không tự động chuyển sang bước tiếp theo.
5. Chờ Kien xác nhận đã click Send (Kien nói, hoặc agent tự quan sát UI đổi
   trạng thái sau khi Kien click — nhưng hành động click luôn là của Kien).
6. **Chỉ sau khi Kien xác nhận đã gửi và UI cho thấy gửi thành công** mới
   insert 1 row vào `outreach_messages` (`post_id`, `poster_id`,
   `direction='out'`, `channel='fb_dm'`, `template`, `body=message1`,
   `sent_at=now()`) và ghi audit `events` với `actor='human'` (Kien là
   người thực hiện hành động gửi, agent chỉ chuẩn bị).
7. **Ngay sau khi ghi DB cho một send, query lại `dashboardkien_outreach`
   cho `poster_id` đó và bắt buộc verify `has_outreached=true` trước khi
   chuyển sang người tiếp theo.**
8. Nếu Kien không click Send (đổi ý, tạm dừng, hoặc không phản hồi), hoặc UI
   lỗi, checkpoint/captcha/login/unusual activity, hoặc không chắc đã gửi
   thành công: dừng ngay, **không insert gì cả**, không đoán, không retry
   mù, không tự click Send thay Kien trong bất kỳ trường hợp nào.

**2026-09-17 — DB đã migrate.** Đọc `information/SKILL.md` mục "Database"
trước khi chạy nếu chưa đọc. Project data thật là ref `cteunhuxrghpozwbnehh`;
bảng hiện tại dùng `posts`, `posters`, `outreach_messages`, `events`, ... và
view outreach thật là `dashboardkien_outreach`.

## Vì sao Kien click Send, không phải agent

Đây không phải một cờ có thể bật/tắt qua config — nó là quy tắc cứng của
skill này. Agent tự động hoá toàn bộ phần tốn thời gian (đọc queue, mở đúng
post, verify đúng người, mở Messenger, gõ đúng nội dung) nhưng hành động gửi
thật cho người lạ trên Facebook luôn cần một người bấm nút. Không có mode
nào trong skill này cho agent tự click Send, kể cả khi được yêu cầu — nếu có
yêu cầu như vậy, agent phải từ chối và trỏ lại mục này.

Agent không bao giờ post/comment/like/join group/submit form trên Facebook.
Paste-và-chờ-Kien-click là ngoại lệ ghi duy nhất, và ngay cả ngoại lệ đó vẫn
cần Kien tự bấm.

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
không bị lọc ra khỏi kết quả trên (`where not has_outreached` không loại
scam) — vẫn phải tự kiểm `scam_flag=false` trước khi chuẩn bị DM cho bất kỳ
ai, không dựa vào view tự loại hộ:

```sql
select poster_id, poster_name, post_id, message1, scam_flag
from dashboardkien_outreach
where outreach_order is not null and not has_outreached and scam_flag = true;
-- liệt kê riêng, báo tên, không chuẩn bị DM cho những người này
```

Trước khi chuẩn bị DM cho mỗi candidate còn lại, phải kiểm tra thêm trực
tiếp `outreach_messages` theo `poster_id`:

```sql
select id, post_id, poster_id, direction, channel, status, sent_at
from outreach_messages
where poster_id = '<poster_id>'
  and direction = 'out'
  and channel = 'fb_dm'
limit 1;
```

Nếu query trả về **bất kỳ row nào** thì skip candidate đó, không phân biệt
row thuộc post hiện tại hay post khác. Nếu schema không còn cột `status`, bỏ
cột đó khỏi `select`; quy tắc skip vẫn giữ nguyên theo sự tồn tại của row.

## Spec

- **Trigger:** `/outreach-prep`.
- **Đọc:** `dashboardkien_outreach`, `outreach_messages`, `data/config.yaml`.
- **Ghi:** `outreach_messages` — 1 **insert** cho mỗi lần Kien gửi thành
  công (không phải agent), sau đó ghi thêm `events` (`actor='human'`), rồi
  verify `dashboardkien_outreach.has_outreached` đã thành `true` cho
  `poster_id` vừa gửi trước khi tiếp tục candidate kế tiếp.
- **Facebook:** chỉ visible browser panel đang login thủ công; không CLI/API/
  headless/cookie session khác.
- **Metrics:** sent (do Kien click), skipped scam, skipped already-outreached,
  queue còn lại, waiting-for-Kien (candidate đã paste, chưa được Kien click).

## Cách chuẩn bị một DM

1. Mở `post_link` bằng visible Facebook browser panel đang login thủ công.
2. Verify poster hiển thị khớp candidate trong queue. Nếu không chắc
   identity, dừng, báo, không làm gì thêm.
3. Mở Message/Messenger từ UI Facebook.
4. Paste **chính xác `message1`**, không rewrite/personalize thêm.
5. **Dừng.** Báo Kien message đã sẵn sàng, chờ Kien click Send.
6. Sau khi Kien click và UI xác nhận gửi thành công, ghi DB (bước dưới).
   Nếu Kien không click, đổi ý, hoặc UI không chắc: không ghi gì, báo trạng
   thái, dừng ở candidate này.

## Sau khi Kien gửi thành công

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

Sau đó ghi audit event, `actor='human'` vì Kien là người thực hiện hành động
gửi:

```sql
insert into events
  (entity_type, entity_id, event, actor, source_url, payload)
values
  ('post', '<post_id>', 'outreach_dm_sent', 'human', '<post_link>',
   jsonb_build_object('channel', 'fb_dm', 'template', '<template>'));
```

Sau mỗi send đã được xác nhận, phải verify ngay:

```sql
select poster_id, has_outreached
from dashboardkien_outreach
where poster_id = '<poster_id>';
```

Kết quả bắt buộc phải là `has_outreached=true` trước khi sang candidate kế
tiếp. Nếu view tính live từ `outreach_messages`, không tự update trực tiếp
view này; insert row gửi thành công là nguồn dữ liệu làm cờ chuyển sang
`true`, còn query trên là bước xác nhận bắt buộc.

## Không được làm

- Không tự click Send, dưới bất kỳ lý do hay yêu cầu nào — đây là quy tắc
  cứng của skill, không phải cờ có thể bật lại.
- Không chuẩn bị DM cho poster có `scam_flag=true` hoặc `has_outreached=true`
  hoặc đã có bất kỳ row `outreach_messages` nào (ở post khác).
- Không rewrite/personalize `message1`.
- Không insert vào `outreach_messages` trước khi Kien xác nhận đã gửi và UI
  xác nhận thành công.
- Không post/comment/like/join/submit form.
- Không dùng Facebook API, CLI, script scraper, headless browser, Chrome
  session khác hoặc cookie ngoài browser panel.
- Không mark đã gửi khi UI chưa xác nhận send thành công hoặc Kien chưa
  click.
- Không vượt **10 outreach DM/24h** (không phân biệt ai click, vẫn là giới
  hạn chung).

## Completion / edge cases

- Queue rỗng -> báo 0 sent, không coi là lỗi.
- Kien không click Send trong candidate hiện tại (bận, đổi ý, tạm dừng) ->
  không insert gì, báo trạng thái "waiting for Kien" và dừng ở đó; không tự
  chuyển sang người tiếp theo mà không có quyết định rõ từ Kien.
- Send UI ambiguous/fail sau khi Kien đã click -> không insert gì, báo
  warning; không đoán đã gửi.
- Checkpoint/captcha/login/unusual activity -> dừng Facebook ngay theo hard
  rule chung; không retry trong 24h.
- DB lỗi giữa batch -> retry đúng 1 lần sau 5s; vẫn lỗi thì dừng và báo
  warning.
- Sau khi insert thành công mà `has_outreached` chưa verify thành `true` ->
  dừng ngay, không sang candidate tiếp theo cho tới khi trạng thái DB được
  làm rõ.
- Đã đạt 10 outreach DM/24h -> dừng, báo còn lại bao nhiêu trong queue.
- Không tự đổi ranking, threshold, `message1`, template hoặc view logic.
