---
name: outreach-prep
description: "Draft availability-check DMs (never sent by the agent) in strict outreach_order from dashboardkien_outreach, using message1 verbatim, and mark status when Kien reports a send. Use with /outreach-prep."
---

# outreach-prep

Skill này soạn **draft** tin nhắn hỏi lại "còn không/vẫn tìm không" theo đúng
thứ tự ưu tiên đã tính sẵn trong view `dashboardkien_outreach` — **không bao
giờ gửi**. Agent không mở Facebook ở skill này (context đã có sẵn trong DB),
chỉ đọc view, ghi draft vào `outreach_messages`, và track trạng thái gửi khi
Kien tự báo đã gửi.

**⚠️ 2026-09-17 — DB đã migrate, đọc `information/SKILL.md` mục "Database"
trước khi chạy skill này nếu chưa đọc.** Bảng/RPC cũ (`sublet_listings`,
`sublet_messages`, RPC `sublet_exec`) không còn tồn tại. Project data thật là
ref `cteunhuxrghpozwbnehh` (không phải "Lamy"); `scripts/db.py` đang hỏng —
đọc/ghi bằng REST trực tiếp với `SUPABASE_SERVICE_ROLE_KEY` từ
`~/.sublet-skills.env`, hoặc MCP Supabase đã xác nhận trỏ đúng project này.

Toàn bộ input, xếp hạng, dedup và nội dung message đã tính sẵn trong 1 view
duy nhất — skill này **không tự tính lại điều kiện gì**, chỉ đọc
`dashboardkien_outreach` theo đúng cột đã có:

```sql
select poster_id, poster_name, post_id, intent, post_link, message1,
       scam_flag, outreach_order
from dashboardkien_outreach
where outreach_order is not null   -- đã qua hết filter của view (validated,
                                     -- individual, không risk/scam auto-exclude,
                                     -- ≤7 ngày, xếp hạng theo fit_score/recency/confidence)
  and not has_outreached
order by outreach_order asc;        -- LÀM ĐÚNG THỨ TỰ NÀY, không nhảy cóc, không tự sắp xếp lại
```

(Chạy qua REST tương đương:
`GET /rest/v1/dashboardkien_outreach?select=poster_id,poster_name,post_id,intent,post_link,message1,scam_flag,outreach_order&outreach_order=not.is.null&has_outreached=eq.false&order=outreach_order.asc`)

`outreach_order` đã gộp sẵn: recency (post mới nhất trước, quá 7 ngày tự động
`outreach_order=null` — không hiện ra nữa) rồi trong cùng tier thì theo mức độ
chi tiết của bài (`confidence`/`fit_score`, cao hơn ưu tiên hơn). `has_outreached`
tính live theo poster (không chỉ theo 1 bài) — tự loại người đã từng nhận tin,
khớp rule "không nhắn 1 người 2 lần" bên dưới. `message1` là nội dung draft đã
chọn sẵn theo intent×language — **copy nguyên văn**, không tự sửa.

**Known gap (không phải việc của skill này để tự vá):** `outreach_order` hiện
không tuyệt đối liên tục 1,2,3... (có khoảng trống rải rác trong dãy số) —
không ảnh hưởng thứ tự tương đối, chỉ cần `order by outreach_order asc` là đủ
đúng thứ tự thật; đừng suy diễn số thứ tự tuyệt đối = số người đã xử lý.

**`scam_flag=true` không tự động loại khỏi view** (theo yêu cầu Kien: chỉ
đánh dấu, để Kien tự xem) — nhưng agent **nên bỏ qua thủ công**, không tạo
draft cho các dòng này, và liệt kê riêng trong báo cáo thay vì im lặng draft.

## Spec

- **Trigger:** Kien gọi tay `/outreach-prep`.
- **Đọc:** `dashboardkien_outreach` (view duy nhất cần đọc để chọn candidate,
  lấy nội dung và biết ai đã outreach); `outreach_messages` chỉ để tránh ghi
  trùng và để trả lời "đã gửi gì cho ai".
