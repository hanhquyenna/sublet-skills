---
name: sublet-scrape-14-groups
description: "Scrape raw data from up to 14 joined Facebook groups, one group at a time, for the latest 14 calendar days. Resume from the database, deduplicate, checkpoint after every batch, and finish each group before moving on. Use with /sublet-scrape-14-groups."
---

# sublet-scrape-14-groups

Đây là skill sublet duy nhất để scrape. `information` là skill duy nhất để
khôi phục context/onboarding. Skill này tự chứa toàn bộ capture workflow; không
phụ thuộc `sublet-scan`, `sublet-backfill`, `sublet-worker` hay skill sublet nào
khác.

## Mục tiêu và thứ tự

- Chọn tối đa 14 group đã `joined=true`, loại group có
  `allows_sublet='no'`, sắp theo `posts_per_day` mới nhất giảm dần.
- Xử lý đúng **một group tại một thời điểm**. Không mở 14 group song song và
  không chuyển group khi group hiện tại chưa complete.
- Với mỗi group, đọc feed chronological từ mới tới cũ trong **14 ngày lịch**
  theo timezone `Europe/Amsterdam`.
- Capture-only: lưu raw, chưa phân loại offering/seeking/scam và chưa match hay
  outreach. Chỉ chạy phân tích khi người vận hành yêu cầu sau khi scrape xong.
  Link được thu thập trước; khả năng truy cập/permalink được kiểm tra tuần tự
  bởi `validate-permalink` sau capture.
- Routine flow không cần hỏi lại; chỉ dừng khi gặp blocker an toàn, DB lỗi,
  Facebook login/checkpoint/captcha/unusual activity, hoặc dữ liệu không thể
  xác minh.

## Quyền và browser hard rule

- Chỉ đọc Facebook bằng **visible Chrome browser-panel automation có UI của
  host**, trong session người dùng đã login thủ công; ưu tiên DOM/accessibility
  tree của panel (Codex: ChatGPT in-app browser panel; Claude Code: Claude in
  Chrome; agent khác: Chrome-panel adapter tương đương).
- Không dùng script scraper, CLI, web-fetch/HTTP/API, Selenium, headless
  browser, cookie, browser session khác hoặc raw page dump để đọc Facebook.
  Script chỉ được dùng cho DB/provenance, không điều khiển Facebook.
- Không join, submit membership form, bật notification, post, comment, like,
  DM, send, donate hoặc tương tác profile.
- Khi thấy login/checkpoint/captcha/“unusual activity” hoặc Facebook yêu cầu
  verification: dừng ngay, ghi stop/incomplete; không retry trong 24 giờ.
- Giữ page-load budget hiện hành: tối đa 4 page load mỗi run và không vượt daily
  volume gate; scroll phải có khoảng chờ human pace nhưng không dùng delay để
  vượt rate limit.

## Batch state và resume

Lưu state vào `sublet_ops_state` key `scrape_14_groups_batch`:

```json
{
  "batch_id": "2026-09-15T22:00:00+02:00",
  "window_days": 14,
  "group_keys": [],
  "current_index": 0,
  "current_group": null,
  "completed": [],
  "blocked": [],
  "status": "running"
}
```

Trước khi mở browser cho `current_group`, kiểm tra DB:

1. Run `sublet_scan_runs` mới nhất có `group_key` và `finished_at is null`.
   Đọc `cursor` JSON: `window_days`, `last_verified_post_at`,
   `last_source_url`, `posts_verified`, `unresolved_cards`, `phase`.
2. Nếu không có run mở, đọc metric mới nhất và `max(posted_at)` của các listing
   có timestamp tuyệt đối. Đọc `max(seen_at)` chỉ để biết lần DB quan sát gần
   nhất; **không** dùng `seen_at` làm thời điểm bài đăng.
3. Nếu timestamp post là `null`, resume bằng verified `source_url`/cursor.
   Không reset về đầu chỉ vì prompt/browser bị dừng hoặc DB vừa hoạt động lại.
