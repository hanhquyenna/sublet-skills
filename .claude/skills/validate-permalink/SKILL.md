---
name: validate-permalink
description: "Validate captured Facebook post links one at a time in the user's browser panel, resolve share URLs when possible, and resume from the database without rechecking finished records."
---

# validate-permalink

Skill này là pha làm sạch sau raw capture. Nó không scrape lại feed, không phân
tích intent, không đọc thêm comment để làm giàu dữ liệu và không gửi gì lên
Facebook. Mục tiêu duy nhất là kiểm tra link đã capture có mở được đúng post
hay không.

## Spec

- **Trigger:** sau mỗi raw-capture batch hoặc khi Kien gọi skill.
- **Đọc:** `sublet_v_link_validation_queue`, listing/context event gần nhất,
  `validate_permalink_state`, Facebook panel.
- **Ghi:** link status/canonical fields trên listing, một provenance event cho
  mỗi kết quả, `sublet_scan_runs(mode='validation')` và cursor state.
- **Metrics:** processed, validated, inaccessible, needs_review, page_loads và
  queue còn lại.
- **Kết quả:** không còn `unvalidated` trong phần queue đã xử lý; không tự
  claim 14-day completeness nếu raw capture vẫn còn unresolved/partial.

## Hard rules

- Chỉ đọc Facebook bằng browser UI của agent trong session người dùng đã login:
  Claude Code dùng Claude in Chrome, Codex dùng ChatGPT in-app browser panel,
  agent khác dùng browser adapter tương đương của host.
- Không dùng CLI, HTTP/API, Selenium, headless browser, cookie hoặc raw page
  dump để đọc Facebook. DB/SQL vẫn chạy bằng `python3 scripts/db.py "<SQL>"`.
- Không like, comment, post, DM, join, submit, bật notification hay thao tác
  nào ngoài navigation/copy/đọc.
- Tối đa 4 Facebook page loads trong một validation run. Dùng một tab panel,
  xử lý tuần tự từng record; không mở song song và không dùng delay để né rate
  limit.
- Login, checkpoint, captcha, unusual activity, verification prompt hoặc lỗi
  browser không được ghi là `inaccessible`: dừng run, ghi `needs_review` với
  lý do, và không retry trong 24 giờ theo hard rules chung.

## Queue và thứ tự

Trước khi mở browser, kiểm tra schema và queue:

```sh
python3 scripts/db.py "select * from sublet_v_link_validation_queue"
```

Queue chuẩn là các listing Facebook có `source_url` và
`link_validation_status='unvalidated'`, sắp theo `seen_at asc, id asc`. Đây là
thứ tự ổn định để lần chạy sau tự tiếp tục phần còn lại; không reset về đầu,
không lấy lại record đã có trạng thái terminal. Không tự retry
`needs_review` trừ khi Kien yêu cầu retry rõ ràng.

Tạo hoặc tiếp tục `sublet_scan_runs(mode='validation')`. Lưu cursor JSON sau
mỗi record trong `sublet_ops_state` key `validate_permalink_state`:

```json
{
  "run_id": 0,
  "last_listing_id": null,
  "processed": 0,
  "validated": 0,
  "inaccessible": 0,
  "needs_review": 0,
  "page_loads": 0,
  "status": "running"
}
```

Status trong từng listing là nguồn sự thật; cursor chỉ giúp audit/resume. Nếu
agent bị ngắt giữa lúc mở link và lúc ghi DB, record vẫn `unvalidated` và sẽ
được xử lý lại an toàn ở lần sau.

## Validate từng record

Với record đầu tiên trong queue:

1. Đọc cùng listing và event `context_captured` mới nhất trước khi navigate:
   `source_url`, group key/name/URL, poster display name, raw text, timestamp
   label, media và text hash. Không dùng LLM để quyết định card boundary.
2. Mở `source_url` trong tab panel đang dùng. Share URL
   `https://www.facebook.com/share/p/<token>/` là input hợp lệ; không tự đoán
   ID từ token. Nếu Facebook redirect về `/groups/<group>/permalink/<id>/` hoặc
   `/posts/<id>/`, chuẩn hóa query/hash bỏ khỏi URL canonical.
