# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Facebook mặc định read-only; ngoại lệ ghi duy nhất là DM theo rule outreach bên dưới — và ngay cả ngoại lệ đó, **agent không bao giờ tự click Send, chỉ Kien mới click**.

## Không bao giờ
1. **Không tự động post, comment, like, join group hoặc submit form trên Facebook.** Agent mặc định chỉ ĐỌC.
   - Ngoại lệ ghi duy nhất là **DM cho poster hợp lệ theo `outreach_order`** (`dashboardkien_outreach`, chưa `message1_sent`) — xem `outreach-prep/SKILL.md`. Từ 2026-09-18 (bản chốt): agent mở post, verify người, mở Messenger, paste nguyên văn `message1`, rồi **dừng lại và chờ Kien tự click Send** — agent không bao giờ tự click Send, dưới bất kỳ lý do hay yêu cầu nào. Không còn cờ `auto_dm`, không còn mô hình "agent tự gửi cả queue".
   - Agent chỉ ghi vào `outreach_messages` **NGAY SAU** khi Kien xác nhận đã click Send và Facebook xác nhận gửi thành công — 1 insert/lần gửi (`status='sent'`, `sent_at=now()`), không update từ draft. Nếu Kien không click hoặc UI không chắc thì **không insert gì**. Sau insert, ghi thêm `events(event='outreach_dm_sent', actor='human', entity_type='post')` — `actor` là `human` vì Kien là người thực hiện hành động gửi.
   - `message1_sent` tính live từ việc tồn tại 1 row `status='sent'` trong `outreach_messages` cho poster đó — tự đúng ngay khi insert, không cần set thêm ở nơi khác. Một row `status` khác (`draft`/`approved`) không tính là đã outreach — không được để nó chặn poster đó mãi mãi (fix 2026-09-21).
   - Post, comment, like, join group, submit form **vẫn tuyệt đối cấm**.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Chạy theo giờ trong `data/config.yaml` (`hours`); từ 2026-09-16 theo yêu cầu Kien, `hours` đặt 24/7 (`00:00`–`23:59`), không còn giới hạn khung giờ trong ngày. Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Được đọc **public profile**, lịch sử public giới hạn của poster/commenter, và comment/reply gắn với post housing đã capture để lưu raw context. Chỉ đọc nội dung đang công khai; không vào DM, nội dung private/ẩn, friend list, album/ảnh, không suy luận thuộc tính nhạy cảm, và không tách riêng số điện thoại/email thành hồ sơ liên hệ. Không thao tác trên profile/comment. Poster hiển thị là `Anonymous participant`/`Người tham gia ẩn danh` hoặc không có profile URL phải được flag là `anonymous`; giữ nguyên label, không đoán danh tính. Anonymous card chỉ access-ready khi có permalink bài viết đã validate thật.
