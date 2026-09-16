# Edge-case registry — mọi tình huống hệ thống phải xử lý, ở đâu, đã test chưa

> **Active scope:** `information`, `sublet-scrape-14-groups`, `validate-permalink`,
> `data-engineer` và `analyze-insights` (mục J/K) được gọi. Các skill name cũ
> trong bảng A–I là historical reference.

Mã E##. Skill tham chiếu trong khối Spec. "Test" = id trong `tests/intent_cases.json` (c###) hoặc `manual` (kiểm tay trong QA sau backfill) hoặc `—` (chưa có, cần thêm).

## A. KNOW — group
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E01 | Group cấm sublet trong tên/rules | `allows_sublet=no` → tier 3, không đọc | sublet-groups | seed |
| E02 | Group cấm agency/link dịch vụ | `allows_agencies=no`; không bao giờ post link ở đó (bạn) | sublet-groups, partner-voice | seed |
| E03 | Join pending nhiều ngày | `group_metrics.join_status=pending`; onboarding nhắc lại, không request lại | onboarding | manual |
| E04 | Group đổi tên/URL | match theo URL; tên mới → update `name`, giữ key | sublet-groups | — |
| E05 | Group hỏi câu khi join | `membership_questions` lưu để bạn trả lời tay | sublet-groups (Codex) | manual |

## B. CAPTURE — scan/email/backfill
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E10 | Checkpoint / captcha / login giữa chu kỳ | dừng ngay, `stopped_reason`, `sublet_inbox(stop)`, `scan_paused_until=+24h`; run_skill gate | sublet-scan, run_skill | manual |
| E11 | Feed hiện lại post cũ (cache) | cursor + 3 URL đã biết liên tiếp → dừng; `source_url` unique | sublet-scan | — |
| E12 | Post không có permalink đọc được | không insert listing; giữ `unresolved_cards` + raw observation trong run cursor, không đoán URL và không DM | sublet-scan, sublet-backfill | manual |
| E13 | Post chỉ có ảnh + 1 emoji | capture; analyze → `other`/low, `needs_full_read`; scan mở permalink ≤2/chu kỳ | sublet-scan, intent-analyze | — |
| E14 | Post rất dài (>2000 ký tự) | capture đầy đủ `raw_text`; analyze đọc 1500 ký tự đầu + 300 cuối (EDIT: found thường ở cuối) | intent-analyze | — |
| E15 | Cùng text đăng 5 group | `text_hash` trùng → `canonical_id`, 1 DM | sublet-scan | — |
| E16 | Cùng listing, text sửa nhẹ mỗi group | fingerprint poster+rent+from ±1d → `canonical_id` | intent-analyze | — |
| E17 | Email digest gộp không có link | `source_url='email:'||msgid||'#n'`, `digest_no_link` | sublet-email | — |
| E18 | Email snippet bị cắt | `needs_full_read` → scan mở permalink | sublet-email | — |
| E19 | Facebook đổi format email | 2 regex trong `gmail_pull.py`; lỗi parse → `sublet_inbox(warning)` | sublet-email | — |
| E20 | Laptop ngủ giữa run | run có `finished_at=null` >30' → run sau đóng nó `stopped_reason='abandoned'`; capture idempotent nhờ `source_url` unique | sublet-scan | — |
| E21 | 2 cron chồng nhau | `flock` trong run_skill.sh → instance 2 skip | run_skill | — |
| E22 | Vượt 350 page load/ngày | scan dừng, `stopped_reason='volume'` | sublet-scan | — |
| E23 | Backfill chạy lại cùng group | `ops_state backfill_<key>` có → dừng | sublet-backfill | — |
| E24 | Group không cho sort chronological | fallback: sort mặc định, dừng khi 20 post liên tiếp cũ hơn `days` | sublet-backfill | — |
| E25 | Profile/commenter không public hoặc không có permalink | lưu phần đang hiển thị với `visibility='partial'`; không đoán danh tính, không retry vô hạn | sublet-scan | manual |
| E26 | Comment pagination vô hạn hoặc Facebook yêu cầu mở rộng | dừng ở 100 comment/reply/post hoặc page-load budget; giữ `context_captured` với `truncated=true` | sublet-scan | manual |
| E27 | Public profile có lịch sử quá dài hoặc nội dung nhạy cảm | chỉ lưu tối đa 10 post/30 ngày; không lưu friend list, album, ảnh, demographic inference hay contact field | sublet-scan | manual |
| E28 | Resume group có timestamp null hoặc run bị dừng | ưu tiên run cursor + verified source_url; `seen_at` chỉ là thời điểm quan sát, không dùng làm post time; không bắt đầu lại từ đầu | sublet-scrape-14-groups, sublet-backfill | manual |
| E29 | Batch 14 group có group chưa complete hoặc bị block | giữ `current_group`, ghi blocked reason, không chuyển group/đóng batch như complete | sublet-scrape-14-groups | manual |
| E30 | Poster hiển thị anonymous/không có profile URL | flag `anonymous_poster`; giữ nguyên label; không đoán danh tính; bắt buộc usable post permalink đã validate trước khi resolved/access-ready, match hoặc outreach | sublet-scrape-14-groups, validate-permalink, analyze-insights | manual |
| E31 | Seeker/offering không khai báo khu vực hoặc ngân sách | ghi `unknown`; không coi là mismatch, không trừ điểm và không loại; chỉ loại khi có conflict rõ ràng; `seen_at` chỉ ghi freshness | analyze-insights, sublet-match | manual |

