# Intent logic — phân loại post bằng lời (nguồn sự thật cho `intent-analyze`)

Mọi thay đổi về cách hiểu một post đều sửa ở đây trước, rồi mới sửa SKILL.md. Sau khi sửa: `/intent-analyze --all`.

## 0. Câu hỏi gốc

**Người đăng CÓ chỗ hay CẦN chỗ?** Nhìn *đối tượng của động từ*, không nhìn động từ.
- "Looking for **someone** to take my room" → tìm người → **OFFERING**
- "Looking for **a room** in Oost" → tìm chỗ → **SEEKING**

## 1. OFFERING — dấu hiệu

| Loại dấu hiệu | EN | NL |
|---|---|---|
| Sở hữu ngôi 1 | my room, our apartment, the flat I rent, my place | mijn kamer, ons appartement, mijn woning |
| Động từ cho | subletting, sublet, renting out, available, offering, free from, taking over (my lease) | aangeboden, te huur, onderhuur, beschikbaar, overname |
| Vắng mặt–quay lại | while I'm away, I'll be abroad, back in January, going on exchange/internship | ik ben weg, ik kom terug in, stage in het buitenland |
| Cấu trúc thông tin | €/month + ngày + khu ở dạng **mô tả** | €/maand + datum + buurt |
| Ảnh | "photos attached", "see pics" | foto's |

## 2. SEEKING — dấu hiệu

| Loại | EN | NL |
|---|---|---|
| Động từ cần | looking for a room/place/studio, searching, need a place, hoping to find, anyone renting | gezocht, op zoek naar, ik zoek, wie heeft |
| Tự giới thiệu | I'm a 24yo student, non-smoker, clean, quiet, working at, my girlfriend and I | ik ben, student, werkend, niet-roker |
| Ngân sách giới hạn | up to, max, budget around, can pay | tot, maximaal, budget |
| Ngày nhu cầu | from 1 Oct, need to move by, starting in, ASAP | vanaf, per, zo snel mogelijk |

## 3. OTHER

**Agency**: nếu post là *một chỗ ở cụ thể có thể thuê* (có giá/khu/ngày) → vẫn `offering` (thường `long_term`) với `poster_type='agency'` — để biết thị trường, không DM. Nếu là quảng cáo dịch vụ / "landlords wanted" / "sign up on our site" / danh sách bán → `other`, `poster_type='agency'`.

**Không xác định được có-hay-cần** (fragment: "Amsterdam. October. 900. Centrum. DM me") → `other`, `confidence='low'`, `notes='needs_full_read'`.

Còn lại: dịch vụ (cleaning, moving, storage), câu hỏi chung (registration, gemeente, deposit law), "found a place, thanks everyone", admin/rules, spam, bán đồ, sự kiện, tìm bạn bè không liên quan chỗ ở.

## 4. OFFERING → `subtype`

| subtype | Nghe như | Deal? | Phân biệt bằng |
|---|---|---|---|
| `sublet_whole` | cả căn, ngày đi–ngày về, "I'll be in Berlin Oct–Jan" | **có** | có available_to; "whole/entire/the apartment"; không nhắc flatmates |
| `sublet_room` | 1 phòng trong flat share, flatmates ở lại | **có** (nhiều nhất) | có available_to; "my room", "flatmates", "shared" |
| `takeover` | "take over my lease/contract", "overname", không ngày về | có, khác: landlord duyệt, chậm, fee cao hơn | không available_to; "contract/lease/huurcontract" |
| `roommate` | "new flatmate", "looking for a roommate", vô thời hạn | biên | không available_to; nhấn vào người ở chung, preference |
| `swap` | "I have X, want Y", exchange | không (Phase 0) | "swap/exchange/ruilen" |
| `short_stay` | giá/đêm, <30 đêm, weekend, "for the holidays" | **không** | per night/nacht; ngày < 30 |
| `long_term` | landlord/agency, "minimum 12 months", indefinite | không | không available_to + poster_type=agency hoặc "minimum X months" ≥ 6 |

Quy tắc quyết:
1. Có **ngày kết thúc** → sublet (whole/room). Không có → takeover / roommate / long_term.
2. **Đơn vị giá** theo đêm → short_stay. Tổng ngày < 30 → short_stay.
3. "Whole / entire / the apartment / studio" và không nhắc flatmates → whole; "my room / a room / flatmates / shared" → room.
4. Nhắc "contract / lease / take over / overname" → takeover.

## 5. SEEKING → `subtype` và có tạo seeker không

