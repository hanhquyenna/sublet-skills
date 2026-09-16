---
name: outreach-prep
description: "Draft availability-check DMs (never sent by the agent) for offering/seeking listings that have a match candidate, save them to sublet_messages as status='draft', and track who was contacted, with what message, and when Kien marks it sent. Use with /outreach-prep."
---

# outreach-prep

Skill này soạn **draft** tin nhắn hỏi lại "còn không/vẫn tìm không" cho các
listing có match candidate — **không bao giờ gửi**. Agent chỉ đọc Facebook để
lấy context (đã có sẵn trong DB, không cần mở Facebook lại ở skill này), ghi
draft vào `sublet_messages`, và track trạng thái gửi khi Kien tự báo đã gửi.

## Spec

- **Trigger:** Kien gọi tay `/outreach-prep`, thường sau khi `analyze-insights`
  đã có match candidate mới.
- **Đọc:** `sublet_insight_matches` (qua `sublet_v_insight_matches_report`),
  `sublet_v_listing_profile`, `sublet_messages` (để biết listing nào đã có
  draft, tránh trùng).
- **Ghi:** `sublet_messages` (`status='draft'`, một dòng mỗi listing lần đầu
  cần draft); không ghi gì khác. Không tạo `sublet_seekers`/`sublet_matches`
  chính thức (khác `sublet_insight_matches`).
- **Không bao giờ:** không mở Facebook, không click Send/Message trên bất kỳ
  giao diện nào, không tự đổi `status` sang `sent` — chỉ Kien đổi (qua lệnh
  `/outreach-prep sent <message_id>` hoặc Kien tự update).
- **Metrics:** `outreach.drafts_created`, `outreach.drafts_pending`,
  `outreach.sent_by_agent` (phải luôn = 0 — R01 registry).
- **Kết quả:** báo số draft mới tạo, số listing bị loại và lý do (risk flag,
  duplicate, anonymous chưa access-ready), số draft đang chờ gửi.

## Hard rule (thừa hưởng nguyên vẹn từ CLAUDE.md, không có ngoại lệ)

- Agent **không bao giờ** post/comment/like/DM/send trên Facebook, không thao
  tác Messenger dù dưới bất kỳ lý do gì kể cả khi Kien tự soạn template và yêu
  cầu trực tiếp. "Agent là mắt và trí nhớ; con người là tay và tên."
- Mọi message tạo ra ở đây bắt buộc `status='draft'`. Chỉ Kien được đổi
  `status='sent'` + `sent_at` — agent chỉ thực hiện đổi này khi Kien **báo rõ
  trong chat** "đã gửi tin X" hoặc gọi lệnh đánh dấu, không tự suy đoán đã gửi.
- Không giới hạn số draft tạo ra (khác với DM thật — PLAN.md giới hạn ≤10
  DM/ngày là cho tin **đã gửi**, không áp cho việc tạo draft). Nhưng vẫn báo
  rõ số lượng để Kien không bị ngợp.

## Input: listing nào được tạo draft

Chỉ tạo draft cho listing xuất hiện trong `sublet_insight_matches` với
`confidence` là `high`, `medium` hoặc `low` (bỏ `weak` — quá nhiều, chưa đủ
tín hiệu để đáng hỏi lại; Kien có thể yêu cầu mở rộng sau). Với mỗi listing
(cả 2 phía seeker và offering đều có thể được draft), áp thêm điều kiện:

1. `link_validation_status='validated'` và không nằm trong
   `sublet_v_link_needs_reverification` (đã đảm bảo vì input là
   `sublet_insight_matches`, nhưng verify lại ở query).
2. Không có `risk_flags` (rỗng) trên listing đó — có risk flag thì **không**
   tạo draft, liệt kê riêng cho Kien tự quyết (đặc biệt
   `community_warning`/`prepay_before_viewing`/`off_platform_redirect`/
   `duplicate_across_posters`: không bao giờ tự động draft).
3. `duplicate_of is null` (không phải bản repost).
4. Nếu poster là `anonymous` (theo R31): chỉ tạo draft khi
   `anonymous_access_ready=true` (permalink đã validate xác nhận đúng bài);
   thiếu điều kiện này thì bỏ qua, liệt kê riêng.
5. Chưa có draft nào trước đó cho listing này (`select 1 from sublet_messages
   where entity_type='listing' and entity_id=<listing.id> and channel='fb_dm'
   and template in ('availability_check_offering',
   'availability_check_seeker')`) — tránh hỏi lại người đã được hỏi.

