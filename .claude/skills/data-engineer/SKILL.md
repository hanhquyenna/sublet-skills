---
name: data-engineer
description: "Turn captured sublet data into reliable, queryable datasets: normalize raw records, enforce provenance and data-quality contracts, deduplicate, build behavior/event aggregates, and maintain idempotent Supabase checkpoints. DB-only; does not browse Facebook or perform semantic matching by itself. Use with /data-engineer."
---

# data-engineer

Skill này là lớp dữ liệu dùng chung cho project sublet. Nó biến raw capture và
first-party lifecycle events thành dữ liệu có thể query, audit và báo cáo được.
Nó nhận cả dữ liệu cũ do `analyze-insights` tạo; không tự ý thay đổi ý nghĩa
semantic đã được chốt.

## Boundary với các skill khác

- `sublet-scrape-14-groups` và `validate-permalink` capture/verify bằng visible
  Chrome panel. `data-engineer` không mở Facebook, không dùng browser và không
  gọi HTTP/API để lấy dữ liệu Facebook.
- `analyze-insights` sở hữu heuristic offering/seeking/other, duplicate/risk
  insight và logic candidate matching. `data-engineer` sở hữu storage contract,
  normalization, QA, aggregates, report views và checkpoint của các kết quả đó.
- Không tạo `sublet_matches` chính thức, không tự gửi outreach, không đổi
  `sublet_listings.kind`, `status`, `scam_score` hay các cột semantic chính thức.
  Candidate heuristic vẫn nằm riêng ở `sublet_insight_matches`.

## Spec

- **Trigger:** Kien gọi `/data-engineer`, hoặc một skill khác cần ingest,
  backfill, audit, aggregate, repair provenance hay dựng data report.
- **Đọc:** `db/schema.sql`, `sublet_*`, `sublet_events`, `sublet_scan_runs`,
  `sublet_ops_state`, `sublet_jobs`, `sublet_inbox`, `sublet_metrics`, cùng
  event/run liên quan.
- **Ghi:** chỉ các bảng cần cho data contract: raw/context events,
  `sublet_metrics`, `sublet_inbox`, `sublet_ops_state`, `sublet_jobs` và các
  view/migration được Kien yêu cầu rõ. Không ghi secret vào repo.
- **Metrics:** data-quality, freshness, dedupe, provenance, pipeline progress
  và customer-behavior aggregates; mỗi metric upsert theo `(day, workflow,
  metric)` và phải nêu rõ numerator/denominator.
- **Completion:** báo số rows đọc/ghi/bỏ qua, duplicate, unknown, lỗi và
  checkpoint cuối. Không báo “complete” nếu còn queue hoặc write thất bại.

## Luật dữ liệu bất biến

1. `sublet_listings.source_url` và `seen_at` là bằng chứng bắt buộc. Không có
   source thì không coi là record hợp lệ; không dùng `seen_at` thay cho
   `posted_at`.
2. Giữ raw nguyên bản. Không overwrite `raw_text`, poster label, timestamp
   label, share URL hoặc payload gốc bằng dữ liệu đã normalize. Dữ liệu chuẩn
   hoá đi vào field/payload riêng và phải truy ngược được về source.
3. Tách ba thời điểm: `posted_at`/`commented_at` là lúc nội dung xảy ra nếu
   Facebook expose; `seen_at`/`captured_at` là lúc quan sát; `created_at` là lúc
   hệ thống ghi event. Không suy ngược thời điểm tuyệt đối từ nhãn tương đối
   nếu không có timezone/bằng chứng đủ rõ.
4. Thiếu dữ liệu là `NULL`, `unknown`, `[]` hoặc `false` đúng theo contract;
   không biến missing thành `0`, `no` hoặc mismatch. `false` chỉ dùng khi đã
   quan sát và xác nhận điều kiện false.