| subtype | Điều kiện | Tạo seeker? |
|---|---|---|
| `seek_sublet` | có cả move_in và move_out | có |
| `seek_room` | chỉ move_in, vô thời hạn | có, move_out=null, flex_days=14 |
| `seek_group` | couple / 2 friends / family | có, people ≥ 2 |
| (không rõ) | không có ngày lẫn ngân sách | **không** tạo seeker — nhưng vẫn gán subtype (`seek_room` mặc định, `seek_group` nếu couple/group) |
| budget nhưng không có ngày | "budget 900, flexible on dates" | có, move_in=null, flex_days=30 |
| dead ("EDIT: found") | bất kỳ | **không** tạo seeker |

Không lưu contact từ post. contact_consent=false.

## 6. Trạng thái đọc từ chính post

- "EDIT: found / RENTED / taken / no longer available / gevonden / verhuurd" → `status='dead'` ngay cả khi post mới.
- "still available / bump / up" → sống, ưu tiên DM.
- "for a friend / posting on behalf / my friend is subletting" → offering, `poster_type='proxy'` (người DM không phải người quyết).
- Nhiều listing / "we have several" / số +31 6 cố định / tên công ty / link → `poster_type='agency'` → không DM.
- Mặc định `poster_type='individual'`.

## 7. `deal_score` 0–100 — đáng DM đến đâu (khác scam_score)

Bắt đầu 50.
- +20 subtype in (sublet_room, sublet_whole) · +5 takeover · −10 roommate · −50 swap/short_stay/long_term
- +15 available_from trong 45 ngày tới · +5 trong 46–90 ngày · −15 >90 ngày · −10 available_from đã qua >7 ngày
- +10 có rent_eur · +10 có available_to · +5 có khu cụ thể
- +10 post <48h · 0 2–7 ngày · −20 >7 ngày
- −40 poster_type=agency · −10 proxy
- −100 status=dead
- −(scam_score / 2)
Kẹp 0–100. DM khi deal_score ≥ 60 và confidence ≠ low.

## 8. `scam_score` 0–100 — bằng lời

Tăng khi:
- **Tiền trước khi gặp**: deposit to reserve, "send €X to hold", "pay first month to secure" (+40)
- **Chủ ở xa, người khác giữ chìa khoá**: "I'm in the UK, my agent/cousin has the keys", "keys will be shipped" (+25)
- **Giá quá đẹp so với khu**: room Amsterdam <€600, studio Centrum <€900 (+25)
- **Chỉ mô tả chung chung**: "beautiful cozy fully furnished modern" mà không có tầng, đường, ga tàu, tên khu (+10)
- **Dồn sang kênh khác ngay**: "email me at…", "WhatsApp only", "DM for details" mà không có thông tin gì (+15)
- **Không có ngày** (+10) · **link lạ / rút gọn** (+20) · **wire / crypto / Western Union / gift card** (+40) · post tự nói "new here / new account" (+10)

Giảm khi:
- Chi tiết vụn vặt thật: tên đường, "3rd floor no lift", "tram 3 stop", tên flatmate, "bike storage" (−20)
- Nhắc thẳng registration / landlord permission / contract (−10)
- Poster trả lời comment (−10, chỉ khi thấy trong feed)

**Quy tắc gộp:**
- Chỉ áp dụng đầy đủ cho `offering`. Với `seeking`: chỉ ghi flag (tiền/WU/link), score tối đa 59, **không** chặn tạo seeker. Với `other`: score tối đa 59 (chỉ để bạn biết).
- Một cơ chế thanh toán chỉ tính một lần: "pay upfront via PayPal/WU/crypto" = tiền-trước-khi-gặp (+40), không cộng thêm +40 cho wire.
- Có bất kỳ tín hiệu **tiền trước khi gặp** → các điểm giảm (chi tiết thật, nhắc registration) **không áp dụng** (scammer cố tình nhắc registration) và score **tối thiểu 60**.
- Link lạ / rút gọn: +20 (không phải +15).

≥60 → nghi ngờ, không match, không DM. 30–59 → DM được nhưng ghi flag cho bạn. <30 → sạch.

## 9. `poster_constraints` — lưu nguyên văn, không chấm điểm nhân thân

Poster hay ghi: female only, no couples, students only, no pets, working professionals, Dutch speakers, no smokers, LGBTQ friendly, age 25–35.
- Lưu **nguyên văn** vào `poster_constraints` để bạn đọc và để không giới thiệu người chắc chắn bị từ chối.
- `match.py` **chỉ** dùng: couples → `people`; pets → `pets`; students/working → `occupation` (điều kiện chỗ ở). **Không** dùng giới tính, tuổi, quốc tịch, ngôn ngữ để chấm điểm.

