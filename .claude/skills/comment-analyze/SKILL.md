---
name: comment-analyze
description: "Read-only pass over public comments already captured under housing posts: for each comment, read the full parent post content, the commenter, and the timestamp together (never the comment text alone) before judging whether it carries a genuine offering/seeking signal. Write comment_reviewed events; never infer intent from a bare 'DM'/'interested' comment. Use with /comment-analyze."
---

# comment-analyze

Skill này đọc comment công khai đã capture sẵn trong `sublet_events` (nằm
trong `comments[]` của event `context_captured`/`capture_unresolved`) và tóm
tắt xem comment nào mang tín hiệu offering/seeking thật, tách biệt với
`analyze-insights` (phân tích **post gốc**) và `data-engineer` (chuẩn hoá
field). Không mở Facebook — mọi input đã có sẵn trong DB.

## Vì sao phải đọc post gốc + commenter + timestamp cùng lúc (yêu cầu rõ của Kien)

**Không bao giờ chấm điểm 1 comment chỉ dựa vào chính nó.** Comment "Dm" hay
"còn không?" vô nghĩa nếu không biết **bài gốc nói gì** (offering hay
seeking, giá bao nhiêu, khu nào), **ai comment** (tên/profile để biết có phải
chính chủ bài gốc reply lại không), và **lúc nào** (comment 3 tuần sau khi
bài đăng thường không còn liên quan, phòng có thể đã có người). Ba thứ này
luôn phải đọc cùng nhau trước khi kết luận bất kỳ điều gì về 1 comment.

## Spec

- **Trigger:** Kien gọi tay `/comment-analyze`, sau khi có comment mới được
  capture (qua `sublet-scrape-14-groups`).
- **Đọc:** `sublet_events` (event `context_captured`/`capture_unresolved`,
  lấy mảng `comments[]` + toàn bộ context bài gốc: `raw_text`, `group_key`,
  `poster.display_name`), `sublet_v_listing_profile` (để có `offer_or_need`,
  `pricing_tag`, `area` của bài gốc — join qua `entity_id`/`listing_id`),
  `sublet_events` cũ event `comment_reviewed` (để biết comment nào đã xử lý,
  tránh chấm lại).
- **Ghi:** `sublet_events(event='comment_reviewed')` — 1 event/comment lần
  đầu xử lý; `sublet_inbox(level='info')` — snapshot khi có comment mới xử
  lý; `sublet_metrics(workflow='analyze', metric='comment_*')`.
- **Không ghi:** không tạo `sublet_listings` mới cho commenter (họ không có
  bài riêng), không ghi cột phân loại chính thức, không tạo
  `sublet_insight_matches` cho commenter (matching cross-post/comment là
  quyết định mở rộng riêng, ngoài scope v1 này — xem "Không làm ở v1" cuối
  file), không mở Facebook.
- **Metrics:** `comment_reviewed_total`, `comment_new_this_run`,
  `comment_has_signal`, `comment_no_signal`, `comment_insufficient_evidence`.
- **Kết quả:** báo số comment đã xử lý, breakdown có/không có tín hiệu, danh
  sách comment có tín hiệu mạnh nhất cho Kien tham khảo.

## Hard rule thừa hưởng (không phải quy tắc mới, đã có sẵn trong data-engineer)

`data-engineer/SKILL.md` mục "Public content behavior" đã ghi: *"Do not infer
that a reaction means intent, that a commenter is a seeker, or that silence
means rejection."* — `comment-analyze` phải tuân đúng câu này. Một comment
ngắn kiểu "Dm", "interested", "still available?", emoji, "🙋" **không đủ**
để kết luận người này là seeker/offering — chỉ là bằng chứng "có tương tác",
ghi `comment_signal='insufficient_evidence'`, không phải `seeking_like`/
`offering_like`.

## Hàng đợi "chưa xử lý" — cùng nguyên tắc idempotent với analyze-insights

Không có bảng comment riêng nên hàng đợi phải tính bằng cách duyệt
`context_captured`/`capture_unresolved` mới nhất của mỗi listing, lấy từng
phần tử `comments[]`, rồi loại phần tử đã có `comment_reviewed` khớp
`comment_url` (hoặc `card_fingerprint`/`commenter_name`+`raw_text` chuẩn hoá
khi không có `comment_url`, giống cách `card_fingerprint` xử lý card không
link). Ghi `comment_reviewed` **ngay sau từng comment** xử lý xong, không đợi
hết batch — agent bị ngắt giữa chừng vẫn resume an toàn.

```sql
-- lấy toàn bộ comment công khai đã capture, kèm context bài gốc
select l.listing_id, l.offer_or_need as parent_offer_or_need,
       l.pricing_tag as parent_pricing_tag, l.group_key, l.poster_name as parent_poster,
       l.raw_text as parent_raw_text,
       c.value as comment
from sublet_v_listing_profile l
join sublet_events e on e.entity_type='listing' and e.entity_id=l.listing_id
  and e.event in ('context_captured','capture_unresolved')
  and e.id = (select max(id) from sublet_events e2 where e2.entity_type=e.entity_type and e2.entity_id=e.entity_id and e2.event=e.event)
cross join lateral jsonb_array_elements(coalesce(e.payload->'comments','[]'::jsonb)) as c(value)
where jsonb_array_length(coalesce(e.payload->'comments','[]'::jsonb)) > 0;
```

Lọc bỏ comment đã có `comment_reviewed` (so theo `comment.comment_url` khi có,
fallback `commenter_name`+normalized text) trước khi xử lý.

