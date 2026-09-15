---
name: viewing-coordinate
description: Khi subletter đồng ý, chọn top 3 seeker đã trả lời YES, soạn tin đề xuất slot cho subletter và tin xác nhận + reminder cho seeker, tạo sublet_viewings, theo dõi show/no-show và trigger fee sau 3 viewing. Dùng khi gõ /viewing-coordinate <listing>.
---

# viewing-coordinate

## Khi subletter trả lời "ok"
1. Update `sublet_listings.status='accepted', accepted_at=now()`. `sublet_events(event='offer_accepted', actor='human')`.
2. Nếu chưa push seekers → chạy `/sublet-draft` phần push trước.

## Chọn shortlist
1. Lấy matches status='replied' (seeker đã YES — người dùng cập nhật bằng `/viewing-coordinate replied <match_id>`), sắp theo score.
2. Top 3 → status='shortlisted'. Nếu <3 YES sau 24h → đề xuất push thêm 10 seeker tiếp theo.

## Soạn (draft, người dùng gửi)
- Cho subletter: `templates/viewing_confirm.md` phần subletter — 3 dòng tóm tắt (ngày, ngân sách, nghề, availability). Không gửi contact seeker cho đến khi subletter chọn slot.
- Khi subletter trả slot: tạo `sublet_viewings(match_id, scheduled_at)` từng người; draft xác nhận cho seeker; draft gửi contact seeker cho subletter.
- Reminder T-3h: draft, lưu `sublet_messages` với `template='viewing_reminder'`. `/sublet-followup` sẽ nhắc bạn gửi.

## Sau viewing
- Người dùng gõ `/viewing-coordinate showed|no_show|cancelled <viewing_id>` → update `attendance`.
- Khi listing có **3 viewings confirmed=true trong ≤72h kể từ accepted_at**: insert `sublet_fees(listing_id, trigger='three_viewings_72h', amount_eur=config.offer.price_eur, invoice_status='draft')` và draft tin fee từ `templates/followup.md` (mục "Subletter sau 3 viewings"). Người dùng gửi + đính Tikkie.
- Người dùng báo signed: `/viewing-coordinate signed <match_id>` → match status='signed', listing status='filled', filled_at, seeker status='housed'. **Chỉ ghi khi có xác nhận từ subletter hoặc seeker** — ghi nguồn vào events.payload.

## Không
- Không hứa kết quả, không thu tiền hộ, không giữ deposit, không chuyển địa chỉ chính xác.
