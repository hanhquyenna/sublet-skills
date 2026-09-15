# PLAN.md — sublet-skills: kế hoạch chi tiết cho agent (Codex/Claude Code) và cho người vận hành

> **Active scope reset (2026-09-15, +`analyze-insights` 2026-09-16):** Bộ
> skill hiện có `information`, `sublet-scrape-14-groups`, `validate-permalink`
> và `analyze-insights` (đọc-only, chạy độc lập sau capture để tóm tắt
> insight thô — không phải pipeline `intent-analyze` chính thức ở mục C4 dưới
> đây). Các workflow cũ khác bên dưới là historical reference, không phải
> skill callable; không gọi hoặc khôi phục chúng nếu người vận hành chưa yêu
> cầu mở rộng scope.

Tài liệu này là nguồn sự thật. Agent đọc phần A–D. Bạn đọc phần E–G. Cả hai đọc phần H (cập nhật logic).

---

## A. Mục tiêu và offer

**Dịch vụ:** broker sublet nhỏ ở Amsterdam. Subletter (người có phòng) nhận 3 người phù hợp đến viewing trong 72h; trả €49 khi người được giới thiệu dọn vào (`config.offer.fee_trigger=move_in`; đổi sang `three_viewings_72h` nếu tỉ lệ thu <70% sau 10 deal). Người tìm nhà (sublettee) dùng miễn phí.

**Agent = mắt + trí nhớ + người soạn. Bạn = tay + tên.** Agent không gửi gì lên Facebook. Bạn tap.

**Thứ tự Phase 0:** join group → backfill 1 group/ngày → intent-analyze trên corpus → QA edge case cùng bạn (kind ≥95%, subtype ≥85%, 0 agency lọt) → mới DM.

**Phase 0 (30 ngày) trả lời 5 câu:** offering thật/ngày theo group · DM→ok % · accepted→3 viewing/72h % · show-up % · fee thu %.

---

## B. Kiến trúc và phân tầng

```
┌─ KNOW ─────────┐  ┌─ CAPTURE ──────────────┐  ┌─ ANALYZE ─────┐  ┌─ MATCH ─────┐  ┌─ VOICE/RUN ───────────────┐
│ sublet-groups  │→ │ sublet-scan  (Chrome)   │→ │ intent-analyze│→ │ sublet-match│→ │ sublet-draft              │
│ groups.yaml    │  │ sublet-email (IMAP)     │  │ (không browser)│  │ match.py    │  │ inbox-triage              │
│ sublet_groups  │  │ → sublet_listings raw   │  │ → kind, fields │  │ → matches   │  │ viewing-coordinate        │
└────────────────┘  └─────────────────────────┘  └───────────────┘  └─────────────┘  │ sublet-followup           │
                                                                                      │ (tất cả đọc partner-voice)│
       ops: onboarding · sublet-report · sublet-diagnose · seeker-intake               └───────────────────────────┘
```

Nguyên tắc tách tầng:
- **Capture** tốn page load Facebook → tối giản, không suy nghĩ, chỉ lưu thô.
- **Analyze** không tốn page load → mọi rule ở đây, chạy lại được (`--all`).
- **Voice** là một skill duy nhất → đổi giọng 1 chỗ, mọi tin đổi theo.
- **Match** deterministic trong `scripts/match.py` → không để LLM tự nghĩ ra điểm.

Runtime:
- Mac (bạn): Claude Code hoặc Codex + Chrome thật (Claude in Chrome / Chrome DevTools MCP profile riêng) + launchd (`ops/install_cron.sh`).
- Hetzner (Phase 2): chỉ skill không cần Chrome (`ops/hetzner.crontab`).
- Supabase project Lamy, bảng `sublet_*`, RLS bật không policy.

---

## C. Từng skill — logic, dữ liệu, cách xử lý, cách cập nhật

Bảng tổng: skill → đọc → ghi → trigger → page load

