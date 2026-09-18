# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Facebook mặc định read-only; ngoại lệ ghi duy nhất là DM theo rule outreach bên dưới — và ngay cả ngoại lệ đó, **agent không bao giờ tự click Send, chỉ Kien mới click**.

## Không bao giờ
1. **Không tự động post, comment, like, join group hoặc submit form trên Facebook.** Agent mặc định chỉ ĐỌC.
   - Ngoại lệ ghi duy nhất là **DM cho poster hợp lệ theo `outreach_order`** (chưa `has_outreached`, không `scam_flag`) — xem `outreach-prep/SKILL.md`. Từ 2026-09-18 (bản chốt): agent mở post, verify người, mở Messenger, paste nguyên văn `message1`, rồi **dừng lại và chờ Kien tự click Send** — agent không bao giờ tự click Send, dưới bất kỳ lý do hay yêu cầu nào. Không còn cờ `auto_dm`, không còn mô hình "agent tự gửi cả queue".
   - Agent chỉ ghi vào `outreach_messages` **NGAY SAU** khi Kien xác nhận đã click Send và Facebook xác nhận gửi thành công — 1 insert/lần gửi, không update. Nếu Kien không click hoặc UI không chắc thì **không insert gì**. Sau insert, ghi thêm `events(event='outreach_dm_sent', actor='human', entity_type='post')` — `actor` là `human` vì Kien là người thực hiện hành động gửi.
   - `has_outreached` tính live từ việc tồn tại bất kỳ row nào trong `outreach_messages` cho poster đó — tự đúng ngay khi insert, không cần set thêm ở nơi khác.
   - Post, comment, like, join group, submit form **vẫn tuyệt đối cấm**.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Chạy theo giờ trong `data/config.yaml` (`hours`); từ 2026-09-16 theo yêu cầu Kien, `hours` đặt 24/7 (`00:00`–`23:59`), không còn giới hạn khung giờ trong ngày. Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `sublet_inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Được đọc **public profile**, lịch sử public giới hạn của poster/commenter, và comment/reply gắn với post housing đã capture để lưu raw context. Chỉ đọc nội dung đang công khai; không vào DM, nội dung private/ẩn, friend list, album/ảnh, không suy luận thuộc tính nhạy cảm, và không tách riêng số điện thoại/email thành hồ sơ liên hệ. Không thao tác trên profile/comment. Poster hiển thị là `Anonymous participant`/`Người tham gia ẩn danh` hoặc không có profile URL phải được flag là `anonymous`; giữ nguyên label, không đoán danh tính. Anonymous card chỉ access-ready khi có permalink bài viết đã validate thật.
6. Mọi agent phải thao tác Facebook bằng **visible Chrome browser-panel automation của host**, đọc DOM/accessibility tree trước (Codex: ChatGPT in-app browser panel; Claude Code: Claude in Chrome; agent khác: Chrome-panel adapter tương đương). Đây là kênh Facebook duy nhất **cho capture chính thức** (ghi `sublet_listings`/`sublet_events` làm nguồn dữ liệu thật). Không dùng CLI/script scraper, web-fetch/HTTP/API, Selenium, headless browser, Chrome session khác hoặc cookie ở nơi khác; script chỉ được dùng cho DB/provenance, **và cho việc parse cục bộ output `read_page` đã lấy về** (`scripts/extract_cards.py` — không gọi thêm request nào tới Facebook, chỉ tách card từ text đã có sẵn để agent đỡ phải tự đọc bằng mắt; xem `sublet-scrape-14-groups/SKILL.md`).
   - **Kênh thứ 2 chính thức — Apify Facebook Groups Scraper, chỉ cho group PUBLIC (mở rộng 2026-09-17 theo yêu cầu Kien):** được phép dùng **duy nhất Apify actor `apify/facebook-groups-scraper`** (kể cả gọi thẳng API `run-sync-get-dataset-items` khi Kien đưa token) làm nguồn capture chính thức — ghi thẳng vào `sublet_listings`/`sublet_events` — nhưng **chỉ với group có `is_private=false`** (Apify không đọc được private group, tự nó đã giới hạn phạm vi). Group `is_private=true`/`null` (chưa xác minh) vẫn bắt buộc qua browser-panel như cũ. Điều kiện bắt buộc:
     - Ghi provenance trung thực: `capture_methods` chứa `"apify_api"` (không giả làm `detail_dom_a11y`/browser-panel), `source_surface="apify_api"`. Không xoá dấu vết nguồn.
     - Kết quả thô của Apify **không tự động trust** — vẫn phải lọc aggregator/spam (thực tế đo được: group7 test cho thấy ~85% kết quả "mới nhất" là bot repost `Student Housing Amsterdam`/`RentHunter`), lọc trùng `duplicate_of`, rồi mới ghi listing.
     - `poster.profile_url` từ Apify có thể là token `pfbid...` (không phải ID số như browser-panel lấy được) — vẫn ghi nhưng đánh dấu `profile_url_type="pfbid"` trong payload, vì không dùng để tạo `facebook.com/profile.php?id=` được như thường lệ.
     - Vẫn phải qua `analyze-insights`/`intent-analyze` để classify offering/seeking — Apify chỉ thay thế bước đọc raw text, không thay bước phân loại.
     - Không dùng Apify để đọc comment, profile riêng, hay DM — ngoài phạm vi actor này.
     - Chi phí tính theo usage Apify — báo Kien số tiền ước tính trước mỗi lần chạy batch lớn (>1 group/run).
7. Không ghi outcome (signed / moved-in) nếu không có xác nhận từ subletter hoặc seeker. Không đoán.
8. Không xếp hạng seeker theo quốc tịch, giới tính, tuổi, tôn giáo, hay bất kỳ tiêu chí phân biệt nào. Chỉ: ngày, ngân sách, khu vực, số người, registration, pets.

## Luôn luôn
- Mỗi record có `source_url` + `seen_at`. Không có nguồn = không tồn tại.
- Match score tính bằng `scripts/match.py` (deterministic). LLM chỉ viết `reasons`.
- Facebook DM: agent chuẩn bị `message1` cho poster hợp lệ theo luật #1 rồi dừng chờ Kien tự click Send; chỉ sau khi Kien gửi và UI xác nhận mới ghi 1 row vào `outreach_messages` (insert-only, không draft/status, actor='human') và ghi audit `events`. Các loại message khác vẫn cần người dùng gửi.
- Ghi `sublet_scan_runs` mỗi chu kỳ (page_loads, new_posts) để tự kiểm soát volume.
- DB lỗi (RPC/HTTP) → thử lại 1 lần sau 5s; vẫn lỗi → dừng skill, `sublet_inbox(warning)`, không ghi nửa chừng (R21).
- Mỗi skill có khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules). Registry: `docs/rules.md`, `docs/edge-cases.md`, `docs/metrics.md`. Thêm hành vi mới = cập nhật cả 3.
- Agent không gửi thông báo đi đâu. Mọi thứ cần người dùng biết → `sublet_inbox`; người dùng đọc trực tiếp trong DB/context map.
- Ngôn ngữ giao tiếp với người dùng: tiếng Việt. Template gửi ra ngoài: EN (mặc định) hoặc NL theo `config.yaml`.

## Dữ liệu
- Supabase (project Lamy), bảng prefix `sublet_`. Dùng Supabase MCP `execute_sql`. Schema: `db/schema.sql`.
- Cấu hình: `data/config.yaml`, danh sách group: `data/groups.yaml`.

## Thứ tự skill hiện tại
`information` → `sublet-scrape-14-groups` → `validate-permalink` (raw capture
trước, link validation sau). `data-engineer` là lớp DB-only để QA, normalize,
aggregate và report; `analyze-insights` là bước đọc-only độc lập, có thể chạy
bất kỳ lúc nào sau capture (không cần chờ validate xong) để tóm tắt insight cho
Kien. `intent-analyze` (bật 2026-09-17) là pipeline phân loại chính thức, ghi
thật `kind`/`subtype`/`poster_type`/... lên `sublet_listings` đã có
`source_url`; scam/deal scoring vẫn để mặc định, chưa bật. Matching và viewing chưa nằm trong active skill scope. `outreach-prep` đã active: tạo draft và có thể gửi pre-existing draft theo rule #1.

## Active scope
- **Context** (`information`): onboarding, quyền agent, DB, state và cách tiếp tục.
- **Capture** (`sublet-scrape-14-groups`): chọn tối đa 14 group, scrape raw 14 ngày,
  dedupe, resume và checkpoint DB. Không phân loại và không outreach.
- **Link validation** (`validate-permalink`): xử lý tuần tự queue link Facebook
  đã capture, giữ share URL gốc, ghi canonical URL nếu xác minh được và phân
  biệt `validated`, `inaccessible`, `needs_review`. Không scrape lại feed.
- **Insight analysis** (`analyze-insights`): đọc-only trên dữ liệu đã capture,
  ước lượng thô offering/seeking/other, phát hiện trùng lặp/repost và pattern
  rủi ro, tóm tắt vào `sublet_inbox`/`sublet_metrics`. Không ghi cột phân loại
  chính thức trên `sublet_listings`, không mở Facebook, không re-đọc listing
  đã có event `insight_reviewed`, không đụng
  `sublet_seekers`/`sublet_matches`/`sublet_messages`. Seeker↔offering
  matching (`sublet_insight_matches`) đã bị **xoá bỏ hoàn toàn 2026-09-17**
  theo quyết định của Kien (dữ liệu phình lên 169k dòng, phần lớn `weak`, mà
  không tương xứng giá trị) — không còn tồn tại trong scope này.
- **Data engineering** (`data-engineer`): DB-only normalization, provenance,
  dedupe, data-quality audits, idempotent checkpoints, customer-behavior event
  aggregates và reports. Không browse Facebook, không tự phân loại semantic,
  không làm identity enrichment và không tự động outreach.
- **Intent analysis** (`intent-analyze`, bật 2026-09-17): đọc
  `sublet_v_analyze_queue` (listing đã có `source_url`, `kind is null`), ghi
  thật `kind`/`subtype`/`poster_type`/`confidence`/`area`/`rent_eur`/
  `available_from`/`available_to`/`registration_allowed`/`poster_constraints`/
  `analyzed_at`... lên `sublet_listings` theo `docs/intent-logic.md`; tạo
  `sublet_seekers` (không contact) cho seeking đủ điều kiện. `poster_type`
  chỉ nhận `individual`/`company`/`anonymous`. `scam_score`/`scam_flags`/
  `deal_score` **để mặc định, chưa tính** (Kien quyết định để sau). Không
  classify `capture_unresolved` thiếu `source_url`, không đụng
  `sublet_matches`/`sublet_messages`, không gọi `scripts/match.py`, không mở
  Facebook.
