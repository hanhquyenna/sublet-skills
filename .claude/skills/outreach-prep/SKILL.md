---
name: outreach-prep
description: "Draft availability-check DMs (never sent by the agent) for qualifying individual offering/seeking listings, save them to sublet_messages as status='draft', and track who was contacted, with what message, and when Kien marks it sent. Use with /outreach-prep."
---

# outreach-prep

Skill này soạn **draft** tin nhắn hỏi lại "còn không/vẫn tìm không" cho từng
listing đủ điều kiện — **không bao giờ gửi**. Agent chỉ đọc Facebook để lấy
context (đã có sẵn trong DB, không cần mở Facebook lại ở skill này), ghi draft
vào `sublet_messages`, và track trạng thái gửi khi Kien tự báo đã gửi.

**2026-09-17 — bỏ bước matching (Kien quyết định):** trước đây skill này lấy
candidate từ `sublet_insight_matches` (seeker↔offering pairing). Bảng đó đã bị
xoá hoàn toàn (169,012 dòng, phần lớn `weak`-tier — data bloat không tương
xứng giá trị). Giờ mỗi listing `offering`/`seeking` genuinely-validated đủ
điều kiện tự nó là 1 candidate — không cần ghép cặp với listing nào khác.

## Spec

- **Trigger:** Kien gọi tay `/outreach-prep`, thường sau khi `intent-analyze`
  đã classify thêm listing mới.
- **Đọc:** `sublet_listings` (kind/area/link_validation_status/poster_name/
  canonical_id), `sublet_v_listing_profile` (risk_flags/language),
  `sublet_v_link_needs_reverification`, `sublet_messages`/
  `sublet_v_outreach_queue` (để biết listing/poster nào đã có draft, tránh
  trùng).
- **Ghi:** `sublet_messages` (`status='draft'`, một dòng mỗi listing lần đầu
  cần draft); không ghi gì khác. Không tạo `sublet_seekers`/`sublet_matches`
  chính thức.
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

Không còn bước ghép cặp seeker↔offering nào cả — mỗi listing `offering`/
`seeking` genuinely-validated, đủ điều kiện dưới đây, tự nó là 1 candidate độc
lập cho draft "còn không/vẫn tìm không". Điều kiện:

1. `kind in ('offering','seeking')` (`intent-analyze` đã phân loại; `kind is
   null` hoặc `kind='other'` chưa/không đủ điều kiện).
2. `link_validation_status='validated'` **và** không nằm trong
   `sublet_v_link_needs_reverification` (loại `link_resolution_method=
   'bulk_unverified_override'` — validated giả, chưa mở link thật).
3. `poster_name is not null` — không có ai để bấm Message thì draft vô dụng.
4. `canonical_id is null` (không phải bản repost/duplicate — chỉ giữ bản gốc
   trong pool).
5. Không có `risk_flags` (rỗng) trên listing đó — có risk flag thì **không**
   tạo draft, liệt kê riêng cho Kien tự quyết (đặc biệt
   `community_warning`/`prepay_before_viewing`/`off_platform_redirect`/
   `duplicate_across_posters`: không bao giờ tự động draft).
6. Chưa có draft nào trước đó cho **listing này** (`select 1 from
   sublet_messages where entity_type='listing' and entity_id=<listing.id>
   and channel='fb_dm' and template in ('availability_check_offering',
   'availability_check_seeker')`) — tránh tạo 2 draft cho cùng 1 bài.