6. Mọi agent phải thao tác Facebook bằng **visible Chrome browser-panel automation của host**, đọc DOM/accessibility tree trước (Codex: ChatGPT in-app browser panel; Claude Code: Claude in Chrome; agent khác: Chrome-panel adapter tương đương). Đây là kênh Facebook duy nhất **cho capture chính thức** (ghi `posts`/`events` — không còn tiền tố `sublet_`, xem `db/schema.sql` — làm nguồn dữ liệu thật). Không dùng CLI/script scraper, web-fetch/HTTP/API, Selenium, headless browser, Chrome session khác hoặc cookie ở nơi khác; script chỉ được dùng cho DB/provenance, **và cho việc parse cục bộ output `read_page` đã lấy về** (`scripts/extract_cards.py` — không gọi thêm request nào tới Facebook, chỉ tách card từ text đã có sẵn để agent đỡ phải tự đọc bằng mắt; xem `sublet-scrape-14-groups/SKILL.md`).
   - **Kênh thứ 2 chính thức — Apify, chỉ cho group PUBLIC (mở rộng 2026-09-17 theo yêu cầu Kien; actor selection mở rộng 2026-09-23 theo yêu cầu tường minh của Kien):** được phép dùng **bất kỳ actor Apify nào agent tự chọn** (kể cả gọi thẳng API `run-sync-get-dataset-items` khi Kien đưa token) làm nguồn capture chính thức — ghi thẳng vào `posts`/`events` — không còn giới hạn cứng vào 1 actor cố định (`apify/facebook-groups-scraper` không còn là lựa chọn bắt buộc duy nhất, agent tự cân nhắc actor phù hợp nhất mỗi lần, ví dụ theo giá, độ phủ, chất lượng dữ liệu trả về). Actor tự chọn vẫn phải thoả **toàn bộ** điều kiện sau, không có ngoại lệ:
     - **Chỉ actor đọc-only, không cần đăng nhập/cookie/session Facebook thật** — cấm tuyệt đối actor yêu cầu login, actor dùng credential/cookie của tài khoản Facebook thật, hay actor có khả năng ghi (post/comment/join/DM).
     - **Chỉ actor scrape post công khai trong group** — cấm actor đọc profile riêng, comment, friend list, album/ảnh, Messenger/DM, hay bất kỳ nội dung không công khai nào, dù actor có khả năng kỹ thuật để làm việc đó.
     - **Chỉ với group có `is_private=false`** (Apify không đọc được private group một cách hợp lệ, tự nó đã giới hạn phạm vi). Group `is_private=true`/`null` (chưa xác minh) vẫn bắt buộc qua browser-panel như cũ.
     - Ghi provenance trung thực: `capture_methods` chứa `"apify_api"` (không giả làm `detail_dom_a11y`/browser-panel), `source_surface="apify_api"`, và tên actor thật đã dùng (vd `payload.apify_actor="apify/facebook-groups-scraper"`) — để review sau biết chính xác actor nào tạo ra record nào, vì giờ actor không cố định.
     - Kết quả thô của Apify **không tự động trust** — vẫn phải lọc aggregator/spam (thực tế đo được: group7 test cho thấy ~85% kết quả "mới nhất" là bot repost `Student Housing Amsterdam`/`RentHunter`), lọc trùng `duplicate_of`, rồi mới ghi listing.
     - `poster.profile_url` từ Apify có thể là token `pfbid...` (không phải ID số như browser-panel lấy được, tuỳ actor) — vẫn ghi nhưng đánh dấu `profile_url_type="pfbid"` trong payload khi gặp, vì không dùng để tạo `facebook.com/profile.php?id=` được như thường lệ.
     - Vẫn phải qua `analyze-insights`/`intent-analyze` để classify offering/seeking — Apify chỉ thay thế bước đọc raw text, không thay bước phân loại.
     - Không dùng Apify để đọc comment, profile riêng, hay DM — ngoài phạm vi kênh này, bất kể actor nào.
     - Chi phí tính theo usage Apify — báo Kien số tiền ước tính (và actor định dùng) trước mỗi lần chạy batch lớn (>1 group/run), và trước lần đầu dùng một actor mới chưa từng chạy.
7. Không ghi outcome (signed / moved-in) nếu không có xác nhận từ subletter hoặc seeker. Không đoán.
8. Không xếp hạng seeker theo quốc tịch, giới tính, tuổi, tôn giáo, hay bất kỳ tiêu chí phân biệt nào. Chỉ: ngày, ngân sách, khu vực, số người, registration, pets.

## Luôn luôn
- Mỗi record có `source_url` + `seen_at`. Không có nguồn = không tồn tại.
- Match score tính bằng `scripts/match.py` (deterministic). LLM chỉ viết `reasons`.
- Facebook DM: agent chuẩn bị `message1` cho poster hợp lệ theo luật #1 rồi dừng chờ Kien tự click Send; chỉ sau khi Kien gửi và UI xác nhận mới ghi 1 row vào `outreach_messages` (`status='sent'`, `actor='human'` trên event) và ghi audit `events`. Các loại message khác vẫn cần người dùng gửi.
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
  `outreach_availability_answers`, `poster_duplicate_posts`. Chi tiết cột,
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
  theo `window_days` (hiện 7 ngày), dedupe, resume và checkpoint DB, kèm
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
