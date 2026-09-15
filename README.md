# sublet-skills

Bộ skill Claude Code để vận hành dịch vụ ghép sublet Amsterdam: agent đọc Facebook (chỉ trong ChatGPT browser panel đang mở cho bạn, chỉ đọc), giữ pool seeker, ghép theo ngày/giá/khu, soạn tin — **bạn gửi**. Offer: *3 người phù hợp đến viewing trong 72h, €49 nếu được, không thì free.*

Đọc [CLAUDE.md](CLAUDE.md) trước — đó là luật cứng. Kế hoạch chi tiết (logic từng skill, schema, cron, cách cập nhật): [PLAN.md](PLAN.md). Codex: [AGENTS.md](AGENTS.md). Context/runtime snapshot: [.claude/skills/information/SKILL.md](.claude/skills/information/SKILL.md). Prompt bàn giao cho agent: [HANDOFF.md](HANDOFF.md). Logic phân loại post bằng lời: [docs/intent-logic.md](docs/intent-logic.md). Registry: [rules](docs/rules.md) · [edge-cases](docs/edge-cases.md) · [metrics](docs/metrics.md) · [audit 2026-09-15](docs/audit-2026-09-15.md). Mỗi skill mở đầu bằng khối **Spec** (lịch · trigger · đọc · ghi · metrics · edge cases · rules).

## Kiến trúc

```
Claude Code (Mac)                         Supabase (project Lamy, bảng sublet_*)
 ├─ ChatGPT browser panel → đọc Facebook    listings · seekers · matches · viewings
 ├─ scripts/match.py → chấm điểm            fees · messages · events · scan_runs
 └─ /loop 12m /sublet-scan                 Hetzner (sau): cron /sublet-email, không cần browser
```

## Setup (30 phút)

1. **Supabase**: project Lamy hiện tại ref `cteunhuxrghpozwbnehh`; chạy `db/schema.sql` nếu DB mới (đã apply cho project hiện tại). RLS bật, không policy → chỉ MCP/service role đọc ghi. Codex dùng `scripts/db.py`, tự đọc `~/.sublet-skills.env` và REST RPC `sublet_exec`.
2. **Facebook browser**: đăng nhập Facebook thủ công trong ChatGPT browser panel. Mọi search/đọc/verify Facebook chỉ chạy trong panel này; không dùng CLI, script, web-fetch/API, headless browser, Chrome session khác, hoặc cookie nơi khác. Join các group trong `data/groups.yaml` bằng tay (2–5 group/ngày). Trong mỗi group tier 1–2: Notifications → **All posts**.
3. **config**: `data/config.yaml` — điền `email.imap_user`, `offer.your_first_name`. Giá/offer đã đặt €49.
4. **Env**: `zsh ops/setup_env.sh` khi cần bổ sung biến — file `~/.sublet-skills.env` (chmod 600) giữ secret Supabase/IMAP, còn `data/config.yaml` giữ config không-secret. Không commit file env.
5. **Seeker form**: tạo Tally form với các cột: name, contact, consent (checkbox), move_in, move_out, budget, areas, people, registration_need, pets, occupation, viewing_availability. Export CSV → `data/seekers_export.csv`.
6. Mở Codex trong thư mục này rồi gõ `/onboarding` — nó dắt qua các bước còn lại. Cron do bạn tự cài nếu cần (`zsh ops/install_cron.sh`).

## Daily loop

| Giờ | Lệnh | Bạn làm |
|---|---|---|
| 08:30 | `/sublet-followup` | Đọc ≤10 việc, gửi các draft |
| 08:30–23:00 | `/loop 12m /sublet-scan` | Để chạy nền. Việc mới rơi vào `sublet_inbox` |
| khi có listing tốt | (tự động) `/intent-analyze` → `/sublet-match` → `/sublet-draft` | Copy DM, mở post, gửi tay. Gõ `/sublet-draft sent <id>` |
| subletter "ok" | `/viewing-coordinate <listing>` | Gửi shortlist, chốt slot, gửi contact |
| sau viewing | `/viewing-coordinate showed\|no_show <viewing_id>` | Gửi Tikkie khi đủ 3 viewing |
| 18:00 | `/sublet-report` | Đọc metrics |
| tuần 1 lần | `/sublet-report 30d` | Quyết định group lên/xuống tier |