## C. ANALYZE — intent (chi tiết rule ở docs/intent-logic.md)
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E30 | "Looking for someone to take my room" | đối tượng = người → offering | intent-analyze | 21 case |
| E31 | Agency đăng listing cụ thể | offering + `poster_type=agency`, không DM | intent-analyze | c-agency ×5 |
| E32 | Fragment không rõ có/cần | other, low, needs_full_read | intent-analyze | c038 |
| E33 | "EDIT: FOUND" | `status=dead`, không tạo seeker | intent-analyze | 7 case |
| E34 | Đăng hộ bạn | `poster_type=proxy` | intent-analyze | 6 case |
| E35 | Tiền trước khi gặp + nhắc registration | sàn scam 60, không trừ điểm | intent-analyze | c054 |
| E36 | Seeker đề nghị trả trước (WU) | seeking, scam max 59, vẫn tạo seeker + flag | intent-analyze | c034 |
| E37 | Giá/tuần, "end of Jan", "Oct–Jan", "ASAP" | ×4.33 làm tròn; cuối tháng; 1→cuối; ngày post | intent-analyze | 13 case |
| E38 | Năm chuyển giao (post 15/12 nói "from 5 Jan") | năm sau | intent-analyze | — |
| E39 | NL số "1.200,-" / "850,-" | 1200 / 850 | intent-analyze | c-nl |
| E40 | Poster constraints (female only…) | lưu nguyên văn, không chấm | intent-analyze, match | 31 case |
| E41 | Swap / short_stay / long_term | subtype đúng, deal_score −50 | intent-analyze | 10 case |
| E42 | Listing đã dead, poster đăng lại sau 2 tuần | listing mới (source_url khác), `notes='reposted'`, không canonical về bản dead | intent-analyze | — |
| E43 | Comment "still available?" của người khác | không phải post → bỏ qua; nếu poster trả lời "yes" trong feed → −10 scam | sublet-scan | — |
| E44 | QA sai ≥2/10 | sửa doc §12, `--all`, so số trước/sau | intent-analyze | tests/ |

## D. DEMAND — seeker
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E50 | Cùng người điền form 3 lần | unique lower(contact) → upsert | seeker-intake | — |
| E51 | Không tick consent nhưng sau đó reply YES cho push | reply = consent → `contact_consent=true`, event `consent_by_reply` | inbox-triage | — |
| E52 | Seeker đổi ngày/ngân sách | update, match cũ `proposed` tính lại | seeker-intake, sublet-match | — |
| E53 | move_in đã qua >14 ngày | followup đề xuất `inactive` | sublet-followup | — |
| E54 | Seeker từ post FB (không contact) | lưu để đo pool, `no_consent` flag, không push | intent-analyze, sublet-match | c-seek |
| E55 | Couple / nhóm | `people≥2`; match veto nếu `max_people` nhỏ hơn | seeker-intake, match | c-group ×8 |

## E. MATCH
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E60 | Listing scam ≥60 | không tạo match | sublet-match | match.py veto |
| E61 | Listing có canonical_id | không match (bản gốc đã match) | sublet-match, view | — |
| E62 | Seeker cần registration, listing unknown | +3, reason "ask" | match.py | smoke |
| E63 | Pets / no couples / students only | flag từ `poster_constraints`, không veto cứng | match.py | smoke |
| E64 | Không có seeker nào ≥50 | listing giữ `new`; draft dùng `offer_triage` không phải `offer_pool` | sublet-draft | — |