```sql
select distinct l.listing_id, l.poster_name, l.offer_or_need, l.source_url,
       l.risk_flags, l.duplicate_of
from (
  select seeker_listing_id as listing_id from sublet_insight_matches where confidence in ('high','medium','low')
  union
  select offering_listing_id as listing_id from sublet_insight_matches where confidence in ('high','medium','low')
) m
join sublet_v_listing_profile l on l.listing_id = m.listing_id
where l.link_validation_status = 'validated'
  and l.duplicate_of is null
  and (l.risk_flags is null or jsonb_array_length(l.risk_flags) = 0)
  and not exists (
    select 1 from sublet_messages sm
    where sm.entity_type = 'listing' and sm.entity_id = l.listing_id
      and sm.channel = 'fb_dm'
      and sm.template in ('availability_check_offering','availability_check_seeker')
  );
```

## Template (Kien chốt bản cuối 2026-09-16, giữ nguyên văn — không tự đổi giọng)

- **Offering** (`template='availability_check_offering'`): `"Hi! I saw your
  post, is the place still available?"`
- **Seeking** (`template='availability_check_seeker'`): `"Hey! I saw your
  post, are you still looking for a place?"`

Bản đầu (`"Hi! Is your place still available?"` / `"Hey! Are you still
looking for a place?"`) đã bị thay — 12 draft tạo ngày 2026-09-16 đã được
UPDATE tại chỗ sang bản mới vì còn `status='draft'` (chưa gửi, sửa tại chỗ an
toàn — khác `sublet_events` là append-only, `sublet_messages` ở trạng thái
draft chưa gửi thì sửa được bình thường).

Ghi đúng nguyên văn 2 câu trên vào `body`, không thêm tên poster, không thêm
chi tiết bài đăng, không nhắc AI/agent/automation — Kien có thể tự sửa/cá
nhân hoá trước khi gửi tay, agent không tự ý mở rộng câu chữ. Nếu Kien đổi
template sau này, cập nhật đúng 2 dòng trên, không suy diễn thêm biến thể.

## Ghi `sublet_messages`

```sql
insert into sublet_messages (entity_type, entity_id, direction, channel, template, body, status)
values ('listing', '<listing_id>', 'out', 'fb_dm', 'availability_check_offering', 'Hi! I saw your post, is the place still available?', 'draft');
```

`entity_type='listing'` (không dùng `'match'`/`'seeker'` vì dự án chưa có
`sublet_seekers`/`sublet_matches` chính thức ở scope hiện tại — liên kết trực
tiếp tới `sublet_listings.id`). Ghi ngay sau mỗi listing xử lý xong, không đợi
hết batch.

## Đánh dấu đã gửi — chỉ Kien

`/outreach-prep sent <message_id>` (hoặc Kien nêu rõ trong chat "đã gửi cho
X"): agent update đúng 1 dòng:

```sql
update sublet_messages set status='sent', sent_at=now() where id='<message_id>' and status='draft';
```

Không tự động đổi status hàng loạt, không đoán đã gửi từ im lặng hay từ việc
Kien "có vẻ đang mở Messenger". Nếu Kien báo đã gửi nhiều tin cùng lúc, xử lý
từng `message_id` một, xác nhận lại số lượng đã update.

## Track "ai / gửi gì / lúc nào" — không cần bảng mới

Đủ dữ liệu từ `sublet_messages` hiện có: `entity_id` (ai — join ngược
`sublet_listings.poster_name`/`source_url`), `body`/`template` (gửi gì),
`created_at` (lúc soạn draft), `sent_at` (lúc Kien xác nhận đã gửi). Query báo
cáo:

```sql
select sm.id, sm.status, sm.template, sm.created_at, sm.sent_at,
       l.poster_name, l.source_url, l.offer_or_need
from sublet_messages sm
join sublet_v_listing_profile l on l.listing_id = sm.entity_id
where sm.channel = 'fb_dm'
  and sm.template in ('availability_check_offering','availability_check_seeker')
order by sm.created_at desc;
```

## Completion và edge cases

- Không có match candidate mới (mọi listing đủ điều kiện đã có draft) → báo
  0 draft mới, không tạo gì, không coi là lỗi.
- Listing bị loại vì risk flag/duplicate/anonymous chưa ready → liệt kê riêng
  trong báo cáo (không im lặng bỏ qua), để Kien tự quyết có muốn xử lý tay
  không.
- DB lỗi giữa batch: retry đúng 1 lần sau 5 giây theo hard rule chung; vẫn
  lỗi thì dừng, báo warning, không claim đã ghi hết.
- Không bao giờ tự nới `confidence` threshold (vd. thêm `weak`) hay tự đổi
  template mà không có yêu cầu rõ từ Kien trong chat.
