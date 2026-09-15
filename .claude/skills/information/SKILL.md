---
name: information
description: "Khôi phục và duy trì context vận hành của dự án sublet-skills: vị trí file, trạng thái hiện tại, Supabase/MCP, browser, dữ liệu và các quyết định chưa chốt. Dùng trước onboarding hoặc khi agent mới cần hiểu toàn bộ dự án."
---

# information — context vận hành sublet-skills

Skill này là bản đồ context, không thay thế luật cứng hay logic chi tiết. Khi có mâu thuẫn, đọc theo thứ tự: `CLAUDE.md` → `AGENTS.md` → `PLAN.md` → tài liệu/skill chuyên môn liên quan. Không ghi secret vào repo.

## Khi dùng

- Dùng đầu mỗi session khi agent mới tiếp quản repo.
- Dùng khi người vận hành hỏi “project đang ở đâu”, “DB dùng thế nào”, hoặc context đã thay đổi.
- Trước `/sublet-scrape-14-groups`, kiểm tra snapshot dưới đây rồi đối chiếu trực tiếp bằng command/DB; không coi số liệu snapshot là bằng chứng mới nhất.

## Snapshot hiện tại

Snapshot này được ghi ngày **2026-09-16**, sau commit `c0c1a2a` và lần resume raw-capture gần nhất:

- Repo chính: `/Users/ad/sublet-skills` (thường gọi bằng `~/sublet-skills`).
- Mục tiêu: dịch vụ broker sublet nhỏ ở Amsterdam, Phase 0 trong 30 ngày.
- Người vận hành: **Kien**. Agent là mắt + trí nhớ + người soạn; Kien là người bấm/gửi.
- Offer hiện tại: người có phòng nhận 3 viewing phù hợp trong 72h; €49 khi người được giới thiệu move-in; seeker dùng miễn phí.
- Database lần kiểm tra gần nhất (2026-09-16): `sublet_groups=103`, `sublet_group_metrics=152`, `sublet_listings=27`, `sublet_events=39`, `sublet_scan_runs=6`, `sublet_ops_state=10`.
- Raw QA của group đang chạy có 27/27 listing URL duy nhất, raw capture không phân tích (`kind=null`), và 29 `context_captured` events contract v2. Có 33 public comments được lưu; 15/27 listing chưa có absolute `posted_at` vì panel không expose timestamp tuyệt đối; key contract v2 và estimate fields không thiếu; không suy luận dữ liệu không hiển thị.
- Đợt backfill group activity cao nhất đang là run resumable `sublet_scan_runs.id=7`; chronological đã vượt boundary tại card **31/08 lúc 23:40**. DB ghi `posts_seen=35`, `new_listings=23`, `posts_verified=27`, `unresolved_cards=15`, `page_loads=2/4`, `boundary_reached=true`; `posts_14d_count` vẫn `null` và `posts_14d_complete=false` vì 15 card chưa có permalink bài viết xác minh được hoặc là embedded/non-housing content. Không chuyển group khi run này chưa hoàn tất.
- Raw capture quality hiện phân bố 19 `complete`, 8 `legacy_normalized`, 2 `legacy_unknown` trong 29 events của group; duplicate URL và comment-shape audit đều sạch. `legacy_*` là trạng thái provenance của dữ liệu cũ, không phải giấy phép suy đoán nội dung còn thiếu.
- DB hiện có 75 group mang cờ `joined=true`; metric mới nhất vẫn được bổ sung từ panel trong lúc kiểm tra. Batch notification vừa đối chiếu có 44 group unique đã báo approved và đều được ghi `joined=true`. Khi hai nguồn lệch nhau, chỉ metric mới nhất có `join_status='joined'` được coi là đủ điều kiện tier 1/2.
- Group selection hiện chỉ dùng `joined=true`, loại group `allows_sublet='no'`, rồi sort theo metric `posts_per_day` mới nhất giảm dần; không tự rank lại tier trong capture.
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

## Onboarding contract cho agent

`information` là context map, không phải giấy phép vượt luật. Agent mới phải
đọc theo thứ tự: `information` → `CLAUDE.md` → `AGENTS.md` → `PLAN.md` → skill
chuyên môn cần chạy. Nếu snapshot mâu thuẫn runtime thì kiểm tra trực tiếp DB,
filesystem và browser rồi cập nhật snapshot; nếu mâu thuẫn `CLAUDE.md` thì
`CLAUDE.md` thắng.

### Quyền và giới hạn

- Agent được đọc/sửa file trong repo, chạy validator, đọc/ghi Supabase qua
  `scripts/db.py`, và commit/push khi người vận hành yêu cầu.
- Quyền filesystem/repo không có nghĩa là được thao tác Facebook. Facebook chỉ
  được đọc qua ChatGPT/Codex in-app browser panel trong session người dùng đã
  login thủ công.
- Không join group, submit form, bật notification, post, comment, like, DM,
  send, donate, đọc DM/private content, friend list hoặc album riêng tư.
- Khi gặp login/checkpoint/captcha/“unusual activity”, dừng ngay, ghi stop theo
  rule và không retry trong 24 giờ.
