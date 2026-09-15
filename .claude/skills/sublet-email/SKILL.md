---
name: sublet-email
description: Đọc email notification Facebook (facebookmail.com) qua IMAP bằng scripts/gmail_pull.py, chuyển thành listing như sublet-scan nhưng không cần browser — chạy được 24/7 trên Hetzner. Dùng khi người dùng gõ /sublet-email hoặc trong cron.
---

# sublet-email

## Spec
| | |
|---|---|
| **Lịch** | cron mỗi 10' (Mac: com.sublet.email; Hetzner 24/7) |
| **Trigger** | `/sublet-email` |
| **Đọc** | Gmail IMAP (facebookmail.com) qua scripts/gmail_pull.py |
| **Ghi** | sublet_listings (source=fb_email), sublet_scan_runs(mode=email), sublet_inbox(warning nếu parse lỗi) |
| **Metrics** | capture.posts_captured_24h |
| **Edge cases** | E17 E18 E19 E20 → `docs/edge-cases.md` |
| **Rules** | R10 R21 → `docs/rules.md` |

Cùng pipeline với `sublet-scan` nhưng nguồn là email. Không đụng Facebook.

## Chuẩn bị (1 lần)
- Trong mỗi group tier 1–2: Group → Notifications → **All posts**.
- Gmail: bật IMAP, tạo App Password. Export `SUBLET_IMAP_USER`, `SUBLET_IMAP_PASS` trong shell (không commit).

## Các bước
1. `insert into sublet_scan_runs(mode) values ('email') returning id`.
2. `python3 scripts/gmail_pull.py --since-days 1` → JSON.
3. Mỗi item có `post_url` chưa có trong `sublet_listings.source_url`: phân loại + extract như sublet-scan bước 5, `source='fb_email'`, `raw_text=snippet`. Email bị cắt → nếu offering thiếu ngày/giá, đánh `notes='needs_full_read'` để sublet-scan mở permalink ở chu kỳ tới (tối đa 2/chu kỳ).
4. Item không có `post_url` (digest gộp): tách từng dòng "X posted in Y", lưu `source_url = 'email:' || message_id || '#' || n` để không trùng, `notes='digest_no_link'`.
5. Cập nhật run. Chạy `/sublet-match` cho offering mới có đủ ngày + giá.
6. Khi chạy xong lần đầu ổn định: thêm `--mark-seen` để không đọc lại.

## Khi lên Hetzner
Cron `*/10 8-23 * * *` gọi Claude Agent SDK với prompt "run /sublet-email". Không cần Chrome.