3. Chỉ gọi là `validated` khi panel đọc được nội dung và xác nhận cùng bài:
   group đúng, poster khớp (anonymous có thể chỉ khớp trạng thái anonymous),
   và text/title hoặc media có đủ dấu hiệu khớp card raw. Một URL HTTP mở được
   nhưng dẫn sai group/sai post là `needs_review`, không phải validated.
4. Nếu Facebook hiển thị rõ nội dung không khả dụng vì post bị xóa, private,
   audience restriction hoặc không còn truy cập được, ghi `inaccessible`.
   Đây là trạng thái terminal của lần xác minh; giữ nguyên raw listing và
   share URL, không bịa `post_id`/canonical URL.
5. Nếu trang mở được nhưng không đủ dấu hiệu để khẳng định đúng bài, hoặc
   redirect lạ, timeout, DOM không đọc được, ghi `needs_review` và nêu lý do.
   Không dùng screenshot một mình để kết luận identity; chỉ dùng screenshot
   làm fallback visual text khi AX không đọc được.
6. Sau từng record, ghi DB ngay, rồi mới lấy record kế tiếp. Không đợi hết
   batch mới checkpoint.

## DB write contract

Giữ `sublet_listings.source_url` đúng URL đã capture, kể cả khi đó là share
URL. Không overwrite evidence gốc bằng canonical URL. Khi thành công, update:

- `link_validation_status='validated'`
- `link_validated_url=<canonical URL nếu panel expose; nếu chỉ share URL thì
  giữ `source_url` và để field này bằng share URL>`
- `link_validated_at=now()`
- tăng `link_validation_attempts`
- `link_validation_note` ngắn, nêu method và field dùng để match

Khi inaccessible, update `link_validation_status='inaccessible'`,
`link_validated_url=null`, thời điểm, attempts và note. Khi blocker/ambiguous,
update `needs_review`; không gọi là inaccessible.

Mỗi kết quả tạo một provenance event gắn `entity_id` listing:

- `event='link_validated'` cho success;
- `event='link_inaccessible'` cho explicit unavailable;
- `event='link_validation_review'` cho blocker/ambiguous.

Payload tối thiểu:

```json
{
  "validation_contract_version": 1,
  "validation_status": "validated",
  "source_url": "https://www.facebook.com/share/p/example/",
  "validated_url": "https://www.facebook.com/groups/.../permalink/.../",
  "link_resolution_method": "share_redirect",
  "post_id": "...",
  "group_match": true,
  "poster_match": true,
  "content_match": true,
  "access_evidence": "panel_dom_a11y",
  "note": "same group, poster and visible title/text"
}
```

Với inaccessible, `validated_url` và `post_id` phải là `null` nếu nội dung
không thể xác minh. Có thể lưu `redirect_url` riêng để audit, nhưng không
được coi nó là verified post URL. Giữ `original_share_url` nếu source URL đã
được chuẩn hóa ở nơi khác.

## Completion và edge cases

- Queue rỗng nghĩa là không còn listing Facebook `unvalidated`; báo số lượng
  theo `validated/inaccessible/needs_review`, không nói rằng toàn bộ 14 ngày
  đã complete nếu còn `capture_unresolved`, card partial hoặc thiếu boundary.
- Card chỉ có `capture_unresolved` event và không có listing/source URL không
  thuộc queue này. Không đánh dấu nó inaccessible; capture skill phải retry
  lấy link evidence sau.
- Nếu source URL trùng listing khác, không tạo listing mới. Ghi validation
  event cho entity hiện có; conflict canonical/content thì `needs_review`.
- Nếu một bài đã validated nhưng capture sau đó thấy text khác, không overwrite
  raw history và không tự revalidate; ghi event mới và chờ yêu cầu audit.
- Không mở comment/profile/media riêng chỉ để validate link. Comment chỉ được
  gắn với post nếu đã có parent-post URL đúng; việc đó thuộc raw capture.
- Sau khi queue được xử lý, cập nhật run cursor/finished_at và thống kê. Nếu
  DB lỗi, retry đúng một lần theo hard rule, rồi dừng và giữ state incomplete.
