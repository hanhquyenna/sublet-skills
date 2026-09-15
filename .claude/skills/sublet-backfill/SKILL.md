---
name: sublet-backfill
description: Đọc lịch sử 60–90 ngày của MỘT group (1 lần duy nhất, chậm, human pace, ≤25 page load/ngày) để có corpus vài trăm post trước khi phân tích edge case. Không phải scan định kỳ. Dùng với /sublet-backfill [group_key] [days].
---

# sublet-backfill

## Spec
| | |
|---|---|
| **Lịch** | tay: 1 group/ngày, 1 lần/group, ngày yên |
| **Trigger** | `/sublet-backfill <group_key> [days]` |
| **Đọc** | 1 group page (chronological) + scroll, sublet_ops_state |
| **Ghi** | sublet_listings (raw), sublet_scan_runs(mode=backfill), sublet_ops_state backfill_<key>, sublet_groups.last_scanned_at |
| **Metrics** | capture.posts_captured_24h; analyze.qa_kind_acc (QA sau backfill) |
| **Edge cases** | E10 E13 E14 E20 E23 E24 → `docs/edge-cases.md` |
| **Rules** | R02 R03 R05 R06 R19 → `docs/rules.md` |

Mục đích: có dữ liệu thật để `intent-analyze` chạy trên vài trăm post và bạn thấy edge case **trước** khi gửi DM đầu tiên. Chạy 1 lần/group, không lặp.

## Chế độ chunk (bắt buộc khi gọi từ sublet-worker)
1 group = ~300 post = quá 1 prompt. Vì vậy backfill **resumable**: mỗi lần chạy là 1 chunk ≤6 phút hoặc ≤60 post, đọc `sublet_jobs.progress` `{last_post_at, posts_done, scrolls}` để tiếp tục từ chỗ dừng (scroll tới khi post cũ hơn `last_post_at`), ghi lại progress khi hết chunk. Job `queued` lại với `next_run_at = now()+15'` — khoảng nghỉ này chính là human pace. Chỉ khi post đã cũ hơn `days` → `done` + `ops_state backfill_<key>`.
Gọi tay `/sublet-backfill <key>` = 1 chunk, không phải cả group.

## Model routing

Đọc `models.sublet_backfill` từ `data/config.yaml`. Nếu runtime cho phép chọn model, dùng model nhỏ/rẻ nhất được cấu hình cho capture lịch sử và phần phân tích; nếu không, giữ model runtime hiện tại. Không dùng routing này cho draft hoặc giao tiếp đối tác.

## Điều kiện
- `sublet_ops_state.chrome_fb_login = yes`; bạn đã là member của group.
- Chưa có `sublet_ops_state('backfill_<group_key>')`. Có rồi → dừng, in ngày đã backfill.
- Trong giờ (`config.hours`). Tổng page load 24h < 300 (backfill chiếm chỗ của scan, nên làm vào ngày yên).

## Cách đọc (human pace)
1. `insert sublet_scan_runs(mode='group_page')` — 1 run cho cả backfill.
2. Chrome: `navigate` `<group url>?sorting_setting=CHRONOLOGICAL` (1 page load). Facebook load thêm post bằng scroll, không đổi URL → **scroll không tính là page load**, nhưng mỗi lần scroll chờ 3–8s ngẫu nhiên, và cứ 10 lần scroll nghỉ 30–90s.
3. `get_page_text` sau mỗi 3 lần scroll; dừng khi: post cũ hơn `days` (mặc định 60), hoặc đã đọc 300 post, hoặc 40 phút trôi qua, hoặc thấy checkpoint/captcha (→ dừng, ghi `stop`).
4. Với mỗi post chưa có `source_url`: capture thô như `sublet-scan` bước 5 (`source='fb_feed'`, `kind=null`). Không mở permalink, không mở comment.
5. Kết thúc: update run (`posts_seen`, `new_listings`, `page_loads`), `sublet_ops_state('backfill_<group_key>', 'yes: <date>, <n> posts')`, `sublet_groups.last_scanned_at`.
6. Gọi `/intent-analyze` cho batch vừa capture (chạy nhiều lượt 40 post cho đến hết `kind is null`).

## Sau backfill — bước "edge case" (làm cùng bạn)
- `/intent-analyze` QA: lấy 20 post ngẫu nhiên đã phân loại, in text + kết quả cạnh nhau, bạn đánh đúng/sai.
- In thống kê: kind × subtype × poster_type; top 10 `deal_score`; 10 `confidence=low`; 10 `scam≥60`.
- Với mỗi lỗi: thêm ví dụ vào `docs/intent-logic.md §12`, sửa rule, `/intent-analyze --all`, so số trước/sau.
- Mục tiêu trước khi DM: kind đúng ≥95%, subtype ≥85%, không có agency lọt vào deal_score ≥60.

## Không
- Không backfill 2 group cùng ngày. Không chạy khi scan cron đang bận (unload `com.sublet.scan` trước nếu cần).
- Không đọc profile, không lưu ảnh, không mở comment.