5. Mọi event mới có provenance: `source_url`, `source`, `source_surface`,
   `scan_run_id`/`job_id` nếu có, `page_load` nếu có, `captured_at`/`observed_at`
   và contract version phù hợp. Legacy event thiếu key được audit là
   `unknown`, không tự bịa giá trị.
6. Không duplicate: ưu tiên khóa tự nhiên/unique hiện có; kiểm tra
   `source_url`, `text_hash`, fingerprint, entity + event + source trước khi
   insert. Upsert phải idempotent và không tạo event lặp khi retry.
7. Event history là append-only. Sửa logic phải recompute aggregate/candidate
   theo batch mới và giữ event cũ; không sửa lẻ làm mất audit trail.

## Workflow chuẩn

### 1. Discover và khóa phạm vi

Đọc `information/SKILL.md`, `CLAUDE.md`, `PLAN.md`, `db/schema.sql` rồi query
DB bằng:

```sh
cd /Users/ad/sublet-skills
python3 scripts/db.py "select count(*) from sublet_listings"
```

Xác định rõ: dataset nào, thời gian nào, workflow/run nào, source nào và có
được phép sửa schema hay chỉ backfill dữ liệu. Không tin snapshot trong skill
nếu query runtime khác.

### 2. Profile trước khi ghi

Audit tối thiểu:

- tổng row, null/empty theo field, khoảng thời gian `posted_at` và `seen_at`;
- duplicate `source_url`, duplicate `text_hash`, near-duplicate cùng poster;
- tỷ lệ `raw_text` giữ nguyên, record có provenance đầy đủ;
- event/context lệch 1–1 với listing, contract version và missing keys;
- trạng thái link: `unvalidated`, `validated`, `inaccessible`, `needs_review`;
- queue/cursor/run đang mở, rows đã review và rows còn pending;
- aggregate có `unknown` bị đếm nhầm thành zero hay không.

Ghi audit vào `sublet_inbox` hoặc `sublet_metrics` khi Kien yêu cầu; không
đưa QA note vào payload mà analyzer đọc như raw fact. `detail_audit` là QA,
không phải raw capture.

### 3. Normalize mà không làm mất raw

Chuẩn hoá vào payload/field phụ, luôn kèm source và uncertainty:

- timezone-aware ISO timestamp khi có absolute timestamp;
- tiền EUR thành số và giữ `pricing_tag`/original text;
- khu vực thành danh sách canonical, giữ raw phrase;
- trạng thái join/link/visibility thành enum đã biết;
- public post/comment/profile context thành event liên kết với listing;
- loại dữ liệu Facebook không hiển thị thành `null`/`[]`/`unknown`, không đoán.

Không tách riêng email, phone, DM, friend list, album hay private profile thành
customer record. Public profile URL chỉ giữ trong context của post/comment đã
capture theo hard rules; không xây hồ sơ theo dõi người dùng.

### 4. Ghi idempotent và checkpoint

Mỗi batch:

1. đọc cursor/state hiện tại;
2. validate schema và provenance;
3. dedupe trước insert;
4. ghi rows/events trong transaction hoặc các bước có thể retry an toàn;
5. verify counts bằng query sau write;
6. cập nhật `sublet_ops_state`/`sublet_scan_runs` cuối cùng.

DB/RPC/HTTP lỗi thì retry đúng một lần sau 5 giây; vẫn lỗi thì dừng, giữ
incomplete, ghi warning và không claim thành công. Không reset cursor về đầu
chỉ vì một batch lỗi.

### 5. Aggregate và report

Tính lại từ nguồn hiện tại, không cộng dồn thủ công. Mọi report phải ghi:

- `as_of` và timezone;
- filters/time window/source;
- numerator, denominator và cách xử lý unknown;
- số raw rows, valid rows, duplicate rows, excluded rows;
- link/source hoặc query để audit ngược.

