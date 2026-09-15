---
name: information
description: "Khôi phục và duy trì context vận hành của dự án sublet-skills: vị trí file, trạng thái hiện tại, Supabase/MCP, browser, dữ liệu và các quyết định chưa chốt. Dùng trước onboarding hoặc khi agent mới cần hiểu toàn bộ dự án."
---

# information — context vận hành sublet-skills

Skill này là bản đồ context, không thay thế luật cứng hay logic chi tiết. Khi có mâu thuẫn, đọc theo thứ tự: `CLAUDE.md` → `AGENTS.md` → `PLAN.md` → tài liệu/skill chuyên môn liên quan. Không ghi secret vào repo.

## Khi dùng

- Dùng đầu mỗi session khi agent mới tiếp quản repo.
- Dùng khi người vận hành hỏi “project đang ở đâu”, “DB dùng thế nào”, hoặc context đã thay đổi.
- Trước `/onboarding`, kiểm tra snapshot dưới đây rồi đối chiếu trực tiếp bằng command/DB; không coi số liệu snapshot là bằng chứng mới nhất.

## Snapshot hiện tại

Snapshot này được ghi ngày **2026-09-15**, sau commit `e6e4b65`, rank metrics và cập nhật backlog:

- Repo chính: `/Users/ad/sublet-skills` (thường gọi bằng `~/sublet-skills`).
- Mục tiêu: dịch vụ broker sublet nhỏ ở Amsterdam, Phase 0 trong 30 ngày.
- Người vận hành: **Kien**. Agent là mắt + trí nhớ + người soạn; Kien là người bấm/gửi.
- Offer hiện tại: người có phòng nhận 3 viewing phù hợp trong 72h; €49 khi người được giới thiệu move-in; seeker dùng miễn phí.
- Database lần kiểm tra gần nhất: `sublet_groups=103`, `sublet_group_metrics=152`, `sublet_listings=10`, `sublet_seekers=0`, `sublet_ops_state=9`.
- Đã audit detail page bằng ChatGPT in-app browser cho 10/10 listings hiện có. Mỗi listing có một `sublet_events.event='detail_audit'`; các bài bị feed collapse đã được lưu lại full text nhìn thấy. Tất cả vẫn `kind=null` và `posted_at=null` vì detail page không expose thời điểm tạo post đáng tin cậy.
- Đợt backfill group activity cao nhất đang là run resumable `sublet_scan_runs.id=7`; đã thấy boundary “2 tuần” nhưng chưa chứng minh capture đủ mọi card. Vì vậy `posts_14d_count` vẫn chưa được chốt và `posts_14d_complete=false`; không báo 8/10 listings đã là tổng 14 ngày.
- Raw capture QA: 10 `context_captured` events hiện chưa có payload đồng nhất cho `reaction_count`, `comment_count`, `timestamp_label`, `media[]` và `truncated`; không được coi đó là “không có dữ liệu”. `sublet-scan` đã được sửa để các lần capture sau luôn ghi đủ key với giá trị raw/null/[] phù hợp.
- DB hiện có 75 group mang cờ `joined=true`; metric mới nhất vẫn được bổ sung từ panel trong lúc kiểm tra. Batch notification vừa đối chiếu có 44 group unique đã báo approved và đều được ghi `joined=true`. Khi hai nguồn lệch nhau, chỉ metric mới nhất có `join_status='joined'` được coi là đủ điều kiện tier 1/2.
- `sublet-groups rank` đã chạy lại từ `posts_per_day`: 8 group tier 1; phân bố tier hiện tại là 8 tier 1, 7 tier 2, 83 tier 3 và 5 chưa xếp tier. `offering_7d` chưa đủ dữ liệu để ghi đè tier tạm.
- Tier 1 hiện cần Kien bật Notifications → All posts thủ công cho 8 group; các group có số cao nhưng đang pending không được đưa vào danh sách.
- Discovery Facebook dùng các batch query English/Dutch về Amsterdam, student housing, kamers, onderhuur và Nederland; tổng DB hiện có 103 group. `data/groups.yaml` đã được đồng bộ từ DB, giữ trường `keywords` và notes.
- `data/config.yaml`: city Amsterdam, timezone `Europe/Amsterdam`, agent nói tiếng Việt, template gửi ra ngoài English, tên Kien. Còn trống `email.imap_user` và `seeker_form.url`; đã thêm advisory model routing: `gpt-5.6-luna` cho intent/backfill, `gpt-6-astra` cho draft/inbox/partner voice.
- `sublet_v_today` tồn tại và lần kiểm tra trả về rỗng; chưa có pipeline DM/viewing/fee.
- Có raw listings/context để capture QA; chưa có seeker, match, DM, viewing hay fee pipeline. Không được chạy outreach chỉ từ raw capture.
- Ba quyết định để dữ liệu sau 30 ngày: `fee_trigger` (move-in hay 3 viewings/72h), promise 72h hay 24h, và có thêm `outreach-prep` hay không.

## Bản đồ project

