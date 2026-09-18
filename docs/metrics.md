# Metrics catalogue — success metric của từng workflow, lưu ở `sublet_metrics` (1 dòng/ngày/metric)

> **Active scope:** hiện đo raw capture/run progress của `sublet-scrape-14-groups`,
> data quality/behavior aggregates của `data-engineer`, insight snapshot của
> `analyze-insights` (hàng `insight_*` dưới đây, workflow `analyze`), và từ
> 2026-09-17 `analyzed_24h`/`offering_7d`/`seeking_7d`/`other_7d` của
> `intent-analyze`. `scam_high_rate`/`low_conf_rate`/`qa_kind_acc` **chưa có ý
> nghĩa** — `intent-analyze` phiên bản hiện tại để `scam_score` mặc định
> (chưa tính), nên `scam_high_rate` sẽ luôn đọc ra 0% (đừng đọc đó là "rule
> quá lỏng", đơn giản là chưa chạy); bật lại 3 metric này khi scam scoring
> được kích hoạt. Match, outreach và report bên dưới vẫn là historical/future
> reference — chưa có skill nào ghi chúng.

`sublet-report` tính và **insert** mỗi 18:00 (`day`, `workflow`, `metric`, `value`, `target`). Không tính lại từ đầu mỗi lần; xu hướng đọc từ bảng.

| workflow | metric | Công thức | Target Phase 0 | Skill tạo dữ liệu |
|---|---|---|---|---|
| know | groups_tier1 | count groups tier=1 | 5–8 | sublet-groups |
| know | groups_notif_on | count joined & notif_all_posts | = tier1+tier2 | onboarding |
| capture | posts_captured_24h | listings seen_at >24h | ≥10 (peak ≥25) | sublet-scan/email |
| capture | page_loads_24h | sum scan_runs.page_loads 24h | ≤350 (R03) | sublet-scan |
| capture | page_loads_per_run_max | max page_loads/run 24h | ≤4 (R02) | sublet-scan |
| capture | dedupe_ratio | listings có canonical_id / offering 7d | 0.2–0.5 (cross-post thật) | scan, analyze |
| capture | comments_captured_24h | raw public comments/replies trong `context_captured` 24h | theo page-load budget | sublet-scan |
| capture | profile_context_items_24h | raw public poster/commenter activity items 24h | theo page-load budget | sublet-scan |
| capture | groups_14d_complete | count group metrics có `posts_14d_complete=true` | theo backfill plan | sublet-backfill |
| capture | posts_14d_verified | sum `posts_14d_count` chỉ ở group metrics complete | theo backfill plan | sublet-backfill |
| capture | stops_24h | runs stopped_reason in (checkpoint, volume) | 0 | sublet-scan |
| analyze | analyzed_24h | listings analyzed_at >24h | = captured | intent-analyze |
| analyze | offering_7d / seeking_7d / other_7d | count by kind | — (đo thị trường) | intent-analyze |
| analyze | scam_high_rate | scam≥60 / offering 7d | 10–30% (0% = rule quá lỏng) | intent-analyze |
| analyze | low_conf_rate | confidence=low / all 7d | ≤25% | intent-analyze |
| analyze | qa_kind_acc | đúng/10 trong QA tuần | ≥95% | intent-analyze QA |
| analyze | insight_listings_total | listings có event `insight_reviewed` | tăng dần theo capture | analyze-insights |
| analyze | insight_new_this_run | listings mới review trong 1 run | — | analyze-insights |
| analyze | insight_offering_like / insight_seeking_like / insight_other_like | count theo `insight_kind_guess` (heuristic, không phải `kind` chính thức) | — (đo thị trường thô) | analyze-insights |
| analyze | insight_duplicate_clusters / insight_duplicate_listings | số cụm trùng lặp / tổng listing bị trùng (text_hash + near-dup) | dedupe_ratio tham khảo trước khi bật canonical_id chính thức | analyze-insights |
| analyze | insight_risk_flagged | listings có ≥1 `insight_risk_flags` | theo dõi xu hướng, không phải scam_score | analyze-insights |
| analyze | insight_unique_posters | distinct poster_name đã review | — | analyze-insights |
| analyze | insight_queue_remaining | listings chưa có `insight_reviewed` | 0 sau khi run xong (không tính listing mới capture sau đó) | analyze-insights |
| data | rows_profiled | rows được profile trong dataset/window | báo cáo đủ phạm vi đã chọn | data-engineer |
| data | rows_missing_required_evidence | rows thiếu `source_url` hoặc `seen_at` | 0 | data-engineer |
| data | provenance_complete_rate | events có contract/source/run/page metadata cần thiết / events audited | 100% cho event mới | data-engineer |
| data | duplicate_source_rows | rows trùng `source_url` hoặc natural key | 0 | data-engineer |
| data | unknown_field_rate | field values `unknown`/null trên denominator có thể quan sát | báo cùng denominator, không target giả | data-engineer |
| data | behavior_posts_with_comments | captured posts có ≥1 public comment / captured posts có comment count quan sát được | theo nguồn và window | data-engineer |
| data | comments_per_observed_post | public comments captured / posts có comment data | theo nguồn và window | data-engineer |
| data | lifecycle_reply_rate | confirmed replies / contacted or prompted entities | đo khi có first-party denominator | data-engineer |
| data | lifecycle_consent_rate | confirmed consent / entities asked for consent | đo khi có first-party denominator | data-engineer |
| data | viewing_show_rate | confirmed attended / scheduled viewings | theo dõi funnel | data-engineer |
| data | accepted_to_move_in_rate | confirmed moved-in / confirmed accepted | theo dõi funnel | data-engineer |
| data | fee_collection_rate | confirmed paid / fees due and trackable | theo dõi funnel | data-engineer |
| demand | seekers_active | v_seekers_active | ≥50 trước khi hứa 72h; ≥100 → 24h | seeker-intake |
| demand | seekers_new_7d | created_at >7d | ≥15 | seeker-intake |
| demand | consent_rate | consent true / all form | ≥80% | seeker-intake |
| match | listings_with_3plus | offering 7d có ≥3 match ≥60 | ≥50% of deal_queue | sublet-match |
| match | avg_top_score | avg max(score) per listing 7d | ≥70 | sublet-match |
| outreach | dm_sent_24h | `outreach_messages.status='sent'` in last 24h | ≤10 agent-sent (R14) | outreach-prep |
| outreach | dm_yes_rate_7d | listings accepted / contacted 7d | ≥30% (<20% → đổi offer) | inbox-triage |
| outreach | yes_rate_by_template | như trên, group by template | so sánh A/B | inbox-triage |
| outreach | draft_backlog | messages status=draft >2h | ≤5 | sublet-followup |
| outreach | sent_by_agent | `events` where actor='agent' and event='outreach_dm_sent' | audit volume; must reconcile 1:1 with agent-sent message rows | outreach-prep |
| outreach | agent_send_audit_mismatch | agent-send event without matching sent message, or sent agent message without event | **0** | outreach-prep |
| inbox | replies_24h | messages direction=in 24h | — | inbox-triage |
| inbox | triage_unclear_rate | "hỏi bạn" / replies | ≤15% | inbox-triage |
| viewing | accepted_to_3v_72h | listings accepted có 3 viewing confirmed ≤72h / accepted | ≥50% | viewing-coordinate |
| viewing | showup_rate | showed / (showed+no_show) | ≥70% | viewing-coordinate |
| viewing | time_to_first_viewing_h | median accepted_at → first scheduled_at | ≤48h | viewing-coordinate |
| fee | fees_sent / fees_paid | count | — | viewing-coordinate |
| fee | collection_rate | paid / sent (sent >7 ngày) | ≥70% (<70% → đổi trigger) | sublet-followup |
| fee | revenue_eur_30d | sum paid | Phase 0 mục tiêu ≥5 deal | — |
| fee | listing_to_fill_days | median seen_at → filled_at | ≤10 | — |
| ops | token_cost_eur_24h | sum events.payload.tokens × giá | ≤€1 | mọi skill (J3 #5) |
| ops | cron_runs_24h / cron_skips_24h | từ ops/logs | runs ≥40, skips có lý do | run_skill |
| ops | jobs_done_24h / jobs_failed_24h | sublet_jobs finished 24h by status | failed ≤2 | sublet-worker |
| ops | job_step_seconds_p50 | median finished−started | ≤300 | sublet-worker |
| ops | backup_ok | file hôm nay tồn tại | 1 | backup.sh |

## Quyết định tự động từ metrics (ghi trong PLAN §I)
- `dm_yes_rate_7d` <20% sau ≥50 DM → đổi offer (A/B template).
- `collection_rate` <70% sau ≥10 fee → `fee_trigger` → `three_viewings_72h`.
- `seekers_active` ≥100 → promise 72h → 24h.
- `stops_24h` ≥1 → cadence ×2, 7 ngày chỉ email.
- `scam_high_rate` = 0 trong 7 ngày → rule scam quá lỏng, review §8.
