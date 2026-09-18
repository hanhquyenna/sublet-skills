# sublet-skills

> **Active scope (cập nhật 2026-09-18):** `information` →
> `sublet-scrape-14-groups` → `validate-permalink` theo thứ tự, cộng
> `analyze-insights` (đọc-only, tóm tắt insight, không phải pipeline chính
> thức) và `data-engineer` (DB-only QA/normalization/behavior aggregates).
> **`intent-analyze` đã bật chính thức từ 2026-09-17** (ghi thật
> `kind`/`subtype`/`poster_type`/... — xem `CLAUDE.md`), và **`outreach-prep`**
> đọc view `dashboardkien_outreach` để soạn **draft** DM theo đúng thứ tự
> `outreach_order`; agent được gửi **draft đã tồn tại** qua browser panel khi
> agent tự gửi trực tiếp `message1` cho poster hợp lệ theo `outreach_order`,
> ghi `outreach_messages` ngay sau khi gửi thành công (không còn draft/status).
> Matching
> seeker↔offering (`sublet_insight_matches`) đã bị **xoá bỏ hoàn toàn
> 2026-09-17** (Kien quyết định, dữ liệu bloat không tương xứng giá trị).
>
> **⚠️ Supabase schema đã migrate hoàn toàn 2026-09-17** — bảng `sublet_*`
> nhắc trong README này (bên dưới, ở phần Kiến trúc/Setup) là schema CŨ, đã
> đổi thành `posts`/`posters`/`post_details`/`post_metrics`/`post_comments`/
> `outreach_messages`/`groups`; RPC `sublet_exec` mà `scripts/db.py` gọi đã bị
> xoá — `db.py` hiện **không dùng được**. Chi tiết đầy đủ, đúng nhất luôn nằm
> ở [.claude/skills/information/SKILL.md](.claude/skills/information/SKILL.md)
> mục "Database" — đọc ở đó trước khi đụng DB, đừng tin phần README dưới đây
> cho tới khi được cập nhật lại theo schema mới.

Bộ skill Claude Code để vận hành dịch vụ ghép sublet Amsterdam: agent đọc Facebook (chỉ trong ChatGPT browser panel đang mở cho bạn, chỉ đọc), giữ pool seeker, ghép theo ngày/giá/khu, soạn tin — **bạn gửi**. Offer: *3 người phù hợp đến viewing trong 72h, €49 nếu được, không thì free.*

Đọc [CLAUDE.md](CLAUDE.md) trước — đó là luật cứng. Kế hoạch chi tiết (logic từng skill, schema, cron, cách cập nhật): [PLAN.md](PLAN.md). Codex: [AGENTS.md](AGENTS.md). Context/runtime snapshot: [.claude/skills/information/SKILL.md](.claude/skills/information/SKILL.md). Prompt bàn giao cho agent: [HANDOFF.md](HANDOFF.md). Logic phân loại post bằng lời: [docs/intent-logic.md](docs/intent-logic.md). Registry: [rules](docs/rules.md) · [edge-cases](docs/edge-cases.md) · [metrics](docs/metrics.md) · [audit 2026-09-15](docs/audit-2026-09-15.md). Mỗi skill mở đầu bằng khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules).

## Kiến trúc

```
Claude Code (Mac)                         Supabase (project riêng, ref cteunhuxrghpozwbnehh)
 ├─ Claude in Chrome → đọc Facebook         posts · posters · post_details · post_comments
 ├─ Apify actor (group public, có filter)   outreach_messages · groups · events · scan_runs
 ├─ scripts/match.py → chấm điểm (chưa dùng)  view: dashboardkien_group, dashboardkien_outreach
 └─ /sublet-scrape-14-groups (manual)       Không có browser automation/cron ngầm
```

*(Không phải project "Lamy" (`gcrolhshguehtshjmcmx`) — đó là project khác,
đừng nhầm khi dùng MCP Supabase mặc định. Xem
[.claude/skills/information/SKILL.md](.claude/skills/information/SKILL.md).)*

## Setup (30 phút)

1. **Supabase**: project riêng cho sublet, ref `cteunhuxrghpozwbnehh` (không
   phải "Lamy"). RLS bật, `anon`/`authenticated` đã bị revoke hoàn toàn — chỉ
   `service_role` đọc/ghi được. `db/schema.sql` trong repo đang mô tả schema
   **cũ** (pre-2026-09-17), chưa cập nhật theo migration thật (`posts`/
   `posters`/`post_details`/...) — đừng chạy nó vào DB hiện tại. `scripts/db.py`
   đang **hỏng** (RPC `sublet_exec` nó gọi đã bị xoá 2026-09-17); đọc/ghi tạm
   qua REST trực tiếp với `SUPABASE_SERVICE_ROLE_KEY` từ `~/.sublet-skills.env`
   cho tới khi có thay thế. Chi tiết: `.claude/skills/information/SKILL.md`.
