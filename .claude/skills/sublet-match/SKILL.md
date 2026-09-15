---
name: sublet-match
description: Ghép một listing sublet với pool seekers bằng scripts/match.py (date window, budget, area, hard constraints), lưu sublet_matches kèm lý do và cờ rủi ro. Dùng khi có listing mới, hoặc người dùng gõ /sublet-match <listing_id|mô tả>.
---

# sublet-match

## Spec
| | |
|---|---|
| **Lịch** | tự động sau intent-analyze (offering deal_score≥60); tay: /sublet-match <id> |
| **Trigger** | `/sublet-match` |
| **Đọc** | 1 listing, sublet_v_seekers_active, scripts/match.py |
| **Ghi** | sublet_matches (score, reasons, risk_flags), sublet_listings.status=matched |
| **Metrics** | match.listings_with_3plus, avg_top_score |
| **Edge cases** | E60 E61 E62 E63 E64 → `docs/edge-cases.md` |
| **Rules** | R09 R11 R18 → `docs/rules.md` |

Score do script tính. Agent chỉ viết `reasons` cho dễ đọc và kiểm tra cờ.

## Các bước
1. Xác định listing: id được truyền, hoặc tìm theo mô tả (`area`, `rent`, mới nhất).
2. Kéo listing (1 row) và tất cả `sublet_seekers where status='active'` qua Supabase `execute_sql`. Ghi ra 2 file tạm trong scratchpad dạng JSON.
3. `python3 scripts/match.py listing.json seekers.json --top 15`.
4. Với mỗi match score ≥ 50: upsert `sublet_matches(listing_id, seeker_id, score, reasons, risk_flags, status='proposed')`. Score < 50 không lưu.
5. Nếu listing `scam_score ≥ 60`: vẫn tính nhưng **không tạo match**, in cảnh báo.
6. Cập nhật `sublet_listings.status='matched'` nếu có ≥1 match ≥ 60.
7. In bảng: rank · seeker · score · 1 dòng lý do · cờ. Đề xuất "push top N?" — không tự push.

## Lưu ý
- Seeker `contact_consent=false` vẫn được match (để đo pool) nhưng bị đánh dấu `no_consent` trong risk_flags và không được draft push.
- Chạy lại khi listing đổi ngày/giá: xoá match cũ status='proposed' rồi tính lại.