| Mục | Vị trí | Vai trò |
|---|---|---|
| Luật cứng | `CLAUDE.md` | Cấm agent post/comment/like/DM/join; giới hạn Facebook và dừng khi checkpoint |
| Luật Codex | `AGENTS.md` | Browser panel duy nhất, DB và runner cho Codex |
| Nguồn sự thật | `PLAN.md` | Pipeline, schema logic, state machine, cron và quy trình sửa rule |
| Bàn giao | `HANDOFF.md` | Prompt tiếp quản và checklist cho agent mới |
| Hướng dẫn | `README.md` | Setup, daily loop, Phase 0 |
| Intent | `docs/intent-logic.md` | `kind`, `subtype`, `poster_type`, constraints, scam, confidence, deal score và test cases |
| Skill dùng chung | `.claude/skills/<name>/SKILL.md` | Skill gốc cho Claude/Codex |
| Symlink Codex | `.agents/skills` | Symlink tới `.claude/skills`; không tạo bản copy thứ hai |
| Database schema | `db/schema.sql` | 11 bảng `sublet_*`, RLS bật |
| Script | `scripts/` | `db.py`, `match.py`, `gmail_pull.py`, `report.py` |
| Template | `templates/` | DM offer, seeker push, viewing confirm, follow-up, FAQ EN/NL |
| Ops | `ops/` | cron Mac, Hetzner crontab, `run_skill.sh`, backup, log |
| Config/data | `data/config.yaml`, `data/groups.yaml` | city/giờ/offer và seed group/keyword |

## Supabase hiện tại

Project canonical hiện tại là **Lamy**, ref `cteunhuxrghpozwbnehh`, URL `https://cteunhuxrghpozwbnehh.supabase.co`. Không dùng project cũ/nhầm.

- Secret nằm ngoài repo trong `~/.sublet-skills.env`, mode `600`, gồm `SUPABASE_URL` và `SUPABASE_SERVICE_ROLE_KEY` (có thể có biến legacy khác). Không in giá trị, không commit, không yêu cầu Kien paste lại vào chat.
- `scripts/db.py` tự đọc file env này và ưu tiên REST RPC `sublet_exec`; workflow hiện tại **không cần** `SUPABASE_DB_URL`, psycopg2 hay source file.
- Mọi SQL từ skill Codex chạy bằng:

  ```sh
  python3 scripts/db.py "select count(*) from sublet_groups"
  ```

  SQL dài có thể truyền qua stdin: `echo "..." | python3 scripts/db.py -`.
- RPC `public.sublet_exec(q text)` đã tồn tại trên project, chạy security definer với `search_path=public`, chỉ cấp execute cho `service_role`. RPC này là runtime setup từ trước và không nằm trong `db/schema.sql`; nếu DB mới thiếu RPC, dừng và xử lý setup rõ ràng, không tự đổi project.
- Supabase MCP đã được cấu hình trong `/Users/ad/.codex/config.toml` với database feature và project ref trên. MCP là kênh phụ để inspect/SQL khi khả dụng; `scripts/db.py` là đường chạy chuẩn, dễ kiểm tra và được các skill nhắc tới.
- Schema có các bảng chính: `sublet_groups`, `sublet_listings`, `sublet_seekers`, `sublet_matches`, `sublet_viewings`, `sublet_fees`, `sublet_messages`, `sublet_events`, `sublet_scan_runs`, `sublet_ops_state`, `sublet_inbox`.
- Không sửa schema chỉ để thêm status Facebook. `sublet_groups` dùng `joined` boolean, `tier`, `is_private`, `member_count`, `notif_all_posts`, `offering_7d` và notes; trạng thái pending cần ghi rõ theo schema/skill trước khi mở rộng.

## Browser và quyền thao tác

Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng ChatGPT browser panel / Codex In-app Browser session đang mở cho người dùng**. Đây là hard rule và supersede mọi hướng dẫn Chrome DevTools/port `9222` cũ trong tài liệu khác.


DB/SQL là luồng riêng: `scripts/db.py` vẫn là kênh chuẩn để đọc/ghi Supabase, nhưng không được dùng để điều khiển Facebook.

Login Facebook là việc Kien làm tay trong ChatGPT browser panel. Agent chỉ đọc feed/search/notifications; không bấm Join, không bật notification, không post/comment/like/DM.

Nếu thấy login, checkpoint, captcha hoặc “unusual activity”: dừng, ghi stop nếu workflow yêu cầu, không retry 24h.

Giới hạn quan trọng: discovery tối đa 3 query và ≤6 Facebook page loads/tuần; scan ≤4 page loads/chu kỳ; inbox-triage ≤6; group page riêng theo daily budget; backfill từng group, cửa sổ 14 ngày, cập nhật DB sau từng batch. Join do người dùng tự làm. Không cố né phát hiện automation.

## Pipeline và nơi ghi dữ liệu

`sublet-groups` → `sublet-scan`/`sublet-email` (capture thô) → `intent-analyze` theo `docs/intent-logic.md` → `sublet-match` dùng `scripts/match.py` → `sublet-draft`/`inbox-triage` → Kien tự gửi → `viewing-coordinate` → `sublet-followup`/`sublet-report`.

- Capture chỉ lưu post thô với `source_url` + `seen_at`, chưa tự phân loại.
- Draft luôn lưu `status='draft'`; chỉ Kien đổi thành `sent`.
- `filled`, `signed`, `paid` chỉ ghi khi có xác nhận thật và kèm nguồn.
- Mọi việc cần Kien biết đưa vào `sublet_inbox`; không tự gửi notification ngoài.

## Quy tắc cập nhật context

Khi setup, DB, browser, config hoặc quyết định thay đổi:

1. Kiểm tra trực tiếp bằng command/DB trước.
2. Cập nhật phần **Snapshot hiện tại** và các file nguồn bị ảnh hưởng; giữ ngày cập nhật.
3. Không ghi secret, token, password, cookie, dữ liệu profile thành viên hoặc thông tin liên hệ riêng tư vào skill.
4. Nếu có mâu thuẫn giữa snapshot và runtime, tin runtime rồi sửa snapshot; nếu mâu thuẫn với `CLAUDE.md`, tin `CLAUDE.md`.
5. Sau thay đổi logic, theo `PLAN.md` phần H và dùng commit message `rule: <gì> vì <lý do>` khi phù hợp.
