---
name: sublet-scrape-14-groups
description: "Điều phối batch capture đầu tiên của 14 Facebook groups: chọn group đã joined theo posts_per_day mới nhất, scrape raw đủ cửa sổ 14 ngày từng group một, resume từ DB, chống duplicate, cập nhật DB sau từng batch và chỉ chuyển group khi group trước hoàn tất. Dùng với /sublet-scrape-14-groups."
---

# sublet-scrape-14-groups

Đọc `CLAUDE.md`, `AGENTS.md` và
`../sublet-scan/references/capture-contract.md` trước khi chạy. Đây là
**batch controller**, không phải scraper riêng: nó gọi quy trình
`sublet-backfill` theo từng group và không bypass capture contract.

## Spec

| | |
|---|---|
| **Lịch** | chạy tay/worker; một batch 14 group tại một thời điểm |
| **Trigger** | `/sublet-scrape-14-groups` |
| **Đọc** | `sublet_groups`, latest `sublet_group_metrics`, `sublet_scan_runs`, `sublet_listings`, `sublet_events`, `sublet_ops_state` |
| **Ghi** | raw listings/context, scan runs, group metrics, `sublet_ops_state` batch progress |
| **Metrics** | `capture.groups_14d_complete`, `capture.posts_14d_verified`, page-load budget |
| **Edge cases** | E10 E12 E20 E23 E24 E25 E26 E27 E28 E29 → `docs/edge-cases.md` |
| **Rules** | R02 R03 R05 R06 R10 R19 R21 R25 R26 R27 R28 → `docs/rules.md` |

## Luật cứng của batch

- Chỉ dùng ChatGPT/Codex in-app browser panel đang đăng nhập thủ công. Không
  dùng script/API/HTTP/Selenium/headless/cookie/browser session khác để đọc
  Facebook.
- Facebook chỉ được đọc. Không join, submit membership form, bật notification,
  post, comment, like, DM, send hoặc donate.
- Một lần chỉ có **một group browser job**. Không mở 14 group song song và
  không giả vờ đã xử lý group nếu chưa capture đủ.
- Mỗi group có cửa sổ **14 ngày lịch**, capture raw post + poster + comment/reply
  công khai nhìn thấy + public context giới hạn; không phân tích intent trong
  bước này.
- Ghi listing/context/progress vào DB sau từng batch. Nếu DB lỗi sau một lần
  retry, dừng và giữ group incomplete.

## Khởi tạo hoặc tiếp tục batch

1. Đọc state `sublet_ops_state` key `scrape_14_groups_batch`. Nếu có batch đang
   chạy, tiếp tục `current_group` và cursor của group đó; không tạo batch mới.
2. Nếu chưa có batch, lấy tối đa 14 group đã `joined=true`, loại group có
   `allows_sublet='no'`, ưu tiên `posts_per_day` từ metric mới nhất giảm dần.
   Metric stale hoặc chưa verified chỉ dùng để xếp thứ tự, không gọi là
   offering thật. Nếu có dưới 14 group đủ điều kiện, ghi số thực tế, không bịa
   đủ 14.
3. Ghi state JSON tối thiểu:

```json
{
  "batch_id": "2026-09-15T22:00:00+02:00",
  "window_days": 14,
  "group_keys": [],
  "current_index": 0,
  "current_group": null,
  "completed": [],
  "blocked": [],
  "status": "running"
}
```

## DB checkpoint trước khi chạm browser

Với `current_group`, đọc theo thứ tự:

1. Run `sublet_scan_runs` mới nhất có `group_key` và `finished_at is null`;
   lấy `cursor` JSON: `window_days`, `last_verified_post_at`,
   `last_source_url`, `posts_verified`, `unresolved_cards`, `phase`.
2. Nếu không có run mở, đọc metric mới nhất và:
   - `max(posted_at)` của các listing đã có timestamp tuyệt đối;
   - `max(seen_at)` chỉ để biết lần quan sát DB gần nhất, **không** dùng nó làm
     thời điểm bài đăng;
   - listing/event mới nhất theo `source_url` để chống bắt đầu lại.
3. Ưu tiên resume cursor của run mở. Không reset về bài mới nhất chỉ vì prompt
   bị dừng, browser reset, hoặc DB vừa hoạt động lại. Nếu timestamp post là
   `null`, resume bằng verified `source_url`/cursor và dedupe DB.
4. Trước mỗi insert, kiểm tra `source_url` và raw `text_hash` hiện có. URL đã có
   thì không insert listing lần hai. Context event contract v2 đã có thì không
   tạo event trùng; chỉ bổ sung khi capture mới có raw evidence rõ ràng hơn và
   giữ provenance cũ.

## Vòng xử lý một group

1. Gọi `/sublet-backfill <current_group> 14` trong chế độ chunk. Skill đó mở
   đúng group chronological trong panel, đọc từ mới tới cũ và capture theo
   `sublet-scan/references/capture-contract.md`.
2. Sau mỗi chunk, kiểm tra DB: số listing mới, số context event contract v2,
   `last_verified_post_at`, `last_source_url`, `unresolved_cards`,
   `posts_14d_complete`. Không lấy `posts_seen` làm tổng 14 ngày.
3. Nếu chưa qua boundary hoặc còn card có permalink chưa xử lý, giữ group là
   `current_group`, queue chunk tiếp theo và không chuyển group.
4. Chỉ khi `posts_14d_complete=true` mới thêm group vào `completed`, tăng
   `current_index`, cập nhật batch state, rồi chọn group kế tiếp. `detail_audit`
   không thay thế `context_captured` và không được tính vào completion.
5. Khi cả danh sách đã complete, set batch `status='complete'`. Nếu group bị
   checkpoint/login/captcha/DB outage/layout blocker, đưa vào `blocked`, giữ
   `status='blocked'`, ghi lý do và không đánh dấu batch complete.

## Completion contract

Batch chỉ hoàn thành khi mọi group trong `group_keys` đều có:

- `posts_14d_complete=true` và `posts_14d_count` là số verified deduplicated;
- raw listings có `source_url` + `seen_at`, `kind=null`;
- context event có `capture_contract_version=2`, `capture_quality='complete'`,
  `scan_run_id`, `page_load`, `source_surface`, và đủ raw keys;
- không còn cursor/card có permalink trong cửa sổ 14 ngày chưa xử lý.

Sau batch capture mới chạy `/intent-analyze` riêng nếu người vận hành yêu cầu.
