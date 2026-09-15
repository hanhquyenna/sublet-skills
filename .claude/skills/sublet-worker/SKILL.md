---
name: sublet-worker
description: Điểm vào duy nhất cho cron — mỗi tick làm ĐÚNG 1 job step có time-box (≤8 phút) từ hàng đợi sublet_jobs theo ưu tiên (scan > analyze > match > email > backfill chunk > verify_group chunk), ghi tiến độ vào progress rồi thoát. Không bao giờ chạy 92 group trong 1 prompt. Dùng với /sublet-worker; cron gọi mỗi 10'.
---

# sublet-worker

## Spec
| | |
|---|---|
| **Lịch** | cron mỗi 10' 08–23 (launchd `com.sublet.worker`); Hetzner: mỗi 10' 24/7 (chỉ job không cần browser) |
| **Trigger** | `/sublet-worker [job_type]` — không tham số = tự chọn |
| **Đọc** | `sublet_jobs` (due, theo priority), `sublet_ops_state`, config |
| **Ghi** | `sublet_jobs` (status, progress, attempts, next_run_at), rồi gọi skill tương ứng |
| **Metrics** | ops.jobs_done_24h, jobs_failed_24h, job_step_seconds_p50 |
| **Edge cases** | E106 E107 E108 E109 → `docs/edge-cases.md` |
| **Rules** | R02 R03 R04 R05 R20 R21 |

## Vì sao có skill này
1 cron tick trong Codex/Claude Code = 1 prompt = 1 lượt làm việc ngắn. Việc lớn (backfill 1 group = 300 post, verify 92 group) **phải chia thành step** và nối qua nhiều tick bằng `progress` trong DB. Cron không cần biết việc gì — chỉ gọi worker.

## Thuật toán 1 tick (time-box 8 phút)
1. **Dọn**: job `running` có `started_at` > 20' → `status='queued'`, `attempts+1`, `progress` giữ nguyên (E106). `attempts ≥ 3` → `failed`, `sublet_inbox(warning)`.
2. **Sinh job định kỳ nếu chưa có** (idempotent nhờ unique open index):
   - `scan` priority 10, `next_run_at = now()` nếu job scan done gần nhất > 12' (và giờ trong `hours`, `chrome_fb_login=yes`, không `scan_paused_until`)
   - `analyze` priority 20 nếu `select count(*) from sublet_v_analyze_queue` > 0
   - `match` priority 30 cho mỗi listing trong `sublet_v_deal_queue` chưa có match (key = listing_id)
   - `email` priority 40 nếu `env_imap=yes` và job email done gần nhất > 10'
   - `backfill` priority 60 cho mỗi group tier 1 `joined` chưa có `ops_state backfill_<key>` (key = group_key) — **chỉ 1 group `running` tại 1 thời điểm**
   - `verify_group` priority 70 cho group `joined=false` hoặc chưa có `sublet_group_metrics` (key = group_key), theo lô 5 group/step
   - `groups_rank` priority 80 nếu CN và chưa chạy hôm nay
3. **Chọn 1 job**: `select * from sublet_jobs where status='queued' and next_run_at <= now() order by priority, next_run_at limit 1`. Không có → in "idle", thoát.
4. **Gate**: job cần browser (`scan`, `backfill`, `verify_group`) và `chrome_fb_login != yes` → `next_run_at = now()+30'`, thoát. Vượt page-load budget 24h → `next_run_at = ngày mai 08:00`.
5. `status='running'`, `started_at=now()`. Chạy **1 step** của skill tương ứng với `progress` hiện tại:
   - `scan` → `/sublet-scan` (bản thân đã ≤4 load, ≤2') → `done`
   - `analyze` → `/intent-analyze` 1 batch 40 → còn hàng đợi thì `queued` lại với `next_run_at=now()`, hết thì `done`
   - `match` → `/sublet-match <key>` → `done`
   - `email` → `/sublet-email` → `done`
   - `backfill` → `/sublet-backfill <key>` **chế độ chunk**: tiếp từ `progress.last_post_at`, tối đa 6 phút hoặc 60 post; ghi `progress={last_post_at, posts_done, scrolls}`; chưa tới `days` → `queued`, `next_run_at=now()+15'` (nghỉ giữa chunk = human pace); tới → `done` + `ops_state backfill_<key>`
   - `verify_group` → mở ≤5 group page (5 load), ghi `sublet_group_metrics` + `sublet_groups.joined/is_private/member_count`; `progress.checked += 5`; hết lô → `done`
   - `groups_rank` → `/sublet-groups rank` → `done`
6. Ghi `finished_at`, in 1 dòng: `job#id type key → status (Xs, page_loads=N)`. Lỗi → `status='queued'`, `attempts+1`, `last_error`, `next_run_at=now()+10'` (R21).

## Ưu tiên giải thích bằng lời
Post mới đáng tiền hơn post cũ → scan trước. Post đã capture mà chưa phân loại là vô dụng → analyze ngay sau. Backfill và verify là "việc nền", chỉ chạy khi 4 việc trên rảnh, và mỗi lần chỉ 1 mẩu để không chiếm page-load budget của scan.

## Ước lượng thời gian thật (Amsterdam, 43 group joined)
| Việc | Kích thước | Số tick | Xong sau |
|---|---|---|---|
| scan | 2 load, feed gom 92 group | mỗi tick 1 lần | liên tục |
| verify 50 group còn lại | 5 group/tick | 10 tick | ~2 giờ |
| backfill 8 group tier 1 × 60 ngày | ~300 post/group, 60 post/chunk | 5 chunk/group → 40 tick | ~1 tuần (xen kẽ với scan, human pace) |
| analyze 2.400 post backfill | 40/batch | 60 tick | cùng tuần |

Không cần nhanh hơn: Phase 0 là 30 ngày.

## Không
- Không chạy 2 job cùng tick. Không chạy job browser song song với backfill của tick khác (unique open index + flock đã chặn).
- Không bỏ qua gate giờ/login/pause dù job "khẩn".
