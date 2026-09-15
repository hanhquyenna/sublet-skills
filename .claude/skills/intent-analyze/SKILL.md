---
name: intent-analyze
description: Đọc các post thô mới trong sublet_listings (kind is null) và phân loại intent (offering = subletter, seeking = sublettee, other), trích requirements có cấu trúc (khu, giá, ngày, term, registration, số người, furnished), chấm scam, tách seeker từ post seeking. Không đụng Facebook. Dùng với /intent-analyze hoặc tự động sau sublet-scan/sublet-email.
---

# intent-analyze

Tầng phân tích tách khỏi tầng capture: chạy lại được bất cứ lúc nào, không tốn page load.

## Input
`select * from sublet_listings where kind is null order by seen_at limit 40` (batch). Thêm tham số `--all` để phân tích lại toàn bộ (khi đổi rule).

## Với mỗi post
1. **Intent** (`kind`):
   - `offering` — người có phòng/căn: "subletting my room", "available from", "looking for someone to take over", "onderhuur aangeboden", "my flatmate is leaving". Poster = **subletter**.
   - `seeking` — người tìm: "looking for a room", "op zoek naar", "need a place from", "anyone renting". Poster = **sublettee**.
   - `other` — agency ads, roommate-only, sale, spam, hỏi chung.
   Nếu post vừa có phòng vừa tìm (swap) → `offering` + notes='swap'.
2. **Requirements** (chỉ với offering; null nếu không có trong text — không đoán):
   `area` (chuẩn hoá theo danh sách khu trong seeker-intake), `room_type`, `rent_eur` (all-in nếu ghi "incl."), `deposit_eur`, `bills_included`, `available_from`, `available_to` (ISO; năm = năm tới gần nhất còn hợp lý), `min_term_days`, `furnished`, `registration_allowed` (yes/no/unknown), `sublet_permission` (yes nếu ghi "landlord approved"; unknown mặc định), `max_people`.
3. **Scam score** 0–100, `scam_flags` từ `config.scam.flags`:
   - +40 deposit/transfer trước viewing · +25 giá <70% thị trường khu đó (room Amsterdam ~€900) · +20 "I'm abroad, my agent will send keys" · +15 không có khu/địa chỉ gì · +15 wire/crypto/Western Union · +10 văn phong stock ("beautiful cozy fully equipped") không có chi tiết thật · −20 có chi tiết cụ thể (tầng, ga tàu, tên đường) · −10 poster trả lời comment.
4. **Seeking → seeker**: nếu có move_in hoặc budget rõ → insert `sublet_seekers(source='fb_seeking', source_url, contact_consent=false, ...)`; không lưu contact. Không có ngày+giá → chỉ đánh `kind='seeking'`, không tạo seeker.
5. Update listing; `sublet_events(event='analyzed', payload={kind, scam_score})`.

## Sau batch
- Với offering mới, scam_score < 60, có `available_from` và `rent_eur` → gọi `/sublet-match`.
- In: n offering / n seeking / n other / n nghi scam, và 3 offering đáng DM nhất (mới nhất, đủ dữ liệu, score thấp).

## Kiểm tra chất lượng (mỗi tuần)
Lấy ngẫu nhiên 10 post đã phân loại, in cạnh kết quả, hỏi bạn đúng/sai. Sai ≥2 → sửa rule trong skill này, chạy `--all`.