- DB write chỉ để lưu dữ liệu capture/progress/metrics và draft. Tin gửi ra
  ngoài luôn là `status='draft'`; chỉ Kien tự gửi.

### Skill registry hiện tại

Bộ sublet được intentionally rút gọn còn đúng **2 skills**:

- `information` — context map và onboarding chi tiết.
- `sublet-scrape-14-groups` — toàn bộ raw scraping workflow cho batch 14 group,
  gồm chọn group, resume, dedupe, capture context và DB checkpoint.

Không coi các skill sublet cũ đã xóa là dependency. Nếu cần phân tích sau này,
đó là quyết định mở rộng mới, không tự khôi phục skill cũ.

Skill source duy nhất là `/Users/ad/sublet-skills/.claude/skills/<name>/SKILL.md`.
`.agents/skills` chỉ là symlink dùng cho Codex; không tạo bản copy thứ hai.
Kiểm tra bằng:

```sh
cd /Users/ad/sublet-skills
find .claude/skills -mindepth 2 -maxdepth 2 -name SKILL.md -print | sort
```

### Database: lưu ở đâu và dùng thế nào

- Database live là Supabase project **Lamy**, ref
  `cteunhuxrghpozwbnehh`; schema chuẩn nằm tại `db/schema.sql`.
- Secret chỉ nằm ngoài repo trong `~/.sublet-skills.env`; không in, commit hoặc
  yêu cầu paste secret vào chat.
- Đường chuẩn để query/update là `python3 scripts/db.py "<SQL>"`, qua RPC
  `public.sublet_exec`; không dùng DB script để điều khiển Facebook.
- `sublet_groups`/`sublet_group_metrics`: group identity, joined/status,
  member/activity, tier và checkpoint 14 ngày.
- `sublet_listings`: raw post với `source_url`, `group_key`, poster, absolute
  `posted_at` nếu thấy, `seen_at`, full `raw_text`, `kind=null`; relative-time
  estimate (nếu parse được) chỉ nằm trong `notes`/context payload và luôn có
  uncertainty; `text_hash` do DB generate.
- `sublet_events`: provenance/context. Event raw chuẩn là
  `context_captured`, contract v2; `detail_audit` là QA riêng, không analyzer.
- `sublet_scan_runs`: run, group, page loads, counts, cursor và stop reason.
- `sublet_ops_state`/`sublet_jobs`: resumable batch/chunk progress.
- `sublet_inbox`: cảnh báo và việc Kien cần biết; `sublet_metrics`: số đo báo cáo.

### Current scrape context

Mục tiêu hiện tại là `/sublet-scrape-14-groups`: tối đa 14 group đã joined,
chọn theo `posts_per_day` mới nhất cao nhất, xử lý tuần tự từng group,
chronological, đủ 14 ngày lịch, không duplicate, ghi DB sau từng batch. Skill
này tự chứa backfill/chunk logic; không gọi skill sublet nào khác.

Trước mỗi chunk, agent phải đọc run mở và DB: ưu tiên `cursor` với
`last_verified_post_at`/`last_source_url`; `max(posted_at)` chỉ là tín hiệu
tham chiếu; `seen_at` là thời điểm quan sát, không phải thời điểm bài đăng.
URL đã tồn tại thì không insert lại. Không chuyển group khi còn card có
permalink chưa xử lý. Chỉ set `posts_14d_complete=true` khi qua boundary và
đã xử lý hết card verified; thấy nhãn “2 tuần” hoặc đạt `posts_seen` chưa đủ.

Capture raw gồm toàn bộ text post, poster/profile URL public nếu hiển thị,
comment/reply public đang thấy, commenter/profile/comment URL, timestamp tuyệt
đối nếu Facebook expose, relative label bổ sung, media metadata hiển thị và
public activity giới hạn. Event mới phải có `capture_contract_version=2`,
`capture_quality`, `scan_run_id`, `page_load`, `source_surface` và đầy đủ
`null`/`[]`/`false` keys. Không phân tích intent trong capture.

### Cách tiếp tục ở session sau

1. Đọc skill này và kiểm tra `git status`, current branch/commit.
2. Query DB để xác nhận group count, latest metric, run mở, cursor, timestamp
   và duplicate source URLs; không tin snapshot nếu runtime khác.
3. Chạy `/sublet-scrape-14-groups`; skill giữ batch state và xử lý từng group.
4. Sau mỗi batch xác nhận listing/context/run/metric đã ghi. DB outage thì retry
   một lần, dừng và giữ incomplete; không báo thành công giả.
5. Sau khi raw batch hoàn tất, chưa có analyzer trong bộ skill hiện tại; chỉ
   thêm analyzer khi Kien yêu cầu mở rộng scope.

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

Giới hạn quan trọng: scrape tối đa 4 Facebook page loads/run và tối đa 14 group/run; từng group có cửa sổ 14 ngày, cập nhật DB sau từng batch. Join do người dùng tự làm. Không cố né phát hiện automation.

## Pipeline và nơi ghi dữ liệu

Active flow chỉ là `information` → `sublet-scrape-14-groups`. Capture xong thì dừng; analyzer, matching, messaging và outreach chưa thuộc scope hiện tại.

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