4. Nếu group đã có `posts_14d_complete=true`, ghi group vào `completed` và bỏ
   qua; không scrape lại.

## Capture từng group

1. Tạo hoặc tiếp tục `sublet_scan_runs(mode='group_page', group_key=<key>)`.
2. Mở URL group với sort chronological trong panel. Đọc từng card từ mới tới
   cũ, expand visible collapse khi có thể, scroll theo chunk time-box. Dùng
   cấu trúc DOM/a11y đang hiển thị trong panel để tách từng card và lấy poster,
   timestamp, text, media, counters và link evidence trước khi chuyển text sang
   bất kỳ bước xử lý nào; không dùng LLM để phát hiện ranh giới card và không
   đọc raw page dump.
3. Capture không mở link để resolve. Với mỗi card, lấy direct permalink nếu
   DOM/a11y expose; nếu không thì dùng đúng post card's **Chia sẻ → Sao chép
   liên kết** trong panel. Cả hai đều là link evidence đủ để lưu raw listing.
   Giữ nguyên URL Facebook đã copy trong `source_url`; không suy ra ID từ share
   token, media URL, tracking parameter, profile commenter hoặc photo ID.
   Gán `link_validation_status='unvalidated'` cho listing mới; `post_id` và
   canonical URL chỉ điền sau khi `validate-permalink` mở link và xác nhận đúng
   bài. Comment permalink có parent path `/posts/<id>/` vẫn là evidence; lưu
   parent URL trong context nhưng không cần mở thêm detail trong capture pass.
   Nếu cả direct permalink và Facebook copy-link đều không lấy được, **không bỏ
   card**: lưu raw card trong `sublet_events(event='capture_unresolved',
   entity_type='fb_card', entity_id=null, source_url=<group_feed_url>)` với
   poster, timestamp label, media/counters, `card_fingerprint`,
   `missing_fields` và `unresolved_reason='no_link_evidence'`. Event này giữ
   dữ liệu để retry capture; validator chỉ xử lý listing có `source_url`, không
   đánh dấu card không có URL là `inaccessible`.

   **Cấm bỏ qua bước lấy link để ưu tiên tốc độ (phát hiện 2026-09-16) —
   giờ chặn cứng ở tầng DB, không chỉ rule bằng lời.** Một phiên trước đã tự
   ý gán `unresolved_reason='link_not_chased_speed_priority'` (và cả
   `reason=null`, hoàn toàn không ghi) cho **423 card trên 7/8 group đã xử
   lý** (group 4→8: 100% card unresolved, 0% ra được listing thật) mà **chưa
   từng thử** direct permalink lẫn Share→Copy link. Hệ quả: hàng trăm bài
   nhà ở thật (không phải bot/spam) bị kẹt vĩnh viễn không có `source_url`,
   không bao giờ vào được `sublet_listings`, không bao giờ tới
   `analyze-insights`/`outreach-prep`. Rule bằng lời không đủ — agent có thể
   lờ đi dưới áp lực tốc độ — nên `db/schema.sql` đã thêm
   `check constraint capture_unresolved_reason_check`: Postgres **tự chối
   insert** nếu `event='capture_unresolved'` mà `unresolved_reason` khác
   đúng chuỗi `'no_link_evidence'` (kể cả `null`). Không tự tạo giá trị mới,
   không lấy lý do "ưu tiên tốc độ"/"page-load budget"/hiệu suất để bỏ qua
   bước thử lấy link cho **mỗi** card có nội dung nhà ở rõ ràng — giờ dù có
   thử cũng bị DB chặn thẳng, không chỉ là vi phạm rule. Nếu cần tăng tốc,
   giảm số card xử lý mỗi run (vẫn đủ raw text + thử link đầy đủ cho từng
   card đã chọn), không giảm chất lượng xử lý từng card.
   Nếu poster là anonymous (`Anonymous participant`, `Người tham gia ẩn danh`,
   hoặc Facebook thể hiện trạng thái ẩn danh nhưng không expose profile URL),
   bắt buộc ghi `poster.visibility='anonymous'`, `anonymous_poster=true` và
   `anonymous_post_permalink_required=true` trong context/notes. Không suy ra
   danh tính từ comment, ảnh, media hay profile khác. Nếu anonymous card không
   có direct permalink/share evidence thì giữ `capture_unresolved`; nếu có
   share URL thì vẫn chỉ là evidence `unvalidated`, chưa phải access-ready.
