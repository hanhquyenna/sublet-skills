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

- Chỉ đọc Facebook qua ChatGPT/Codex in-app browser panel trong session người
  dùng đã login thủ công.
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
   cũ, expand visible collapse khi có thể, scroll theo chunk time-box.
3. Mỗi post chỉ được insert khi group và permalink đã xác minh. Chuẩn hóa URL
   bằng cách bỏ query/hash; kiểm tra `source_url` và raw text hash trước insert.
   URL đã có thì không tạo listing mới.
4. Lưu `sublet_listings`:
   `source='fb_feed'`, `group_key`, `source_url`, `poster_name`, full
   `raw_text`, `posted_at` chỉ khi absolute timestamp hiển thị rõ, `seen_at`,
   `kind=null`. `text_hash` là generated column, không insert thủ công.
5. Lưu một `sublet_events` event `context_captured` với raw context contract
   bên dưới. Nếu listing đã có context event contract v2 hoàn chỉnh, không tạo
   event trùng; chỉ bổ sung khi capture mới có evidence rõ ràng hơn.
6. Sau **từng batch**, ghi listing/event + run cursor/progress + metric group.
   Không chờ hết 14 group mới update DB.

### Raw context contract v2

Mỗi `context_captured` payload phải có đủ key, kể cả khi không thấy giá trị:

```json
{
  "capture_contract_version": 2,
  "capture_quality": "complete",
  "scan_run_id": 7,
  "page_load": 1,
  "source_surface": "codex_in_app_browser",
  "post_text": "...",
  "timestamp_label": "2 weeks ago",
  "posted_at_observed": null,
  "poster": {
    "display_name": "...",
    "profile_url": null,
    "visibility": "public"
  },
  "post_url": "https://www.facebook.com/groups/.../posts/.../",
  "reaction_count": null,
  "comment_count": null,
  "media": [],
  "comments": [],
  "poster_public_activity": [],
  "commenter_public_activity": [],
  "truncated": false
}
```

Capture tất cả comment/reply công khai đang hiển thị, tối đa 100 mỗi post. Chỉ
đọc public profile/activity trực tiếp gắn với post đã capture, tối đa 10 post
hoặc 30 ngày mỗi poster/commenter. Lưu raw text, verified URL, absolute date
nếu có, relative label nếu có và `visibility`. Không đọc DM/private content,
friend list, album/ảnh riêng tư, không tách phone/email thành contact profile,
không suy luận thuộc tính nhạy cảm.

## Completion và chống báo sai

- Card không có permalink xác minh là `unresolved_cards`; không insert listing,
  không đoán URL và không tính vào verified total.
- Nhãn “2 tuần”, `posts_seen`, hoặc việc hết time-box **không** chứng minh đã
  capture đủ 14 ngày.
- Chỉ set `sublet_group_metrics.posts_14d_count`,
  `posts_14d_complete=true`, `posts_14d_checked_at` khi đã qua boundary 14 ngày
  và xử lý hết card trong window có permalink xác minh.
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
