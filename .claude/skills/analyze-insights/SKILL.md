---
name: analyze-insights
description: "Read-only insight pass over already-captured Facebook raw listings in Supabase: coarse offering/seeking/other split, duplicate/repost cluster detection, and risk/scam pattern flags, summarized into sublet_inbox + sublet_metrics. Never re-reads a listing already marked insight_reviewed. No Facebook/browser access — DB only. Use with /analyze-insights."
---

**2026-09-17 — matching removed (Kien's explicit decision):** the old "Bước 3"
seeker↔offering matching step and its table `sublet_insight_matches` are gone
(dropped from DB and from this file). The table had ballooned to 169,012 rows
(152,501 `weak`-tier) — data bloat with no proportionate value. This skill is
read-only insight/signal summarization only, as described below.

# analyze-insights

Skill này đọc dữ liệu **đã có sẵn** trong `sublet_listings`/`sublet_events` và
tóm tắt lại thành insight cho Kien xem — không mở Facebook, không cần browser
tool nào. Đây **không phải** pipeline `intent-analyze` chính thức mô tả trong
`docs/intent-logic.md` (kind/subtype/poster_type/confidence/scam_score theo
rule đầy đủ, 12 test case) — pipeline đó vẫn ngoài active scope và sở hữu các
cột đó trên `sublet_listings`. `analyze-insights` chỉ đưa ra **tín hiệu thô,
tham khảo**, không phải quyết định cuối, và không bao giờ ghi vào
`sublet_listings.kind`, `.subtype`, `.poster_type`, `.confidence`,
`.scam_score`, `.scam_flags`, `.deal_score`, `.status`, `.analyzed_at` — để
tránh xung đột với pipeline chính thức khi nó được bật sau này.

Phần storage/provenance/normalization/QA/behavior aggregates dùng chung thuộc
`data-engineer`. Khi cần các việc đó, đọc hoặc gọi skill này; đừng nhân bản
logic data engineering thành một heuristic mới trong `analyze-insights`.

## Spec

- **Trigger:** Kien gọi tay, thường sau khi `sublet-scrape-14-groups` capture
  xong một phần; không phụ thuộc kết quả `validate-permalink` và không cần
  chờ link đã validated — insight chỉ cần `raw_text`.
- **Đọc:** `sublet_listings` (id, raw_text, text_hash, poster_name, group_key,
  seen_at, link_validation_status), `sublet_events` (event `context_captured`
  cho metadata bổ sung nếu cần, và event `insight_reviewed` cũ để biết listing
  nào đã xử lý).
- **Ghi:** `sublet_events(event='insight_reviewed')` — một dòng mỗi listing xử
  lý lần đầu; `sublet_inbox(level='info')` — snapshot tổng hợp mỗi lần có dữ
  liệu mới; `sublet_metrics(workflow='analyze', metric='insight_*')` — số
  đếm, upsert theo ngày; `sublet_ops_state(key='analyze_insights_state')` —
  cursor run gần nhất.
- **Không ghi:** không đụng cột phân loại chính thức trên `sublet_listings`
  (xem trên); không tạo `sublet_seekers`/`sublet_matches`/`sublet_messages`;
  không gửi gì ra ngoài Facebook/kênh khác.
- **Metrics tạo ra:** `insight_listings_total`, `insight_new_this_run`,
  `insight_offering_like`, `insight_seeking_like`, `insight_other_like`,
  `insight_duplicate_clusters`, `insight_duplicate_listings`,
  `insight_risk_flagged`, `insight_unique_posters`, `insight_queue_remaining`
  (luôn 0 sau khi chạy xong vì mọi listing đều được ghi `insight_reviewed`),
  `insight_pricing_tagged`, `insight_no_pricing`.
- **Kết quả:** một bản tóm tắt trong `sublet_inbox` + số liệu trong
  `sublet_metrics`; không claim đây là phân loại chính thức, không tự động
  chuyển `listings.status`.

## Không bao giờ

- Không mở/đọc Facebook dưới bất kỳ hình thức nào — input đã nằm sẵn trong DB,
  không cần browser, không cần Claude in Chrome/Codex panel.
- Không ghi `kind`/`subtype`/`poster_type`/`confidence`/`scam_score`/
  `scam_flags`/`deal_score`/`status`/`analyzed_at` lên `sublet_listings`.
- Không tạo hay sửa `sublet_seekers`, `sublet_matches`, `sublet_messages`, và
  không đề xuất outreach cho listing cụ thể nào.
- Không coi việc actor không có post trong corpus, không có public activity,
  không có comment, hoặc thiếu profile link/field là bằng chứng phủ định. Các
  trường hợp này là `unknown`/`partial` và phải được giữ cho review hoặc lần
  capture sau; không gán `no_offering`, `no_seeking`, `inactive` hay
  `not_a_match`. `other_like` do thiếu evidence không phải negative intent.
- Không re-đọc/re-chấm một listing đã có event `insight_reviewed`, trừ khi
  Kien yêu cầu rõ ràng chạy lại (ví dụ raw_text được cập nhật, hoặc Kien gõ
  "rescan"/"phân tích lại"). Không tự động rescan chỉ vì heuristic đổi.
- Không claim "đã phân tích toàn bộ database" nếu còn listing chưa có
  `insight_reviewed` — luôn báo đúng số queue còn lại/đã xử lý.

## Hàng đợi "chưa insight" — cơ chế không phân tích lại

Trước khi xử lý, luôn query hàng đợi:

```sql
select l.id, l.poster_name, l.group_key, l.seen_at, l.text_hash,
       l.link_validation_status, l.raw_text
from sublet_listings l
where not exists (
  select 1 from sublet_events e
  where e.entity_type = 'listing'
    and e.entity_id = l.id
    and e.event = 'insight_reviewed'
)
order by l.seen_at, l.id;
```

Đây là nguồn sự thật duy nhất cho "đã insight hay chưa" — không dùng biến nhớ
tạm, không dùng ngày tháng ước lượng. Mỗi listing xử lý xong phải ghi event
`insight_reviewed` **ngay lập tức** (không đợi hết batch); nếu agent bị ngắt
giữa chừng, listing đó vẫn chưa có event nên vẫn nằm trong hàng đợi và được xử
lý lại an toàn ở lần sau — cùng nguyên tắc idempotent như `validate-permalink`.

Nếu Kien yêu cầu rescan, thêm điều kiện lọc theo `created_at` của event cũ
(chỉ rescan các listing có event trước một mốc thời gian Kien nêu ra), không
xoá event cũ — insight mới là bản bổ sung, `sublet_events` giữ append-only.

**Phần tổng hợp (duplicate cluster, đếm số) luôn tính lại trên toàn bộ dataset
hiện có**, không chỉ phần mới trong hàng đợi — vì một listing mới có thể trùng
với listing cũ đã review rồi. Bước này thuần SQL (group theo `text_hash`/
fingerprint chuẩn hoá), không cần đọc lại `raw_text` bằng agent/LLM, nên không
vi phạm nguyên tắc "không phân tích lại" — nguyên tắc đó áp dụng cho bước tốn
công đọc-hiểu từng bài, không áp dụng cho phép đếm SQL rẻ tiền.

## Bước 1 — heuristic score cho từng listing trong hàng đợi

Tính điểm bằng quy tắc (không cần agent đọc kỹ mọi bài; chỉ bài borderline mới
cần đọc tay ở Bước 2). Case-insensitive, khớp trên `raw_text` gốc.

**offering_score +1 mỗi khi khớp:**
- Có giá tiền dạng `€` + số, hoặc `eur`/`euro` kèm số.
- Cụm offering EN: `for rent`, `to rent`, `available from`, `available now`,
  `room available`, `apartment available`, `sublet`, `subletting`,
  `renting out`.
- Cụm offering NL: `te huur`, `aangeboden`, `kamer vrij`, `komt vrij`,
  `vrijgekomen`.
- Mô tả tài sản ở ngôi thứ ba: diện tích (`m2`/`m²`), `furnished`/
  `gemeubileerd`, tên khu vực + postcode dạng `\d{4}\s?[A-Z]{2}`.
- Có hướng dẫn liên hệ kiểu người bán: `dm for more info`, `contact:`,
  `viewing possible`.

**seeking_score +1 mỗi khi khớp:**
- Mở đầu ngôi thứ nhất: `i'm looking for`, `i am looking for`, `looking for a`,
  `we are looking for`, `we're looking for`, `searching for`, `op zoek naar`,
  `ik zoek`, `wij zoeken`, `zoeken naar`.
- Tự giới thiệu bản thân như người apply: tuổi + quốc tịch/nghề nghiệp trong
  câu đầu (`i'm <tên>, <số> years old` / `, from <nước>`), hoặc
  `student`/`intern`/`relocating`/`moving to amsterdam`.
- Ngân sách nêu như giới hạn trên: `budget:`, `up to €`, `max €`.
- Câu hỏi/đề nghị người khác liên hệ mình: `if you have anything`,
  `please dm me`, `let me know if`.

**other_signal (không cộng điểm 2 bên trên, đánh dấu riêng):**
- Không có từ nào liên quan nhà ở (`room`/`apartment`/`studio`/`house`/
  `kamer`/`woning`/`appartement`) trong toàn bộ text → có thể là quảng cáo
  dịch vụ khác hoặc cảnh báo cộng đồng, không phải listing nhà.
- Có `scam`/`warning`/`beware`/`oplichting` gần đầu câu → cảnh báo cộng đồng,
  không phải một listing — đánh dấu `community_warning`, không tính offering
  hay seeking.

**Phân loại thô (`insight_kind_guess`):**
- `offering_score > seeking_score` và `offering_score ≥ 1` → `offering_like`.
- `seeking_score > offering_score` và `seeking_score ≥ 1` → `seeking_like`.
- Cả hai đều 0, hoặc có `community_warning`, hoặc không có từ khoá nhà ở →
  `other_like`.
- `offering_score == seeking_score` và cả hai ≥ 1 → **borderline**, chuyển
  Bước 2.

## Bước 2 — đọc tay cho borderline

Chỉ những listing borderline (điểm hoà) hoặc `raw_text` bị cắt (`truncated`
trong context event, hoặc kết thúc bằng "[visible text truncated after this
point]") mới cần agent đọc kỹ toàn văn để quyết `insight_kind_guess`. Ghi rõ
`insight_method='manual_read'` cho các listing này thay vì `'heuristic'`, để
sau này biết mức tin cậy khác nhau.

## Duplicate/repost detection (SQL, không tốn LLM)

1. **Exact duplicate:** group theo `text_hash`. Mọi nhóm có `count(*) > 1` là
   một cluster; mọi id trong cluster (trừ id có `seen_at` sớm nhất) được đánh
   dấu `duplicate_of=<id sớm nhất>`.
2. **Near-duplicate cùng người đăng:** với các listing không trùng
   `text_hash`, so `poster_name` giống nhau và bản rút gọn của `raw_text`
   (lowercase, bỏ khoảng trắng thừa, bỏ 200 ký tự đầu để so) giống nhau ≥95%
   theo so khớp chuỗi đơn giản (hoặc giống hệt sau khi lowercase) → cùng
   cluster, đánh dấu `repost_same_poster=true`. Đây thường là 1 bài bị capture
   2 lần qua 2 `source_url` khác nhau (permalink trực tiếp và share URL) — một
   giới hạn dedupe đã biết của capture hybrid, không phải lỗi phân tích.
3. **Cross-poster giống hệt nhau:** hai `poster_name` khác nhau nhưng
   `raw_text` chuẩn hoá giống nhau (hoặc giống ≥95%) → tín hiệu mạng lưới
   nhiều tài khoản, đánh dấu `risk_flag='duplicate_across_posters'` (xem thêm
   bên dưới), **không** gộp chung `duplicate_of` vì đây là 2 identity khác
   nhau, không phải cùng 1 bài bị capture lặp.

## Risk/scam heuristic flags (tham khảo, không phải scam_score chính thức)

Ghi vào `insight_risk_flags` (mảng text), mỗi flag độc lập, có thể nhiều flag:

- `unusually_low_rent`: trích số sau `€`/`eur` gần từ rent/huurprijs/month; nếu
  <€500 và mô tả là phòng/căn hộ tại Amsterdam → flag (ngưỡng tham khảo, không
  phải kết luận scam).
- `off_platform_redirect`: text chứa `wa.me/`, `t.me/`, hoặc số điện thoại +
  yêu cầu nhắn ngay lập tức ra kênh khác trước khi trao đổi gì trên Facebook.
- `prepay_before_viewing`: cụm kiểu `pay before viewing`/`reservation fee`/
  `deposit before`/`key is with me`/`i'm abroad` — theo đúng pattern cảnh báo
  scam thật đã thấy trong corpus (ví dụ post #5 trong run 2026-09-15).
- `duplicate_across_posters`: xem mục trên.
- `generic_low_detail_listing`: `offering_like` nhưng không có số tiền cụ thể,
  không có khu vực/postcode, không có ngày available — chỉ có câu chung chung
  kiểu "Comfortable rentals. Great locations. Easy move-in."
- `community_warning`: xem Bước 1 — không phải rủi ro của chính bài đó, mà là
  cảnh báo Kien nên đọc.

Không tự động gán những flag này vào `sublet_listings.scam_score` — chỉ đưa
vào payload event và snapshot để Kien tham khảo; scam scoring chính thức có
bảng cộng/trừ riêng trong `docs/intent-logic.md` khi pipeline đó được bật.

## DB write contract

### Event mỗi listing (bắt buộc ngay sau khi xử lý xong 1 listing)

```json
{
  "insight_contract_version": 1,
  "insight_method": "heuristic",
  "insight_kind_guess": "seeking_like",
  "offering_score": 0,
  "seeking_score": 3,
  "risk_flags": [],
  "duplicate_of": null,
  "repost_same_poster": false,
  "pricing_tag": "no_pricing",
  "price_or_budget_eur": null,
  "run_at": "2026-09-16T09:00:00+02:00"
}
```

`pricing_tag`/`price_or_budget_eur` là 2 field từ Bước 1.5 — bắt buộc có mặt
trên mọi event mới, kể cả khi `no_pricing`/`null`. Event cũ trước khi thêm 2
field này không bị sửa lại (append-only); chỉ backfill nếu Kien yêu cầu rõ
ràng.

`entity_type='listing'`, `entity_id=<listing id>`, `event='insight_reviewed'`,
`source_url=<listing.source_url>`.

**Lưu ý lịch sử (2026-09-16):** 95 event `insight_reviewed` ghi trong ngày
2026-09-16 có thêm 4 field `start_date`/`start_date_label`/`end_date`/
`duration_label` do đặt sai chỗ lúc đầu (đã sửa, xem mục "Bước 1.6 đã chuyển
sang data-engineer" phía trên). Không xoá/sửa các event cũ đó
(append-only) — 4 field thừa trong payload cũ vô hại, chỉ là dữ liệu trùng
lặp; nguồn đúng cho các field này từ giờ là event `listing_normalized` do
`data-engineer` ghi, đọc qua `sublet_v_listing_profile`.

### Snapshot tổng hợp — chỉ ghi khi có ít nhất 1 listing mới trong run này

Tránh spam `sublet_inbox` khi hàng đợi rỗng (không có gì mới để báo). Lưu
thẳng **report đầy đủ** vào `sublet_inbox.body` — không tách ra file local +
chỉ lưu path/link vào DB. Lý do: Postgres `text` chịu được tới 1GB, một report
cho vài chục–vài trăm listing chỉ tốn vài–vài chục KB, không đáng lo "nặng
DB"; còn file local chỉ tồn tại trên máy đang chạy agent, Kien không đọc được
từ nơi khác, dễ lệch nếu file bị xoá/di chuyển, và đi ngược nguyên tắc
`CLAUDE.md` "mọi thứ cần Kien biết → `sublet_inbox`; Kien đọc trực tiếp trong
DB". Không cần bảng/asset store riêng cho report này.

Format `sublet_inbox`:

- `level='info'`
- `title='Insight snapshot: <n> listing mới (<group_name hoặc "nhiều group">)'`
- `body` gồm đầy đủ:
  1. Tổng số đã review, breakdown `offering_like`/`seeking_like`/`other_like`.
  2. Danh sách cụm trùng lặp: mỗi cụm 1 dòng — id gốc, số bản trùng, poster,
     có phải cross-poster hay không.
  3. Danh sách listing có `risk_flags` — id, poster, flag(s), trích 1 câu
     ngắn (≤120 ký tự) từ `raw_text` làm bằng chứng, không trích toàn văn.
  4. Số poster khác nhau, queue còn lại (nên là 0 sau khi chạy xong).
- `entity_type='insight_run'`, `entity_id=null`.
- Nếu batch quá lớn khiến `body` vượt ~200KB (mốc tham khảo, không phải giới
  hạn cứng của Postgres), cắt bớt: giữ toàn bộ số đếm/breakdown, chỉ liệt kê
  chi tiết cho risk-flag và cụm trùng lặp **lớn nhất** (ví dụ top 30), ghi rõ
  "còn N mục khác, xem đầy đủ qua `select * from sublet_events where
  event='insight_reviewed' and created_at >= <run_at>`" thay vì dump hết. Đây
  chỉ là van an toàn cho corpus rất lớn, không áp dụng ở quy mô hiện tại
  (vài chục–vài trăm listing/run).

### Metrics — upsert theo ngày, dùng đúng constraint `(day, workflow, metric)`

```sql
insert into sublet_metrics (day, workflow, metric, value, meta)
values (current_date, 'analyze', 'insight_offering_like', 12, '{"group_key":"..."}')
on conflict (day, workflow, metric)
do update set value = excluded.value, meta = excluded.meta, computed_at = now();
```

Ghi tất cả metric liệt kê ở khối Spec theo cùng pattern upsert này; `value`
luôn là snapshot tại thời điểm chạy (không cộng dồn thủ công), vì query đếm
lại từ DB mỗi lần là nguồn sự thật.

### Cursor `sublet_ops_state.key='analyze_insights_state'`

```json
{
  "last_run_at": "2026-09-16T09:00:00+02:00",
  "processed_this_run": 12,
  "total_reviewed": 57,
  "queue_remaining": 0
}
```

## Completion và edge cases

- Hàng đợi rỗng ngay từ đầu (mọi listing đã có `insight_reviewed`) → không ghi
  `sublet_inbox` mới, chỉ báo Kien trong chat số liệu hiện có (đọc từ
  `sublet_metrics`/cursor cũ), không chạy lại phân tích.
- `raw_text` rỗng hoặc chỉ có emoji/link ảnh → `insight_kind_guess='other_like'`,
  `insight_method='heuristic'`, không đoán thêm.
- Listing đã bị đánh `duplicate_of` ở lần chạy trước nhưng lần này có thêm bản
  trùng mới → cập nhật cluster bằng cách ghi thêm `insight_reviewed` cho bản
  mới (không sửa event cũ, append-only), snapshot lần này nêu cluster đã lớn
  hơn.
- DB lỗi (RPC/HTTP) giữa lúc ghi: retry đúng một lần sau 5 giây theo hard rule
  chung; vẫn lỗi thì dừng, giữ `analyze_insights_state.status` ở giá trị cũ,
  không claim đã ghi xong, báo warning cho Kien.
- Không bao giờ dùng kết quả skill này để tự động chuyển `listings.status`,
  tạo seeker, hay soạn draft — đó là việc của pipeline `intent-analyze` +
  `sublet-match` + `sublet-draft` khi được kích hoạt lại, ngoài scope hiện tại.
