---
name: intent-analyze
description: Đọc các post thô mới trong sublet_listings (kind is null) và phân loại intent (offering = subletter, seeking = sublettee, other), trích requirements có cấu trúc (khu, giá, ngày, term, registration, số người, furnished), chấm scam, tách seeker từ post seeking. Không đụng Facebook. Dùng với /intent-analyze hoặc tự động sau sublet-scan/sublet-email.
---

# intent-analyze

Analyzer chỉ đọc `sublet_listings` có `kind is null` và raw evidence từ
`sublet_events.event='context_captured'`. Chỉ dùng context event contract v2;
loại khỏi input mọi `detail_audit`/QA note và không biến chúng thành raw
evidence mới. Capture fields thiếu vẫn là `null`/`[]`/`false`, không được đoán.

## Spec
| | |
|---|---|
| **Lịch** | tự động sau scan/email/backfill; tay: /intent-analyze [--all] |
| **Trigger** | `/intent-analyze` |
| **Đọc** | sublet_v_analyze_queue (40), docs/intent-logic.md |
| **Ghi** | sublet_listings (kind, subtype, poster_type, fields, scam, deal_score, confidence, canonical_id, analyzed_at), sublet_seekers (từ seeking), sublet_events(analyzed) |
| **Metrics** | analyze.analyzed_24h, offering_7d, scam_high_rate, low_conf_rate, qa_kind_acc; capture.dedupe_ratio |
| **Edge cases** | E13 E14 E30–E44 → `docs/edge-cases.md` |
| **Rules** | R06 R09 R17 R18 → `docs/rules.md` |

Tầng phân tích tách khỏi tầng capture: chạy lại được bất cứ lúc nào, không tốn page load.

**Nguồn sự thật cho mọi rule là `docs/intent-logic.md`.** Đọc nó trước khi phân loại. SKILL.md này chỉ là quy trình; nếu hai nơi khác nhau, docs thắng.

## Model routing

Đọc `models.intent_analyze` từ `data/config.yaml`. Nếu runtime cho phép chọn model, dùng model đó (mặc định hiện tại là model nhỏ/rẻ cho phân tích); nếu không cho phép, giữ model runtime hiện tại và không tìm cách bypass giới hạn. Không áp dụng routing tiết kiệm này cho draft, inbox-triage hoặc partner-voice.

## Input
`select * from sublet_v_analyze_queue` (40 post kind is null, cũ nhất trước). Thêm tham số `--all` để phân tích lại toàn bộ (khi đổi rule).

## Với mỗi post (theo docs/intent-logic.md)
1. **kind**: offering / seeking / other — theo mục 0–3 (đối tượng của động từ, không phải động từ).
2. **subtype**: offering → mục 4 (sublet_whole / sublet_room / takeover / roommate / swap / short_stay / long_term); seeking → mục 5 (seek_sublet / seek_room / seek_group).
3. **poster_type**: individual / proxy / agency — mục 6. Agency → không bao giờ DM.
4. **status từ post**: "found / rented / taken" → `status='dead'` — mục 6.
5. **Trường** (chỉ offering; null nếu không có trong text): area, room_type, rent_eur, deposit_eur, bills_included, available_from, available_to, min_term_days, furnished, registration_allowed, sublet_permission, max_people — chuẩn hoá theo mục 11.
6. **poster_constraints**: nguyên văn — mục 9. Không dùng để chấm điểm nhân thân.
7. **scam_score + scam_flags**: mục 8.
8. **deal_score**: mục 7 (0–100; DM khi ≥60 và confidence ≠ low).
9. **confidence**: mục 10; low → `notes='needs_full_read'`.
10. **seeking → seeker**: mục 5; không lưu contact; `contact_consent=false`.
11. **Cross-post fingerprint** (chỉ offering, canonical_id còn null): tìm listing offering khác cùng city có cùng `poster_name` và `rent_eur` và `available_from` (±1 ngày), seen_at sớm hơn → set `canonical_id` = bản sớm nhất. Cùng 1 người đăng 5 group = 1 deal, 1 DM.
12. Update listing (`analyzed_at=now()`); `sublet_events(event='analyzed', payload={kind, subtype, poster_type, scam_score, deal_score, confidence})`.

## Sau batch
- Với offering mới: `deal_score ≥ 60`, `scam_score < 60`, `confidence != low`, `poster_type != agency`, có `available_from` và `rent_eur` → gọi `/sublet-match`.
- In: n offering (theo subtype) / n seeking / n other / n dead / n nghi scam, và 3 offering `deal_score` cao nhất.

## Kiểm tra chất lượng (mỗi tuần)
Lấy ngẫu nhiên 10 post đã phân loại, in cạnh kết quả, hỏi bạn đúng/sai. Sai ≥2 → sửa `docs/intent-logic.md` (thêm ví dụ vào mục 12), chạy `--all`. 10 ví dụ ở mục 12 là bộ test tối thiểu: chạy lại sau mỗi lần sửa rule.