Có seeker mới: dán tin nhắn của họ vào chat và gõ `/seeker-intake`. Post của bạn 0 phản hồi: `/sublet-diagnose <link>`.

## Skills

| Skill | Làm gì | Gửi gì ra ngoài? |
|---|---|---|
| `information` | Context/runtime snapshot: project, DB, browser, file map, quyết định | Không |
| `onboarding` | Checklist khởi động, tự kiểm + hỏi bạn, ghi sublet_ops_state | Không |
| `inbox-triage` | Đọc reply (Messenger đọc-only / bạn dán) → phân loại → cập nhật trạng thái → draft trả lời (FAQ điền sẵn) | **Bạn gửi** |
| `sublet-groups` | Tìm group (FB search, đọc-only), rank tier theo offering/7d, cursor chống lặp | Không |
| `sublet-backfill` | Đọc lịch sử 60–90 ngày của 1 group, 1 lần, human pace → corpus để soi edge case trước khi DM | Không |
| `sublet-scan` | **Capture-only**: groups/feed + notifications → post thô (link, text, time, group), dừng ở cursor | Không |
| `intent-analyze` | Post thô → intent (subletter/sublettee), requirements có cấu trúc, scam score, tự match | Không |
| `partner-voice` | Giọng + luật nói với subletter (xin hợp tác) và người tìm nhà (free, broker được subletter trả) | — (được draft/followup dùng) |
| `sublet-email` | Email notification FB → listings (chạy được trên Hetzner) | Không |
| `seeker-intake` | Tally/WhatsApp/text → seekers | Không |
| `sublet-match` | `match.py` → sublet_matches có lý do | Không |
| `sublet-draft` | DM offer + push seeker → `status='draft'` | **Bạn gửi** |
| `viewing-coordinate` | Shortlist 3, slot, reminder, fee trigger | **Bạn gửi** |
| `sublet-followup` | Việc hôm nay + draft follow-up | **Bạn gửi** |
| `sublet-diagnose` | Vì sao post 0 view | Không |
| `sublet-report` | Metrics Phase 0 → sublet_inbox | Không |

## Giới hạn an toàn (đã code vào skill)
- ≤4 page load Facebook/chu kỳ, ≤~400/ngày, chỉ 08–23h, dừng ngay khi thấy checkpoint.
- Agent không bao giờ post/comment/like/DM/join. Mọi tin đi ra do người gửi.
- ≤10 DM offer/ngày. Mỗi thread ≤2 follow-up.
- Không thu tiền hộ, không giữ deposit, không chuyển địa chỉ chính xác qua bạn.
- Không xếp hạng theo quốc tịch/giới tính/tuổi.

## Phase 0 — 30 ngày, câu hỏi cần trả lời
1. Bao nhiêu offering thật/ngày, group nào? (`/sublet-report`)
2. DM → "ok" bao nhiêu %? (mốc 30%)
3. Listing accepted → 3 viewing trong 72h bao nhiêu %? (mốc 50%)
4. Show-up? Fee thu được? (mốc 70% / 70%)
5. Subletter có chịu thêm "apply via link" vào post không?

Dưới mốc → đổi offer/giá, không đổi kiến trúc. Đạt mốc → lúc đó mới viết daemon + Hetzner cho phần email/matching, và giữ Chrome trên Mac (hoặc Mac mini) cho phần đọc.

## Hetzner (Phase 2)
Chỉ chạy: `sublet-email`, `sublet-match`, `sublet-followup` (draft), `sublet-report`. **Không bao giờ** chạy Chrome/Facebook trên VPS — IP datacenter + session cá nhân = checkpoint.
