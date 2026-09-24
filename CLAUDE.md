# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Facebook mặc định read-only; ngoại lệ ghi duy nhất là DM theo rule outreach bên dưới — và ngay cả ngoại lệ đó, **agent không bao giờ tự click Send, chỉ Kien mới click**.

## Không bao giờ
1. **Không tự động post, comment, like, join group hoặc submit form trên Facebook.** Agent mặc định chỉ ĐỌC.
   - Ngoại lệ ghi duy nhất là **DM cho poster hợp lệ theo `outreach_order`** (`dashboardkien_outreach`, chưa `message1_sent`) — xem `outreach-prep/SKILL.md`. **Cập nhật 2026-09-22 (quyết định tường minh của Kien, đảo ngược bản chốt 2026-09-18):** agent mở post, verify người, mở Messenger, paste nguyên văn `message1`, **và tự click Send** — không còn chờ Kien click nữa. Xử lý theo batch (mặc định 20 người/lần chạy, Kien có thể chỉnh), đi đúng thứ tự `outreach_order`, dừng ngay nếu gặp checkpoint/CAPTCHA/login/unusual-activity hoặc trạng thái gửi không rõ ràng (rule #4 vẫn áp dụng nguyên vẹn).
   - Agent ghi vào `outreach_messages` **NGAY SAU** khi tự click Send và Facebook xác nhận gửi thành công — 1 insert/lần gửi (`status='sent'`, `sent_at=now()`), không update từ draft. Nếu UI không chắc chắn đã gửi thì **không insert gì**, dừng lại. Sau insert, ghi thêm `events(event='outreach_dm_sent', actor='agent', entity_type='post')` — `actor` là `agent` vì agent tự thực hiện hành động gửi (không còn `actor='human'`).
   - `message1_sent` tính live từ việc tồn tại 1 row `status='sent'` trong `outreach_messages` cho poster đó — tự đúng ngay khi insert, không cần set thêm ở nơi khác. Một row `status` khác (`draft`/`approved`) không tính là đã outreach — không được để nó chặn poster đó mãi mãi (fix 2026-09-21).
   - Post, comment, like, join group, submit form **vẫn tuyệt đối cấm**.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Chạy theo giờ trong `data/config.yaml` (`hours`); từ 2026-09-16 theo yêu cầu Kien, `hours` đặt 24/7 (`00:00`–`23:59`), không còn giới hạn khung giờ trong ngày. Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Được đọc **public profile**, lịch sử public giới hạn của poster/commenter, và comment/reply gắn với post housing đã capture để lưu raw context. Chỉ đọc nội dung đang công khai; không vào DM, nội dung private/ẩn, friend list, album/ảnh, không suy luận thuộc tính nhạy cảm. Không thao tác trên profile/comment.
   - **Cập nhật 2026-09-24 (quyết định tường minh của Kien, đảo ngược bản cũ "không tách riêng số điện thoại/email thành hồ sơ liên hệ"):** liên hệ mà poster **tự đăng công khai** trong post (email, số điện thoại, WhatsApp, Telegram, Instagram) và trong reply của họ (`answer1`/`answer2`), cùng Facebook profile + link post, **được** tách ra thành record theo loại trong `post_contacts` (xem `db/schema.sql`), qua `refresh_post_contacts()` — regex deterministic trên `posts.body`/`outreach_availability_answers`, idempotent, chỉ thêm cái còn thiếu, phạm vi là các post trong `dashboardkien_outreach`. Kien đọc qua view `outreach_contacts` (1 dòng/poster, 1 cột/loại). Vẫn **cấm**: lấy contact từ nguồn không công khai (DM của người khác, friend list, profile private), suy đoán contact không được viết ra, và cho `anon`/app Roomie đọc 2 object này (RLS bật, không có policy, đã `revoke` khỏi `anon`/`authenticated`). Telegram trong post là dấu hiệu scam mạnh (30/30 post có Telegram đều `scam_flag`), không phải kênh liên hệ ưu tiên. Poster hiển thị là `Anonymous participant`/`Người tham gia ẩn danh` hoặc không có profile URL phải được flag là `anonymous`; giữ nguyên label, không đoán danh tính. Anonymous card chỉ access-ready khi có permalink bài viết đã validate thật.
6. Mọi agent phải thao tác Facebook bằng **visible Chrome browser-panel automation của host**, đọc DOM/accessibility tree trước (Codex: ChatGPT in-app browser panel; Claude Code: Claude in Chrome; agent khác: Chrome-panel adapter tương đương). Đây là kênh Facebook duy nhất **cho capture chính thức** (ghi `posts`/`events` — không còn tiền tố `sublet_`, xem `db/schema.sql` — làm nguồn dữ liệu thật). Không dùng CLI/script scraper, web-fetch/HTTP/API, Selenium, headless browser, Chrome session khác hoặc cookie ở nơi khác; script chỉ được dùng cho DB/provenance, **và cho việc parse cục bộ output `read_page` đã lấy về** (`scripts/extract_cards.py` — không gọi thêm request nào tới Facebook, chỉ tách card từ text đã có sẵn để agent đỡ phải tự đọc bằng mắt; xem `sublet-scrape-14-groups/SKILL.md`).
   - **Kênh thứ 2 chính thức — Apify Facebook Groups Scraper, chỉ cho group PUBLIC (mở rộng 2026-09-17 theo yêu cầu Kien):** được phép dùng **duy nhất Apify actor `apify/facebook-groups-scraper`** (kể cả gọi thẳng API `run-sync-get-dataset-items` khi Kien đưa token) làm nguồn capture chính thức — ghi thẳng vào `posts`/`events` — nhưng **chỉ với group có `is_private=false`** (Apify không đọc được private group, tự nó đã giới hạn phạm vi). Group `is_private=true`/`null` (chưa xác minh) vẫn bắt buộc qua browser-panel như cũ. Điều kiện bắt buộc:
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
- Facebook DM: agent chuẩn bị `message1` cho poster hợp lệ theo luật #1, tự click Send, rồi ghi 1 row vào `outreach_messages` (`status='sent'`) và audit `events` (`actor='agent'`) ngay khi UI xác nhận gửi thành công. Các loại message khác (`message2`/follow-up) vẫn cần người dùng gửi — chỉ `message1` (outreach-prep) được auto-send.
- Ghi `scan_runs` mỗi chu kỳ (page_loads, new_posts) để tự kiểm soát volume.
- DB lỗi (RPC/HTTP) → thử lại 1 lần sau 5s; vẫn lỗi → dừng skill, `inbox(warning)`, không ghi nửa chừng (R21).
- Mỗi skill có khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules). Registry: `docs/rules.md`, `docs/edge-cases.md`, `docs/metrics.md`. Thêm hành vi mới = cập nhật cả 3.
- Agent không gửi thông báo đi đâu. Mọi thứ cần người dùng biết → `inbox`; người dùng đọc trực tiếp trong DB/context map.
- Ngôn ngữ giao tiếp với người dùng: tiếng Việt. Template gửi ra ngoài: EN (mặc định) hoặc NL theo `config.yaml`.

