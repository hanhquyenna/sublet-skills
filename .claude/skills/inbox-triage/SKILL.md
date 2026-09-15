---
name: inbox-triage
description: Đọc reply đến (Messenger trong Chrome thật — chỉ đọc, ≤6 page load; WhatsApp/Telegram/email do bạn dán hoặc forward), gắn vào đúng listing/seeker/match, phân loại (ok / question / no / negotiating / scam / yes-viewing / done), cập nhật trạng thái, và soạn câu trả lời theo partner-voice để bạn tap gửi. Câu hỏi thường gặp dùng template FAQ có sẵn nên tap 1 phát là xong. Dùng với /inbox-triage, chạy trong cron 20'.
---

# inbox-triage

Đây là "tai" của hệ thống. Đọc `partner-voice` trước. **Skill này không gửi gì.** Nó đọc, phân loại, cập nhật trạng thái, và xếp sẵn câu trả lời.

## Nguồn reply
1. **Messenger**: Chrome `navigate` `https://www.facebook.com/messages/t/` (**1 page load**), `get_page_text` danh sách hội thoại; mở tối đa **5 hội thoại có tin chưa đọc** (mỗi cái 1 load, tổng ≤6). Không mở hội thoại không liên quan đến sublet.
2. **WhatsApp/Telegram/email**: bạn dán hoặc forward vào chat; hoặc Telegram MCP đọc tin bạn forward vào chat riêng với bot.

## Gắn vào entity
- Tên người gửi + nội dung ↔ `sublet_listings.poster_name` (subletter) hoặc `sublet_seekers.name/contact` (seeker). Không chắc → hỏi bạn 1 câu, không đoán.
- Lưu `sublet_messages(direction='in', channel, body, entity_type, entity_id, status='received')`.

## Phân loại & chuyển trạng thái
| Reply | Ý | Update | Draft cho bạn |
|---|---|---|---|
| "ok / sure / yes let's do it" (subletter) | chấp nhận offer | listing → `accepted`, `accepted_at` | gọi `/viewing-coordinate` → draft shortlist |
| "how does it work / who are you / cost? / dates?" | hỏi thông tin | — | draft từ `templates/faq.md` (điền sẵn, bạn tap) |
| "no thanks / already found" | từ chối | listing → `declined` hoặc `filled` (nếu found) | draft 1 dòng cảm ơn, đóng thread |
| "I'll pay less / only if free / what if nobody signs" | negotiating | notes | draft 2 phương án trả lời, **bạn chọn** — agent không quyết tiền |
| "send me your seekers' numbers first" / yêu cầu tiền / link lạ | scam/risk | listing scam_score +40, notes | không draft; cảnh báo bạn qua Telegram |
| seeker: "YES + availability" | muốn xem | match → `replied`, ghi availability | gọi viewing-coordinate khi đủ 3 |
| seeker: "NO" | không hợp | match → `rejected` | không gửi listing này nữa |
| seeker: "DONE / TAKING / moved in today" | kết quả | viewing attendance; match → `signed` nếu taking; listing → `filled` | trigger fee (viewing-coordinate) → draft tin Tikkie |
| không rõ | — | — | hỏi bạn |

## Output
Bảng: ai · kênh · phân loại · trạng thái mới · draft (id). Mọi draft đều `sublet_messages status='draft'`; bạn gõ `/sublet-draft sent <id>` sau khi gửi. Nếu có `accepted` mới hoặc `scam` → Telegram ngay.

## Không
- Không gửi bất kỳ tin nào. Không gửi contact seeker. Không thương lượng giá.
- Không mở >6 page load. Không đọc hội thoại không liên quan.