7. **Chưa từng nhắn cho người này qua bất kỳ listing nào khác** (kiểm theo
   `poster_name`, không chỉ theo `listing_id`) — cùng 1 poster có thể có
   nhiều bài khác nhau (không phải repost, không bị loại ở điều kiện 4); nếu
   họ **đã có** message (`draft` hoặc `sent`) từ lần chạy trước, **không** tạo
   thêm draft mới cho bài khác của họ. Lý do: nhắn 1 người 2 lần trong cùng
   đợt outreach là làm phiền, không phải "thêm cơ hội". Dùng `poster_name` dù
   biết đây là tín hiệu yếu (2 người trùng tên thật vẫn có thể xảy ra,
   `data-engineer` đã ghi rõ "display_name giống nhau không đủ để merge
   identity") — với outreach thì **thà bỏ sót 1 draft hiếm khi trùng tên còn
   hơn nhắn phiền ai đó 2 lần**, ngược chiều với nguyên tắc recall-first dùng
   cho trích xuất dữ liệu (đó là ưu tiên không bỏ sót dữ liệu, không áp dụng
   cho hành động nhắm vào người thật). **Rule này giữ nguyên vẹn từ thiết kế
   cũ, không đổi khi bỏ bước matching.**

Anonymous poster (theo R31): chỉ tạo draft khi `anonymous_access_ready=true`
(permalink đã validate xác nhận đúng bài); thiếu điều kiện này thì bỏ qua,
liệt kê riêng.

```sql
select l.id as listing_id, l.poster_name, l.kind, l.source_url, l.language,
       prof.risk_flags
from sublet_listings l
left join sublet_v_listing_profile prof on prof.listing_id = l.id
where l.kind in ('offering','seeking')
  and l.link_validation_status = 'validated'
  and l.id not in (select id from sublet_v_link_needs_reverification)
  and l.poster_name is not null
  and l.canonical_id is null
  and (prof.risk_flags is null or jsonb_array_length(prof.risk_flags) = 0)
  and not exists (
    select 1 from sublet_messages sm
    where sm.entity_type = 'listing' and sm.entity_id = l.id
      and sm.channel = 'fb_dm'
      and sm.template in ('availability_check_offering','availability_check_seeker')
  )
  and not exists (
    -- điều kiện 7: người này (theo poster_name) chưa nhận message nào qua listing khác
    select 1 from sublet_v_outreach_queue oq
    where oq.poster_name = l.poster_name
      and oq.template in ('availability_check_offering','availability_check_seeker')
  );
```

## Template (chốt bản cuối 2026-09-16, mở rộng theo ngôn ngữ 2026-09-17 theo yêu cầu Kien — giữ nguyên văn, không tự đổi giọng)

`template` column vẫn chỉ mang **kind** (`availability_check_offering` /
`availability_check_seeker`) — giữ nguyên để không phá logic dedup/report ở
các phần khác của skill này. **`body`** (nội dung thật gửi đi) được chọn theo
**2 trục: kind (offering/seeking) × `sublet_listings.language`** (cột
data-engineer detect bằng `langdetect`, thêm 2026-09-17) — tra bảng dưới đây,
không tự dịch/diễn giải thêm:

| kind | `language` | `body` |
|---|---|---|
| offering | `en` (hoặc bất kỳ giá trị nào khác `nl`, kể cả `null`) | `Hi! I saw your post, is the place still available?` |
| offering | `nl` | `Hoi! Ik zag je bericht, is de plek nog beschikbaar?` |
| seeking | `en` (hoặc bất kỳ giá trị nào khác `nl`, kể cả `null`) | `Hey! I saw your post, are you still looking for a place?` |
| seeking | `nl` | `Hey! Ik zag je bericht, ben je nog op zoek naar een plek?` |

Chỉ 2 ngôn ngữ có bản dịch riêng (en/nl chiếm 97.7% dữ liệu hiện có — 695+401
trên 1122). Mọi `language` khác (af/da/es/de/fr/...) hoặc `null` **mặc định
về bản tiếng Anh** — không tự dịch sang ngôn ngữ khác dù `language` cho biết
đó là tiếng gì, tránh dịch sai/lệch giọng khi chưa được Kien duyệt. Nếu Kien
muốn thêm ngôn ngữ thứ 3 (vd Tây Ban Nha), thêm 1 dòng mới vào bảng trên theo
đúng yêu cầu rõ ràng của Kien, không tự suy diễn thêm.

Bản đầu tiên (`"Hi! Is your place still available?"` / `"Hey! Are you still
looking for a place?"`) đã bị thay bằng bản `en` ở trên — 12 draft tạo ngày
2026-09-16 đã được UPDATE tại chỗ sang bản mới vì còn `status='draft'` (chưa
gửi, sửa tại chỗ an toàn — khác `sublet_events` là append-only,
`sublet_messages` ở trạng thái draft chưa gửi thì sửa được bình thường).

Ghi đúng nguyên văn câu tương ứng vào `body`, không thêm tên poster, không
thêm chi tiết bài đăng, không nhắc AI/agent/automation — Kien có thể tự
sửa/cá nhân hoá trước khi gửi tay, agent không tự ý mở rộng câu chữ. Nếu Kien
đổi template sau này, cập nhật đúng bảng trên, không suy diễn thêm biến thể.

## Ghi `sublet_messages`

Lấy `kind` và `language` từ listing trước khi chọn `body` theo bảng trên.

```sql
-- vi du: offering + language='nl'
insert into sublet_messages (entity_type, entity_id, direction, channel, template, body, status)
values ('listing', '<listing_id>', 'out', 'fb_dm', 'availability_check_offering', 'Hoi! Ik zag je bericht, is de plek nog beschikbaar?', 'draft');
-- vi du: offering + language khac 'nl' (hoac null) -> mac dinh ban en
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

## Track "ai / gửi gì / lúc nào" — view `sublet_v_outreach_queue`, không cần bảng mới

Đủ dữ liệu từ `sublet_messages` hiện có, gộp sẵn qua view
`sublet_v_outreach_queue` (thêm 2026-09-16) — 1 dòng/message, có
`message_id, status, template, body, created_at, sent_at, poster_name,
source_url, poster_profile_url, offer_or_need, group_key`.
`poster_profile_url` lấy từ event `context_captured` mới nhất — không phải
lúc nào cũng có (Facebook không luôn lộ link profile trong feed); thiếu thì
Kien mở `source_url` (bài gốc) để tìm người đăng, không phải lỗi thiếu dữ
liệu.

```sql
select * from sublet_v_outreach_queue where status='draft';
```

Không tạo bảng "người sẽ DM" riêng — đúng nguyên tắc `data-engineer`
("không cần tạo bảng người dùng mới mặc định, liên kết qua listing_id"); view
đủ dùng ở quy mô hiện tại (chục draft/lần).

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
