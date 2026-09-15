---
name: inbox-triage
description: Đọc reply đến (Messenger trong Chrome thật — chỉ đọc, ≤6 page load; WhatsApp/Telegram/email do bạn dán hoặc forward), gắn vào đúng listing/seeker/match, phân loại (ok / question / no / negotiating / scam / yes-viewing / done), cập nhật trạng thái, và soạn câu trả lời theo partner-voice để bạn tap gửi. Câu hỏi thường gặp dùng template FAQ có sẵn nên tap 1 phát là xong. Dùng với /inbox-triage, chạy trong cron 20'.
---

# inbox-triage

## Spec
| | |
|---|---|
| **Lịch** | cron mỗi 20' 08–23 (com.sublet.inbox); tay khi dán reply |
| **Trigger** | `/inbox-triage` |
| **Đọc** | Messenger (≤6 loads, đọc-only), text bạn dán, sublet_listings/seekers/matches, templates/faq.md, partner-voice |
| **Ghi** | sublet_messages (in + draft), sublet_listings.status (accepted/declined/filled), sublet_matches.status/replied_at, sublet_viewings.attendance, sublet_seekers.contact_consent (E51), sublet_inbox(action/warning) |
| **Metrics** | inbox.replies_24h, triage_unclear_rate; outreach.dm_yes_rate_7d |
| **Edge cases** | E51 E80–E87 → `docs/edge-cases.md` |
| **Rules** | R01 R02 R08 R12 R13 R23 → `docs/rules.md` |

Đây là "tai" của hệ thống. Đọc `partner-voice` trước. **Skill này không gửi gì.** Nó đọc, phân loại, cập nhật trạng thái, và xếp sẵn câu trả lời.

## Nguồn reply
1. **Messenger**: Chrome `navigate` `https://www.facebook.com/messages/t/` (**1 page load**), `get_page_text` danh sách hội thoại; mở tối đa **5 hội thoại có tin chưa đọc** (mỗi cái 1 load, tổng ≤6). Không mở hội thoại không liên quan đến sublet.
2. **WhatsApp/Telegram/email**: bạn dán hoặc forward vào chat; (không có kênh nào khác đọc hộ — bạn dán).

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
| "send me your seekers' numbers first" / yêu cầu tiền / link lạ | scam/risk | listing scam_score +40, notes | không draft; insert `sublet_inbox(level='warning', ...)` |
| seeker: "YES + availability" | muốn xem | match → `replied`, ghi availability | gọi viewing-coordinate khi đủ 3 |
| seeker: "NO" | không hợp | match → `rejected` | không gửi listing này nữa |
| seeker: "DONE / TAKING / moved in today" | kết quả | viewing attendance; match → `signed` nếu taking; listing → `filled` | trigger fee (viewing-coordinate) → draft tin Tikkie |
| seeker: YES nhưng `contact_consent=false` (E51) | reply = consent | `contact_consent=true`, event `consent_by_reply` | tiếp tục như YES |
| subletter: "found someone" khi đã có viewing (E84) | filled ngoài bạn | listing → `filled`, notes='filled_externally', **không** fee; viewings → `cancelled` | draft báo seeker + đề xuất listing khác |
| seeker YES nhưng listing đã filled (E85) | trễ | match → `rejected` | draft "đã có người, mình gửi cái khác" |
| subletter muốn thu phí seeker (E83, R23) | không hợp lệ | notes, `sublet_inbox(warning)` | draft từ chối lịch sự: seeker luôn free |
| không rõ | — | — | hỏi bạn |

## Output
Bảng: ai · kênh · phân loại · trạng thái mới · draft (id). Mọi draft đều `sublet_messages status='draft'`; bạn gõ `/sublet-draft sent <id>` sau khi gửi. Mỗi `accepted` mới → `sublet_inbox(level='action')`; mỗi `scam` → `sublet_inbox(level='warning')`.

## Không
- Không gửi bất kỳ tin nào. Không gửi contact seeker. Không thương lượng giá.
- Không mở >6 page load. Không đọc hội thoại không liên quan.