4. Lưu `sublet_listings`:
   `source='fb_feed'`, `group_key`, `source_url`, `poster_name`, full
   `raw_text`, `posted_at` chỉ khi absolute timestamp hiển thị rõ, `seen_at`,
   `kind=null`, `link_validation_status='unvalidated'`. `text_hash` là
   generated column, không insert thủ công. `source_url` được phép là
   Facebook `share/p/...` chưa resolve.
   Nếu Facebook chỉ expose relative label, được phép tính thời điểm ước lượng
   từ `capture_now` (giờ `Europe/Amsterdam`) nhưng **không** ghi đè vào
   `posted_at`. Ghi estimate trong `notes` của listing và các key
   `posted_at_estimated`, `posted_at_estimate_basis`,
   `posted_at_estimate_uncertainty_hours` trong context payload. Luôn giữ
   nguyên `timestamp_label` làm evidence gốc.
5. Lưu một `sublet_events` event `context_captured` với raw context contract
   bên dưới. Nếu listing đã có context event contract v2 hoàn chỉnh, không tạo
   event trùng; chỉ bổ sung khi capture mới có evidence rõ ràng hơn.
6. Sau **từng batch**, ghi listing/event + run cursor/progress + metric group.
   Không chờ hết 14 group mới update DB.

### Default feed-first hybrid capture

Đây là cách chạy mặc định để giữ cùng raw contract nhưng giảm page navigation:

1. **Feed pass:** sau mỗi chunk scroll, dùng DOM/a11y trong panel để enumerate
   từng card và lấy core fields (`post_id`/permalink nếu có, poster, timestamp,
   text, media metadata và counters). Dedupe theo permalink/text hash ngay tại
   batch; không mở detail cho mọi post. **Không tự đọc bằng mắt output
   `read_page` để tìm ranh giới card** — pipe output đó qua
   `python3 scripts/extract_cards.py` để tách card trước (xem chi tiết dưới
   "Post extractor"). Script chỉ là gợi ý cấu trúc tốc độ, không phải link
   evidence đã xác minh; mọi rule capture/detail-gate/dedupe bên dưới vẫn áp
   dụng nguyên vẹn cho output của nó.
2. **Detail gate:** chỉ mở permalink riêng cho card thiếu permalink cần verify,
   text còn collapsed, comment/reply cần đọc, hoặc metadata quan trọng chỉ
   hiện ở detail. Giữ nguyên các giá trị feed đã có và merge các field detail
   bổ sung; `null` từ detail không được xoá evidence feed.
3. **Source precedence:** khi cùng field có hai giá trị, ưu tiên
   `detail_dom_a11y` > `feed_dom_a11y` > `screenshot_fallback`. Ghi các nguồn
   đã dùng vào `capture_methods`; không claim output giống detail-first nếu
   detail gate chưa được thoả.
4. **Screenshot fallback:** chỉ chụp viewport hiện tại khi AX không đọc được
   visual text. Long screenshot/extension không phải nguồn chính: Facebook có
   thể virtualize card ngoài viewport, OCR có thể sai text/URL/timestamp. Ảnh
   không bao giờ đủ để verify group hoặc permalink; nếu chỉ có screenshot thì
   giữ card partial/unresolved.
5. **Acceptance:** output được coi là cùng contract khi field union sau merge
   có đủ schema v2, mọi field không thấy có `missing_fields`, và comment có
   parent-post URL hợp lệ. Chỉ detail audit từng post mới cho coverage tương
   đương detail-first; hybrid không được quảng cáo là byte-identical.

### Post extractor (`scripts/extract_cards.py`) — dùng ở Feed pass

