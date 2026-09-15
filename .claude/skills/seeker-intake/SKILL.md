---
name: seeker-intake
description: Nhập seeker (người tìm sublet) từ Tally CSV export, tin nhắn WhatsApp/Telegram dán vào, hoặc mô tả tay → chuẩn hoá thành sublet_seekers với date window, budget, areas, consent. Dùng khi người dùng gõ /seeker-intake hoặc dán một yêu cầu tìm phòng.
---

# seeker-intake

## Nguồn
- `data/seekers_export.csv` (Tally export; cột tự do — đọc header rồi map).
- Text dán trực tiếp: "Hi, tôi cần phòng 1/10–15/1, budget 900, Oost/West, 1 người, cần registration".
- Người dùng mô tả bằng lời.

## Chuẩn hoá
- `move_in`, `move_out`: ISO date. Thiếu năm → năm gần nhất trong tương lai. "Flexible ±1 week" → `flex_days=7`. "ASAP" → hôm nay, `flex_days=14`.
- `budget_eur`: số nguyên, all-in nếu họ nói "incl.". "up to 900" → 900.
- `areas`: mảng tên khu chuẩn Amsterdam: Centrum, West, Oud-West, Zuid, De Pijp, Oost, Noord, Nieuw-West, Zuidoost, Westerpark, Bos en Lommer, Indische Buurt, Amstelveen, Diemen. Không rõ → `[]` (= flexible).
- `people`, `registration_need`, `pets`, `occupation` (student/intern/worker/other), `viewing_availability` (text).
- `contact`: số/email/handle **chỉ khi họ tự cung cấp trong form**. `contact_consent=true` chỉ khi form có checkbox đồng ý hoặc họ nói rõ. Không có consent → vẫn lưu nhưng không push.
- Trùng (cùng contact hoặc cùng tên+move_in): update, không insert.

## Ghi
Insert/update `sublet_seekers`, `sublet_events(event='intake')`. In lại 1 dòng tóm tắt để người dùng kiểm tra: "Tên · 1/10→15/1 (±7d) · ≤€900 · Oost/West · 1p · reg:yes · consent:yes".

## Không
- Không lấy passport, payslip, BSN, ảnh giấy tờ ở bước này.
- Không xếp hạng hay ghi chú về quốc tịch/giới tính.