2. **Facebook browser**: đăng nhập Facebook thủ công trong ChatGPT browser panel. Mọi search/đọc/verify Facebook chỉ chạy trong panel này; không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie nơi khác. Join các group trong `data/groups.yaml` bằng tay (2–5 group/ngày). Trong mỗi group tier 1–2: Notifications → **All posts**.
3. **config**: `data/config.yaml` — điền `email.imap_user`, `offer.your_first_name`. Giá/offer đã đặt €49.
4. **Env**: `zsh ops/setup_env.sh` khi cần bổ sung biến — file `~/.sublet-skills.env` (chmod 600) giữ secret Supabase/IMAP, còn `data/config.yaml` giữ config không-secret. Không commit file env.
5. **Seeker form**: tạo Tally form với các cột: name, contact, consent (checkbox), move_in, move_out, budget, areas, people, registration_need, pets, occupation, viewing_availability. Export CSV → `data/seekers_export.csv`.
6. Mở Codex trong thư mục này, đọc `/information`, rồi chạy
   `/sublet-scrape-14-groups` khi muốn bắt đầu capture. Hiện chưa bật cron tự động
   cho scrape/validate (đêm 2026-09-16 có thử bật cron 20 phút rồi Kien yêu cầu
   gỡ lại trong cùng phiên — xem lịch sử git nếu cần bật lại có chủ đích).

## Current loop

| Bước | Lệnh | Kết quả |
|---|---|---|
| 1 | `/information` | Khôi phục context, quyền, DB và cursor hiện tại |
| 2 | `/sublet-scrape-14-groups` | Capture tuần tự tối đa 14 group, mỗi group 14 ngày |
| 3 | `/validate-permalink` | Validate queue link Facebook đã capture, resume từ DB |
| 4 | `/intent-analyze` | Ghi thật `kind`/`subtype`/`poster_type`/`confidence`/... lên listing đã có `source_url` (bật 2026-09-17) |
| 5 | `/outreach-prep` | Soạn draft theo `outreach_order`; agent có thể gửi **pre-existing draft** nguyên văn qua browser panel theo send permission trong skill |
| — | `/analyze-insights` | Đọc-only, chạy bất kỳ lúc nào sau bước 2: tóm tắt offering/seeking/duplicate/risk cho Kien, bỏ qua listing đã review |
| — | `/data-engineer` | DB-only: normalize, audit provenance, dedupe, checkpoint, customer-behavior aggregates và report |

Match/viewing chính thức (bảng riêng, không phải seeker↔offering matching cũ
đã bị xoá) vẫn ngoài active scope hiện tại.

## Skills

| Skill | Làm gì | Gửi gì ra ngoài? |
|---|---|---|
| `information` | Context/runtime snapshot, quyền agent, DB, state và onboarding | Không |
| `sublet-scrape-14-groups` | Chọn tối đa 14 group, capture raw 14 ngày tuần tự, resume/dedupe/checkpoint | Không |
| `validate-permalink` | Kiểm tra link từng listing trong browser panel, ghi validated/inaccessible/needs_review | Không |
| `analyze-insights` | Đọc-only trên DB (không mở Facebook): offering/seeking/other thô, cụm trùng lặp, cờ rủi ro, tóm tắt vào inbox/metrics; không re-đọc listing đã `insight_reviewed` | Không |
| `data-engineer` | Chuẩn hoá raw/insight/lifecycle events, QA, dedupe, provenance, behavior aggregates và report; không browse Facebook, không semantic matching/outreach | Không |
| `intent-analyze` | Phân loại chính thức offering/seeking/other, `poster_type`, `confidence`, area/rent/date, ghi thật lên DB (bật 2026-09-17) | Không |
| `outreach-prep` | Gửi trực tiếp `message1` theo `outreach_order`; ghi `outreach_messages` chỉ sau khi gửi thành công (không draft/status) | **Có, có điều kiện** — agent tự gửi theo `outreach_order`, không cần hỏi lại từng tin; body phải giữ nguyên và audit sau khi gửi |

## Giới hạn an toàn (đã code vào skill)
- ≤4 page load Facebook/chu kỳ, ≤~400/ngày, 24/7 (đổi từ 08–23h ngày 2026-09-16 theo yêu cầu Kien), dừng ngay khi thấy checkpoint.
- Agent không bao giờ post/comment/like/join/submit form. DM là ngoại lệ duy nhất: gửi trực tiếp `message1` cho poster hợp lệ (không `scam_flag`, chưa `has_outreached`) qua visible browser panel, ghi `outreach_messages` chỉ sau khi gửi thành công, theo `outreach-prep`.
- Không thu tiền hộ, không giữ deposit, không chuyển địa chỉ chính xác qua bạn.
- Không xếp hạng theo quốc tịch/giới tính/tuổi.

## Phase 0 — capture hiện tại

Mục tiêu đang bật là hoàn tất raw capture 14 ngày cho tối đa 14 group đã joined,
ghi từng batch vào DB, resume từ cursor và không duplicate. Phân tích offering,
matching, messaging và outreach chỉ mở lại khi Kien yêu cầu.

Dưới mốc → đổi offer/giá, không đổi kiến trúc. Đạt mốc → lúc đó mới viết daemon + Hetzner cho phần email/matching, và giữ Chrome trên Mac (hoặc Mac mini) cho phần đọc.

## Hetzner (chưa bật)

Không có sublet cron đang hoạt động. Facebook capture chỉ chạy thủ công trong
ChatGPT browser panel trên máy của Kien; không chạy Facebook trên VPS.
