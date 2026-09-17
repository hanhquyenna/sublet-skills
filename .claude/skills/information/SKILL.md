---
name: information
description: "Khôi phục và duy trì context vận hành của dự án sublet-skills: vị trí file, trạng thái hiện tại, Supabase/MCP, browser, dữ liệu và các quyết định chưa chốt. Dùng trước onboarding hoặc khi agent mới cần hiểu toàn bộ dự án."
---

# information — context vận hành sublet-skills

Skill này là bản đồ context, không thay thế luật cứng hay logic chi tiết. Khi có mâu thuẫn, đọc theo thứ tự: `CLAUDE.md` → hướng dẫn host-specific (ví dụ `AGENTS.md` cho Codex) → `PLAN.md` → tài liệu/skill chuyên môn liên quan. Không ghi secret vào repo.

## Khi dùng

- Dùng đầu mỗi session khi agent mới tiếp quản repo.
- Dùng khi người vận hành hỏi “project đang ở đâu”, “DB dùng thế nào”, hoặc context đã thay đổi.
- Trước `/sublet-scrape-14-groups`, kiểm tra snapshot dưới đây rồi đối chiếu trực tiếp bằng command/DB; không coi số liệu snapshot là bằng chứng mới nhất.

## Snapshot hiện tại

Snapshot này được ghi ngày **2026-09-16**, sau lần resume raw-capture gần nhất; luôn đối chiếu runtime trước khi hành động:

- Repo chính: `/Users/ad/sublet-skills` (thường gọi bằng `~/sublet-skills`).
- Mục tiêu: dịch vụ broker sublet nhỏ ở Amsterdam, Phase 0 trong 30 ngày.
- Người vận hành: **Kien**. Agent là mắt + trí nhớ + người soạn; Kien là người bấm/gửi.
- Offer hiện tại: người có phòng nhận 3 viewing phù hợp trong 72h; €49 khi người được giới thiệu move-in; seeker dùng miễn phí.
- Database lần kiểm tra gần nhất (2026-09-16): `sublet_groups=103`, `sublet_group_metrics=152`, `sublet_listings=57`, `sublet_events=70`, `sublet_scan_runs=6`, `sublet_ops_state=10`; validation queue có 54 listing `unvalidated`, 2 `validated`, 1 `inaccessible` (các số này là snapshot, phải query lại trước khi dùng).
- **Cập nhật đêm 2026-09-16 (sau snapshot trên, vẫn phải query lại):** đã validate hết 54 record cũ (29 verify thật qua browser panel `link_resolution_method='direct_permalink'`, 25 record bulk-mark `validated` theo lệnh trực tiếp của Kien **không** mở link — phân biệt qua `link_resolution_method='bulk_unverified_override'` trong event `link_validated` hoặc `link_validation_note`). Group 1 (`amsterdam-housing-apartments-rooms-287563233830552`) đã lên 61 listings, vẫn `posts_14d_complete=false`, 6 card unresolved gần mốc 31/8 chưa tìm ra; Kien quyết định đánh dấu group này `blocked` trong `scrape_14_groups_batch` (operator decision, không phải FB blocker) và chuyển `current_index` sang group 2 (`amsterdam-apartment-and-rooms-for-rent-no-agencies-please-231203323708543`).
- **Group 2: `posts_14d_complete=true` (chốt 2026-09-16).** Sau 1 phiên dài (~1h20') + 1 phiên dọn dẹp + 1 lượt resume: 14 listings, 185 `capture_unresolved` (dedupe 4 bản trùng do bug RPC "returning" — xem gotcha trong `scripts/db.py`; chuẩn hoá lại `capture_quality` cho 161/185 record về đúng 3 giá trị enum `complete`/`partial`/`legacy_normalized`, không tự phong `complete` khi chỉ dọn từ DB). Boundary xác nhận tại card ngày 2026-09-01 (trước window bắt đầu 2026-09-03). Đây **không phải** re-verify zero-gap từng scroll (group 108K thành viên, quá active để làm nổi) — chỉ đạt tiêu chuẩn nới lỏng 2026-09-16: boundary qua + mọi card có raw data. `current_index` đã chuyển sang group 3, giờ cũng đã complete (xem dòng dưới).
- **Group 3 (`amsterdam-apartments-rent-share-sell-flats-netherlands-1041179470847701`): `posts_14d_complete=true` (chốt 2026-09-16).** 18 listings + 55 `capture_unresolved` = 73 record. Boundary xác nhận qua comment timestamp "2 tuần" (trước window 2026-09-03). Từ giữa batch này trở đi dùng cách nhanh hơn: ghi `capture_unresolved` thẳng từ text/poster thấy trong feed, **không** click mở permalink cho từng card (đúng rule nới lỏng — link không chặn completion), nên phần lớn card group3 có `link_resolution_method='not_attempted'`, `post_id=null`. Nhiều poster/text trùng với group1/group2 (spam cross-post: Aminu Muh'd, Fatima Haruna, HelpfulReindeer9448, Idris Yusuf Sulaiman, Alhassan Barbie/Tiamiyu Sukurat template "Modern Studio and apartments"...). `current_index` đã chuyển sang group 4 (`expats-netherlands-housing-work-amsterdam-utrecht-den-haag-1157446251688203`), chưa scrape gì.
- **Gotcha `scripts/db.py`/`sublet_exec`:** RPC dò chữ "returning" bằng regex trên toàn bộ câu lệnh, kể cả trong text/JSON literal (không chỉ mệnh đề SQL RETURNING thật) — gây "syntax error near into" cho INSERT/UPDATE bình thường nếu nội dung ghi vào chứa chữ đó. Tránh dùng chữ "returning" trong bất kỳ text nào truyền qua `db.py`.
- **Cron scrape/validate: đã thử rồi gỡ lại cùng đêm 2026-09-16.** Một phiên
  từng thêm launchd job `com.sublet.scrape_and_validate` (mỗi 1200s, gọi
  `sublet-scrape-14-groups` rồi `validate-permalink` nối tiếp qua
  `ops/run_scrape_and_validate.sh`); job này **chưa từng thực sự cài trên
  máy** (không có trong `launchctl list`/plist khi kiểm tra lại), và Kien yêu
  cầu bỏ hẳn script + tài liệu đó vì "chỉ là tạm cho phiên này". `ops/install_cron.sh`
  và README đã revert về chỉ có `com.sublet.backup` (23:30). `data/config.yaml→hours`
  vẫn giữ 24/7 (`00:00`–`23:59`, xem CLAUDE.md #3) vì đó là yêu cầu riêng, không
  gắn với cron đã gỡ. `ops/run_skill.sh` vẫn nhận `validate-permalink` trong
  whitelist (hữu ích khi gọi tay/`claude -p` thủ công), chỉ phần lịch tự động
  20 phút là bị gỡ.
- **Matching removed (2026-09-17):** seeker↔offering matching
  (`sublet_insight_matches`, từng thêm đêm 2026-09-16) đã bị Kien quyết định
  bỏ hẳn — bảng phình lên 169,012 dòng (152,501 `weak`-tier, do lỗi thiết kế
  combinatorial ở scale lớn) mà không tương xứng giá trị. Bảng và view liên
  quan (`sublet_v_insight_matches_report`) đã bị drop khỏi DB và schema; xem
  ghi chú tương ứng trong `analyze-insights/SKILL.md`. `outreach-prep` giờ
  nguồn candidate trực tiếp từ `sublet_listings`, không qua bước matching nào.
- **Recall-first matching rule (chốt 2026-09-16):** không có post/public
  activity/comment/profile link hoặc thiếu field không có nghĩa là actor không
  có offering, seeker intent hay không phù hợp. Giữ `unknown`/`partial` trong
  review pool; chỉ hard-exclude khi có contradiction rõ ràng hoặc hard rule
  khác. Ưu tiên false positive hơn false negative; không đảo ngược rule này
  chỉ vì corpus capture hiện tại chưa đủ.
- Raw QA của group đang chạy có 57 listing URL duy nhất, 57 `context_captured` tương ứng 1–1, raw capture không phân tích (`kind=null`). Các link mới giữ share URL nếu chưa resolve và ghi method `facebook_copy_link`; timestamp/field không hiển thị vẫn giữ null và có missing fields; không suy luận dữ liệu không hiển thị.
- Đợt backfill group activity cao nhất đang là run resumable `sublet_scan_runs.id=7`; chronological đã vượt boundary tại card **31/08 lúc 23:40**. DB ghi `posts_seen=66`, `new_listings=54`, `posts_verified=58`, `unresolved_cards=6`, `page_loads=4/4`, `boundary_reached=true`; `posts_14d_count` vẫn `null` và `posts_14d_complete=false` vì còn card unresolved/partial. Không chuyển group khi run này chưa hoàn tất.
- Chín card mới đã được xử lý bằng browser panel qua Share → Sao chép liên kết và ghi checkpoint: Prince Rajput (2), Luana Ilídia, Jerry Meng, Ella Rule, HelpfulReindeer9448, Luis Miguel Remiro Pernia, Lia Proti và Michiel Weerts. Duplicate listing URL và one-to-one listing/context QA của group đang sạch; `context_captured` vẫn tách khỏi `detail_audit`.
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
| Luật host-specific | `CLAUDE.md`, `AGENTS.md` | Luật cứng chung và hướng dẫn adapter/runner theo agent |
| Nguồn sự thật | `PLAN.md` | Pipeline, schema logic, state machine, cron và quy trình sửa rule |
| Bàn giao | `HANDOFF.md` | Prompt tiếp quản và checklist cho agent mới |
| Hướng dẫn | `README.md` | Setup, daily loop, Phase 0 |
| Intent | `docs/intent-logic.md` | `kind`, `subtype`, `poster_type`, constraints, scam, confidence, deal score và test cases |
| Skill dùng chung | `.claude/skills/<name>/SKILL.md` | Skill gốc dùng được cho Claude Code, Codex và agent tương thích |
| Symlink Codex | `.agents/skills` | Symlink tới `.claude/skills`; host khác dùng source skill chung |
| Database schema | `db/schema.sql` | 11 bảng `sublet_*`, RLS bật |
| Script | `scripts/` | `db.py`, `match.py`, `gmail_pull.py`, `report.py` |
| Template | `templates/` | DM offer, seeker push, viewing confirm, follow-up, FAQ EN/NL |
| Ops | `ops/` | cron Mac, Hetzner crontab, `run_skill.sh`, backup, log |
| Config/data | `data/config.yaml`, `data/groups.yaml` | city/giờ/offer và seed group/keyword |

## Onboarding contract cho agent

`information` là context map, không phải giấy phép vượt luật. Agent mới phải
đọc theo thứ tự: `information` → `CLAUDE.md` → hướng dẫn host-specific (ví dụ
`AGENTS.md` cho Codex) → `PLAN.md` → skill chuyên môn cần chạy. Nếu snapshot
mâu thuẫn runtime thì kiểm tra trực tiếp DB, filesystem và browser rồi cập nhật
snapshot; nếu mâu thuẫn `CLAUDE.md` thì `CLAUDE.md` thắng.

### Quyền và giới hạn

- Agent được đọc/sửa file trong repo, chạy validator, đọc/ghi Supabase qua
  `scripts/db.py`, và commit/push khi người vận hành yêu cầu.
- Quyền filesystem/repo không có nghĩa là được thao tác Facebook. **Mọi agent
  phải dùng visible Chrome browser-panel automation của host và đọc DOM/
  accessibility tree của panel trước.** Claude Code dùng Claude in Chrome,
  Codex dùng ChatGPT in-app browser panel, agent khác dùng Chrome-panel adapter
  tương đương được host cung cấp. Đây là kênh Facebook duy nhất; không dùng
  CLI/script scraper, web-fetch/HTTP/API, Selenium, headless, Chrome session
  khác hoặc cookie ở nơi khác.
- Không join group, submit form, bật notification, post, comment, like, DM,
  send, donate, đọc DM/private content, friend list hoặc album riêng tư.
- Khi gặp login/checkpoint/captcha/“unusual activity”, dừng ngay, ghi stop theo
  rule và không retry trong 24 giờ.
- DB write chỉ để lưu dữ liệu capture/progress/metrics và draft. Tin gửi ra
  ngoài luôn là `status='draft'`; chỉ Kien tự gửi.

### Skill registry hiện tại

Bộ sublet hiện có đúng **5 skills active**:

- `information` — context map và onboarding chi tiết.
- `sublet-scrape-14-groups` — toàn bộ raw scraping workflow cho batch 14 group,
  gồm chọn group, resume, dedupe, capture context và DB checkpoint.
- `validate-permalink` — xử lý tuần tự queue link đã capture trong browser panel;
  giữ share URL gốc, ghi canonical URL nếu xác minh được và phân biệt
  `validated`, `inaccessible`, `needs_review`.
- `analyze-insights` — đọc-only trên DB, không mở Facebook; ước lượng thô
  offering/seeking/other, phát hiện trùng lặp/repost và pattern rủi ro, tóm tắt
  vào `sublet_inbox`/`sublet_metrics`. Không ghi `kind`/`subtype`/`scam_score`
  chính thức (nhường cho `intent-analyze` khi được bật) và không re-đọc listing
  đã có event `insight_reviewed` (Kien: 2026-09-16, "chỉ analyze để chỉ ra
  insight thôi, đừng analyze lại data đã analyze rồi"). Bước matching
  seeker↔offering (`sublet_insight_matches`) đã bị **xoá bỏ hoàn toàn
  2026-09-17** theo quyết định của Kien — không còn trong scope skill này.
- `data-engineer` — DB-only normalization, provenance, dedupe, data-quality,
  checkpoint, customer-behavior events và aggregate/report; không browse
  Facebook, không tự phân loại semantic hay outreach.

Không coi các skill sublet cũ đã xóa là dependency (ví dụ `intent-analyze`,
`sublet-groups`, `sublet-backfill` — thư mục còn rỗng, không có `SKILL.md`,
chỉ là tàn dư lịch sử). Nếu cần khôi phục scope của chúng, đó là quyết định mở
rộng mới của Kien, không tự khôi phục.

Skill source duy nhất là `/Users/ad/sublet-skills/.claude/skills/<name>/SKILL.md`.
`.agents/skills` chỉ là symlink cho Codex; không tạo bản copy thứ hai ở host
khác.
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
  uncertainty; `text_hash` do DB generate. Link mới bắt đầu ở
  `link_validation_status='unvalidated'`; `link_validated_url` giữ canonical
  sau khi validator xác nhận, còn `source_url` luôn giữ evidence gốc.
- `sublet_events`: provenance/context. Event raw chuẩn là
  `context_captured`, contract v2; `detail_audit` là QA riêng, không analyzer.
- `sublet_scan_runs`: run, group, page loads, counts, cursor và stop reason.
- `sublet_ops_state`/`sublet_jobs`: resumable batch/chunk progress.
- `sublet_inbox`: cảnh báo và việc Kien cần biết; `sublet_metrics`: số đo báo cáo.

#### Tổng quan toàn bộ 15 bảng `sublet_*` (row count snapshot 2026-09-16, luôn query lại)

**Lưu ý quan trọng:** `sublet_groups.tier` (1/2/3) là **mức ưu tiên nhóm có sẵn
trong DB từ trước** (dùng để chọn group nào đưa vào batch scrape), **không
liên quan** đến số thứ tự "group 1, group 2, ... group 14" trong
`scrape_14_groups_batch.group_keys` — đó chỉ là vị trí trong danh sách batch
đang chạy. Một agent từng nhầm hai khái niệm này và kết luận sai rằng "tier 2
chưa được scrape vì thiếu code" rồi đề xuất sửa `scripts/match.py` thành
scraper CLI — **sai hoàn toàn**: `match.py` là script chấm điểm match
(deterministic, R11), không phải scraper; và mọi scraping Facebook **chỉ được
làm qua browser panel thủ công**, không bao giờ qua CLI/script (CLAUDE.md rule
#6). Batch 14-group hiện tại chỉ chọn tier 1 và tier 3 (không có tier 2 nào)
theo quyết định chủ động khi lập danh sách, không phải lỗi/thiếu sót.

| Bảng | Row count | Mô tả ngắn |
|---|---|---|
| `sublet_groups` | 103 | Danh mục group Facebook đã discover: `key`, `url`, `tier` (ưu tiên chọn group), `joined`, `member_count`, `allows_sublet`, keywords/notes. |
| `sublet_group_metrics` | 158 | Metric theo group theo thời điểm check: `posts_per_day`, `posts_14d_count`, `posts_14d_complete`, `posts_14d_checked_at`, `join_status`. **Có duplicate row cho vài group_key** (bug đã biết, task cleanup đã spawn) — khi query, ưu tiên row có `posts_14d_checked_at` mới nhất. |
| `sublet_listings` | 95 | Listing đã resolve thành record có cấu trúc (thường sau `validate-permalink` hoặc `data-engineer` normalize): `source_url`, `group_key`, poster, `raw_text`, `link_validation_status`. |
| `sublet_seekers` | 0 | Seeker profile — chưa dùng, thuộc scope matching/outreach tương lai. |
| `sublet_matches` | 0 | Match chính thức seeker↔listing — chưa dùng. |
| `sublet_viewings` | 0 | Lịch viewing — chưa dùng. |
| `sublet_fees` | 0 | Phí dịch vụ (€49 khi move-in) — chưa dùng. |
| `sublet_messages` | 12 | Draft tin nhắn/DM (`status='draft'` mặc định; chỉ Kien đổi `sent`, trừ khi `outreach.auto_dm=true` — xem CLAUDE.md #1). |
| `sublet_events` | 958 | Event log provenance cho mọi hành động ghi nhận. Phân bố theo loại: `capture_unresolved` 433 (raw card không chase link, phổ biến nhất từ 2026-09-16 trở đi), `insight_reviewed` 198, `context_captured` 95, `listing_normalized` 95, `comment_reviewed` 61, `link_validated` 56, `detail_audit` 10, `capture_reconciled` 5, `group_joined_confirmed` 3, `link_inaccessible` 1, `capture_quality_cleanup` 1. |
| `sublet_scan_runs` | 74 | Một row/run scrape (≤4 page load): `group_key`, `page_loads`, `posts_seen`, `new_listings`, `cursor`, `stopped_reason`. Dùng để tính R03 (≤350 page load/24h). |
| `sublet_ops_state` | 12 | State máy resumable dạng key-value JSON, quan trọng nhất là `scrape_14_groups_batch` (group_keys, current_index, completed[], blocked[], current_progress). |
| `sublet_inbox` | 7 | Cảnh báo/thông tin Kien cần đọc (level=stop/warning/info). |
| `sublet_metrics` | 21 | Số đo báo cáo tổng hợp (không phải per-group, khác `sublet_group_metrics`). |
| `sublet_jobs` | 0 | Job/chunk resumable khác `sublet_ops_state` — hiện chưa dùng. |

**Tình trạng batch 14-group (2026-09-16, snapshot — query `scrape_14_groups_batch` để lấy số mới nhất):**
6/14 group đã `posts_14d_complete=true` (group2 no-agencies-please: 199 record;
group3 apartments-rent-share-sell: 73 record; group4 expats-netherlands: 50
record; group5 housing-rooms-sublets-3396...: 32 `capture_unresolved`; group6
woning-huren-in-amsterdam: 63 `capture_unresolved`; group7
amsterdam-rooms-and-apartments (172K): 42 `capture_unresolved`). Group1
(`amsterdam-housing-apartments-rooms-287563233830552`) là `blocked` (operator
decision, 61 listings nhưng 6 card cũ chưa resolve, không phải FB chặn).
Group8 (`apartments-for-rent-in-amsterdam-housing-rooms-studios-sublets-expats`,
2.9K thành viên) đang dở, mới ~4/14 ngày, 8 event đã ghi — resume từ
`current_progress` trong ops_state. Nhóm nhỏ này có nhiều dấu hiệu scam
(ảnh watermark lạ, comment bị tắt, template giá €500-2000 lặp lại) và trùng
với scam ring "Modern Studio and apartments" đã thấy ở group5 — xác nhận scam
ring hoạt động xuyên nhiều group.

### Current scrape context

Mục tiêu hiện tại là `/sublet-scrape-14-groups` rồi `/validate-permalink`, có
thể xen `/data-engineer` để QA/normalize/aggregate và `/analyze-insights` bất
kỳ lúc nào sau capture để xem tình hình: tối đa 14 group đã joined,
chọn theo `posts_per_day` mới nhất cao nhất, xử lý tuần tự từng group,
chronological, đủ 14 ngày lịch, không duplicate, ghi DB sau từng batch. Skill
này tự chứa backfill/chunk logic; sau capture gọi riêng `validate-permalink`,
không gọi analyzer/match/outreach.

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
Anonymous poster (`Anonymous participant`/`Người tham gia ẩn danh` hoặc trạng
thái ẩn danh không có profile URL) phải giữ nguyên label và được flag
`anonymous_poster=true`; không đoán danh tính. Card anonymous chỉ
`anonymous_access_ready=true` sau khi có usable post permalink đã validate
thật; share URL chưa validate hoặc card không có link không được dùng cho
profile follow-up hay outreach.

### Cách tiếp tục ở session sau

1. Đọc skill này và kiểm tra `git status`, current branch/commit.
2. Query DB để xác nhận group count, latest metric, run mở, cursor, timestamp
   và duplicate source URLs; không tin snapshot nếu runtime khác.
3. Chạy `/sublet-scrape-14-groups`; skill giữ batch state và xử lý từng group.
4. Chạy `/validate-permalink`; skill lấy record đầu tiên còn
   `link_validation_status='unvalidated'`, xử lý tuần tự và resume từ DB.
5. Sau mỗi batch xác nhận listing/context/run/metric đã ghi. DB outage thì retry
   một lần, dừng và giữ incomplete; không báo thành công giả.
6. Muốn xem tình hình chung, chạy `/analyze-insights` (đọc-only, không mở
  Facebook) — skill tự bỏ qua listing đã có event `insight_reviewed`, chỉ xử
  lý phần mới. Đây vẫn không phải pipeline `intent-analyze` chính thức; chỉ
  thêm pipeline đó khi Kien yêu cầu mở rộng scope.
7. Khi cần biến raw/insight thành dataset queryable hoặc kiểm tra customer
   behavior, chạy `/data-engineer`; skill này không mở Facebook và không thay
   đổi semantic fields chính thức.

## Supabase hiện tại

Project canonical hiện tại là **Lamy**, ref `cteunhuxrghpozwbnehh`, URL `https://cteunhuxrghpozwbnehh.supabase.co`. Không dùng project cũ/nhầm.

- Secret nằm ngoài repo trong `~/.sublet-skills.env`, mode `600`, gồm `SUPABASE_URL` và `SUPABASE_SERVICE_ROLE_KEY` (có thể có biến legacy khác). Không in giá trị, không commit, không yêu cầu Kien paste lại vào chat.
- `scripts/db.py` tự đọc file env này và ưu tiên REST RPC `sublet_exec`; workflow hiện tại **không cần** `SUPABASE_DB_URL`, psycopg2 hay source file.
- Mọi SQL từ skill chạy bằng:

  ```sh
  python3 scripts/db.py "select count(*) from sublet_groups"
  ```

  SQL dài có thể truyền qua stdin: `echo "..." | python3 scripts/db.py -`.
- RPC `public.sublet_exec(q text)` đã tồn tại trên project, chạy security definer với `search_path=public`, chỉ cấp execute cho `service_role`. RPC này là runtime setup từ trước và không nằm trong `db/schema.sql`; nếu DB mới thiếu RPC, dừng và xử lý setup rõ ràng, không tự đổi project.
- Codex có thể có Supabase MCP trong `/Users/ad/.codex/config.toml`; agent
  khác có thể dùng connector/MCP riêng nếu host cung cấp. Đây chỉ là kênh phụ
  để inspect/SQL khi khả dụng; `scripts/db.py` đọc `~/.sublet-skills.env` và là
  đường chạy chuẩn, không phụ thuộc agent.
- Schema có các bảng chính: `sublet_groups`, `sublet_listings`, `sublet_seekers`, `sublet_matches`, `sublet_viewings`, `sublet_fees`, `sublet_messages`, `sublet_events`, `sublet_scan_runs`, `sublet_ops_state`, `sublet_inbox`.
- Không sửa schema chỉ để thêm status Facebook. `sublet_groups` dùng `joined` boolean, `tier`, `is_private`, `member_count`, `notif_all_posts`, `offering_7d` và notes; trạng thái pending cần ghi rõ theo schema/skill trước khi mở rộng.

## Browser và quyền thao tác

Mọi thao tác Facebook (search, đọc, verify) **chỉ dùng visible Chrome browser
panel automation có UI trong session browser thật đã được người dùng login thủ
công; ưu tiên DOM/accessibility tree của panel**. Claude Code dùng Claude in
Chrome; Codex dùng ChatGPT in-app browser panel; agent khác dùng Chrome-panel
adapter tương đương được host cung cấp. Không dùng CLI/script scraper,
web-fetch/HTTP/API, Selenium, headless browser, cookie ở nơi khác, hay browser
session khác. Rule này supersede mọi hướng dẫn Chrome DevTools/port `9222` cũ.


DB/SQL là luồng riêng: `scripts/db.py` vẫn là kênh chuẩn để đọc/ghi Supabase, nhưng không được dùng để điều khiển Facebook.

Login Facebook là việc Kien làm tay trong browser UI tương ứng. Agent chỉ đọc
feed/search/notifications; không bấm Join, không bật notification,
không post/comment/like/DM.

Nếu thấy login, checkpoint, captcha hoặc “unusual activity”: dừng, ghi stop nếu workflow yêu cầu, không retry 24h.

Giới hạn quan trọng: scrape tối đa 4 Facebook page loads/run và tối đa 14 group/run; từng group có cửa sổ 14 ngày, cập nhật DB sau từng batch. Join do người dùng tự làm. Không cố né phát hiện automation.

## Pipeline và nơi ghi dữ liệu

Active flow là `information` → `sublet-scrape-14-groups` →
`validate-permalink`, cộng `analyze-insights` chạy độc lập bất kỳ lúc nào sau
capture. Capture xong thì validator xử lý queue link; `analyze-insights` chỉ
tóm tắt insight đọc-only. Pipeline `intent-analyze` chính thức, messaging và
outreach chưa thuộc scope hiện tại.

- Capture chỉ lưu post thô với `source_url` + `seen_at`, chưa tự phân loại và
  chưa mở link để resolve. Share URL là evidence hợp lệ nhưng bắt đầu ở trạng
  thái `unvalidated`; card không lấy được link vẫn lưu `capture_unresolved`.
- Validation chỉ mở từng link trong panel, xác nhận group/poster/content rồi
  ghi trạng thái và provenance event. Checkpoint/login/UI lỗi là
  `needs_review`, không phải `inaccessible`.
- `analyze-insights` chỉ đọc `raw_text` đã có, ghi event `insight_reviewed` +
  snapshot `sublet_inbox`/`sublet_metrics`; không đụng `kind`/`subtype`/
  `scam_score` chính thức và không mở Facebook.
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