- **Ghi:** `outreach_messages` (`status='draft'`, một dòng mỗi `post_id`+
  `poster_id` lần đầu cần draft). Không ghi gì khác, không tạo bảng mới.
- **Không bao giờ:** không mở Facebook, không click Send/Message ở bất kỳ
  giao diện nào, không tự đổi `status` sang `sent` — chỉ Kien đổi (qua lệnh
  `/outreach-prep sent <message_id>` hoặc Kien tự báo trong chat).
- **Metrics:** số draft mới tạo, số draft đang chờ (`status='draft'`), số đã
  gửi (`status='sent'`, phải luôn do Kien báo, không phải agent tự đổi).
- **Kết quả báo cáo:** số draft mới tạo (kèm `outreach_order` thấp nhất→cao
  nhất đã xử lý, để Kien biết có đi đúng thứ tự không), số dòng bị bỏ qua vì
  `scam_flag=true` (liệt kê tên), tổng số người còn lại trong queue
  (`outreach_order is not null and not has_outreached`).

## Hard rule (thừa hưởng nguyên vẹn từ CLAUDE.md, không có ngoại lệ)

- Agent **không bao giờ** post/comment/like/DM/send trên Facebook, không thao
  tác Messenger dù dưới bất kỳ lý do gì kể cả khi Kien tự soạn template và yêu
  cầu trực tiếp. "Agent là mắt và trí nhớ; con người là tay và tên."
- Mọi message tạo ra ở đây bắt buộc `status='draft'`. Chỉ Kien được đổi
  `status='sent'` + `sent_at` — agent chỉ thực hiện đổi này khi Kien **báo rõ
  trong chat** "đã gửi tin X" hoặc gọi lệnh đánh dấu, không tự suy đoán đã gửi
  từ im lặng hay hành vi khác.
- Không giới hạn số draft tạo ra (khác với DM thật đã gửi, có giới hạn riêng
  trong `PLAN.md`). Nhưng vẫn báo rõ số lượng để Kien không bị ngợp.
- Không nhắn 1 người (theo `poster_id`) 2 lần trong 2 đợt outreach khác nhau —
  `has_outreached` trong view đã tự tính việc này (dựa trên
  `outreach_messages.status='sent'` join theo `poster_id`); nếu view đã trả về
  `not has_outreached` thì tin theo, không tự query lại logic riêng.

## Đi qua queue: luôn theo `outreach_order`, không tự sắp xếp lại

1. Query `dashboardkien_outreach` như SQL/REST ở trên, `order by
   outreach_order asc`.
2. Xử lý **tuần tự từng dòng theo đúng thứ tự trả về** — không nhảy cóc, không
   ưu tiên theo cảm tính riêng (ví dụ "bài này nhìn hấp dẫn hơn"); nếu Kien
   muốn đổi tiêu chí xếp hạng, đó là việc sửa logic trong view
   `dashboardkien_outreach` (báo Kien / DBA quyết định), không phải việc
   skill này tự làm.
3. Với mỗi dòng: nếu `scam_flag=true` → bỏ qua, ghi vào danh sách "skipped
   (scam_flag)" cho báo cáo, **không** insert draft. Nếu không → tạo draft
   (mục dưới).
4. Ghi `outreach_messages` ngay sau khi xử lý xong 1 dòng, không đợi hết cả
   batch rồi ghi 1 lần — để nếu bị dừng giữa chừng, DB vẫn phản ánh đúng tiến
   độ thật.

## Ghi draft vào `outreach_messages`

`message1` từ `dashboardkien_outreach` đã đúng nội dung cần gửi — copy thẳng
vào `body`, không tự tra lại bảng intent×language nào khác (view đã làm việc
đó). `template` ghi theo `intent` để giữ dedup dễ đọc:
`intent='offering'` → `template='availability_check_offering'`;
`intent='seeking'` → `template='availability_check_seeker'`.