## 10. `confidence`

- `high`: có ≥2 trong (rent, available_from, area) + intent rõ.
- `medium`: 1 trong 3, intent rõ.
- `low`: 0 trong 3, hoặc post <15 từ, hoặc intent mâu thuẫn → `notes='needs_full_read'` để scan mở permalink (≤2/chu kỳ). Không DM low.
- **`kind=other`**: đếm 3 trường **không áp dụng**. `high` khi rõ ràng không phải listing (câu hỏi, dịch vụ, cảm ơn, admin); `low` chỉ khi <15 từ hoặc fragment không xác định được. `poster_type=null` cho other (trừ agency).

## 11. Chuẩn hoá trường

- Ngày: ISO. Thiếu năm → năm gần nhất trong tương lai còn hợp lý, **tính từ ngày post** (post 15/9 nói "from 1 Oct" → 1/10 năm nay; "from 1 March" → 1/3 năm sau). "mid-X" → 15/X, flex 7. "end of X" → **ngày cuối tháng** X. "early X" → 5/X, flex 7. Chỉ tên tháng ("Oct–Jan", "Feb–June") → ngày 1 tháng đầu → ngày cuối tháng cuối. "ASAP / available now / immediately" → ngày post, flex 14. "this weekend" → thứ Bảy gần nhất sau ngày post; "ADE weekend" (tháng 10) → tra lịch, nếu không rõ → null.
- Giá: số nguyên EUR/tháng = tuần × 4.33, làm tròn đến euro ("€250/week" → 1083; "€300/week" → 1299). Theo đêm → `rent_eur=null` (short_stay). Với `seeking`: `rent_eur` = ngân sách tối đa ("800–950" → 950; "up to 900" → 900). "incl." / "all-in" / "inclusief" → bills_included='all'. "excl." → 'none'. "+ €50 bills" → rent ghi số gốc, bills_included='+50'.
- Khu: map về danh sách chuẩn (Centrum, West, Oud-West, Zuid, De Pijp, Oost, Noord, Nieuw-West, Zuidoost, Westerpark, Bos en Lommer, Indische Buurt, Amstelveen, Diemen). "near Sloterdijk" → West; "Jordaan" → Centrum; "Rivierenbuurt" → Zuid; "Watergraafsmeer" → Oost. Không map được → null.
- `room_type`: room / studio / apartment / other. "studio" và "apartment" chỉ khi poster nói vậy.
- `registration_allowed`: yes chỉ khi nói "registration possible/inschrijving mogelijk"; no khi "no registration"; còn lại unknown.
- `sublet_permission`: yes chỉ khi nói "landlord approved/allowed/knows"; no khi "landlord doesn't know / keep it quiet"; còn lại unknown.
- `max_people`: "couples ok / 2 people" → 2; "single only / 1 person" → 1; mặc định null.
- `furnished` (thêm 2026-09-26, Kien quyết định — cột có sẵn trong schema từ đầu nhưng chưa từng có tiêu chí): true chỉ khi nói rõ furnished/gemeubileerd hoặc liệt kê nội thất đi kèm; false chỉ khi nói rõ unfurnished; không nhắc gì tới nội thất → null, không đoán.

## 12. Ví dụ chuẩn (dùng làm test)

| Post (rút gọn) | kind | subtype | poster_type | ghi chú |
|---|---|---|---|---|
| "Subletting my room in Oost 1 Oct–15 Jan, €850 incl, flatmates are 2 girls, registration not possible" | offering | sublet_room | individual | high; reg=no |
| "Looking for someone to take over my studio in De Pijp, contract with landlord, €1200, from Nov" | offering | takeover | individual | no available_to |
| "Hi! 25F student looking for a room from 1 Sept to Dec, budget 900, anywhere reachable by bike" | seeking | seek_sublet | — | seeker: people=1, areas=[] |
| "We have several furnished apartments available, call +31 6…" | offering | long_term | agency | không DM |
| "Whole apartment available while I'm in Lisbon 10 Oct–20 Dec, €1500, Westerpark, photos attached" | offering | sublet_whole | individual | high |
| "Room available this weekend only, €60/night" | offering | short_stay | individual | deal_score thấp |
| "EDIT: FOUND. Thanks all!" | offering | (giữ) | — | status=dead |
| "Posting for a friend: her room in Zuid free Oct–Jan, €900" | offering | sublet_room | proxy | |
| "Beautiful cozy studio in centre, €600, I'm abroad, my agent will send keys after deposit" | offering | sublet_whole | individual | scam ≥ 80 |
| "Does anyone know how to register at gemeente without a contract?" | other | — | — | |