## Bước 1 — đọc 3 thứ cùng lúc, không tách rời

Với mỗi comment trong hàng đợi, tập hợp đủ:

1. **Post gốc:** `parent_offer_or_need` (offering/seeking/other của bài gốc,
   đã có sẵn từ `analyze-insights`), `parent_raw_text` (rút gọn đủ hiểu ngữ
   cảnh — giá, khu, ngày nếu có), `parent_poster` (để loại trường hợp chính
   chủ tự comment vào bài mình).
2. **Commenter:** `commenter_name`, `commenter_profile_url` nếu có,
   `visibility` (public/partial) — không suy danh tính từ ảnh/tên trùng.
3. **Thời điểm:** `commented_at` (absolute nếu Facebook expose) hoặc
   `original_time_label` (relative) — dùng để đánh giá độ liên quan (comment
   quá lâu sau bài gốc thường ít giá trị, nhưng **không tự loại** chỉ vì cũ,
   ghi vào `reasons` để Kien tự cân nhắc).

Nếu `commenter_name` trùng `parent_poster` (chính chủ tự trả lời/cập nhật bài
mình, ví dụ "Vẫn còn phòng nhé mọi người"), đánh dấu `is_parent_poster=true`
— đây có thể là tín hiệu "vẫn còn" hữu ích (bổ sung cho bài gốc) nhưng
**không phải** 1 lead mới, không tính vào `comment_has_signal`.

## Bước 2 — heuristic tín hiệu (dùng lại pattern của analyze-insights Bước 1)

Áp cùng `OFFERING_PATTERNS`/`SEEKING_PATTERNS` đã định nghĩa trong
`analyze-insights/SKILL.md` lên **raw_text của chính comment** (không phải
bài gốc). Chỉ kết luận `comment_signal` khi:

- **`seeking_like`**: comment nêu rõ nhu cầu riêng của người comment (khác
  bài gốc), ví dụ "I'm also looking for something around €700, is there
  anything else available?" — có ngân sách/khu vực/thời điểm cụ thể của
  chính họ, không chỉ hỏi về bài gốc.
- **`offering_like`**: comment nêu rõ họ có chỗ khác để cung cấp, ví dụ "I
  have a room available in Oost if you're still looking, DM me" — tương tác
  ngược với bài `seeking_like` gốc.
- **`insufficient_evidence`** (mặc định khi không rõ): mọi comment ngắn,
  chung chung, chỉ xác nhận quan tâm mà không có chi tiết riêng của người
  comment ("Dm", "interested", "still available?", "🙋", emoji, "Yes please",
  "Sent you a message"). Đây là **đa số** comment thực tế — không cố suy diễn
  thêm để tăng số `has_signal`.
- **`other`**: comment lạc đề, spam, hoặc câu hỏi không liên quan tới nhu cầu
  nhà ở (hỏi giá điện, hỏi thú cưng được không mà không có ý định thuê/rao).

## DB write contract

```json
{
  "comment_contract_version": 1,
  "parent_listing_id": "<uuid>",
  "parent_offer_or_need": "offering_like",
  "commenter_name": "...",
  "commenter_profile_url": null,
  "comment_url": null,
  "commented_at": null,
  "original_time_label": "2 giờ",
  "comment_raw_text": "...",
  "is_parent_poster": false,
  "comment_signal": "insufficient_evidence",
  "reasons": ["no specific budget/area/timing stated by commenter"],
  "run_at": "2026-09-16T20:00:00+02:00"
}
```

`entity_type='listing'`, `entity_id=<parent_listing_id>` (comment không có
listing riêng nên gắn vào bài gốc — nhất quán với cách `context_captured` đã
lưu comment lồng trong payload bài gốc), `event='comment_reviewed'`,
`source_url=<comment_url nếu có, fallback parent listing source_url>`.

## Snapshot `sublet_inbox`

Chỉ ghi khi có ≥1 comment mới xử lý trong run này. Liệt kê riêng các comment
`comment_signal` khác `insufficient_evidence`/`other` (tức có tín hiệu thật)
kèm: bài gốc nói gì, ai comment, comment nói gì, link (nếu có) — để Kien tự
đọc, không tự động đưa vào matching.

## Không làm ở v1 (mở rộng sau nếu Kien yêu cầu)

- **Không tạo `sublet_insight_matches` cho commenter.** Commenter không có
  `listing_id` (không có bài riêng) nên không khớp được schema Bước 3 của
  `analyze-insights` hiện tại. Muốn commenter thành candidate matching thật
  cần quyết định thiết kế riêng (có thể cần 1 bảng nhẹ lưu "candidate từ
  comment" tách khỏi `sublet_listings`) — đây là mở rộng scope mới, không tự
  làm khi chưa được yêu cầu rõ.
- Không tự động outreach/DM cho commenter dù `comment_signal` là gì.
- Không đọc DM riêng, không đọc comment trên bài không phải housing post.

## Completion và edge cases

- Không có comment nào trong hàng đợi (đã xử lý hết hoặc chưa capture được
  comment nào) → báo 0, không coi là lỗi.
- Comment thiếu `comment_url` (Facebook không expose) → dùng
  `commenter_name` + normalized text làm khoá dedupe fallback; nếu 2 comment
  trùng cả 2 field này ở cùng 1 bài, coi là cùng 1 comment (tránh xử lý
  trùng), không phải bug.
- DB lỗi giữa batch: retry đúng 1 lần sau 5 giây theo hard rule chung; vẫn
  lỗi thì dừng, báo warning, không claim đã xử lý hết.
