# Rules registry — mỗi luật: enforce ở đâu, kiểm bằng gì

Nguồn luật: `CLAUDE.md`. File này là chỉ mục để audit. Skill tham chiếu bằng mã R##.

| # | Luật | Enforce ở | Kiểm chứng | Trạng thái |
|---|---|---|---|---|
| R01 | Agent không post/comment/like/DM/join/gửi gì trên Facebook | CLAUDE.md #1; mọi skill chỉ có tool đọc; `sublet_messages.status='sent'` chỉ do người đổi | metric `outreach.sent_by_agent` phải = 0 (event actor='agent' & event='sent') | enforce |
| R02 | ≤4 page load/chu kỳ scan; ≤6 inbox-triage; ≤3 diagnose; ≤6/tuần discover | `sublet-scan` bước 2–6; `sublet_scan_runs.page_loads` | metric `capture.page_loads_per_run` max ≤4 | enforce |
| R03 | ≤~350 page load/ngày | `sublet-scan` điều kiện 2 (đếm 24h) | metric `capture.page_loads_24h` ≤350 | enforce |
| R04 | Chỉ chạy 08–23 Amsterdam; không chạy <2' sau wake | `ops/run_skill.sh` gate giờ + boottime | log `ops/logs/*.log` có "skip (ngoài giờ)" | enforce |
| R05 | Checkpoint/captcha/login → dừng, `sublet_inbox(stop)`, `scan_paused_until` +24h | `sublet-scan` bước 2; `run_skill.sh` gate pause | metric `ops.checkpoints` ; log "skip (paused)" | enforce |
| R06 | Không đọc profile, không lưu ảnh, không lưu contact từ post | `sublet-scan` "Không làm"; `intent-analyze` bước 10; `seeker-intake` | review: `sublet_seekers.contact is null where source='fb_seeking'` | enforce |
| R07 | Không headless, không cookie ngoài browser thật đã login tay | CLAUDE.md #6; AGENTS.md | không đo được tự động — audit tay | policy |
| R08 | Không ghi filled/signed/paid nếu không có xác nhận; ghi nguồn vào events.payload | `viewing-coordinate` "Sau viewing"; `inbox-triage` bảng | `sublet_events` cho mọi `filled/signed/paid` phải có `payload.source` | enforce |
| R09 | Không xếp hạng theo nationality/gender/age/religion | `scripts/match.py` chỉ dùng dates/budget/area/people/reg/pets/occupation; `poster_constraints` lưu nguyên văn không chấm | code review `match.py` | enforce |
| R10 | Mỗi record có `source_url` + `seen_at` | schema not null `seen_at`; `source_url` unique; capture bước 5 | `select count(*) from sublet_listings where source_url is null` = 0 | enforce |
| R11 | Match score từ `match.py`, LLM chỉ viết reasons | `sublet-match` bước 3 | `sublet_matches.score` luôn đi kèm `reasons` | enforce |
| R12 | Mọi tin ra ngoài là draft; chỉ người đổi `sent` | `sublet-draft`, `inbox-triage`, `viewing-coordinate`, `sublet-followup` | R01 metric | enforce |
| R13 | Mọi tin ra ngoài đọc `partner-voice` trước; ≤90 từ DM đầu, ≤40 follow-up; không nhắc AI | 4 skill trên có dòng "Đọc partner-voice trước" | grep body draft: không chứa "AI|agent|automation" | enforce |
| R14 | ≤10 DM offer/ngày; ≤2 follow-up/thread; ≤3 push/seeker/ngày | `sublet-draft` kiểm đếm; `sublet-followup` đếm; `push_count` | metric `outreach.dm_sent_today` ≤10; `outreach.followups_per_thread` ≤2 | enforce |
| R15 | Không thu tiền hộ, không giữ deposit, không chuyển địa chỉ chính xác qua bạn | `viewing-coordinate` "Không"; templates | audit tay templates | policy |
| R16 | Agent không gửi notification đi đâu; mọi thứ → `sublet_inbox` | mọi skill; không còn Telegram | grep repo "telegram" chỉ còn enum channel | enforce |
| R17 | Nguồn rule phân loại là `docs/intent-logic.md`; sửa xong chạy `--all` + test | `intent-analyze` header | `tests/score_intent.py` kind ≥98% | enforce |
| R18 | 1 subletter đăng nhiều group = 1 deal, 1 DM | `text_hash` + `canonical_id` (scan bước 5, analyze bước 11); view `deal_queue` lọc | metric `analyze.cross_posts_linked`; audit: không DM listing có canonical_id | enforce |
| R19 | Không backfill 2 group/ngày; không chạy khi scan cron bận | `sublet-backfill` "Không"; `ops_state backfill_<key>` | ops_state | enforce |
| R20 | Cron không chồng lên nhau (1 skill 1 instance) | `ops/run_skill.sh` flock | log "skip (locked)" | enforce |
| R21 | DB lỗi (RPC/HTTP) → thử lại 1 lần sau 5s, vẫn lỗi → dừng skill, `sublet_inbox(warning)`, không ghi nửa chừng | CLAUDE.md "Luôn luôn"; mọi skill | log | enforce |
| R22 | Agent không tự join group, không tự login | `onboarding` mục 4, 6; `sublet-groups` | `sublet_groups.joined` chỉ do người tick | enforce |
| R23 | Không nhận yêu cầu thu phí từ seeker (kể cả khi subletter đòi) — từ chối + cảnh báo | `partner-voice`; `inbox-triage` E-case | `sublet_inbox(warning)` | enforce |
| R24 | Secret không vào repo; key qua chat phải rotate | `.gitignore`; `~/.sublet-skills.env` chmod 600 | `git grep -i "service_role_key\|eyJ"` = 0 | enforce |

Quy trình sửa luật: sửa CLAUDE.md → cập nhật dòng ở đây → cập nhật skill enforce → thêm edge case vào `docs/edge-cases.md` nếu có → commit "rule: …".