| Skill | Đọc | Ghi | Trigger | FB loads |
|---|---|---|---|---|
| onboarding | config, sublet_groups, ops_state | sublet_ops_state | tay, lần đầu | 1 |
| sublet-groups | FB search, sublet_listings (đếm) | sublet_groups, data/groups.yaml | tuần (discover tay, rank cron CN) | ≤6/tuần |
| sublet-scrape-14-groups | groups, latest metrics, scan runs, listings/events, batch state | batch state + gọi backfill từng group | tay/worker | không tự đọc Facebook; serialize browser jobs |
| validate-permalink | link queue chưa kiểm tra, context event gần nhất | listing link status + validation events + cursor | sau raw capture, tuần tự | ≤4/run |
| sublet-backfill | 1 group, chronological, 14 ngày, resumable | sublet_listings raw, context events, scan_runs, group_metrics, ops_state | tay/worker, từng group | panel-only, theo page-load budget |
| sublet-scan | FB groups/feed, /notifications, scan_runs.cursor | sublet_listings (kind=null), sublet_scan_runs, sublet_groups.last_post_seen_at, sublet_events | cron 12' | ≤4 |
| sublet-email | Gmail IMAP | như scan (source=fb_email) | cron 10' (Hetzner 24/7) | 0 |
| intent-analyze | sublet_listings kind is null | sublet_listings (kind, fields, scam), sublet_seekers (từ seeking), sublet_events | sau scan/email | 0 |
| seeker-intake | Tally CSV / text dán | sublet_seekers | tay / cron export | 0 |
| sublet-match | 1 listing + seekers active | sublet_matches, listings.status | sau analyze; tay | 0 |
| sublet-draft | listing, matches, templates, partner-voice | sublet_messages (draft), listings.status=contacted khi bạn báo sent | sau match; tay | 0 |
| inbox-triage | Messenger (đọc), tin bạn dán | sublet_messages (in), listings/matches/viewings status, sublet_messages (draft) | cron 20' | ≤6 |
| viewing-coordinate | matches replied, viewings | sublet_viewings, sublet_fees, sublet_messages (draft), status | khi accepted; tay | 0 |
| sublet-followup | mọi bảng | sublet_messages (draft) | cron 08:30 | 0 |
| sublet-diagnose | 1 post FB + group | listings.notes, events | tay | ≤3 |
| sublet-report | mọi bảng | sublet_inbox | cron 18:00 | 0 |

### C1. sublet-groups
- **Logic:** discover = FB search 3 query × 1 load, parse tên/url/member/private, upsert `sublet_groups` (tier=null). rank = đếm `offering_7d` từ `sublet_listings`, áp rule tier 1 (≥10) / 2 (2–9) / 3 (<2 hoặc allows_sublet=no), ghi ngược `data/groups.yaml`. `posts_per_day` chỉ xếp thứ tự capture khi offering_7d hoặc 14-day capture chưa đủ.
- **Dữ liệu:** `sublet_groups(key, name, url, tier, is_private, member_count, allows_sublet, allows_agencies, joined, notif_all_posts, offering_7d, last_post_seen_at, last_scanned_at, last_ranked_at, notes)`.
- **Xử lý lỗi:** search không hiện kết quả → thử query kế; group không có member count → null; url trùng → update, không insert.
- **Cập nhật logic:** ngưỡng tier ở mục "/sublet-groups rank" trong SKILL.md; query search trong `config.city` + danh sách từ khoá trong SKILL.md.

### C2. sublet-scan (capture-only)
- **Logic:** kiểm giờ + tổng page_loads 24h (≥350 → dừng) + skip ngẫu nhiên 1/12 → mở `groups/feed` → đọc từ trên xuống → dừng khi gặp `cursor` run trước hoặc 3 URL đã biết → `/notifications` → insert thô mỗi post mới → ghi cursor = permalink đầu tiên → gọi `/intent-analyze`.
- **Dữ liệu ghi:** `sublet_listings(source, source_url [unique], group_key, poster_name, posted_at, seen_at, raw_text, kind=null)`; `sublet_scan_runs(mode, page_loads, posts_seen, new_listings, cursor, stopped_reason)`; `sublet_events(event='captured')`.
- **Xử lý:** login/checkpoint/captcha → `stopped_reason`, `sublet_inbox(level='stop')`, không chạy 24h (ghi `sublet_ops_state('scan_paused_until')`). Không map được group → tạo group key mới tier=null. Post không có direct permalink → dùng Share → Copy link và insert raw với `link_validation_status='unvalidated'`; chỉ khi không lấy được direct/comment/share evidence mới ghi `capture_unresolved`, không đoán URL.
- **Cập nhật logic:** cadence/ngưỡng trong `config.scan`; điều kiện dừng trong SKILL.md bước 3.

