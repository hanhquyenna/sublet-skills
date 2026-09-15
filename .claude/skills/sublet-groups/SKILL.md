---
name: sublet-groups
description: Tìm và xếp hạng group Facebook housing/sublet cho một thành phố (đọc-only, qua Facebook search trong Chrome thật), lưu sublet_groups, quyết định tier 1/2/3 theo số post offering thực tế, và đề xuất group nào nên join/bật notification tuần này. Dùng với /sublet-groups [discover|rank|status].
---

# sublet-groups

Quản lý "biết group nào". Chỉ đọc. Không join (bạn join tay), không post.

## /sublet-groups discover  (chạy 1 lần/tuần, ≤6 page load)
1. Chrome: `navigate` `https://www.facebook.com/search/groups/?q=<query>` cho tối đa 3 query từ `data/config.yaml → city` × ["housing", "sublet", "rooms apartments"] (thêm "huurwoning", "kamer" nếu NL). **1 page load/query.** Scroll 2 lần, `get_page_text`.
2. Mỗi kết quả: tên, url, member count (nếu hiện), public/private, mô tả ngắn. Không mở từng group.
3. Đánh giá từ tên + mô tả: `allows_sublet` (yes/no/unknown — tên có "NO SUBLET"/"illegal rentals not allowed" → no), `allows_agencies` (tên có "No agencies" → false), ngôn ngữ.
4. Upsert `sublet_groups` (key = slug từ tên, unique url). Group mới → `tier=null`, `joined=false`.
5. In bảng ứng viên mới, sắp theo member_count, kèm đề xuất: "join 3 group này tuần này". Tối đa 5 đề xuất/tuần — Facebook giữ request nếu join dồn.

## /sublet-groups rank  (chạy được ngay nhờ group_metrics; chính xác sau ≥7 ngày scan)
0. **Tier tạm khi chưa có offering_7d** (tuần đầu): lấy `posts_per_day` mới nhất từ `sublet_group_metrics` cho mỗi group đã `joined`:
   - ≥3 post/ngày và allows_sublet != no → tier 1 (tối đa 8 group; nhiều hơn → chọn theo posts_per_day)
   - 0.5–3 → tier 2 · <0.5 hoặc không có metrics → tier 3
   Ghi `notes='tier tạm từ posts_per_day'`. Khi có `offering_7d` (bước 1–2) → ghi đè.
1. `select group_key, count(*) filter (where kind='offering' and seen_at > now()-interval '7 days') as offering_7d, avg(scam_score) ... from sublet_listings group by group_key`.
2. Quy tắc tier:
   - tier 1: offering_7d ≥ 10 và allows_sublet != no → đọc qua feed (đã là member, notification All posts)
   - tier 2: 2–9 offering_7d → chỉ email notification
   - tier 3: <2 hoặc allows_sublet = no → giữ trong DB, không đọc
3. Update `sublet_groups.tier`, `offering_7d`, `last_ranked_at`. **Đồng bộ ngược** `data/groups.yaml` (viết lại file từ DB, giữ notes).
4. In thay đổi tier + lý do.

## /sublet-groups status
Bảng: key · tier · joined · notif_all_posts · offering_7d · last_scanned_at · notes. Nhắc việc bạn cần làm tay: join pending, bật notification.

## Chống lặp scan (dùng bởi sublet-scan)
- `sublet_scan_runs.cursor` = permalink post mới nhất đã thấy ở đầu feed trong run trước. Run sau đọc feed từ trên xuống, **dừng khi gặp cursor** hoặc 3 URL liên tiếp đã có trong `sublet_listings` — không scroll tiếp.
- Mỗi group có `last_post_seen_at`; email/notification có timestamp cũ hơn → bỏ qua không cần query DB.

## Anti-ban (tóm tắt, chi tiết trong CLAUDE.md)
- Không mở từng group để scan; feed gom. Mở trang group riêng ≤20/ngày, chỉ khi cần full post.
- discover ≤6 page load/tuần; join ≤5 group/tuần, do bạn bấm.
- Không dùng search với từ khoá lặp lại mỗi giờ — search 1 lần/tuần là đủ.
