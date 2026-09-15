---
name: sublet-report
description: Báo cáo cuối ngày và metrics Phase 0 (posts/ngày theo group, scam rate, DM→yes, fill trong 72h, show-up, fee thu, page loads) từ Supabase qua scripts/report.py, ghi sublet_inbox. Dùng với /sublet-report [7d].
---

# sublet-report

## Các bước
1. Kéo qua `execute_sql` (7 ngày, hoặc 30 ngày nếu tham số `30d`):
   - `select * from sublet_listings where seen_at > now() - interval '7 days'`
   - `select * from sublet_seekers`
   - `select * from sublet_matches where created_at > now() - interval '7 days'`
   - `select * from sublet_viewings where created_at > now() - interval '30 days'`
   - `select * from sublet_fees`
   - `select * from sublet_scan_runs where started_at > now() - interval '7 days'`
   - `select id,status,entity_type,created_at from sublet_messages where created_at > now() - interval '7 days'`
2. Ghi thành 1 JSON `{listings, seekers, matches, viewings, fees, scan_runs, messages}` trong scratchpad → `python3 scripts/report.py < data.json`.
3. Thêm 3 dòng nhận xét của agent: group nào đáng lên tier 1 / xuống tier 3; yes-rate so với mốc 30%; có dấu hiệu volume Facebook cao không.
4. Insert `sublet_inbox(level='info', title='Report {date}', body=<markdown>)`. In bản đầy đủ ra terminal.

## Mốc Phase 0 (30 ngày) — để tự đánh giá
- ≥200 offering thật/tháng trong tier 1–2
- DM→yes ≥ 30% (dưới 20% = đổi offer)
- ≥50% listing accepted có 3 viewing trong 72h
- Show-up ≥ 70%
- Fee thu ≥ 70% fee gửi
- Page loads/ngày ≤ 400
