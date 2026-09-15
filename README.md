# sublet-skills

> **Active scope (2026-09-16):** bốn skill sublet: `information`,
> `sublet-scrape-14-groups`, `validate-permalink` theo thứ tự, cộng
> `analyze-insights` (đọc-only, chạy độc lập bất kỳ lúc nào sau capture để tóm
> tắt insight — không phải pipeline `intent-analyze` chính thức). Các phần
> phân tích đầy đủ, matching, messaging, outreach, email và Hetzner bên dưới
> là historical/future notes, không phải workflow đang bật.

Bộ skill Claude Code để vận hành dịch vụ ghép sublet Amsterdam: agent đọc Facebook (chỉ trong ChatGPT browser panel đang mở cho bạn, chỉ đọc), giữ pool seeker, ghép theo ngày/giá/khu, soạn tin — **bạn gửi**. Offer: *3 người phù hợp đến viewing trong 72h, €49 nếu được, không thì free.*

Đọc [CLAUDE.md](CLAUDE.md) trước — đó là luật cứng. Kế hoạch chi tiết (logic từng skill, schema, cron, cách cập nhật): [PLAN.md](PLAN.md). Codex: [AGENTS.md](AGENTS.md). Context/runtime snapshot: [.claude/skills/information/SKILL.md](.claude/skills/information/SKILL.md). Prompt bàn giao cho agent: [HANDOFF.md](HANDOFF.md). Logic phân loại post bằng lời: [docs/intent-logic.md](docs/intent-logic.md). Registry: [rules](docs/rules.md) · [edge-cases](docs/edge-cases.md) · [metrics](docs/metrics.md) · [audit 2026-09-15](docs/audit-2026-09-15.md). Mỗi skill mở đầu bằng khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules).

## Kiến trúc

```
Claude Code (Mac)                         Supabase (project Lamy, bảng sublet_*)
 ├─ ChatGPT browser panel → đọc Facebook    listings · seekers · matches · viewings
 ├─ scripts/match.py → chấm điểm            fees · messages · events · scan_runs
 └─ /sublet-scrape-14-groups (manual)       Không có browser automation/cron ngầm
```

## Setup (30 phút)

1. **Supabase**: project Lamy hiện tại ref `cteunhuxrghpozwbnehh`; chạy `db/schema.sql` nếu DB mới (đã apply cho project hiện tại). RLS bật, không policy → chỉ MCP/service role đọc ghi. Codex dùng `scripts/db.py`, tự đọc `~/.sublet-skills.env` và REST RPC `sublet_exec`.
2. **Facebook browser**: đăng nhập Facebook thủ công trong ChatGPT browser panel. Mọi search/đọc/verify Facebook chỉ chạy trong panel này; không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie nơi khác. Join các group trong `data/groups.yaml` bằng tay (2–5 group/ngày). Trong mỗi group tier 1–2: Notifications → **All posts**.
3. **config**: `data/config.yaml` — điền `email.imap_user`, `offer.your_first_name`. Giá/offer đã đặt €49.
4. **Env**: `zsh ops/setup_env.sh` khi cần bổ sung biến — file `~/.sublet-skills.env` (chmod 600) giữ secret Supabase/IMAP, còn `data/config.yaml` giữ config không-secret. Không commit file env.
5. **Seeker form**: tạo Tally form với các cột: name, contact, consent (checkbox), move_in, move_out, budget, areas, people, registration_need, pets, occupation, viewing_availability. Export CSV → `data/seekers_export.csv`.
6. Mở Codex trong thư mục này, đọc `/information`, rồi chạy
   `/sublet-scrape-14-groups` khi muốn bắt đầu capture. Hiện chưa bật cron tự động.

## Current loop

| Bước | Lệnh | Kết quả |
|---|---|---|
| 1 | `/information` | Khôi phục context, quyền, DB và cursor hiện tại |
| 2 | `/sublet-scrape-14-groups` | Capture tuần tự tối đa 14 group, mỗi group 14 ngày |
| 3 | `/validate-permalink` | Validate queue link Facebook đã capture, resume từ DB |
| — | `/analyze-insights` | Đọc-only, chạy bất kỳ lúc nào sau bước 2: tóm tắt offering/seeking/duplicate/risk cho Kien, bỏ qua listing đã review |

Pipeline `intent-analyze` chính thức, match, messaging, viewing và outreach đều ngoài active scope hiện tại.

## Skills

| Skill | Làm gì | Gửi gì ra ngoài? |
|---|---|---|
| `information` | Context/runtime snapshot, quyền agent, DB, state và onboarding | Không |
| `sublet-scrape-14-groups` | Chọn tối đa 14 group, capture raw 14 ngày tuần tự, resume/dedupe/checkpoint | Không |
| `validate-permalink` | Kiểm tra link từng listing trong browser panel, ghi validated/inaccessible/needs_review | Không |
| `analyze-insights` | Đọc-only trên DB (không mở Facebook): offering/seeking/other thô, cụm trùng lặp, cờ rủi ro, tóm tắt vào inbox/metrics; không re-đọc listing đã `insight_reviewed` | Không |

## Giới hạn an toàn (đã code vào skill)
- ≤4 page load Facebook/chu kỳ, ≤~400/ngày, chỉ 08–23h, dừng ngay khi thấy checkpoint.
- Agent không bao giờ post/comment/like/DM/join. Mọi tin đi ra do người gửi.
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
