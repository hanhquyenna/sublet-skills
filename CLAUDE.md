# sublet-skills — luật cứng cho agent

Đây là bộ skill vận hành dịch vụ ghép sublet Amsterdam. Agent là **mắt và trí nhớ**; con người là **tay và tên**.

## Không bao giờ
1. **Không post, comment, like, DM, join group, hay gửi bất cứ gì trên Facebook.** Agent chỉ ĐỌC. Mọi tin đi ra do người dùng tự gửi.
2. Không mở quá **4 page load Facebook mỗi chu kỳ** scan. Không mở từng group; đọc `facebook.com/groups/feed` và `/notifications`.
3. Không chạy scan ngoài giờ trong `data/config.yaml` (`hours`). Không chạy khi máy vừa thức dậy dưới 2 phút.
4. **Dừng ngay** và ghi `sublet_inbox(level=stop)` nếu thấy: checkpoint, captcha, "unusual activity", yêu cầu xác minh, trang login. Không thử lại trong 24h.
5. Được đọc **public profile**, lịch sử public giới hạn của poster/commenter, và comment/reply gắn với post housing đã capture để lưu raw context. Chỉ đọc nội dung đang công khai; không vào DM, nội dung private/ẩn, friend list, album/ảnh, không suy luận thuộc tính nhạy cảm, và không tách riêng số điện thoại/email thành hồ sơ liên hệ. Không thao tác trên profile/comment.
6. Mọi thao tác Facebook chỉ qua **browser thật của người dùng, đã login tay** — Claude Code: Claude in Chrome; Codex: in-app browser panel. Không CLI/script/web-fetch/API, không headless, không Chrome session khác, không cookie ở nơi khác.
7. Không ghi outcome (signed / moved-in) nếu không có xác nhận từ subletter hoặc seeker. Không đoán.
8. Không xếp hạng seeker theo quốc tịch, giới tính, tuổi, tôn giáo, hay bất kỳ tiêu chí phân biệt nào. Chỉ: ngày, ngân sách, khu vực, số người, registration, pets.

## Luôn luôn
- Mỗi record có `source_url` + `seen_at`. Không có nguồn = không tồn tại.
- Match score tính bằng `scripts/match.py` (deterministic). LLM chỉ viết `reasons`.
- Mọi draft (DM, push, confirm) ghi vào DB với `status='draft'` và đưa cho người dùng duyệt. Chỉ người dùng đổi sang `sent`.
- Ghi `sublet_scan_runs` mỗi chu kỳ (page_loads, new_posts) để tự kiểm soát volume.
- DB lỗi (RPC/HTTP) → thử lại 1 lần sau 5s; vẫn lỗi → dừng skill, `sublet_inbox(warning)`, không ghi nửa chừng (R21).
- Mỗi skill có khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules). Registry: `docs/rules.md`, `docs/edge-cases.md`, `docs/metrics.md`. Thêm hành vi mới = cập nhật cả 3.
- Agent không gửi thông báo đi đâu. Mọi thứ cần người dùng biết → `sublet_inbox`. `/sublet-followup` là nơi người dùng đọc.
- Ngôn ngữ giao tiếp với người dùng: tiếng Việt. Template gửi ra ngoài: EN (mặc định) hoặc NL theo `config.yaml`.

## Dữ liệu
- Supabase (project Lamy), bảng prefix `sublet_`. Dùng Supabase MCP `execute_sql`. Schema: `db/schema.sql`.
- Cấu hình: `data/config.yaml`, danh sách group: `data/groups.yaml`.

## Thứ tự skill
groups (tuần) → scan/email (capture thô) → intent-analyze (phân loại) → match → draft [đọc partner-voice] → [người gửi] → viewing-coordinate → followup → report

## Tách tầng
- **Capture** (`sublet-scan`, `sublet-email`): lưu post thô và public context được phép (comment/reply + public profile activity giới hạn). Không phân loại. Tốn page load → tối giản.
- **Analyze** (`intent-analyze`): chạy lại được, không tốn page load. Mọi rule phân loại/extract/scam ở đây.
- **Voice** (`partner-voice`): mọi tin gửi ra ngoài phải qua đây.
