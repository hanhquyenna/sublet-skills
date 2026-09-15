---
name: sublet-report
description: Báo cáo cuối ngày và metrics Phase 0 (posts/ngày theo group, scam rate, DM→yes, fill trong 72h, show-up, fee thu, page loads) từ Supabase qua scripts/report.py, ghi sublet_inbox. Dùng với /sublet-report [7d].
---

# sublet-report

## Spec
| | |
|---|---|
| **Lịch** | cron 18:00 (com.sublet.report); tay: /sublet-report [7d|30d] |
| **Trigger** | `/sublet-report` |
| **Đọc** | mọi bảng sublet_* (7–30 ngày), scripts/report.py --metrics-json |
| **Ghi** | sublet_metrics (1 dòng/ngày/metric), sublet_inbox(info) |
| **Metrics** | tất cả — xem docs/metrics.md |
| **Edge cases** | E104 → `docs/edge-cases.md` |
| **Rules** | R16 → `docs/rules.md` |

## Các bước
1. Kéo qua `execute_sql` (7 ngày, hoặc 30 ngày nếu tham số `30d`):
   - `select * from sublet_listings where seen_at > now() - interval '7 days'`
   - `select * from sublet_seekers`
   - `select * from sublet_matches where created_at > now() - interval '7 days'`
   - `select * from sublet_viewings where created_at > now() - interval '30 days'`
   - `select * from sublet_fees`
   - `select * from sublet_scan_runs where started_at > now() - interval '7 days'`
   - `select id,status,entity_type,created_at from sublet_messages where created_at > now() - interval '7 days'`
2. Ghi thành 1 JSON `{listings, seekers, matches, viewings, fees, scan_runs, messages}` trong scratchpad → `python3 scripts/report.py --metrics-json < data.json`.
2b. Phần sau `<!-- metrics-json -->` là mảng `{workflow, metric, value, target}` → `insert into sublet_metrics(day, workflow, metric, value, target) values (...) on conflict (day, workflow, metric) do update set value=excluded.value, target=excluded.target, computed_at=now()`. Thêm tay các metric chưa có trong script (`know.*`, `analyze.low_conf_rate`, `viewing.accepted_to_3v_72h`, `ops.*`) bằng SQL trực tiếp theo công thức trong `docs/metrics.md`.
2c. Kiểm ngưỡng tự động (docs/metrics.md mục 'Quyết định tự động'): vi phạm → `sublet_inbox(level='action', title='Metric: <tên> = <giá trị> (target <t>) → <đề xuất>')`.
3. Thêm 3 dòng nhận xét của agent: group nào đáng lên tier 1 / xuống tier 3; yes-rate so với mốc 30%; có dấu hiệu volume Facebook cao không.
4. Insert `sublet_inbox(level='info', title='Report {date}', body=<markdown>)`. In bản đầy đủ ra terminal.

### Quy tắc báo cáo backfill 14 ngày

- Báo riêng `posts_14d_count` chỉ khi `posts_14d_complete=true`; nếu chưa đủ,
  báo `known_verified_posts` và lý do incomplete, không gọi đó là tổng 14 ngày.
- Tách rõ activity tổng (`posts_per_day`) khỏi offering thật (`kind='offering'`).
- Có thể đếm raw comments/replies và public-context items từ
  `context_captured`, nhưng không biến chúng thành listing, seeker, match hay
  điểm scam trước bước `intent-analyze`.

## Mốc Phase 0 (30 ngày) — để tự đánh giá
- ≥200 offering thật/tháng trong tier 1–2
- DM→yes ≥ 30% (dưới 20% = đổi offer)
- ≥50% listing accepted có 3 viewing trong 72h
- Show-up ≥ 70%
- Fee thu ≥ 70% fee gửi
- Page loads/ngày ≤ 400
