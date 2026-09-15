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
- Routine flow không cần hỏi lại; chỉ dừng khi gặp blocker an toàn, DB lỗi,
  Facebook login/checkpoint/captcha/unusual activity, hoặc dữ liệu không thể
  xác minh.

## Quyền và browser hard rule

- Chỉ đọc Facebook qua browser integration có UI của agent trong session người
  dùng đã login thủ công. Claude Code dùng Claude in Chrome; Codex dùng
  in-app browser panel; agent khác dùng browser adapter tương đương được host
  cung cấp.
- Không dùng script scraper, HTTP/API, Selenium, headless browser, cookie,
  browser session khác hoặc raw page dump để đọc Facebook.
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
   timestamp, text, permalink trước khi chuyển text sang bất kỳ bước xử lý
   nào; không dùng LLM để phát hiện ranh giới card và không đọc raw page dump.
3. Mỗi post chỉ được insert khi group và link evidence của Facebook đã xác
   minh (direct permalink, comment-parent permalink, hoặc share URL lấy bằng
   “Chia sẻ → Sao chép liên kết”). Chuẩn hóa URL bằng cách bỏ query/hash; kiểm
   tra `source_url` và raw text hash trước insert. URL đã có thì không tạo
   listing mới. Lưu `post_id` chỉ khi parse được từ permalink đã verify; không
   suy ra ID từ media URL hay tracking parameter.
   Nếu card không expose permalink trực tiếp, dùng đúng post card's **Chia sẻ
   → Sao chép liên kết** trong panel. URL Facebook trả về là evidence hợp lệ
   cho card đó: ưu tiên mở/resolve thành `/groups/<group>/permalink/<id>/`;
   nếu page-load budget không cho phép resolve, lưu nguyên
   `https://www.facebook.com/share/p/<token>/` làm `source_url`, ghi
   `link_resolution_method='facebook_copy_link'`, và để `post_id=null` nếu
   token không chứa ID. Một comment permalink của Facebook có path chứa rõ
   `/posts/<id>/` cũng được chuẩn hóa về parent post URL và ghi
   `link_resolution_method='comment_permalink'`; không tự tạo URL từ profile
   commenter hoặc media/photo ID.
   Nếu cả direct permalink, comment-parent permalink và Facebook copy-link đều
   không lấy được, **không bỏ card**: ghi một event
   `sublet_events(event='capture_unresolved', entity_type='fb_card',
   entity_id=null, source_url=<group_feed_url>)` với raw card text, poster,
   timestamp label, media/counters đang thấy, `card_fingerprint`,
   `missing_fields` và `unresolved_reason='no_link_evidence'`. Event này là
   hàng chờ resolve, không phải listing và không được tính vào verified total.
4. Lưu `sublet_listings`:
   `source='fb_feed'`, `group_key`, `source_url`, `poster_name`, full
   `raw_text`, `posted_at` chỉ khi absolute timestamp hiển thị rõ, `seen_at`,
   `kind=null`. `text_hash` là generated column, không insert thủ công.
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
   batch; không mở detail cho mọi post.
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

Capture tất cả comment/reply công khai đang hiển thị, tối đa 100 mỗi post. Chỉ
đọc public profile/activity trực tiếp gắn với post đã capture, tối đa 10 post
hoặc 30 ngày mỗi poster/commenter. Lưu raw text, verified URL, absolute date
nếu có, relative label nếu có và `visibility`. Không đọc DM/private content,
friend list, album/ảnh riêng tư, không tách phone/email thành contact profile,
không suy luận thuộc tính nhạy cảm.

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
  `/posts/<id>/`, là đã có link evidence và được tính vào verified total; vẫn
  ghi `post_id=null` nếu share token chưa resolve được. Chỉ card không có
  direct/comment permalink **và** không có share URL evidence mới là
  `unresolved_cards`; raw card vẫn phải được lưu bằng `capture_unresolved`,
  không đoán URL từ media/photo ID.
- Nhãn “2 tuần”, `posts_seen`, hoặc việc hết time-box **không** chứng minh đã
  capture đủ 14 ngày.
- Chỉ set `sublet_group_metrics.posts_14d_count`,
  `posts_14d_complete=true`, `posts_14d_checked_at` khi đã qua boundary 14 ngày
  và xử lý hết card trong window có verified link evidence; mọi card còn
  `unresolved` hoặc `partial` phải được xử lý/ghi nhận đúng state trước khi
  complete. `capture_unresolved` bảo đảm không mất raw data nhưng không tự biến
  card đó thành verified.
- Nếu feed virtualized, text vẫn collapsed, DB outage, browser reset hoặc có
  unresolved cards: giữ count null/known-but-incomplete, giữ run mở hoặc stop
  reason; không chuyển group.
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
