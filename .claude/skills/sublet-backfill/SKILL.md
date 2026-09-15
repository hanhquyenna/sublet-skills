---
name: sublet-backfill
description: Đọc lịch sử 14 ngày của MỘT group (resumable, chậm, human pace, panel-only), lưu đầy đủ raw post và public context nhìn thấy vào database, rồi để intent-analyze xử lý sau. Không phải scan định kỳ. Dùng với /sublet-backfill [group_key] [days].
---

# sublet-backfill

Đọc `CLAUDE.md`, `AGENTS.md` và
`../sublet-scan/references/capture-contract.md` trước khi chạy. Skill này là
capture-only: không phân tích intent và không thao tác để thay đổi Facebook.

## Spec

| | |
|---|---|
| **Lịch** | tay/worker: từng group, mỗi group một lần, human pace |
| **Trigger** | `/sublet-backfill <group_key> [days]` — mặc định `14` |
| **Đọc** | một group page chronological + scroll, sublet_ops_state, sublet_group_metrics |
| **Ghi** | sublet_listings raw, sublet_events(context_captured), sublet_scan_runs(mode=group_page), sublet_group_metrics, sublet_ops_state, sublet_groups.last_scanned_at |
| **Metrics** | capture.posts_14d_verified, capture.groups_14d_complete, page-load budget |
| **Edge cases** | E10 E12 E13 E14 E20 E23 E24 E25 E26 E27 → `docs/edge-cases.md` |
| **Rules** | R02 R03 R05 R06 R10 R19 R21 R25 R26 → `docs/rules.md` |

## Chế độ chunk (bắt buộc khi gọi từ sublet-worker)

Một group có thể vượt 1 prompt. Mỗi tick chỉ xử lý một chunk, tối đa khoảng 6
phút hoặc 60 post, rồi lưu progress và queue lại sau khoảng nghỉ human pace.
Progress phải giữ tối thiểu:

```json
{
  "window_days": 14,
  "sorting": "CHRONOLOGICAL",
  "last_verified_post_at": null,
  "last_source_url": null,
  "posts_verified": 0,
  "unresolved_cards": 0,
  "scrolls": 0,
  "phase": "capturing"
}
```

Chỉ khi đã qua mốc 14 ngày **và** mọi card có permalink trong window đã được
xử lý mới đóng run/job, set `posts_14d_count`, `posts_14d_complete=true`,
`posts_14d_checked_at`, và ghi `ops_state backfill_<group_key>`. Gọi tay cũng
chỉ là một chunk; chưa đủ điều kiện thì không báo hoàn tất.

## Điều kiện và thứ tự

- `chrome_fb_login=yes`, group đã được người dùng join, đang trong giờ
  `Europe/Amsterdam`, và không vượt page-load budget.
- Chọn group đã joined có `posts_per_day` mới nhất cao nhất trước. Đây chỉ là
  tín hiệu volume; không coi là offering thật. Chỉ một group browser job chạy
  tại một thời điểm.
- Nếu đã có `ops_state backfill_<group_key>` với trạng thái hoàn tất thì dừng;
  nếu run dang dở thì tiếp tục đúng cursor, không bắt đầu lại từ đầu.

## Cách đọc và ghi

1. Insert `sublet_scan_runs(mode='group_page', group_key=<key>)` hoặc tiếp tục
   run đang mở. Cửa sổ tính theo 14 ngày lịch từ thời điểm run, timezone
   `Europe/Amsterdam`.
2. Trong ChatGPT/Codex in-app browser panel, mở
   `<group url>?sorting_setting=CHRONOLOGICAL` (page load), rồi scroll với
   khoảng chờ nhỏ. Đọc từng card từ mới tới cũ; không dùng script, API,
   headless browser, cookie, HTTP, hay browser session khác.
3. Dừng chunk khi hết time-box/limit; dừng toàn bộ ngay khi thấy login,
   checkpoint, captcha, “unusual activity”, verification request, layout không
   đọc được, hoặc DB lỗi sau một lần retry. Run vẫn incomplete và phải ghi lý do.
4. Với mỗi post có group + permalink xác minh: lưu full `raw_text`, poster,
   timestamp tuyệt đối nếu Facebook thật sự hiển thị, `seen_at`, `kind=null`,
   rồi lưu `context_captured` theo capture contract v2 với `scan_run_id`,
   `page_load`, `source_surface='codex_in_app_browser'`. Giữ comment/reply đang
   hiển thị (tối đa 100/post), profile URL public nếu có, và public activity
   trực tiếp gắn với post (tối đa 10 post hoặc 30 ngày mỗi poster/commenter).
5. Không đoán permalink. Card thiếu link là `unresolved_cards`, không insert
   listing và không tính vào `posts_14d_count`.
6. Sau **từng batch**, ghi listing + event + cursor/progress và cập nhật metric
   group. Không chờ hết 67/103 group mới ghi DB. `posts_seen` không đồng nghĩa
   tổng post 14 ngày, nhất là khi feed virtualized.
7. Không gọi `intent-analyze` trong capture step. Sau khi raw capture hoàn tất,
   chạy analyzer riêng trên các row `kind is null`.

## Không làm

- Không join group, trả lời/submit membership form, bật notification,
  post/comment/like/DM/send/donate.
- Không vào DM, private profile/content, friend list, album/ảnh riêng tư; không
  tách email/số điện thoại thành contact profile và không suy luận thuộc tính
  nhạy cảm.
- Không đóng run hoặc ghi `posts_14d_complete=true` chỉ vì thấy nhãn “2 tuần”,
  đạt `posts_seen`, hết time-box, hoặc gặp lỗi DB.

## Sau khi capture hoàn tất

Chỉ lúc người vận hành yêu cầu mới chạy `/intent-analyze` theo
`docs/intent-logic.md`, sau đó mới match/draft. Mọi draft vẫn là `status='draft'`
để người dùng tự gửi.
