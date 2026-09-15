# Edge-case registry — mọi tình huống hệ thống phải xử lý, ở đâu, đã test chưa

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
| E12 | Post không có permalink đọc được | `source_url='feed:'||hash||date`; `notes='no_permalink'`; không DM cho đến khi có link | sublet-scan | — |
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

## Coverage
- Có test tự động: nhóm C (intent) — 100 case.
- Kiểm tay trong QA sau backfill: A, B (E10–E13), C (E42–E43).
- **Chưa có test**: D–I. Thêm dần: mỗi case gặp thật → ghi vào đây + `tests/ops_cases.md` (kịch bản + kết quả mong đợi).