### C3. sublet-email
- **Logic:** `gmail_pull.py --since-days 1` → mỗi email có post_url chưa có → insert thô `source='fb_email'`, raw_text=snippet; digest gộp → tách dòng, `source_url='email:'||msgid||'#n'`. Snippet ngắn → intent-analyze đánh `needs_full_read` → scan mở permalink (≤2/chu kỳ).
- **Cập nhật:** regex subject/URL trong `scripts/gmail_pull.py` (Facebook đổi format email thỉnh thoảng — sửa 2 regex đó).

### C4. intent-analyze
- **Nguồn rule:** `docs/intent-logic.md` (bằng lời, EN/NL keywords, 12 ví dụ test). SKILL.md chỉ là quy trình.
- **Logic:** batch 40 post `kind is null` → intent (offering/seeking/other) → extract fields (null nếu không có trong text) → scam score theo bảng cộng/trừ → seeking có ngày+giá → tạo seeker (no contact) → gọi match cho offering đủ dữ liệu.
- **Dữ liệu ghi:** `sublet_listings(kind, area, room_type, rent_eur, deposit_eur, bills_included, available_from, available_to, min_term_days, furnished, registration_allowed, sublet_permission, max_people, scam_score, scam_flags, notes)`; `sublet_seekers(source='fb_seeking')`; `sublet_events(event='analyzed', payload)`.
- **Xử lý:** text quá ngắn/không rõ → `kind='other'`, notes='needs_full_read' nếu có dấu hiệu offering; ngày không có năm → năm tới gần nhất còn hợp lý; giá theo tuần → ×4.33.
- **Cập nhật logic:** toàn bộ rule ở SKILL.md (từ khoá intent, bảng scam, chuẩn hoá khu). Sau khi sửa: `/intent-analyze --all`. QA hàng tuần: 10 post ngẫu nhiên, sai ≥2 → sửa rule.

### C5. seeker-intake
- **Logic:** CSV/text → chuẩn hoá ngày (ISO, flex_days), budget all-in, areas theo danh sách chuẩn, consent chỉ khi có checkbox/nói rõ; trùng contact → update.
- **Dữ liệu:** `sublet_seekers(source, name, contact, contact_consent, move_in, move_out, flex_days, budget_eur, areas[], people, registration_need, pets, occupation, viewing_availability, status)`.
- **Cập nhật:** danh sách khu chuẩn và mapping cột Tally trong SKILL.md.

### C6. sublet-match
- **Logic:** kéo listing + seekers active → `match.py` → score 0–100 (date 45, budget 25, area 15, constraints 15; veto khi scam≥60) → lưu ≥50 → listing.status=matched nếu có ≥60.
- **Dữ liệu:** `sublet_matches(listing_id, seeker_id, score, reasons, risk_flags[], status='proposed')`.
- **Cập nhật logic:** trọng số trong `scripts/match.py` (hàm `score`). Đổi xong chạy `/sublet-match <id>` cho listing đang mở; match cũ status='proposed' bị tính lại.

### C7. sublet-draft
- **Logic:** đọc partner-voice → điền `templates/dm_offer.md` với chi tiết thật của post → kiểm 10 DM/ngày → lưu draft; push seeker: matches ≥60 + consent, ≤15, không địa chỉ/không tên poster.
- **Dữ liệu:** `sublet_messages(entity_type, entity_id, direction='out', channel, template, body, status='draft')`. Khi bạn báo `sent`: `status='sent', sent_at`, listing→`contacted`/match→`pushed`.
- **Cập nhật:** template trong `templates/`, giọng trong `partner-voice`, giới hạn/ngày trong SKILL.md.

### C8. inbox-triage
- **Logic:** Messenger (≤6 loads) + tin bạn dán → gắn entity (không chắc → hỏi) → phân loại theo bảng → chuyển trạng thái → draft trả lời (FAQ từ `templates/faq.md` điền sẵn; negotiating → 2 phương án; scam → không draft, cảnh báo).
- **Dữ liệu:** `sublet_messages(direction='in')`, cập nhật `listings.status` (accepted/declined/filled), `matches.status` (replied/rejected/signed), `viewings.attendance`, `listings.scam_score`.
- **Xử lý:** tin không liên quan → bỏ qua, không lưu. 2 người cùng tên → hỏi bạn.
- **Cập nhật:** bảng phân loại + FAQ.