## Dữ liệu
- Supabase project ref `cteunhuxrghpozwbnehh` (`cteunhuxrghpozwbnehh.supabase.co`).
  **Không phải** project tên "Lamy" — "Lamy" là nhầm lẫn cũ trong tài liệu,
  không phải tên project thật; nếu MCP `supabase` trả về bảng khác (vd không
  có `posts`/`posters`/`dashboardkien_*`), đó là sai project, đừng đọc/ghi.
- **Bảng không còn tiền tố `sublet_`** (đổi hoàn toàn qua 15+ migration,
  2026-09-15 → nay): `posts`, `posters`, `post_details`, `post_comments`,
  `post_metrics`, `groups`, `group_metrics`, `events`, `scan_runs`,
  `ops_state`, `inbox`, `daily_metrics`, `jobs`, `outreach_messages`,
  `outreach_availability_answers`, `poster_duplicate_posts`, `post_contacts`
  (thêm 2026-09-24, xem luật #5). Chi tiết cột,
  đổi tên cụ thể (vd `kind→intent`, `raw_text→body`, `group_key→group_id`):
  `db/schema.sql` (regenerated 2026-09-21 từ introspection DB thật — tin file
  này, không tin bản cũ trước đó nếu thấy lưu ở nơi khác).
  `sublet_seekers`/`sublet_matches`/`sublet_viewings`/`sublet_fees` **không
  tồn tại**, chưa từng có data nên không migrate. Bảng seeker/demand mới (vd
  cho WhatsApp intake) phải đặt tên theo convention thật (không prefix, vd
  `seekers`), không theo tên cũ.
- Dùng Supabase MCP `execute_sql`/`apply_migration`. RPC `sublet_exec` (qua
  `scripts/db.py`) vẫn còn — từng bị xoá 2026-09-17 vì lý do bảo mật
  (arbitrary SQL), được tạo lại 2026-09-21 theo yêu cầu tường minh của Kien vì
  `scripts/db.py`/Codex path phụ thuộc nó và chưa có thay thế.
- 2 view Kien thực sự đọc: `public.dashboardkien_group` (scraping/recovery),
  `public.dashboardkien_outreach` (outreach message1). Định nghĩa đầy đủ, cập
  nhật nhất: `docs/dashboard-source-of-truth.md`.
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
Kien.

**Cảnh báo 2026-09-21:** `intent-analyze` được nhắc trong tài liệu như "pipeline
phân loại chính thức, bật 2026-09-17" nhưng **không tồn tại như một SKILL.md**
trong `.claude/skills/` — không có file, không gọi được qua `/intent-analyze`.
1121/1122 `posts` hiện đã có `intent`/`confidence` (gần như 100%), nên phân
loại rõ ràng ĐÃ xảy ra, nhưng nhiều khả năng qua 1 lần chạy tay/script rời của
đồng nghiệp, không phải qua 1 skill sống lặp lại được. Hệ quả: **post mới
capture vào (kể cả qua repair/recovery của `sublet-scrape-14-groups`) sẽ
không tự động được phân loại `intent`/`confidence` bởi bất kỳ skill nào đang
tồn tại** — cần Kien quyết định viết lại skill này hay dùng cách khác trước
khi backlog phân loại phình lên lại.

Matching và viewing chưa nằm trong active skill scope. `outreach-prep` and
`following-message` are active for strict-order first outreach and verified
reply follow-up.

## Active scope
- **Context** (`information`): onboarding, quyền agent, DB, state và cách tiếp tục.
- **Capture** (`sublet-scrape-14-groups`): chọn tối đa 14 group, scrape raw
  theo `window_days` (hiện 14 ngày — mở rộng 2026-09-23 theo yêu cầu Kien, vì
  cửa sổ 7 ngày cũ khiến `dashboardkien_outreach` co lại nhanh hơn tốc độ
  scrape/classify/validate bù vào), dedupe, resume và checkpoint DB, kèm
  find-or-create `posters`. Không phân loại và không outreach.
- **Link validation** (`validate-permalink`): xử lý tuần tự queue link Facebook
  đã capture, giữ share URL gốc, ghi canonical URL nếu xác minh được và phân
  biệt `validated`, `inaccessible`, `needs_review`. Không scrape lại feed.
- **Insight analysis** (`analyze-insights`): đọc-only trên dữ liệu đã capture,
  ước lượng thô offering/seeking/other, phát hiện trùng lặp/repost và pattern
  rủi ro, tóm tắt vào `inbox`/`daily_metrics`. Không ghi cột phân loại
  chính thức trên `posts`, không mở Facebook, không re-đọc post đã có event
  `insight_reviewed`, không đụng `outreach_messages`. Seeker↔offering matching
  đã bị **xoá bỏ hoàn toàn 2026-09-17** theo quyết định của Kien (dữ liệu phình
  lên 169k dòng, phần lớn `weak`, mà không tương xứng giá trị) — không còn tồn
  tại trong scope này. (Bảng/skill file này chưa được rà lại theo schema mới
  kể từ đợt đổi tên 2026-09-17 — xác nhận tên cột/bảng thật khi dùng.)
- **Data engineering** (`data-engineer`): DB-only normalization, provenance,
  dedupe, data-quality audits, idempotent checkpoints, customer-behavior event
  aggregates và reports. Không browse Facebook, không tự phân loại semantic,
  không làm identity enrichment và không tự động outreach. (SKILL.md hiện vẫn
  viết theo tên bảng `sublet_*` cũ — chưa được rà lại theo schema mới.)
- **Intent analysis** (`intent-analyze`): xem cảnh báo ở trên — chưa tồn tại
  như một skill sống. Nếu/khi viết lại, đọc post có `url` không null và
  `intent is null` (tương đương `sublet_v_analyze_queue` cũ), ghi
  `intent`/`subtype`/`confidence` lên `posts` và `areas`/`price_eur`/
  `available_from`/`available_to`/`registration_allowed`/`requirements`/...
  lên `post_details` theo `docs/intent-logic.md`; `poster_type` chỉ nhận
  `individual`/`company`/`anonymous`, ghi trên `posters.type`. `scam_score`/
  `scam_flags` để mặc định, chưa tính (Kien quyết định để sau). Không
  classify post thiếu `url`, không gọi `scripts/match.py`, không mở Facebook.