Trước khi insert, kiểm tra chưa có draft/sent nào cho đúng `post_id` này (dedup
theo bài) — view đã tự lo phần "chưa từng nhắn người này qua bài khác" (qua
`has_outreached`), chỉ cần tự check thêm theo `post_id` để không tạo 2 draft
cho cùng 1 bài nếu skill chạy nhiều lần trong ngày:

```sql
select 1 from outreach_messages
where post_id = '<post_id>' and channel = 'fb_dm';
-- có kết quả -> đã có draft/sent cho bài này rồi, bỏ qua, không insert lại
```

Insert khi chưa có:

```sql
insert into outreach_messages (post_id, poster_id, direction, channel, template, body, status)
values ('<post_id>', '<poster_id>', 'out', 'fb_dm', '<availability_check_offering|availability_check_seeker>', '<message1 nguyen van>', 'draft');
```

(REST tương đương: `POST /rest/v1/outreach_messages` với body JSON đúng các
cột trên, header `Prefer: return=representation` nếu cần lấy lại `id`.)

Không thêm tên poster, không thêm chi tiết bài đăng, không nhắc AI/agent/
automation vào `body` — Kien có thể tự sửa/cá nhân hoá trước khi gửi tay,
agent không tự ý mở rộng câu chữ trong `message1`.

## Đánh dấu đã gửi — chỉ Kien, và `has_outreached` tự cập nhật live theo đó

`/outreach-prep sent <message_id>` (hoặc Kien nêu rõ trong chat "đã gửi cho
X"): agent update đúng 1 dòng:

```sql
update outreach_messages set status='sent', sent_at=now() where id='<message_id>' and status='draft';
```

(REST: `PATCH /rest/v1/outreach_messages?id=eq.<message_id>&status=eq.draft`
với body `{"status":"sent","sent_at":"<now iso>"}`.)

Vì `dashboardkien_outreach.has_outreached` là cột tính live từ
`outreach_messages.status='sent'`, agent **không cần và không được** tự set
`has_outreached` ở đâu khác — chỉ cần update đúng `outreach_messages` là view
tự phản ánh đúng ngay ở lần query kế tiếp. Không tự động đổi status hàng
loạt, không đoán đã gửi từ im lặng hay từ việc Kien "có vẻ đang mở Messenger".
Nếu Kien báo đã gửi nhiều tin cùng lúc, xử lý từng `message_id` một, xác nhận
lại số lượng đã update ở cuối.

## Track "ai / gửi gì / lúc nào"

Không cần view phụ nào khác — `dashboardkien_outreach` đã có đủ
`has_outreached`/`outreach_order`/`message1`/`scam_flag` để biết ai đang chờ,
ai đã xong; `outreach_messages` là log thật của từng tin (draft/sent, lúc
nào). Muốn xem toàn bộ đang chờ gửi:

```sql
select poster_name, post_link, message1, outreach_order
from dashboardkien_outreach
where outreach_order is not null and not has_outreached
order by outreach_order asc;
```

Muốn xem đã gửi bao nhiêu:

```sql
select count(*) from outreach_messages where status = 'sent';
```

## Completion và edge cases

- Queue rỗng (`outreach_order is not null and not has_outreached` không có
  dòng nào) → báo 0 draft mới, không tạo gì, không coi là lỗi.
- Dòng bị bỏ qua vì `scam_flag=true` → liệt kê riêng trong báo cáo (không im
  lặng bỏ qua), để Kien tự quyết có muốn xử lý tay không.
- REST/DB lỗi giữa batch: retry đúng 1 lần sau 5 giây theo hard rule chung;
  vẫn lỗi thì dừng, báo warning, không claim đã ghi hết.
- Không bao giờ tự đổi logic xếp hạng trong view, tự nới `confidence`
  threshold, hay tự đổi nội dung `message1`/template mà không có yêu cầu rõ
  từ Kien trong chat — mọi thay đổi loại đó là sửa `dashboardkien_outreach`
  (DDL), không phải việc của skill runtime này.
