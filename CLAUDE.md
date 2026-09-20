# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Facebook mặc định read-only; outreach dùng `message1` nguyên văn và chỉ auto-send khi premessage/auto-send đã bật.

## Không bao giờ
1. **Không tự động post, comment, like, join group hoặc submit form trên Facebook.** Agent mặc định chỉ ĐỌC.
   - Agent chỉ bấm Send khi người dùng đã cho phép việc gửi và workflow yêu cầu gửi. Khi gửi, dùng body nguyên văn trong database.
   - Sau UI send thành công, ghi row `status='sent'`, `sent_at`, và audit `events(event='outreach_dm_sent', actor='agent', entity_type='post')`. Nếu UI không chắc đã gửi thì không ghi.
   - Post, comment, like, join group, submit form **vẫn tuyệt đối cấm** dù cờ `auto_dm` là gì.
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
- Mọi confirmed Facebook DM phải được ghi vào `outreach_messages` **sau** khi UI cho thấy đã gửi; sau đó ghi audit `events`. Nếu schema có `status`, ghi `sent`; nếu không có, không yêu cầu cột đó. Không ghi trước khi gửi và không ghi khi trạng thái UI mơ hồ.
- Ghi `sublet_scan_runs` mỗi chu kỳ (page_loads, new_posts) để tự kiểm soát volume.
- DB lỗi (RPC/HTTP) → thử lại 1 lần sau 5s; vẫn lỗi → dừng skill, `sublet_inbox(warning)`, không ghi nửa chừng (R21).
- Mỗi skill có khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules). Registry: `docs/rules.md`, `docs/edge-cases.md`, `docs/metrics.md`. Thêm hành vi mới = cập nhật cả 3.
- Agent không gửi thông báo đi đâu. Mọi thứ cần người dùng biết → `sublet_inbox`; người dùng đọc trực tiếp trong DB/context map.
- Ngôn ngữ giao tiếp với người dùng: tiếng Việt. Template gửi ra ngoài: EN (mặc định) hoặc NL theo `config.yaml`.

## Dữ liệu
- Supabase (project Lamy), bảng prefix `sublet_`. Dùng Supabase MCP `execute_sql`. Schema: `db/schema.sql`.
- Cấu hình: `data/config.yaml`, danh sách group: `data/groups.yaml`.

### Outreach / reply-follow-up data rules
- `dashboardkien_outreach` is the authoritative ordered queue. Resume by the
  lowest `outreach_order` whose outcome is neither a confirmed outgoing DM nor
  an explicit `outreach_unavailable=true`; never resume from a count.
- `following-message` is the separate reply workflow. It trusts a fresh,
  identity-matched incoming Messenger message, not a preview, unread dot,
  stale accessibility tree, or screenshot from another thread.
- A live `message2_sent` view property is derived from confirmed outgoing
  `outreach_messages` rows. It must not be set from a pasted draft.

## Thứ tự skill hiện tại
`information` → `sublet-scrape-14-groups` → `validate-permalink` (raw capture
trước, link validation sau). `data-engineer` là lớp DB-only để QA, normalize,
aggregate và report; `analyze-insights` là bước đọc-only độc lập, có thể chạy
bất kỳ lúc nào sau capture (không cần chờ validate xong) để tóm tắt insight cho
Kien. `intent-analyze` (bật 2026-09-17) là pipeline phân loại chính thức, ghi
thật `kind`/`subtype`/`poster_type`/... lên `sublet_listings` đã có
`source_url`; scam/deal scoring vẫn để mặc định, chưa bật. Matching và viewing chưa nằm trong active skill scope. `outreach-prep` and `following-message` are active for strict-order first outreach and verified reply follow-up.

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