Report matching đọc từ `sublet_v_insight_matches_report`, phải giữ đủ
`high`, `medium`, `low`, `weak`, score, reasons, source URL và raw post text
nếu view/query có thể lấy. `weak` không được gộp vào `low` hoặc bị ẩn.

Khi heuristic matching đổi, xoá/rebuild toàn bộ `sublet_insight_matches` theo
đúng migration/run contract rồi ghi rõ “full recompute”; không upsert chắp vá
để giữ score/reasons của logic cũ.

## Customer-behavior data model

“Behavior” ở đây là hành vi quan sát được, không phải hồ sơ suy đoán. Dùng
`sublet_events` làm event log chung thay vì tạo person table riêng.

### A. Public content behavior

Chỉ lưu những gì đang hiển thị công khai trên post housing đã capture:

```json
{
  "event": "context_captured",
  "entity_type": "listing",
  "entity_id": "<listing-id>",
  "observed_at": "2026-09-16T10:00:00+02:00",
  "payload": {
    "post": {
      "comment_count": 10,
      "reaction_count": 13,
      "timestamp_label": "2 days ago",
      "media": [],
      "truncated": false
    },
    "comments": [
      {
        "commenter_name": "public display name",
        "commenter_profile_url": null,
        "raw_text": "Is this still available?",
        "commented_at": null,
        "visibility": "partial"
      }
    ],
    "capture_contract_version": 2,
    "capture_quality": "partial",
    "source_surface": "facebook_group_feed"
  }
}
```

Store observed counts and comments as evidence. Do not infer that a reaction
means intent, that a commenter is a seeker, or that silence means rejection.
Anonymous users remain anonymous; no identity resolution from photos, names or
cross-posts.

### B. First-party customer lifecycle behavior

When the user or customer explicitly provides evidence, record events such as
`form_submitted`, `reply_received`, `consent_given`, `viewing_scheduled`,
`viewing_attended`, `accepted`, `signed`, `moved_in`, `fee_paid` with:

- `occurred_at` when known and `observed_at` when the system recorded it;
- entity/listing/match/viewing ID;
- source (`form`, `email`, `user_report`, `browser_read`, etc.);
- actor visibility and confirmation level;
- raw evidence or a short reference, without unnecessary contact data.

Only confirmed events may drive funnel metrics or outcome fields. A draft,
public comment, match candidate or heuristic risk flag is not a conversion.

Useful aggregates include: comments per captured post, posts with any public
question, time from post to first observed comment, reply/consent rate,
viewing-show rate, accepted-to-move-in rate, fee collection rate and counts by
group/time window. Always show sample size and unknown denominator.

### C. Per-user/entity normalized profile

Khi Kien yêu cầu biến raw data thành dữ liệu dễ dùng, tạo một normalized view
hoặc payload theo từng actor/entity có evidence. Không cần tạo bảng người dùng
mới mặc định; ưu tiên liên kết qua `listing_id`, `event.entity_id` và source
URL. Chỉ gộp hai record thành một actor khi có định danh public rõ ràng và
không mâu thuẫn; `display_name` giống nhau không đủ để merge.

Schema logic tối thiểu:

```json
{
  "entity_id": "<listing-or-event-id>",
  "actor_role": "offering | seeking | unknown",
  "actor_label": "public display name or Anonymous participant",
  "actor_profile_url": null,
  "visibility": "public | anonymous | partial | unknown",
  "offer_or_need": "offering | seeking | both | unknown",
  "budget_eur": null,
  "price_eur": null,
  "location": [],
  "move_in_date": null,
  "start_date": null,
  "end_date": null,
  "duration": null,
  "requirements": [],
  "occupancy_or_people": null,
  "registration_need": "yes | no | unknown",
  "pets": "yes | no | unknown",
  "evidence": [
    {"field": "budget_eur", "source_url": "...", "raw_text": "..."}
  ],
  "extraction_quality": "complete | partial | unknown"
}
```

Field semantics:

- `actor_role`/`offer_or_need`: `offering` nếu evidence cho thấy người đó có
  chỗ; `seeking` nếu evidence cho thấy người đó cần chỗ; `both` chỉ khi hai
  hướng đều xuất hiện trong evidence. Không suy ra role từ tên, ảnh,
  nationality hay comment ngắn không đủ ngữ cảnh.
- `budget_eur` là ngân sách seeker; `price_eur` là giá của offering. Giữ
  `pricing_tag`, currency gốc và câu raw đi kèm; không đặt giá bằng 0 khi
  không có giá.
- `location` là các khu vực/postcode được nêu; giữ cả canonical value và raw
  phrase nếu normalize. Không nêu location = `[]`/`unknown`, không phải
  “location mismatch”.
- `move_in_date` là ngày seeker muốn chuyển vào; `start_date` là ngày offering
  bắt đầu có chỗ. `end_date` là ngày kết thúc nếu có. Không dùng
  `seen_at`/`commented_at` làm một trong các ngày này.
- `duration` giữ nguyên cách nói (“3 months”, “short stay”) và chỉ thêm ngày
  tính được khi evidence đủ rõ; không tự bịa năm hoặc timezone.
- `requirements` là yêu cầu được viết trong raw text, ví dụ registration,
  furnished, private room, students/couples/pets, viewing availability. Giữ
  nguyên constraint nhạy cảm nếu cần audit nhưng không biến nó thành tiêu chí
  phân biệt hay ranking người.

Mỗi extracted field phải truy ngược được về `source_url`/event và có quality
hoặc uncertainty. Nếu hai bài của cùng public actor mâu thuẫn, giữ cả hai
evidence với `conflict=true`; không tự chọn giá/ngày “mới nhất” nếu chưa có
quy tắc thời gian rõ ràng. Đây là data structuring, không phải bước chấm match
hay quyết định outreach.

## Data-quality checks before completion

Run the smallest relevant queries/checks:

```sql
-- required listing evidence
select count(*) as missing_source_or_seen
from sublet_listings
where source_url is null or seen_at is null;

-- duplicate source URLs
select source_url, count(*)
from sublet_listings
group by source_url
having count(*) > 1;

-- insight candidate tier distribution
select confidence, count(*)
from sublet_insight_matches
group by confidence
order by case confidence
  when 'high' then 0 when 'medium' then 1 when 'low' then 2 else 3 end;
```

For each failed check, classify `blocker`, `warning` or `unknown`; do not hide
the issue by bulk-marking rows as verified. A row with no usable permalink can
still preserve raw post/comment data, but cannot be treated as validated for
anonymous access, matching or outreach.

## Do not do

- Không browse Facebook, không click, không join, không submit form và không
  gửi message.
- Không scrape bằng script, API, HTTP, Selenium, headless browser hay cookie.
- Không làm giàu hồ sơ người dùng, đoán identity/intent/demographics hoặc tạo
  lead score từ nationality, gender, age, religion.
- Không coi missing area/budget là mismatch; đó là `unknown`.
- Không gán `offering`/`seeking`, budget, location, move-in hoặc requirements
  chỉ từ tên/profile/comment rời rạc; mọi field phải có evidence link được.
- Không sửa raw event cũ để làm số liệu “đẹp hơn”.
- Không dùng customer-behavior aggregate để tự động outreach; mọi outreach
  vẫn cần skill riêng và người dùng duyệt.

## Handoffs

- Sau raw capture: `data-engineer` kiểm tra contract/provenance/duplicates;
  `validate-permalink` xử lý link queue.
- Sau semantic insight: `analyze-insights` tạo/giải thích heuristic events và
  `sublet_insight_matches`; `data-engineer` QA, aggregate và report.
- Khi Kien bổ sung rule semantic mới vào `analyze-insights`, cập nhật data
  contract/metrics ở đây chỉ khi field, provenance hoặc aggregate thật sự đổi.