## F. OUTREACH — draft
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E70 | Đã 10 DM hôm nay | cảnh báo, không draft thêm | sublet-draft | — |
| E71 | Listing >7 ngày | deal_score −20; nếu vẫn ≥60 thì draft nhắc "still looking?" | sublet-draft | — |
| E72 | Poster là proxy | DM hỏi "bạn hay bạn của bạn quyết?" | sublet-draft | — |
| E73 | Post bằng NL | template NL | sublet-draft | — |
| E74 | Seeker push_count hôm nay ≥3 | bỏ qua seeker đó hôm nay | sublet-draft | — |
| E75 | Chưa có `seeker_form.url` | offer dùng "forward me the replies" | sublet-draft | — |

## G. INBOX — reply
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E80 | "ok" nhưng từ người khác tên poster | hỏi bạn, không tự gắn | inbox-triage | — |
| E81 | Subletter mặc cả fee | 2 phương án, bạn chọn | inbox-triage | — |
| E82 | Subletter đòi số seeker trước | không gửi; scam +40; warning | inbox-triage | — |
| E83 | Subletter muốn thu phí seeker | từ chối lịch sự (R23), warning | inbox-triage, partner-voice | — |
| E84 | "Found someone" sau khi đã xếp viewing | listing `filled` (không phải qua bạn) → không fee; huỷ viewing, báo seeker | inbox-triage, viewing-coordinate | — |
| E85 | Seeker "YES" nhưng listing đã filled | draft "đã có người, mình gửi cái khác" | inbox-triage | — |
| E86 | Reply không liên quan sublet | bỏ qua, không lưu | inbox-triage | — |
| E87 | 2 subletter cùng tên hiển thị | hỏi bạn | inbox-triage | — |

## H. VIEWING / FEE
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E90 | <3 YES sau 24h | push thêm 10 | viewing-coordinate | — |
| E91 | No-show | `no_show`, seeker notes; 2 lần → `inactive` | viewing-coordinate | — |
| E92 | Subletter chọn người ngoài 3 người của bạn | không fee (không phải người bạn giới thiệu); hỏi có muốn thêm người không | viewing-coordinate | — |
| E93 | Move-in nhưng subletter không trả lời Tikkie | nhắc 1 lần sau 3 ngày; 7 ngày → `disputed`; không nhắc nữa | sublet-followup | — |
| E94 | Seeker báo move-in, subletter im | ghi `signed` với nguồn = seeker; fee sent | viewing-coordinate | — |
| E95 | Dọn vào rồi dọn ra sau 3 ngày | fee vẫn tính (đã move-in); ghi notes | viewing-coordinate | — |

## I. OPS
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E100 | RPC/HTTP lỗi | retry 1 lần sau 5s; vẫn lỗi → dừng, `sublet_inbox(warning)` (R21) | mọi skill | — |
| E101 | Service key bị rotate | db.py lỗi 401 → inbox warning "cập nhật ~/.sublet-skills.env" | db.py | — |
| E102 | Đổi máy | onboarding chạy lại chỉ mục ⬜ | onboarding | — |
| E103 | DST (cuối tháng 10 / cuối tháng 3) | mọi giờ tính bằng `TZ=Europe/Amsterdam`, không hardcode UTC | run_skill, skills | — |
| E104 | Backup fail | log; followup hôm sau hiện "backup thiếu" | backup.sh, followup | — |
| E105 | 2 agent (Claude Code + Codex) sửa cùng file | commit nhỏ, pull --rebase trước khi sửa; file `information` chỉ Codex sửa | quy ước | — |
| E106 | Job `running` quá 20' (prompt chết giữa chừng) | worker dọn: → queued, attempts+1, giữ progress; ≥3 → failed + warning | sublet-worker | — |
| E107 | 1 prompt không đủ cho 1 group backfill | chunk ≤6'/≤60 post, progress.last_post_at, nối qua nhiều tick | sublet-backfill, worker | — |
| E108 | Hàng đợi nhiều việc, page-load budget hết | job browser → next_run_at = mai 08:00; job không browser vẫn chạy | sublet-worker | — |
| E109 | 92 group cần verify | 5 group/step, xen kẽ, không bao giờ 1 prompt | sublet-groups verify | — |