### C9. viewing-coordinate
- **Logic:** accepted → shortlist 3 từ matches `replied` theo score → draft cho subletter (3 dòng tóm tắt, chưa contact) → subletter trả slot → tạo viewings, draft confirm seeker + gửi contact cho subletter → reminder T-3h (followup nhắc bạn) → attendance → fee trigger theo `config.offer.fee_trigger` → draft tin Tikkie.
- **Dữ liệu:** `sublet_viewings(match_id, scheduled_at, confirmed, attendance, landlord_feedback)`, `sublet_fees(listing_id, trigger, amount_eur, invoice_status)`, `sublet_messages(draft)`.
- **Xử lý:** <3 YES sau 24h → đề xuất push thêm 10; no-show → seeker notes, không loại ngay; signed chỉ ghi khi có xác nhận (nguồn ghi vào events.payload).
- **Cập nhật:** fee trigger trong config; số người shortlist trong SKILL.md.

### C10. sublet-followup
- **Logic:** 8 truy vấn (draft cũ >2h, DM 3–4 ngày không reply, maybe-later 5 ngày, viewing hôm nay, viewing hôm qua chưa kết quả, fee draft/sent>5 ngày, seeker hết hạn, accepted <3 YES) → gộp với `sublet_inbox` chưa done → ≤10 việc, draft sẵn.
- **Cập nhật:** ngưỡng ngày trong SKILL.md; template trong `templates/followup.md`.

### C11. sublet-report
- **Logic:** 7 query → JSON → `scripts/report.py` → 3 nhận xét agent → `sublet_inbox`.
- **Cập nhật:** metrics trong `scripts/report.py`; mốc Phase 0 trong SKILL.md.

### C12. sublet-diagnose, onboarding — xem SKILL.md tương ứng.

---

## D. State machines (agent phải tôn trọng)

```
listing:  new → (analyze) matched → (bạn sent DM) contacted → accepted | declined | dead
          accepted → viewing → filled            (filled chỉ khi có xác nhận move-in)
          bất kỳ → dead (2 follow-up không reply)   scam_score≥60 → không bao giờ contacted
match:    proposed → pushed → replied → shortlisted → viewing → signed | rejected
seeker:   active → matched → viewing → housed | inactive
message:  draft → sent (chỉ bạn) ; in: received
fee:      draft → sent → paid | waived | disputed
viewing:  pending → showed | no_show | cancelled
```

Ai được đổi gì:
- `message.status → sent`: **chỉ người** (qua `/sublet-draft sent <id>`).
- `listing.filled`, `match.signed`, `fee.paid`: **chỉ khi có xác nhận** từ subletter/seeker/Tikkie; agent ghi kèm nguồn.
- Còn lại: agent.

---

## E. Cho bạn — onboarding (ngày 0–7)

Chạy `/onboarding`, nó dắt từng bước. Tóm tắt việc **chỉ bạn làm được**:

| Ngày | Việc | Thời gian |
|---|---|---|
| 0 | Điền `config.yaml` (imap_user, your_first_name). Login Facebook trong Chrome. Gmail App Password → `~/.zshrc`. | 20' |
| 0 | `zsh ops/install_cron.sh` | 1' |
| 0–7 | Join group tier 1–2, **≤5/ngày**. Mỗi group joined: bật Notifications → All posts | 5'/ngày |
| 1 | Tạo Tally form seeker (12 cột trong README), link vào config. Điền 3 người quen. | 30' |
| 1 | Đọc `partner-voice`, sửa 2 dòng định vị theo giọng bạn | 10' |
| 2 | Gửi DM đầu tiên từ draft | 5' |

---

## F. Cho bạn — vận hành hàng ngày (sau onboarding)

Mọi thứ dưới đây **tự chạy** (launchd). Bạn chỉ làm cột phải.

