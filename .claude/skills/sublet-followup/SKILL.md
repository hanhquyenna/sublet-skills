---
name: sublet-followup
description: Danh sách việc cần bạn hôm nay — thread im lặng, viewing sắp tới cần reminder, fee chưa thu, draft chưa gửi, seeker hết hạn — kèm draft follow-up đã soạn. Dùng buổi sáng với /sublet-followup.
---

# sublet-followup

Chạy 1 lần/ngày, buổi sáng. Không gửi gì. Đưa ra ≤10 việc, ưu tiên theo tiền và thời gian.

## Truy vấn
1. **Draft chưa gửi**: `sublet_messages status='draft'` cũ hơn 2h → liệt kê, nhắc gửi hoặc xoá.
2. **DM không trả lời**: listings `status='contacted'`, `contacted_at` 3–4 ngày trước, chưa có message `direction='in'` → draft follow-up #1 (templates/followup.md). Nếu đã có follow-up #1 và thêm 4 ngày → đánh `status='dead'`, không draft nữa.
3. **"Maybe later"**: listings có notes chứa "later"/"maybe", 5 ngày → draft check-in với số seeker đang match.
4. **Viewing hôm nay**: `sublet_viewings scheduled_at` trong 24h, attendance='pending' → draft reminder T-3h cho seeker; liệt kê giờ.
5. **Viewing hôm qua chưa có kết quả**: attendance='pending', scheduled_at < now → hỏi bạn showed/no_show; draft tin hỏi seeker (TAKING/NOT TAKING/WAITING).
6. **Fee**: `sublet_fees invoice_status='draft'` → nhắc gửi; `'sent'` >5 ngày chưa paid → draft nhắc nhẹ 1 lần rồi thôi.
7. **Seekers hết hạn**: `move_in` < hôm nay − 14 ngày và status='active' → đề xuất set 'inactive' (hỏi bạn).
8. **Listing accepted nhưng <3 YES sau 24h** → đề xuất push thêm.

## Output
Bảng: # · việc · ai · draft có sẵn (id) · deadline. Sau bảng: "Gõ `/sublet-draft sent <ids>` khi gửi xong."
Gửi bản rút gọn (≤8 dòng) lên Telegram nếu `config.telegram.chat_id` có.