Lý do: trước script này, agent phải tự đọc toàn bộ output `read_page`
(30-50K ký tự) bằng mắt để tìm ranh giới từng card — đây là nguồn token lớn
nhất trong pipeline (xem PLAN.md mục J1/J3 #1). Script chạy hoàn toàn cục bộ
trên text `read_page` đã lấy về, **không gọi thêm bất kỳ request nào tới
Facebook**, nên không đổi gì về page-load budget hay rủi ro bị flag.

Cách dùng:

```sh
python3 scripts/extract_cards.py < read_page_output.txt
```

Cách hoạt động: tách card theo marker `button "Hành động đối với bài viết này
của <Poster>"` — quan sát thấy marker này ổn định ở cả 2 kiểu layout đã gặp
(dialog xem 1 post lẫn feed nhiều post liền, có hoặc không có role `article`
bọc ngoài mỗi post). **Không dùng role `article`/`dialog` làm ranh giới** —
bản đầu tiên của script từng làm vậy và test trên dữ liệu thật cho thấy sai
hoàn toàn (chỉ bắt được comment, bỏ sót toàn bộ post thật) vì Facebook không
luôn bọc post bằng `article`.

Mỗi card trả về gồm `poster_name`, `post_id` (nếu tìm được qua permalink trực
tiếp hoặc qua parent path của comment), `timestamp_label`, `post_text_guess`,
`reaction_count`, `comment_count`, `media_urls`, `missing_fields`,
`confidence` (`high`/`medium`/`low`) và `needs_detail_gate` (true khi không
tìm được `post_id` ở tầng feed — đúng lúc cần mở post riêng hoặc dùng
Share→Copy link theo rule Detail gate ở trên, không được bỏ card).

Giới hạn đã biết, không giấu:
- Đây là **gợi ý cấu trúc**, không phải link evidence đã xác minh. Không được
  ghi thẳng `post_id` của script vào `sublet_listings`/`context_captured` mà
  bỏ qua bước lấy direct permalink hoặc Share→Copy link thật.
- `post_text_guess` là suy đoán (chuỗi `generic`/`heading` dài nhất sau
  marker, loại UI chrome) — vẫn có thể sai với post có cấu trúc lạ (post đã
  edit nhiều lần, có poll, có nhiều ảnh). Card `confidence='low'` hoặc thiếu
  `post_text_guess` vẫn cần agent tự đọc kỹ như trước khi có script.
- Facebook đổi DOM theo thời điểm/AB test; script có thể cần cập nhật regex
  khi gặp layout mới. Nếu script trả về `card_count=0` trên output có post
  thật, đó là dấu hiệu layout đã đổi — báo cho Kien, không tự suy diễn dữ liệu
  thiếu.

### Raw context contract v2

Mỗi `context_captured` payload phải có đủ key, kể cả khi không thấy giá trị:

```json
{
  "capture_contract_version": 2,
  "capture_quality": "complete",
  "scan_run_id": 7,
  "page_load": 1,
  "source_surface": "user_browser_panel",
  "capture_now": "2026-09-15T23:00:00+02:00",
  "capture_methods": ["feed_dom_a11y"],
  "group": {
    "key": "amsterdam-housing-apartments-rooms-287563233830552",
    "name": "Amsterdam Housing, Apartments & Rooms",
    "url": "https://www.facebook.com/groups/287563233830552/"
  },
  "post_id": "1126264226627111",
  "link_resolution_method": "direct_permalink",
  "link_validation_status": "unvalidated",
  "link_validated_url": null,
  "post_title": null,
  "post_text": "...",
  "language_label": null,
  "visibility": "public",
  "edited_label": null,
  "shared_post": null,
  "timestamp_label": "2 weeks ago",
  "posted_at_observed": null,
  "poster": {
    "display_name": "...",
    "profile_url": null,
    "visibility": "public"
  },
  "post_url": "https://www.facebook.com/groups/.../posts/.../",
  "posted_at_estimated": null,
  "posted_at_estimate_basis": null,
  "posted_at_estimate_uncertainty_hours": null,
  "reaction_count": null,
  "reaction_breakdown": null,
  "comment_count": null,
  "share_count": null,
  "media": [],
  "comments": [],
  "comments_captured_count": 0,
  "comment_capture_status": "not_loaded",
  "poster_public_activity": [],
  "commenter_public_activity": [],
  "missing_fields": [],
  "truncated": false
}
```

Card chưa resolve dùng payload raw tối thiểu riêng (không giả `post_url`):

```json
{
  "capture_contract_version": 2,
  "capture_quality": "unresolved",
  "source_surface": "user_browser_panel",
  "capture_now": "2026-09-15T23:00:00+02:00",
  "group_key": "...",
  "post_id": null,
  "post_url": null,
  "link_resolution_method": "facebook_copy_link_failed",
  "link_validation_status": "unvalidated",
  "link_validated_url": null,
  "raw_card_text": "...",
  "poster": {"display_name": "...", "profile_url": null},
  "timestamp_label": null,
  "media": [],
  "reaction_count": null,
  "comment_count": null,
  "card_fingerprint": "sha256(normalized group + poster + time + card text)",
  "missing_fields": ["post_url", "post_id"],
  "unresolved_reason": "no_link_evidence"
}
```

Khi chạy lại, tìm `capture_unresolved` bằng `card_fingerprint` trước khi ghi
event mới. Khi một card lấy được link evidence, tạo listing/context event bình
thường, liên kết fingerprint trong payload và đánh dấu event unresolved đã
resolved; không tạo bản sao.

### Recovery nhanh cho card `capture_unresolved` cũ — dùng search-trong-group

Thay vì cuộn chronological lại từ đầu group để tìm 1 card cụ thể (chậm, tốn
nhiều page load), dùng tính năng **"Tìm kiếm trong nhóm này"** có sẵn trên mọi
Facebook group (nút search icon trong panel group):

1. Mở group, bấm nút search-trong-group.
2. Gõ nguyên văn 1 cụm đặc trưng, ngắn (5–10 từ) từ `raw_text` đã capture
   trong event `capture_unresolved` — càng đặc thù càng ít nhiễu kết quả.
3. Nếu Facebook cho lọc, dùng **Posted By** (nhập/so khớp `poster.display_name`
   đã capture) và **Date** để thu hẹp, không chỉ dựa vào text.
4. Đối chiếu kết quả với `card_fingerprint` (poster + timestamp + text đã
   chuẩn hoá) — chỉ nhận khi khớp rõ ràng, giống nguyên tắc recovery của
   `validate-permalink` (không đoán khi có nhiều ứng viên).
5. Bấm vào kết quả đúng để mở bài, lấy permalink từ URL hoặc Share → Sao chép
   liên kết — vẫn tuân `unresolved_reason` chỉ được `no_link_evidence` nếu
   sau cùng vẫn không tìm ra (không dùng lại reason cũ đã bị chặn ở DB).
6. Khi tìm được, tạo `sublet_listings` + `context_captured` bình thường,
   `link_validation_status='unvalidated'` như 1 card mới, liên kết
   `card_fingerprint` để đánh dấu event `capture_unresolved` gốc đã resolved.

Nhanh hơn cuộn hàng chục lần vì mỗi card thường chỉ tốn 2–3 thao tác (mở
search → gõ → bấm kết quả) thay vì scroll dò từng đoạn thời gian. Vẫn tính
vào page-load budget ≤4/run như bình thường; ưu tiên card có nội dung nhà ở
rõ ràng (cá nhân thật) trước card dạng repost hàng loạt từ 1 tài khoản
aggregator.

Capture tất cả comment/reply công khai đang hiển thị, tối đa 100 mỗi post. Chỉ
đọc public profile/activity trực tiếp gắn với post đã capture, tối đa 10 post
hoặc 30 ngày mỗi poster/commenter. Lưu raw text, verified URL, absolute date
nếu có, relative label nếu có và `visibility`. Không đọc DM/private content,
friend list, album/ảnh riêng tư, không tách phone/email thành contact profile,
không suy luận thuộc tính nhạy cảm.

**Anonymous gate:** anonymous card phải có permalink bài viết được
`validate-permalink` mở và xác nhận đúng group + đúng nội dung trước khi dùng
cho profile follow-up, official analysis/matching hoặc outreach. Share URL chưa
validate không đủ điều kiện; không có permalink thì không truy cập profile/post
riêng, không DM và không đánh dấu anonymous là resolved.

### Raw capture checklist

Per verified post, capture every field that is visibly available; a missing
value is different from a value of zero or an empty list:

- identity: group key/name/URL, post ID, canonical post permalink, poster
  display name and public profile URL;
- link evidence: direct permalink nếu Facebook expose; comment permalink có
  parent path `/posts/<id>/`; hoặc Facebook share URL được tạo bởi thao tác
  **Sao chép liên kết** và method `facebook_copy_link`; không suy luận post ID
  từ share token.
- content: post title, full expanded text, language as shown (do not infer a
  language), visibility/public label, edited/shared/repost label;
- time: `capture_now`, original absolute timestamp if exposed, original
  relative label, and estimate fields only under the estimate rule below;
- engagement: total reactions, reaction breakdown, comment count, and share
  count when shown; keep each as `null` when Facebook does not expose it;
- attachments: every visible image/video/link attachment with type, verified
  URL, alt text/caption, and position/count when shown;
- discussion: visible public comments and nested replies with raw text,
  commenter/profile URL, comment/reply permalink, timestamp label or absolute
  date, and `visibility`;
- provenance: page load, source surface, capture quality, truncation, and a
  `missing_fields` list explaining what was not exposed.

For comments, expand “view more comments” and visible replies when this is a
read-only panel action, up to 100 comments per post. Set
`comment_capture_status='complete'` only after the visible comment thread is
exhausted; use `not_loaded`, `partially_loaded`, or `capped_100` otherwise.
Never use `comments=[]` to mean “there are no comments” when the thread was not
loaded. Do not capture the comment composer, private replies, or hidden data.

Integrity invariant: for every comment, strip query/hash from `comment_url` and
verify that its parent `/posts/<post_id>` matches the captured `post_url`.
Also verify `comment_id` is present when Facebook exposes it. If the parent
does not match, do not attach the comment to that listing: keep it in a
quarantine/mapping-review record until the parent post is verified. A comment
text or commenter name alone is never enough to assign it to a post.

`capture_quality='complete'` means the post text was fully expanded and the
visible metadata/thread were exhausted or explicitly recorded as unavailable;
`partial` means collapse, virtualization, or an unexpanded thread prevented
that. `legacy_normalized` is only for DB-only normalization of older events and
does not claim a new browser capture.

### Relative timestamp estimate

- Tính estimate ngay lúc capture, từ `capture_now`, không lấy thời điểm chạy
  analyzer hay thời điểm insert DB. Parse các label rõ như phút/giờ/ngày/tuần
  (kể cả nhãn Việt/Anh/Hà Lan); không đoán từ comment timestamp để suy ra thời
  điểm post.
- Độ bất định tối thiểu: phút/giờ `±1h`, ngày `±24h`, tuần `±72h`, tháng
  `±168h`. Nếu label mơ hồ như “recently”, “1 month” không đủ chi tiết hoặc
  không parse được thì để cả ba key estimate là `null` và ghi
  `posted_at_estimate_unavailable` vào notes.
- Notes phải ghi theo dạng dễ lọc, ví dụ
  `posted_at_estimated=2026-09-15T22:20:00+02:00; basis="2 hours"; uncertainty_hours=1`.
- Estimate chỉ phục vụ sort/triage tham khảo. Không dùng estimate để chốt
  `posts_14d_complete`, vượt boundary 14 ngày, tính `posts_14d_count`, hay
  thay thế `posted_at` trong logic dedupe/resume. Khi cần chứng minh đủ 14
  ngày, vẫn phải có absolute timestamp hoặc boundary Facebook xác minh được.

## Completion và chống báo sai

- Card không có permalink trực tiếp nhưng đã lấy được Facebook share URL bằng
  **Chia sẻ → Sao chép liên kết**, hoặc có comment permalink với parent path
  `/posts/<id>/`, là đã có link evidence và được lưu vào raw queue với
  `link_validation_status='unvalidated'`; vẫn ghi `post_id=null` cho tới khi
  validator xác nhận. Chỉ card không có direct/comment permalink **và** không
  có share URL evidence mới là `unresolved_cards`; raw card vẫn phải được lưu
  bằng `capture_unresolved`, không đoán URL từ media/photo ID.
- Nhãn “2 tuần”, `posts_seen`, hoặc việc hết time-box **không** chứng minh đã
  capture đủ 14 ngày.
- **Số lượng card unresolved (thiếu link) không chặn completion** (nới lỏng
  2026-09-16 theo yêu cầu Kien, thay cho ngưỡng ≤5/≤10% đặt ra trước đó cùng
  ngày — bỏ hẳn, không dùng số ngưỡng nào nữa). Group active cỡ lớn (chục
  nghìn thành viên) gần như không bao giờ đạt 0 card unresolved vì bài mới
  dồn nhanh hơn tốc độ capture cho phép (≤4 page load/run); việc resolve link
  là việc của `validate-permalink` (kể cả recovery), không phải điều kiện để
  `sublet-scrape-14-groups` complete một group.
- **Điều kiện complete thật sự chỉ còn hai vế: (1) đã qua boundary 14 ngày,
  và (2) mọi card trong window đã có raw data đầy đủ** — card có link thì lưu
  listing bình thường; card không có link vẫn bắt buộc lưu đủ raw qua event
  `capture_unresolved` (poster, timestamp/label, **toàn bộ raw text**, media,
  counters, `card_fingerprint`, theo đúng "Raw context contract v2" phía
  trên) — y hệt mức chi tiết của card có link, chỉ khác thiếu
  `post_url`/`post_id`. Link đợi validate-permalink xử lý sau, không đợi ở
  bước này. Khi đạt (1)+(2), set `posts_14d_complete=true`,
  `posts_14d_count`, `posts_14d_checked_at` và chuyển group bình thường dù
  còn bao nhiêu card unresolved link.
- Cái duy nhất **không được bỏ qua**: nội dung raw (text/poster/media/comment)
  của mỗi card. "Chưa có link" được bỏ qua thoải mái ở bước này; "chưa có raw
  data" thì không bao giờ được coi là complete.
- Nếu feed virtualized, text vẫn collapsed, DB outage, browser reset: giữ
  count null/known-but-incomplete, giữ run mở hoặc stop reason; không chuyển
  group — đây là lý do khác (chưa capture được raw data), không liên quan số
  lượng card thiếu link. Card thiếu link nhưng đã có raw data đầy đủ thì
  không cần giữ run mở, được complete bình thường.
- Chỉ khi `posts_14d_complete=true` mới thêm group vào `completed` và chuyển
  `current_index` sang group kế tiếp. Nếu group bị blocker, thêm vào `blocked`
  và giữ batch chưa complete.

## Database và tiếp tục flow

- Database live: Supabase project Lamy; schema tham chiếu `db/schema.sql`; SQL
  qua `python3 scripts/db.py "<SQL>"`, không dùng để điều khiển Facebook.
- Bảng capture: `sublet_listings`, `sublet_events`, `sublet_scan_runs`,
  `sublet_group_metrics`, `sublet_groups`.
- Bảng state: `sublet_ops_state` và `sublet_jobs` nếu chạy theo chunk.
- DB lỗi: retry đúng một lần sau 5 giây; vẫn lỗi thì dừng, giữ incomplete và
  báo warning. Không claim database đã update nếu chưa có xác nhận.
- Sau khi toàn bộ batch raw capture hoàn tất, người vận hành mới yêu cầu bước
  phân tích riêng; không tự gửi tin ra ngoài.