## J. ANALYZE-INSIGHTS (active, đọc-only trên DB)
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E110 | Listing đã có event `insight_reviewed` | bỏ qua, không đọc lại `raw_text`; chỉ tính lại aggregate (SQL, không tốn LLM) | analyze-insights | manual |
| E111 | Agent bị ngắt giữa lúc xử lý 1 listing (chưa ghi event) | listing vẫn nằm trong `not exists insight_reviewed`, xử lý lại an toàn lần sau — idempotent | analyze-insights | manual |
| E112 | 1 bài bị capture 2 lần qua 2 `source_url` khác nhau (permalink + share URL) | phát hiện qua `text_hash` hoặc near-dup cùng poster; đánh `repost_same_poster`/`duplicate_of`, không coi là 2 bài thật | analyze-insights | manual |
| E113 | 2 poster khác nhau đăng y hệt cùng 1 đoạn text quảng cáo | `risk_flag='duplicate_across_posters'`, không gộp `duplicate_of` (2 identity khác nhau) | analyze-insights | manual |
| E114 | `raw_text` rỗng hoặc chỉ có emoji/link ảnh | `insight_kind_guess='other_like'`, không đoán thêm | analyze-insights | manual |
| E115 | Kien yêu cầu rescan (raw_text được cập nhật, hoặc muốn phân tích lại) | thêm event `insight_reviewed` mới, không xoá/sửa event cũ (append-only); chỉ xảy ra khi có yêu cầu rõ, không tự động | analyze-insights | manual |
| E116 | Hàng đợi rỗng khi gọi skill | không ghi `sublet_inbox` mới (tránh spam); báo Kien số liệu cũ trong chat, không tự chạy lại phân tích | analyze-insights | manual |
| E117 | Report tổng hợp lớn bất thường (corpus rất lớn) | giữ toàn bộ breakdown số đếm; chỉ liệt kê chi tiết top cụm trùng lặp/risk-flag lớn nhất, trỏ sang `sublet_events` cho phần còn lại thay vì dump hết vào `sublet_inbox.body` | analyze-insights | — |

## K. DATA-ENGINEER (active, DB-only)
| # | Tình huống | Xử lý | Skill | Test |
|---|---|---|---|---|
| E120 | Raw row thiếu `source_url`/`seen_at` hoặc event thiếu provenance | giữ row ở trạng thái incomplete/unknown, báo audit; không bulk-mark verified và không claim complete | data-engineer | manual |
| E121 | Retry làm trùng listing/event | dedupe theo unique source/entity-event-source/text fingerprint; upsert idempotent, giữ event history | data-engineer | manual |
| E122 | Missing budget/location/date/requirements | giữ `NULL`/`unknown`/`[]`; không biến thành zero/no/mismatch và không loại candidate chỉ vì thiếu | data-engineer, analyze-insights | manual |
| E123 | Một actor có nhiều listing hoặc display name trùng | chỉ merge khi public identity rõ và không mâu thuẫn; nếu không thì giữ entity riêng, không tạo person profile suy đoán | data-engineer | manual |
| E124 | Actor có cả bài offering và seeking | `offer_or_need='both'` chỉ khi cả hai hướng có evidence; field nào không có evidence vẫn unknown | data-engineer | manual |
| E125 | Public comment/reaction bị hiểu thành conversion | lưu như observed behavior; không suy ra intent, consent, reply hay rejection nếu chưa có evidence first-party | data-engineer | manual |
| E126 | Hai event có thời điểm khác nhau | tách `occurred_at`, `observed_at`, `created_at`; không dùng `seen_at` làm move-in/start date | data-engineer | manual |
| E127 | Thay đổi heuristic matching | full recompute `sublet_insight_matches`, ghi run/provenance và giữ event cũ; không sửa lẻ score/reasons | data-engineer, analyze-insights | manual |

## Coverage
- Có test tự động: nhóm C (intent) — 100 case.
- Kiểm tay trong QA sau backfill: A, B (E10–E13), C (E42–E43).
- **Chưa có test**: D–I, J (E110–E117, mới thêm 2026-09-16). Thêm dần: mỗi case gặp thật → ghi vào đây + `tests/ops_cases.md` (kịch bản + kết quả mong đợi).
