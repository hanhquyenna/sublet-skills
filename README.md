# sublet-skills

Bộ skill Claude Code để vận hành dịch vụ ghép sublet Amsterdam: agent đọc Facebook (trong Chrome thật của bạn, chỉ đọc), giữ pool seeker, ghép theo ngày/giá/khu, soạn tin — **bạn gửi**. Offer: *3 người phù hợp đến viewing trong 72h, €49 nếu được, không thì free.*

Đọc [CLAUDE.md](CLAUDE.md) trước — đó là luật cứng.

## Kiến trúc

```
Claude Code (Mac)                         Supabase (project Lamy, bảng sublet_*)
 ├─ Claude in Chrome → đọc groups/feed      listings · seekers · matches · viewings
 ├─ scripts/match.py → chấm điểm            fees · messages · events · scan_runs
 ├─ Telegram MCP     → báo cáo cho BẠN
 └─ /loop 12m /sublet-scan                 Hetzner (sau): cron /sublet-email, không cần browser
```

## Setup (30 phút)

1. **Supabase**: chạy `db/schema.sql` (đã apply nếu bạn dùng project Lamy qua MCP). RLS bật, không policy → chỉ MCP/service role đọc ghi.
2. **Chrome**: đăng nhập Facebook trong Chrome thật. Join các group trong `data/groups.yaml` bằng tay (2–5 group/ngày, đừng vội). Trong mỗi group tier 1–2: Notifications → **All posts**.
3. **config**: `data/config.yaml` — điền `telegram.chat_id`, `email.imap_user`. Giá/offer đã đặt €49.
4. **Email (tuỳ chọn, cho 24/7)**: Gmail App Password → `export SUBLET_IMAP_USER=... SUBLET_IMAP_PASS=...` trong `~/.zshrc`. Không commit.
5. **Seeker form**: tạo Tally form với các cột: name, contact, consent (checkbox), move_in, move_out, budget, areas, people, registration_need, pets, occupation, viewing_availability. Export CSV → `data/seekers_export.csv`.
6. Mở Claude Code trong thư mục này: `cd ~/sublet-skills && claude`.

## Daily loop

| Giờ | Lệnh | Bạn làm |
|---|---|---|
| 08:30 | `/sublet-followup` | Đọc ≤10 việc, gửi các draft |
| 08:30–23:00 | `/loop 12m /sublet-scan` | Để chạy nền. Telegram báo khi có sublet mới |
| khi có listing tốt | (tự động) `/sublet-match` → `/sublet-draft` | Copy DM, mở post, gửi tay. Gõ `/sublet-draft sent <id>` |
| subletter "ok" | `/viewing-coordinate <listing>` | Gửi shortlist, chốt slot, gửi contact |
| sau viewing | `/viewing-coordinate showed\|no_show <viewing_id>` | Gửi Tikkie khi đủ 3 viewing |
| 18:00 | `/sublet-report` | Đọc metrics |
| tuần 1 lần | `/sublet-report 30d` | Quyết định group lên/xuống tier |

Có seeker mới: dán tin nhắn của họ vào chat và gõ `/seeker-intake`. Post của bạn 0 phản hồi: `/sublet-diagnose <link>`.

## Skills

| Skill | Làm gì | Gửi gì ra ngoài? |
|---|---|---|
| `sublet-scan` | groups/feed + notifications → listings, scam score, tự match | Không |
| `sublet-email` | Email notification FB → listings (chạy được trên Hetzner) | Không |
| `seeker-intake` | Tally/WhatsApp/text → seekers | Không |
| `sublet-match` | `match.py` → sublet_matches có lý do | Không |
| `sublet-draft` | DM offer + push seeker → `status='draft'` | **Bạn gửi** |
| `viewing-coordinate` | Shortlist 3, slot, reminder, fee trigger | **Bạn gửi** |
| `sublet-followup` | Việc hôm nay + draft follow-up | **Bạn gửi** |
| `sublet-diagnose` | Vì sao post 0 view | Không |
| `sublet-report` | Metrics Phase 0 → Telegram | Chỉ cho bạn |

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
Chỉ chạy: `sublet-email`, `sublet-match`, `sublet-followup` (draft), `sublet-report`, Telegram. **Không bao giờ** chạy Chrome/Facebook trên VPS — IP datacenter + session cá nhân = checkpoint.
