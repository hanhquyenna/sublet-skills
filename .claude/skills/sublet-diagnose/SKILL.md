---
name: sublet-diagnose
description: Chẩn đoán vì sao post sublet của bạn (hoặc của subletter đang hợp tác) có 0 phản hồi — pending approval, bị gỡ, đăng sai giờ, thiếu giá/ngày/ảnh, group không cho sublet — và đề xuất sửa. Dùng với /sublet-diagnose <link post>.
---

# sublet-diagnose

Chỉ đọc. ≤3 page load.

## Các bước
1. `navigate` tới link post. Nếu "content not available" → **bị gỡ hoặc pending**. Ghi nhận.
2. Nếu hiện: đọc post + đếm comment/reaction + thời gian đăng. `navigate` tới trang group (1 load) → đọc "About"/rules nếu hiện, đếm số post trong 1 giờ quanh thời điểm đăng (đông = bị trôi).
3. Đối chiếu `data/groups.yaml`: group `allows_sublet=false`? `allows_agencies=false` mà post có link dịch vụ?
4. Checklist nội dung: dòng đầu có giá + ngày + khu? có ảnh? có "registration yes/no"? có số người? độ dài <120 từ? tiếng Anh + 1 dòng NL?
5. Giờ đăng: tốt nhất 08–10h và 18–21h giờ Amsterdam, Chủ nhật tối. Đăng 0–7h = trôi.

## Output
- Kết luận 1 dòng: *pending / removed / live-buried / live-weak-content / group-mismatch*.
- 3 việc sửa cụ thể, kèm bản post viết lại (EN, ≤100 từ, dòng đầu = "€{rent} · {room_type} · {area} · {from}→{to} · registration {yes/no}").
- Nếu post là của subletter đang hợp tác: lưu `notes` vào listing + `sublet_events(event='diagnosed')`.