| Giờ | Tự động | Bạn (tổng ~25'/ngày) |
|---|---|---|
| 08:30 | `sublet-followup` → đọc `sublet_inbox` + 8 truy vấn | Mở Claude Code, đọc, gửi các draft (5–10 tap) |
| 08:00–23:00 mỗi 12' | `sublet-scan` → `intent-analyze` → `sublet-match` → `sublet-draft` | Mỗi lần mở Claude Code: `/sublet-followup` → mở post, gửi DM. ≤10/ngày |
| mỗi 10' (24/7 khi lên Hetzner) | `sublet-email` → cùng pipeline | — |
| mỗi 20' | `inbox-triage` → cập nhật trạng thái, draft trả lời | Tap gửi FAQ/trả lời; quyết các case negotiating |
| khi subletter "ok" | `viewing-coordinate` → draft shortlist | Gửi shortlist; khi có slot → gửi confirm + contact |
| sau viewing | — | Gõ `/viewing-coordinate showed|no_show <id>`; seeker báo move-in → `signed` |
| move-in | fee draft + Tikkie text | Gửi Tikkie |
| 18:00 | `sublet-report` → sublet_inbox | Đọc lúc followup hôm sau |
| CN 10:00 | `sublet-groups rank` | Join/rời group theo đề xuất |
| CN | — | `/sublet-groups discover` (tay, 6 loads), `/intent-analyze` QA 10 post |

Việc bạn **không bao giờ** phải làm: đọc group, phân loại, nhớ ai đã nói gì, tính ai hợp ai, nhớ follow-up, tính fee.

---

## G. Cron / lịch chạy — ai chạy skill nào

**Nguyên tắc (từ 2026-09-15): 1 cron tick = 1 prompt = 1 job step.** Cron không gọi skill trực tiếp cho việc nền; gọi `sublet-worker`, worker chọn 1 job từ `sublet_jobs` theo ưu tiên, làm ≤8', ghi `progress`, thoát. Việc lớn (backfill 300 post, verify 92 group) tự chia chunk và nối qua nhiều tick. Không có "check 92 group" — post mới đọc qua `groups/feed` (1 trang gom hết) + email.

**Mac (launchd, `ops/install_cron.sh`)** — cần Chrome thật, máy thức:

| Job | Skill | Lịch | Cần Chrome |
|---|---|---|---|
| com.sublet.worker | sublet-worker → scan/analyze/match/email/backfill chunk/verify chunk | mỗi 600s, 08–23 | tuỳ job |
| com.sublet.inbox | inbox-triage | mỗi 1200s, 08–23 | ✅ |
| com.sublet.followup | sublet-followup | 08:30 | ❌ |
| com.sublet.report | sublet-report | 18:00 | ❌ |
| com.sublet.groups | sublet-groups rank | CN 10:00 | ❌ |

`ops/run_skill.sh` tự bỏ qua ngoài giờ và khi máy vừa wake <2'. Log: `ops/logs/`.

**Hetzner (Phase 2, `ops/hetzner.crontab`)** — chỉ: sublet-email, sublet-match, sublet-followup, sublet-report, sublet-groups rank. **Không bao giờ** scan/inbox/discover/diagnose (Chrome + IP datacenter = checkpoint).

**Chạy tay (không cron):** onboarding, sublet-groups discover, sublet-diagnose, seeker-intake (hoặc cron export Tally nếu muốn), `/sublet-draft sent`, `/viewing-coordinate showed|signed`.

Runner: `SUBLET_RUNNER=claude` (mặc định, `claude -p "/<skill>"`) hoặc `codex` (`codex exec "Run the <skill> skill"`).

---

## H. Cập nhật logic — ở đâu, thế nào

| Muốn đổi | Sửa ở | Sau đó |
|---|---|---|
| Giờ chạy, cadence, ngưỡng page load | `data/config.yaml → scan, hours` | không cần gì |
| Giá, fee trigger, promise, tên bạn | `data/config.yaml → offer` | draft mới tự dùng |
| Group nào tier nào | `sublet_groups` (DB) hoặc `/sublet-groups rank` | scan tự theo |
| Từ khoá intent, subtype, scam, deal_score, chuẩn hoá khu | `docs/intent-logic.md` (thêm ví dụ mục 12) | `/intent-analyze --all`, kiểm 10 ví dụ |
| Trọng số match | `scripts/match.py → score()` | `/sublet-match <id>` cho listing mở |
| Giọng, định vị, giới hạn từ | `partner-voice/SKILL.md` | draft mới tự theo |
| Câu chữ template | `templates/*.md` | draft mới tự theo |
| FAQ | `templates/faq.md` | inbox-triage tự theo |
| Phân loại reply | `inbox-triage/SKILL.md` bảng | không cần gì |
| Regex email Facebook | `scripts/gmail_pull.py` | chạy lại `/sublet-email` |
| Heuristic offering/seeking/risk-flag của insight (active) | `.claude/skills/analyze-insights/SKILL.md` | không rescan tự động; chỉ áp dụng cho listing xử lý sau khi sửa, trừ khi Kien yêu cầu rescan |
| Metrics | `scripts/report.py` | `/sublet-report` |
| Luật cứng | `CLAUDE.md` (+ `AGENTS.md` trỏ sang) | mọi skill |

Quy trình sửa: sửa file → commit với message "rule: <gì> vì <lý do>" → nếu là intent/match: chạy lại trên dữ liệu cũ, so số offering/scam/match trước–sau trong `/sublet-report` → giữ hay revert. Không sửa rule trong lúc cron đang chạy skill đó (`launchctl unload` trước, `load` sau).

---

## I. Cổng chuyển phase

| Từ → đến | Điều kiện | Việc |
|---|---|---|
| Phase 0 → 1 | 30 ngày, ≥200 offering/tháng, DM→ok ≥30%, ≥5 deal thu được tiền | Đổi promise 72h→24h nếu pool ≥100; bật WhatsApp channel; Hetzner cho email/match/report |
| Phase 1 → 2 | fee thu ≥70%, show-up ≥70%, bạn <30'/ngày | Thêm thành phố 2 (Rotterdam/Utrecht) với người vận hành riêng; landlord dashboard đơn giản |
| Bất kỳ | DM→ok <20% sau 50 DM | Đổi offer (giá/promise), không đổi kiến trúc |
| Bất kỳ | fee thu <70% sau 10 deal | `fee_trigger` → `three_viewings_72h` |
| Bất kỳ | 1 checkpoint Facebook | Giảm cadence ×2, xem lại page loads, 7 ngày không scan bằng browser (chỉ email) |

---

## K. Registry (sau audit 2026-09-15)
- `docs/rules.md` — R01–R24, enforce ở đâu, kiểm bằng gì
- `docs/edge-cases.md` — E01–E105 theo stage, skill xử lý, test coverage
- `docs/metrics.md` — 35 metric, công thức, target, lưu `sublet_metrics`, 5 quyết định tự động
- Mỗi skill có khối **Spec**. Thêm hành vi mới = Spec + 3 registry.

## J. Chi phí và cải tiến — xếp theo ROI (cập nhật 2026-09-15)

### J1. Chi phí thật của hệ thống này
Server ~€0 (Supabase free, Mac của bạn). Chi phí duy nhất đáng kể là **LLM token**, và nó đến từ 3 chỗ:

| Nguồn token | Ước tính/ngày (Amsterdam, 40 group) | Cách cắt |
|---|---|---|
| `sublet-scan` đọc feed (text a11y ~20–30k ký tự × 60 chu kỳ) | lớn nhất nếu để LLM đọc cả feed | **Không cho LLM đọc feed.** Extract post bằng DOM/a11y → chỉ đưa LLM text từng post *mới* (đã lọc bằng cursor + text_hash). Từ ~1.5M token/ngày xuống ~100k |
| `intent-analyze` (40 post/batch) | ~50–100 post/ngày × ~1.5k token | Dùng **Haiku 4.5** cho phân loại (doc + post ngắn, rule rõ) — rẻ ~10× Opus, eval mù đã cho thấy rule đủ rõ. Opus chỉ cho draft/voice |
| `sublet-draft` / `inbox-triage` | ≤10 DM + ≤30 reply/ngày | Nhỏ; giữ model tốt vì đây là thứ khách đọc |
| `sublet-backfill` | post/group trong cửa sổ 14 ngày × 1 lần | Chạy theo chunk resumable; không phân tích trong capture |

→ Mục tiêu: **< €1/ngày** LLM ở Phase 0. Đo bằng: log token trong `sublet_scan_runs.notes` và `sublet_events.payload.tokens`.

### J2. Đã làm hôm nay (rẻ, ROI cao)
| # | Cải tiến | Vì sao ROI cao | Ở đâu |
|---|---|---|---|
| 1 | **Dedupe cross-post** (`text_hash` + `canonical_id` + fingerprint poster/rent/from) | 1 subletter đăng 5 group = 1 DM thay vì 5 → tránh spam, tiết kiệm 80% DM | schema v2, `sublet-scan` bước 5, `intent-analyze` bước 11, view `deal_queue` |
| 2 | **Tier tạm từ `group_metrics.posts_per_day`** | Không phải chờ 7 ngày để biết đọc group nào; Codex đã có số này cho 47 group | `sublet-groups rank` bước 0 |
| 3 | **Views** (`v_deal_queue`, `v_analyze_queue`, `v_seekers_active`, `v_today`) | Skill ngắn hơn, ít lỗi SQL, ít token | schema v2; `sublet-draft`, `sublet-followup`, `intent-analyze` |
| 4 | **`push_count`/`last_pushed_at`** giới hạn ≤3 push/seeker/ngày | Không đốt pool seeker | schema v2, `sublet-draft` |
| 5 | **Backup JSON hàng ngày** (`ops/backup.sh`, launchd 23:30, Hetzner cron) | Free tier không có PITR; mất DB = mất 30 ngày | ops/ |
| 6 | `updated_at` + trigger, `in_reply_to`, `city`, `payment_link` | Followup tính "im lặng bao lâu"; reply nối với offer; mở thành phố 2 | schema v2 |
| 7 | CLAUDE.md #6 runtime-neutral (Claude in Chrome / Codex panel) | 2 agent không sửa qua lại cùng 1 dòng | CLAUDE.md |

### J3. Backlog — xếp theo (giá trị ÷ công), làm theo thứ tự
| # | Việc | Công | Giá trị | Khi nào |
|---|---|---|---|---|
| 1 | **Post extractor bằng DOM/a11y** trong scan: tách từng post (poster, time, text, permalink) trước khi đưa LLM | 1–2h | Cắt 90% token scan, tăng độ chính xác permalink | Trước khi bật cron scan |
| 2 | **Model routing**: intent-analyze + backfill → Haiku 4.5; draft/inbox/voice → Opus/Sonnet | 30' (config + 1 dòng trong skill) | ~10× rẻ phần phân loại | Cùng lúc với #1 |
| 3 | **QA loop trên corpus thật** sau backfill group đầu (20 post, sửa doc §12, `--all`) | 1h với bạn | Edge case thật mà test giả không có | Ngay khi backfill xong |
| 4 | **Seeker form → webhook** (Tally → Supabase REST insert trực tiếp) thay vì export CSV | 30' | Seeker vào pool tức thì, không cần chạy intake tay | Khi có form |
| 5 | Token accounting: ghi tokens vào `sublet_events.payload` mỗi skill | 30' | Biết chính xác €/ngày | Tuần 1 |
| 6 | **Rotate service key + DB password** sau khi Codex setup xong | 5' | Key đã đi qua chat | Hôm nay |
| 7 | `sublet_group_metrics` → tự động: sublet-groups discover ghi metrics thay vì Codex làm tay | 1h | Lặp lại được cho thành phố 2 | Phase 1 |
| 8 | Enum Postgres thay `check` | 30' | Sạch hơn, không cấp bách | Phase 1 |
| 9 | Hetzner cho email/match/followup/report/backup | 2h | 24/7 phần không cần browser | Khi laptop-closed thành vấn đề thật |
| 10 | `outreach-prep` (điền sẵn draft vào ô Messenger, bạn Enter) | 2h | 10 DM = 1 phút | Chỉ nếu tap gửi thành nút thắt |

### J4. Không làm (đã cân nhắc, không đáng)
- Vector search / embeddings cho match: date + budget + area deterministic là đủ; embeddings chỉ thêm chi phí và khó giải thích cho subletter.
- Realtime (Supabase realtime/websocket): cron 12' đủ cho sublet.
- Multi-account Facebook: không, vì lý do ban.
- Dashboard web: `sublet_v_today` + `/sublet-followup` là dashboard. Làm UI khi có người thứ 2 vận hành.
