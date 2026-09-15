# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Agent là **mắt và trí nhớ**; con người là **tay và tên**.

## Không bao giờ
1. **Không post, comment, like, DM, join group, hay gửi bất cứ gì trên Facebook.** Agent chỉ ĐỌC. Mọi tin đi ra do người dùng tự gửi.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Không chạy scan ngoài giờ trong `data/config.yaml` (`hours`). Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `sublet_inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Không đọc profile member, không lưu ảnh, không lưu số điện thoại/email từ post trừ khi poster tự ghi trong post và cần để liên hệ.
6. Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel đang mở cho người dùng**. Không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie ở nơi khác để thao tác/verify Facebook.
7. Không ghi outcome (signed / moved-in) nếu không có xác nhận từ subletter hoặc seeker. Không đoán.
8. Không xếp hạng seeker theo quốc tịch, giới tính, tuổi, tôn giáo, hay bất kỳ tiêu chí phân biệt nào. Chỉ: ngày, ngân sách, khu vực, số người, registration, pets.

## Luôn luôn
- Mỗi record có `source_url` + `seen_at`. Không có nguồn = không tồn tại.
- Match score tính bằng `scripts/match.py` (deterministic). LLM chỉ viết `reasons`.
- Mọi draft (DM, push, confirm) ghi vào DB với `status='draft'` và đưa cho người dùng duyệt. Chỉ người dùng đổi sang `sent`.
- Ghi `sublet_scan_runs` mỗi chu kỳ (page_loads, new_posts) để tự kiểm soát volume.
- Agent không gửi thông báo đi đâu. Mọi thứ cần người dùng biết → `sublet_inbox`. `/sublet-followup` là nơi người dùng đọc.
- Ngôn ngữ giao tiếp với người dùng: tiếng Việt. Template gửi ra ngoài: EN (mặc định) hoặc NL theo `config.yaml`.

## Dữ liệu
- Supabase (project Lamy), bảng prefix `sublet_`. Dùng Supabase MCP `execute_sql`. Schema: `db/schema.sql`.
- Cấu hình: `data/config.yaml`, danh sách group: `data/groups.yaml`.

## Thứ tự skill
groups (tuần) → scan/email (capture thô) → intent-analyze (phân loại) → match → draft [đọc partner-voice] → [người gửi] → viewing-coordinate → followup → report

## Tách tầng
- **Capture** (`sublet-scan`, `sublet-email`): chỉ lưu post thô. Không phân loại. Tốn page load → tối giản.
- **Analyze** (`intent-analyze`): chạy lại được, không tốn page load. Mọi rule phân loại/extract/scam ở đây.
- **Voice** (`partner-voice`): mọi tin gửi ra ngoài phải qua đây.
