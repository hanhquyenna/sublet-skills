---
name: sublet-scan
description: CAPTURE-ONLY — quét post mới trên Facebook qua groups/feed + notifications trong Chrome thật (chỉ đọc, ≤4 page load), lưu thô (post, link, text, thời gian, group) vào sublet_listings với kind=null, dừng ở cursor của lần trước để không lặp, rồi gọi intent-analyze. Dùng với /sublet-scan hoặc trong /loop.
---

# sublet-scan

Read `references/capture-contract.md` before any group-history or context
capture. It is the shared contract for the 14-day raw capture, provenance,
public comments/profile context, resumable progress, and database checkpoints.

## Spec
| | |
|---|---|
| **Lịch** | cron mỗi 12' 08–23 (launchd com.sublet.scan); skip ngẫu nhiên 1/12 |
| **Trigger** | `/sublet-scan` |
| **Đọc** | groups/feed + /notifications (≤4 loads), sublet_scan_runs.cursor, sublet_listings.text_hash, sublet_ops_state |
| **Ghi** | sublet_listings (raw, kind=null, canonical_id), sublet_scan_runs, sublet_groups.last_post_seen_at, sublet_events(captured), sublet_inbox(action/stop) |
| **Metrics** | capture.posts_captured_24h, page_loads_24h, page_loads_per_run_max, stops_24h, dedupe_ratio |
| **Edge cases** | E10 E11 E12 E13 E15 E20 E21 E22 E43 → `docs/edge-cases.md` |
| **Rules** | R02 R03 R04 R05 R06 R10 R18 R20 → `docs/rules.md` |

Đọc CLAUDE.md trước. Skill này **chỉ đọc**. Không click Like/Comment/Join/Send.

## Điều kiện chạy
0. Run trước có `finished_at is null` và `started_at` > 30' → update `stopped_reason='abandoned'`, `finished_at=now()` (E20).
1. Đọc `data/config.yaml`. Nếu giờ hiện tại (Europe/Amsterdam) ngoài `hours` → dừng, ghi 1 dòng "ngoài giờ".
2. Đếm `sublet_scan_runs` 24h qua: nếu tổng `page_loads` ≥ 350 → dừng, báo "gần ngưỡng volume".
3. Random: 1/12 chu kỳ bỏ qua (giả lập nghỉ). Ghi "skip ngẫu nhiên".

## Các bước
1. `insert into sublet_scan_runs(mode) values ('feed') returning id` — nhớ id.
2. Chrome (Claude in Chrome / mcp__claude-in-chrome): `navigate` tới `https://www.facebook.com/groups/feed/`. **1 page load.**
   - Nếu trang là login / checkpoint / captcha / "unusual activity": cập nhật run `stopped_reason`, insert `sublet_inbox(level='stop', title='Facebook checkpoint — scan dừng 24h')`, ghi `sublet_ops_state('scan_paused_until', now()+24h)`, **dừng toàn bộ**.
3. Dùng accessibility tree/DOM đã hiển thị trong ChatGPT browser panel để nhận diện từng post trước khi đưa text cho LLM. Không lấy cả trang làm một blob. Scroll xuống tối đa 3 lần (`computer scroll`), mỗi lần chờ 2–5s. **Dừng sớm** khi: gặp `cursor` của run trước (`select cursor from sublet_scan_runs where mode='feed' and cursor is not null order by id desc limit 1`), hoặc 3 permalink liên tiếp đã có trong `sublet_listings.source_url`.
   - Tách theo từng node bài đăng (thường là `article`/landmark lặp lại). Trong mỗi node, lấy poster từ heading/link tên người đăng, thời gian từ `time` hoặc nhãn tương đối, toàn bộ text hiển thị của chính post, và permalink đầu tiên khớp `/groups/.../posts/...` hoặc `/permalink/...`. Không trộn nav, reaction count, comment composer hay text comment vào `raw_text`; nếu các metadata đó hiển thị thì giữ riêng trong raw payload/context.
   - Chuẩn hoá permalink (bỏ query/hash) rồi kiểm tra `source_url` và `text_hash` bằng DB **trước** khi đưa record vào hàng đợi. Thiếu permalink thì không insert vì vi phạm luật provenance; ghi lại là unresolved trong run để kiểm tra thủ công sau.
   - Chỉ gửi các record mới đã tách (poster, posted_at, source_url, group_key, raw_text) cho bước phân tích; không gửi lại record đã có `text_hash`. Giữ raw metadata/context trong `sublet_events`, không làm mất vì giới hạn token; mỗi chu kỳ chỉ đưa phần record mới vào analyzer, tối đa khoảng 25 post hoặc khoảng 7.000 token text + 3.000 token instruction. Phần dư ở lại `sublet_v_analyze_queue` cho chu kỳ sau, không cắt text trong DB.
