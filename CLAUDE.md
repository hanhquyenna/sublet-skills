# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Agent là **mắt và trí nhớ**; con người là **tay và tên**.

## Không bao giờ
1. **Không post, comment, like, DM, join group, hay gửi bất cứ gì trên Facebook.** Agent chỉ ĐỌC. Mọi tin đi ra do người dùng tự gửi.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Chạy theo giờ trong `data/config.yaml` (`hours`); từ 2026-09-16 theo yêu cầu Kien, `hours` đặt 24/7 (`00:00`–`23:59`), không còn giới hạn khung giờ trong ngày. Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `sublet_inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Được đọc **public profile**, lịch sử public giới hạn của poster/commenter, và comment/reply gắn với post housing đã capture để lưu raw context. Chỉ đọc nội dung đang công khai; không vào DM, nội dung private/ẩn, friend list, album/ảnh, không suy luận thuộc tính nhạy cảm, và không tách riêng số điện thoại/email thành hồ sơ liên hệ. Không thao tác trên profile/comment. Poster hiển thị là `Anonymous participant`/`Người tham gia ẩn danh` hoặc không có profile URL phải được flag là `anonymous`; giữ nguyên label, không đoán danh tính. Anonymous card chỉ access-ready khi có permalink bài viết đã validate thật.
6. Mọi agent phải thao tác Facebook bằng **visible Chrome browser-panel automation của host**, đọc DOM/accessibility tree trước (Codex: ChatGPT in-app browser panel; Claude Code: Claude in Chrome; agent khác: Chrome-panel adapter tương đương). Đây là kênh Facebook duy nhất. Không dùng CLI/script scraper, web-fetch/HTTP/API, Selenium, headless browser, Chrome session khác hoặc cookie ở nơi khác; script chỉ được dùng cho DB/provenance, **và cho việc parse cục bộ output `read_page` đã lấy về** (`scripts/extract_cards.py` — không gọi thêm request nào tới Facebook, chỉ tách card từ text đã có sẵn để agent đỡ phải tự đọc bằng mắt; xem `sublet-scrape-14-groups/SKILL.md`).
7. Không ghi outcome (signed / moved-in) nếu không có xác nhận từ subletter hoặc seeker. Không đoán.
8. Không xếp hạng seeker theo quốc tịch, giới tính, tuổi, tôn giáo, hay bất kỳ tiêu chí phân biệt nào. Chỉ: ngày, ngân sách, khu vực, số người, registration, pets.

## Luôn luôn
- Mỗi record có `source_url` + `seen_at`. Không có nguồn = không tồn tại.
- Match score tính bằng `scripts/match.py` (deterministic). LLM chỉ viết `reasons`.
- Mọi draft (DM, push, confirm) ghi vào DB với `status='draft'` và đưa cho người dùng duyệt. Chỉ người dùng đổi sang `sent`.
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
trước, link validation sau). `analyze-insights` là bước đọc-only độc lập, có
thể chạy bất kỳ lúc nào sau capture (không cần chờ validate xong) để tóm tắt
insight cho Kien; không phải pipeline `intent-analyze` chính thức. Các bước
match, draft, viewing và outreach chưa nằm trong active skill scope.

## Active scope
- **Context** (`information`): onboarding, quyền agent, DB, state và cách tiếp tục.
- **Capture** (`sublet-scrape-14-groups`): chọn tối đa 14 group, scrape raw 14 ngày,
  dedupe, resume và checkpoint DB. Không phân loại và không outreach.
- **Link validation** (`validate-permalink`): xử lý tuần tự queue link Facebook
  đã capture, giữ share URL gốc, ghi canonical URL nếu xác minh được và phân
  biệt `validated`, `inaccessible`, `needs_review`. Không scrape lại feed.
- **Insight analysis** (`analyze-insights`): đọc-only trên dữ liệu đã capture,
  ước lượng thô offering/seeking/other, phát hiện trùng lặp/repost và pattern
  rủi ro, tóm tắt vào `sublet_inbox`/`sublet_metrics`. Cũng tính ứng viên
  matching seeker↔offering (`sublet_insight_matches`, xem SKILL.md "Bước 3") —
  chỉ trên listing đã `link_validation_status='validated'` **và** không nằm
  trong `sublet_v_link_needs_reverification`. Không ghi cột phân loại chính
  thức trên `sublet_listings`, không mở Facebook, không re-đọc listing đã có
  event `insight_reviewed`, không đụng `sublet_seekers`/`sublet_matches`/
  `sublet_messages` (khác `sublet_insight_matches`, bảng riêng chỉ mang tính
  tham khảo).
