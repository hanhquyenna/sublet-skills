# tests/

- `intent_cases.json` — 100 post Facebook giả lập có nhãn (sinh bởi subagent theo docs/intent-logic.md, phân bố cố định: 45 offering / 33 seeking / 22 other).
- `intent_cases_blind.json` — cùng 100, không nhãn. Đưa cho classifier.
- `intent_predictions.json` — kết quả lần chạy 2026-09-15 (classifier chỉ đọc doc + blind).
- `score_intent.py` — chấm. `python3 tests/score_intent.py --show-errors`.

## Kết quả 2026-09-15 (doc v1, trước khi vá 5 lỗ)
kind 99% · subtype 99% · poster_type 100% · dead 100% · scam_bucket 96% · confidence 82% (toàn bộ lỗi là `other` chưa có rule) · fields 98–100%.
Sau khi vá doc (§3 agency/fragment, §5 seeking holes, §8 gộp scam, §10 other, §11 chuẩn hoá): chạy lại classifier mù để xác nhận.

## Cách chạy lại
1. Spawn agent A: sinh case theo doc (giữ phân bố), ghi 2 file.
2. Spawn agent B: chỉ đọc doc + blind, ghi predictions.
3. `python3 tests/score_intent.py --show-errors`. Mục tiêu: kind ≥98%, subtype ≥95%, agency 100%, scam-high không lọt.
