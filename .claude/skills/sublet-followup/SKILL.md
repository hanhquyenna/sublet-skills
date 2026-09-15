---
name: sublet-followup
description: Danh sách việc cần bạn hôm nay — thread im lặng, viewing sắp tới cần reminder, fee chưa thu, draft chưa gửi, seeker hết hạn — kèm draft follow-up đã soạn. Dùng buổi sáng với /sublet-followup.
---

# sublet-followup

## Spec
| | |
|---|---|
| **Lịch** | cron 08:30 (com.sublet.followup); tay bất kỳ lúc nào |
| **Trigger** | `/sublet-followup` |
| **Đọc** | sublet_v_today, sublet_inbox, sublet_messages, sublet_listings, sublet_viewings, sublet_fees, sublet_seekers, ops/backup |
| **Ghi** | sublet_messages (draft follow-up), sublet_listings.status=dead, sublet_fees.invoice_status=disputed, sublet_inbox.read_at, sublet_seekers.status=inactive (sau khi bạn OK) |
| **Metrics** | outreach.draft_backlog; fee.collection_rate; ops.backup_ok |
| **Edge cases** | E53 E93 E104 → `docs/edge-cases.md` |
| **Rules** | R12 R13 R14 R16 → `docs/rules.md` |

> **Đọc `partner-voice` trước khi soạn bất kỳ tin nào.** Định vị, giọng, giới hạn 90/40 từ, minh bạch ai trả phí — đều ở đó.

Chạy 1 lần/ngày, buổi sáng. Không gửi gì. Đưa ra ≤10 việc, ưu tiên theo tiền và thời gian.

## Truy vấn
0. `select * from sublet_v_today` — gom sẵn draft chưa gửi, viewing 36h tới, fee mở, inbox chưa done. Dùng làm khung; các mục dưới bổ sung phần view chưa có.
1. **Draft chưa gửi**: `sublet_messages status='draft'` cũ hơn 2h → liệt kê, nhắc gửi hoặc xoá.
2. **DM không trả lời**: listings `status='contacted'`, `contacted_at` 3–4 ngày trước, chưa có message `direction='in'` → draft follow-up #1 (templates/followup.md). Nếu đã có follow-up #1 và thêm 4 ngày → đánh `status='dead'`, không draft nữa.
3. **"Maybe later"**: listings có notes chứa "later"/"maybe", 5 ngày → draft check-in với số seeker đang match.
4. **Viewing hôm nay**: `sublet_viewings scheduled_at` trong 24h, attendance='pending' → draft reminder T-3h cho seeker; liệt kê giờ.
5. **Viewing hôm qua chưa có kết quả**: attendance='pending', scheduled_at < now → hỏi bạn showed/no_show; draft tin hỏi seeker (TAKING/NOT TAKING/WAITING).
6. **Fee**: `sublet_fees invoice_status='draft'` → nhắc gửi; `'sent'` >5 ngày chưa paid → draft nhắc nhẹ 1 lần rồi thôi.
7. **Seekers hết hạn**: `move_in` < hôm nay − 14 ngày và status='active' → đề xuất set 'inactive' (hỏi bạn).
8. **Listing accepted nhưng <3 YES sau 24h** → đề xuất push thêm.
9. **Fee sent >7 ngày chưa paid** (E93) → `invoice_status='disputed'`, không nhắc nữa, ghi vào report.
10. **Backup hôm qua thiếu** (`ops/backup/<hôm qua>/` không có) (E104) → 1 dòng cảnh báo.

## Output
Bảng: # · việc · ai · draft có sẵn (id) · deadline. Sau bảng: "Gõ `/sublet-draft sent <ids>` khi gửi xong."
Đầu tiên đọc `sublet_inbox where done_at is null` — đó là hàng đợi; gộp với 8 truy vấn dưới, không lặp. Cuối cùng đánh `read_at=now()` cho các mục đã hiển thị. Không gửi đi đâu cả.
