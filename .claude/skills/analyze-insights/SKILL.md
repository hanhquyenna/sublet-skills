---
name: analyze-insights
description: "Read-only insight pass over already-captured Facebook raw listings in Supabase: coarse offering/seeking/other split, duplicate/repost cluster detection, and risk/scam pattern flags, summarized into sublet_inbox + sublet_metrics. Never re-reads a listing already marked insight_reviewed. No Facebook/browser access — DB only. Use with /analyze-insights."
---

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
  lý lần đầu; `sublet_insight_matches` — ứng viên seeker↔offering (xem "Bước 3 —
  matching candidates" bên dưới); `sublet_inbox(level='info')` — snapshot tổng
  hợp mỗi lần có dữ liệu mới; `sublet_metrics(workflow='analyze',
  metric='insight_*')` — số đếm, upsert theo ngày;
  `sublet_ops_state(key='analyze_insights_state')` — cursor run gần nhất.
- **Không ghi:** không đụng cột phân loại chính thức trên `sublet_listings`
  (xem trên); không tạo `sublet_seekers`/`sublet_matches`/`sublet_messages`
  (khác `sublet_insight_matches` — bảng riêng, chỉ là tín hiệu tham khảo, xem
  dưới); không gửi gì ra ngoài Facebook/kênh khác.
- **Metrics tạo ra:** `insight_listings_total`, `insight_new_this_run`,
  `insight_offering_like`, `insight_seeking_like`, `insight_other_like`,
  `insight_duplicate_clusters`, `insight_duplicate_listings`,
  `insight_risk_flagged`, `insight_unique_posters`, `insight_queue_remaining`
  (luôn 0 sau khi chạy xong vì mọi listing đều được ghi `insight_reviewed`),
  `insight_match_candidates_high/medium/low/weak`, `insight_pricing_tagged`,
  `insight_no_pricing`. The `weak` metric is required; do not collapse it into
  `low` or omit it from the snapshot.
- **Kết quả:** một bản tóm tắt trong `sublet_inbox` + số liệu trong
  `sublet_metrics`; không claim đây là phân loại chính thức, không tự động
  chuyển `listings.status`.

## Không bao giờ

- Không mở/đọc Facebook dưới bất kỳ hình thức nào — input đã nằm sẵn trong DB,
  không cần browser, không cần Claude in Chrome/Codex panel.
- Không ghi `kind`/`subtype`/`poster_type`/`confidence`/`scam_score`/
  `scam_flags`/`deal_score`/`status`/`analyzed_at` lên `sublet_listings`.
- Không tạo hay sửa `sublet_seekers`, `sublet_matches`, `sublet_messages`, và
  không đề xuất outreach cho listing cụ thể nào. `sublet_insight_matches` là
  bảng riêng biệt (xem "Bước 3") — không bao giờ ghi cùng ý nghĩa/quy trình với
  `sublet_matches`.
- Không tính match cho listing `link_validation_status<>'validated'` hoặc nằm
  trong `sublet_v_link_needs_reverification` (validated giả, chưa mở link
  thật) — xem "Bước 3".
- Không coi việc actor không có post trong corpus, không có public activity,
  không có comment, hoặc thiếu profile link/field là bằng chứng phủ định. Các
  trường hợp này là `unknown`/`partial` và phải được giữ cho review hoặc lần
  capture sau; không gán `no_offering`, `no_seeking`, `inactive` hay
  `not_a_match`. `other_like` do thiếu evidence không phải negative intent.
- Với anonymous poster, chỉ tính insight match khi context có
  `anonymous_poster=true`, `anonymous_access_ready=true` và permalink bài viết
  đã validate. Nếu thiếu permalink usable, vẫn có thể thống kê raw insight
  tổng quan nhưng không tạo candidate match cho listing đó.
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

## Bước 3 — matching candidates (validated-only)

> **Đổi nguồn dữ liệu đầu vào (2026-09-17, Kien duyệt kiến trúc):** trước đây
> Bước 3 lấy `kind_guess`/khu vực/giá từ `insight_kind_guess` trong event
> `insight_reviewed` — heuristic riêng của chính `analyze-insights` (Bước 1/2
> ở trên), chỉ chạy thủ công và mới xử lý 198 event/~49 listing. Trong khi đó
> pipeline chính thức `intent-analyze` (xem `docs/intent-logic.md`) đã phân
> loại **882 listing** thẳng vào `sublet_listings.kind`/`.area`/`.rent_eur`
> theo rule đầy đủ hơn nhiều — nhưng Bước 3 cũ không bao giờ đọc các cột đó,
> nên gần như toàn bộ dữ liệu đã phân loại chính thức bị bỏ phí, matching chỉ
> chạy trên phần nhỏ. Kien chọn phương án hợp nhất 2 pipeline (thay vì chạy
> lại Bước 1/2 riêng cho phần backlog): Bước 3 giờ đọc trực tiếp
> `sublet_listings.kind`/`.area`/`.rent_eur` (cột của `intent-analyze`) thay
> vì `insight_kind_guess`/`insight_reviewed`. `kind='offering'` tương đương
> `insight_kind_guess='offering_like'` cũ, `kind='seeking'` tương đương
> `seeking_like`, `kind='other'` tương đương `other_like` (vẫn loại khỏi pool,
> vẫn không coi là negative intent). `canonical_id` (cột `sublet_listings`,
> "cùng 1 listing đăng ở nhiều group → trỏ về bản đầu") thay cho
> `duplicate_of` cũ trong event `insight_reviewed` — cùng ý nghĩa, chỉ khác
> nơi lưu. `sublet_listings.area`/`.rent_eur` đã chuẩn hoá theo
> `docs/intent-logic.md` §11 (area map về danh sách chuẩn, `rent_eur` với
> `kind='seeking'` chính là ngân sách tối đa — đúng ý nghĩa
> `price_or_budget_eur` cũ) nên dùng thẳng, không cần trích lại từ `raw_text`.
> Vì đổi **nguồn input** của chấm điểm, đây là thay đổi buộc **tính lại toàn
> bộ** (xem "Ghi `sublet_insight_matches`" bên dưới) — không phải chạy tiếp
> incremental trên 545 dòng cũ. Bước 1.5 (`pricing_tag`/`price_or_budget_eur`)
> vẫn giữ nguyên cho mục đích riêng của nó (đọc-only, không phân biệt
> offering/seeking chính thức), nhưng Bước 3 không còn phụ thuộc nó nữa.

Tính lại ứng viên khớp seeker↔offering trên **toàn bộ** listing đã
`intent-analyze` phân loại (không chỉ phần mới) mỗi lần chạy Bước 3. Đây vẫn
là tín hiệu tham khảo — **không phải** `sublet_matches` chính thức, không tạo
`sublet_seekers`, không tự outreach.

### Input: chỉ listing đã "sạch" theo cả 3 điều kiện

1. `link_validation_status='validated'` **và** không nằm trong
   `sublet_v_link_needs_reverification` (tức không phải
   `link_resolution_method='bulk_unverified_override'` — record được đánh dấu
   validated mà chưa từng mở link thật). Lý do: matching dựa trên nội dung bài;
   nếu bài chưa verify thật (có thể đã bị xoá/đổi/sai group) thì match dựa trên
   nó là vô nghĩa hoặc sai.
2. `sublet_listings.kind` là `offering` hoặc `seeking` (bỏ `other` chỉ khỏi
   phép ghép hiện tại, **không** coi là negative intent). Listing `kind is
   null` (chưa qua `intent-analyze`) hoặc `kind='other'` phải giữ trong
   unknown/review pool, không xoá hay đánh dấu không phù hợp.
3. **Không phải bản repost/duplicate** (nới rộng 2026-09-16, xem quyết định
   cross-group bên dưới): loại listing có `canonical_id` khác `null` — chỉ
   giữ lại bản gốc (id được các bản khác trỏ `canonical_id` tới) trong pool
   matching. Lý do: một người đăng cùng 1 bài ở nhiều group không phải N cơ
   hội khác nhau; nếu không lọc, bỏ giới hạn group ở bước dưới sẽ nhân bản 1
   match thật thành N match giả theo số group họ đăng. Trùng text nhưng khác
   `poster_name` (spam network khác identity) **không** bị loại ở đây; rủi ro
   của case đó là việc của `risk_flags` (`analyze-insights` Bước "Risk/scam
   heuristic"), không phải việc của bước lọc này.

```sql
select l.id, l.poster_name, l.source_url, l.seen_at, l.raw_text, l.group_key,
  l.kind, l.area, l.rent_eur, l.canonical_id
from sublet_listings l
where l.link_validation_status = 'validated'
  and l.id not in (select id from sublet_v_link_needs_reverification)
  and l.kind in ('offering', 'seeking')
  and l.canonical_id is null
```

**Không còn điều kiện `group_key = <group đang xử lý>`** — xem "Cross-group
matching" ngay dưới đây.

### Cross-group matching (đổi 2026-09-16 theo yêu cầu Kien)

Bước 3 **không còn giới hạn trong 1 group**. Lý do: seeker/offering là 2 bài
độc lập theo `listing_id`; người tìm nhà ở Amsterdam không quan tâm bài đăng ở
group Facebook nào, nên giới hạn cùng-group trước đây là quyết định tuỳ tiện
của thiết kế đầu, không phải rào cản dữ liệu thật. So khớp seeker × offering
trên **toàn bộ** danh sách đã lọc (mọi group), miễn qua được loại trừ cứng và
tín hiệu bên dưới. Đây không phải "identity resolution" — không cần gộp danh
tính người dùng nào cả, chỉ cần so từng cặp `listing_id` độc lập; xem thêm
`data-engineer/SKILL.md` mục "Per-user/entity normalized profile" về việc
data-engineer **không** xây bảng khách hàng riêng và tại sao đó không phải
điều kiện tiên quyết cho cross-group matching.

Điều kiện tiên quyết bắt buộc đi kèm: lọc duplicate/repost ở điều kiện 3 phía
trên phải chạy **trước khi** bỏ giới hạn group, nếu không 1 offering đăng lại
ở nhiều group sẽ tạo nhiều match giả cho cùng 1 seeker.

### Loại trừ cứng trước khi tính tín hiệu

- **Không bao giờ khớp một poster với chính họ.** Nếu `seeker.poster_name`
  trùng `offering.poster_name` (cùng người vừa đăng seeking vừa đăng offering,
  hoặc 2 bản capture trùng của cùng 1 post), bỏ qua cặp đó ngay, không tính
  điểm. Đây là điều kiện cứng theo yêu cầu Kien, áp dụng trước mọi tín hiệu
  khu vực/ngân sách/thời điểm bên dưới, và áp dụng xuyên group (so sánh
  `poster_name`, không so `group_key`).
- `seeker.id == offering.id` không thể xảy ra do đã lọc theo `kind` khác
  nhau, nhưng vẫn kiểm tra phòng hờ nếu logic lọc thay đổi sau này.
- Bản repost/duplicate (`canonical_id` khác null) đã bị loại khỏi pool ở bước
  Input trên; không cần lọc lại ở đây, nhưng nếu code thay đổi khiến bản
  duplicate lọt vào, áp dụng lại điều kiện đó trước khi tính điểm.

### Bước 1.5 — tag `pricing`/`no_pricing` (đi kèm classification, không phải skill riêng)

Ngay sau khi có `insight_kind_guess` cho một listing, trích thêm 2 field và ghi
cùng event `insight_reviewed` (không phải event riêng, không phải skill riêng
— đây vẫn là 1 bước rẻ tiền, thuần regex trên `raw_text` đã có sẵn trong DB,
không cần Facebook, không cần LLM đọc lại):

- `pricing_tag`: `'pricing'` nếu trích được ít nhất 1 số tiền EUR hợp lệ
  (200–5000, xem quy tắc trích bên dưới) trong `raw_text`; `'no_pricing'` nếu
  không có số nào. Tag này cho biết ngay listing nào **không thể** dùng tín
  hiệu ngân sách/giá ở Bước 3 (matching), tách bạch với `insight_kind_guess`
  (một listing có thể là `seeking_like` + `no_pricing`, nghĩa là seeker chưa
  nêu ngân sách — vẫn hợp lệ để match theo khu vực, chỉ không match được theo
  giá).
- `price_or_budget_eur`: số đã trích (ngân sách cao nhất với seeker, giá thấp
  nhất với offering), hoặc `null` nếu `no_pricing`.

Lý do tách thành tag rõ ràng thay vì để ẩn trong logic Bước 3: khi review lại
kết quả matching, đếm nhanh được bao nhiêu % listing có giá (`select
payload->>'pricing_tag', count(*) from sublet_events where
event='insight_reviewed' group by 1`) mà không cần chạy lại phép trích. Đây
**không phải** lý do để tách thành skill `/data-engineer` riêng — vẫn là 1
bước trong `analyze-insights`, dùng chung code trích số với Bước 3, không có
queue/cursor/spec riêng. Tách skill chỉ đáng làm nếu có ≥2 skill khác cần dùng
lại tag này độc lập với `analyze-insights`; hiện tại chưa có.

### Bước 1.6 đã chuyển sang `data-engineer` (sửa 2026-09-16, đặt sai chỗ lúc đầu)

Trích `start_date`/`end_date`/`duration_label` là **normalization** (parse
ngày/thời hạn từ text đã biết), không phải heuristic ngữ nghĩa
offering/seeking — thuộc ranh giới của `data-engineer` (mục "3. Normalize mà
không làm mất raw": *"timezone-aware ISO timestamp khi có absolute
timestamp"*), không phải `analyze-insights`. Xem chi tiết đầy đủ ở
`data-engineer/SKILL.md` mục "Normalize thời điểm bắt đầu/kết thúc/thời hạn
thuê". `analyze-insights` chỉ **đọc** 4 field đó (qua
`sublet_v_listing_profile`) làm input tham khảo cho Bước 3 khi cần, không tự
tính lại.

### Tín hiệu so khớp (mỗi seeker × mỗi offering, xuyên toàn bộ group)

Một offering có thể khớp với nhiều seeker, và một seeker có thể khớp với
nhiều offering — đây là hành vi **đúng, không phải bug**. Không giới hạn
"mỗi seeker chỉ 1 offering tốt nhất"; Kien tự lọc/chọn từ danh sách đầy đủ.

> **Lịch sử quyết định (đêm 2026-09-16, đừng đảo ngược mà không hỏi lại
> Kien):** bản đầu của Bước 3 yêu cầu **bắt buộc** có tín hiệu khu vực HOẶC
> ngân sách mới được tạo candidate — Kien chỉ ra đây là lỗi thiết kế thật:
> "if they not disclosed area, doesn't mean they don't match". Một phiên
> khác sau đó thử sửa bằng cách bỏ hẳn `seen_at` khỏi tín hiệu/reasons; Kien
> từ chối hướng đó ("không được"). Thiết kế **chốt cuối cùng** là bên dưới:
> `seen_at` (cửa sổ 7 ngày) là **điều kiện chính** để tạo candidate — không
> phải khu vực hay ngân sách. Khu vực/ngân sách chỉ **loại** khi có bằng
> chứng mâu thuẫn thật (cả hai bên nêu rõ và lệch nhau), không bao giờ loại
> vì thiếu dữ liệu.

- **Thời điểm (`seen_at`) — điều kiện chính:** hai bên phải cách nhau
  **≤ 7 ngày** (Kien gọi là "a week back", chốt sau khi cân nhắc 3/14/7 ngày)
  mới được xét làm candidate. Đây là cổng chính, không phải tín hiệu phụ như
  bản thiết kế cũ — luôn xuất hiện trong `reasons` (vd.
  `"seen_at cách nhau 1 ngày (trong cửa sổ 7 ngày)"`), không bị coi là kém
  quan trọng hơn khu vực/ngân sách.
- **Khu vực:** dùng `sublet_listings.area` (đã chuẩn hoá về danh sách khu
  chuẩn bởi `intent-analyze`, xem `docs/intent-logic.md` §11 — đổi 2026-09-17
  từ việc tự trích tên khu trong `raw_text`; cùng ý nghĩa, chỉ khác nguồn:
  giờ đọc cột đã chuẩn hoá sẵn thay vì tự regex lại). Trùng khu hoặc khu liền
  kề theo bảng cố định = tín hiệu dương (+2), cộng vào `reasons`. Một bên
  không có `area` (null) = **không loại, không suy diễn**, chỉ đơn giản không
  có tín hiệu dương này. Cả hai bên có `area` rõ ràng mà không trùng/không
  liền kề = loại thẳng (đây là bằng chứng mâu thuẫn thật, không phải thiếu dữ
  liệu).
- **Ngân sách/giá:** dùng `sublet_listings.rent_eur` (đổi 2026-09-17 từ
  `pricing_tag`/`price_or_budget_eur` của Bước 1.5 — cùng ý nghĩa, nguồn
  chính xác hơn: `intent-analyze` đã chuẩn hoá theo `docs/intent-logic.md`
  §11, và với `kind='seeking'` thì `rent_eur` chính là ngân sách tối đa, đúng
  ý nghĩa cũ của `price_or_budget_eur` cho seeker). Cả hai bên có số **và**
  `0.5 ≤ (giá offering / ngân sách seeker) ≤ 1.1` = tín hiệu dương (+2). Biên
  dưới 0.5 **vẫn giữ** (xem "Edge case đã phát hiện" — case
  Esteban/Samrawit), không phải điều Kien bảo bỏ; điều Kien từ chối là việc
  bỏ `seen_at`, không phải biên ngân sách. Một bên không có `rent_eur` (null)
  = không loại, không suy diễn. Cả hai có `rent_eur` mà tỷ lệ ngoài [0.5, 1.1]
  = loại thẳng.

### Thang điểm `score` — không có sàn tối thiểu, `seen_at` luôn +1

| Tín hiệu | Điểm | Điều kiện |
|---|---:|---|
| Vượt qua cổng `seen_at` ≤7 ngày, không bị loại bởi khu vực/ngân sách | +1 | luôn cộng — đây là điều kiện để candidate tồn tại, không phải bonus |
| Khu vực trùng/liền kề | +2 | bonus, không bắt buộc |
| Ngân sách/giá trong khoảng [0.5, 1.1] | +2 | bonus, không bắt buộc |

Tối đa = 5 (cả ba). Không có sàn điểm tối thiểu để lưu — mọi cặp qua được cổng
`seen_at` và không bị 2 loại trừ cứng (khu vực/ngân sách mâu thuẫn thật, hoặc
cùng poster) đều được lưu, kể cả khi chỉ có điểm 1 (`confidence='weak'`).
Đây là chủ đích: thà show nhiều để Kien tự lọc, còn hơn heuristic tự ý giấu
một match thật chỉ vì trích được ít dữ liệu.

### Xếp hạng confidence

- `high`: có cả khu vực **và** ngân sách khớp (điểm 5).
- `medium`: chỉ khu vực khớp (điểm 3).
- `low`: chỉ ngân sách khớp (điểm 3).
- `weak`: chỉ qua được cổng `seen_at`, không có bằng chứng khu vực lẫn ngân
  sách (điểm 1) — vẫn là candidate hợp lệ, không phải nhiễu; gắn nhãn `weak`
  để Kien biết đây là "chưa loại được, chưa có bằng chứng dương" chứ không
  phải "đã xác nhận yếu".

### Ghi `sublet_insight_matches` (bảng riêng, KHÔNG phải `sublet_matches`)

```sql
insert into sublet_insight_matches
  (seeker_listing_id, offering_listing_id, confidence, score, reasons,
   seeker_budget_eur, offering_price_eur, seeker_areas, offering_areas)
values (...)
on conflict (seeker_listing_id, offering_listing_id) do nothing;
```

`on conflict do nothing` giữ idempotent cho **rerun thường** (có listing mới,
logic tính điểm không đổi): chạy lại không tạo trùng cặp, không cần xoá gì.

**Ngoại lệ — khi chính logic tính điểm/tín hiệu thay đổi** (vd. sửa ngưỡng,
thêm/bớt tín hiệu, như case biên dưới 0.5 ở trên): `on conflict do nothing`
sẽ giữ lại các cặp cũ sai theo logic cũ mà không xoá, vì cặp (seeker,
offering) không đổi — chỉ điểm/lý do đổi. Trường hợp này phải
`delete from sublet_insight_matches where id > 0` (RPC từ chối `delete`
không có `where`) rồi tính và insert lại **toàn bộ** theo logic mới, không chỉ
phần chênh lệch. Nêu rõ trong `sublet_inbox`/chat khi làm việc này là
"tính lại toàn bộ do sửa logic", không phải "insight mới".

Đọc lại toàn bộ qua view `sublet_v_insight_matches_report` (join sẵn
poster/URL 2 bên, sort theo confidence rồi score) khi cần dựng báo cáo.

### Báo cáo cho Kien

Khi Kien yêu cầu "làm báo cáo"/"flag ra bảng data": dựng từ
`sublet_v_insight_matches_report`, cột tối thiểu — ngày chạy, seeker (tên +
link `source_url`), offering (tên + link `source_url`), nội dung raw của hai
bài nếu có trong view/query, lý do khớp (`reasons`), score và confidence.
Phải hiển thị đủ cả bốn tier `high`, `medium`, `low`, `weak`; không được bỏ
`weak` chỉ vì tier này không có evidence khu vực/ngân sách. Có thể xuất Artifact
(bảng HTML) để Kien xem/chia sẻ dễ hơn dump JSON; nêu rõ đây là tín hiệu
đọc-only, không phải danh sách đã xác nhận outreach. Nhóm `high` lên đầu; nếu
`high` rỗng, nói thẳng thay vì im lặng bỏ qua tầng đó (dữ liệu 14 ngày/1 group
ban đầu có thể chưa đủ để có cặp `high`).

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