4. `navigate` tới `https://www.facebook.com/notifications` — **page load 2** — đọc "X posted in <group>", lấy link post nếu có. Bỏ qua notification cũ hơn `last_post_seen_at` của group đó (trong `sublet_groups`).
5. Với mỗi post chưa có `source_url` trong DB: **chỉ capture raw, không phân loại/chuẩn hoá**:
   - `source` ('fb_feed' | 'fb_notif'), `source_url` (permalink, bỏ query string), `group_key` (map tên group → `sublet_groups.key`, fuzzy; không map được → key = slug tên, insert group mới tier=null), `poster_name` (display name như hiện), `posted_at` chỉ set khi timestamp post hiển thị rõ; nếu chỉ có label tương đối hoặc không có thì giữ `null` và lưu nguyên label vào event payload, `raw_text` (toàn bộ text post sau mở detail/collapse, không cắt), `kind = null`.
   - Trước analyzer, giữ nguyên các tín hiệu raw mà panel hiển thị: raw header/post text, raw timestamp label, poster display name + public profile URL nếu hiện, permalink, reaction/comment counters, trạng thái collapsed/truncated, media link + alt/OCR description hiển thị (không tải ảnh), và comment/reply raw text + display name + public profile URL + timestamp label + permalink + quan hệ reply.
   - Không ở bước này: parse giá/ngày/khu vực, gán `offering`/`seeking`/`other`, tính scam/deal/confidence, gán segment/urgency/contactability, hoặc tạo `missing_fields`/`next_action`. Các giá trị đó thuộc `intent-analyze`/feature engineering.
   - **Dedupe trước khi insert**: `select id from sublet_listings where text_hash = md5(lower(regexp_replace(<raw_text>, '\s+', ' ', 'g'))) limit 1`. Có → insert vẫn (giữ source_url riêng cho provenance) nhưng set `canonical_id = <id đó>` và **không** đưa vào hàng đợi DM. Không có → insert bình thường.
   - Insert `sublet_listings`; insert `sublet_events(event='captured', source_url)` and, when context was read, a `context_captured` event using the shared contract with `scan_run_id`, page-load ordinal, and `source_surface`.
   - Update `sublet_groups.last_post_seen_at` = max(posted_at).
   - Permalink đầu tiên đọc được ở đầu feed → ghi vào `sublet_scan_runs.cursor` của run này.
6. Nếu một post có `notes='needs_full_read'` (do intent-analyze đánh) : được phép mở permalink để đọc full post — **page load 3–4, tối đa 2 post/chu kỳ**, và ghi vào `mode='group_page'` run riêng. Chỉ capture raw detail/context; không mở DM/private content, không click Like/Comment/Join/Send, không tải ảnh.
7. Cập nhật run: `finished_at`, `page_loads`, `posts_seen`, `new_listings`.
8. Nếu `new_listings > 0`: gọi `/intent-analyze` (phân loại + extract + scam + tự match). Scan không tự phân loại.
9. In tóm tắt 3 dòng: captured / (từ intent-analyze) offering-seeking-scam / đã match. Với mỗi listing mới đáng DM → insert `sublet_inbox(level='action', title='DM sẵn: {area} €{rent} {from}→{to}', entity_type='listing', entity_id, message_id=<draft>)`.

## Không làm
- Không mở từng group trong groups.yaml. Feed đã gom.
- Không mở profile ngoài public context gắn trực tiếp với post housing đã capture; không đọc DM/private content, friend list, album/ảnh riêng tư, hay tách contact fields. Không lưu binary ảnh; chỉ giữ media URL/alt/OCR text nếu panel hiển thị.
- Không chạy khi máy vừa wake < 2 phút (kiểm tra bằng `uptime`/thời gian từ run trước).

## Capture contract (panel-only)

- Nguồn duy nhất là accessibility tree/DOM mà browser panel cung cấp; không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, cookie hay raw page dump để đọc Facebook.
- Tạo một record JSON nhỏ cho mỗi post sau khi tách: `poster_name`, `posted_at`, `source_url`, `group_name`, `raw_text`, cùng các trường raw tùy chọn `timestamp_label`, `profile_url`, `reaction_count`, `comment_count`, `media[]`, `comments[]`, `truncated`. LLM chỉ nhận các record JSON mới này; nó không được tự suy đoán permalink, poster hoặc thời gian từ phần còn thiếu.
- `sublet_events.event='context_captured'` chỉ chứa provenance/raw evidence: `capture_contract_version`, `scan_run_id`, `page_load`, `source_surface`, text, labels, URLs, media alt/OCR text, counters và reply edges. Không ghi các nhãn phân tích như `visible_fields`, `missing_from_listing_row`, `offering_complete`, `seeker_hot`, `contact_friction`, `scam_evidence` hoặc score vào capture event.
- Mỗi `context_captured` payload phải có `capture_contract_version=2`, `scan_run_id`, `page_load`, `source_surface='codex_in_app_browser'`, `capture_quality`, và cùng raw contract kể cả khi giá trị rỗng: `post_text` (hoặc `listing_id` tham chiếu tới `raw_text`), `timestamp_label`, `posted_at_observed` nếu có, `poster` (display name + URL nếu hiện), `post_url`, `reaction_count`, `comment_count`, `media[]` (URL/alt text/OCR description nếu panel hiển thị), `comments[]` (raw text, author, URL, timestamp label, `reply_to`) và `truncated`. Không dùng việc thiếu key để biểu thị “không có”; dùng `null`, `[]` hoặc `false` để phân biệt chưa thấy với không có. Event thiếu các key này phải được đánh dấu `legacy_unknown`/incomplete và không được coi là contract-complete.
- Nếu layout thay đổi và không còn nhận diện được article/permalink, dừng capture an toàn, cập nhật `stopped_reason`, không fallback sang đọc toàn trang hay đoán dữ liệu.
