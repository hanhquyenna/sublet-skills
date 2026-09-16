#!/usr/bin/env python3
"""extract_cards.py — tách card thô từ output read_page (accessibility tree)
mà KHÔNG cần LLM tự đọc raw text để tìm ranh giới bài.

Vấn đề nó giải quyết: trong sublet-scrape-14-groups, bước "Feed pass" yêu cầu
"dùng cấu trúc DOM/a11y... để tách từng card... trước khi chuyển text sang bất
kỳ bước xử lý nào; không dùng LLM để phát hiện ranh giới card" (xem SKILL.md).
Trước khi có script này, agent phải tự đọc toàn bộ output read_page (thường
30-50K ký tự mỗi lần) để mắt tìm bài — tốn token nhất trong toàn bộ pipeline
(xem PLAN.md mục J1, J3 #1).

Lịch sử: bản đầu tiên của script này dùng role `article`/`dialog` làm ranh
giới card. Test trên dữ liệu thật (2026-09-16) cho thấy cách đó SAI: Facebook
không luôn bọc post bằng `article` — có run thì có (dialog xem 1 post), có run
thì không (feed nhiều post liền, chỉ COMMENT mới có role `article`). Bản đó bỏ
sót toàn bộ post thật, chỉ bắt được comment. Bản hiện tại dùng marker đáng tin
cậy hơn: mỗi post luôn có đúng 1 nút
`button "Hành động đối với bài viết này của <Poster>"` — quan sát thấy marker
này xuất hiện ổn định ở cả 2 kiểu layout đã thấy. Card = từ marker này tới
marker kế tiếp (hoặc article bình luận kế tiếp).

Cách dùng:
    python3 scripts/extract_cards.py < read_page_output.txt
    python3 scripts/extract_cards.py path/to/read_page_output.txt
    (hoặc import extract_cards(text) từ module khác)

QUAN TRỌNG — đây chỉ là công cụ hỗ trợ tốc độ, KHÔNG thay thế luật capture:
- Output là gợi ý cấu trúc (best-effort parse), không phải link evidence đã
  xác minh. Agent vẫn phải theo đúng SKILL.md: lấy direct permalink hoặc dùng
  Chia sẻ→Sao chép liên kết trong panel thật, không tự suy ra post_id/URL chỉ
  từ những gì script này đoán được.
- Khi `post_id` là null (Facebook không lộ permalink ở tầng feed cho post đó),
  script trả về `needs_detail_gate=true` — đúng tinh thần "Detail gate" trong
  SKILL.md: agent phải mở post đó riêng hoặc dùng Share→Copy link, không được
  bỏ qua card chỉ vì thiếu post_id ở bước feed pass.
- Không tự ý ghi DB, không tự gọi bất cứ card nào là "verified". Facebook đổi
  cấu trúc DOM theo view/thời điểm — card có `confidence='low'` vẫn cần agent
  tự đọc kỹ như trước.
- Script chạy hoàn toàn cục bộ trên text đã có sẵn (do read_page/get_page_text
  đã lấy về), không gọi thêm bất kỳ request nào tới Facebook.
"""

import json
import re
import sys
import hashlib
from dataclasses import dataclass, field, asdict
from typing import Optional

POST_MARKER_RE = re.compile(
    r'button\s+"Hành động đối với bài viết này của (.+?)"\s*\[ref_(\d+)\]'
)
COMMENT_BLOCK_START_RE = re.compile(
    r'^\s*article\s+"Bình luận dưới tên (.+?) (?:vào|lúc) '
)
GROUP_LINK_RE = re.compile(
    r'"([^"]+)"[^\n]*href="[^"]*(https://www\.facebook\.com/groups/\d+/)"'
)
POST_PERMALINK_RE = re.compile(
    r'link\s+"([^"]*)"[^\n]*href="([^"]*(?:'
    r'multi_permalinks=(\d+)'
    r'|/groups/\d+/posts/(\d+)'
    r'|/groups/\d+/permalink/(\d+)'
    r')[^"]*)"'
)
COMMENT_PARENT_RE = re.compile(
    r'href="[^"]*/groups/\d+/posts/(\d+)/\?comment_id=(\d+)'
)
REACTION_RE = re.compile(r'"Thích:\s*([\d.,]+)\s*người"')
COMMENT_COUNT_RE = re.compile(r'"([\d.,]+)\s*bình luận"')
SHARE_COUNT_RE = re.compile(r'"([\d.,]+)\s*lượt chia sẻ"')
PHOTO_MEDIA_RE = re.compile(r'href="(https://www\.facebook\.com/photo[^"]*)"')

UI_NOISE = {
    'tham gia', 'thích', 'bình luận', 'chia sẻ', 'phù hợp nhất', 'mới nhất',
    'đăng nhập', 'bạn quên tài khoản ư', 'facebook', 'quay lại trang trước',
    'thoát chế độ gõ trước', 'tìm kiếm trên facebook', 'trang chủ',
    'thước phim', 'marketplace', 'nhóm', 'trò chơi', 'messenger', 'thông báo',
    'trang cá nhân của bạn', 'đã chia sẻ với nhóm công khai', 'bài viết mới',
    'đã tham gia', 'mời', 'nhớ mật khẩu', 'đóng', 'lúc khác', 'xem thêm',
    'ẩn hoặc báo cáo bình luận này', 'trả lời',
}


@dataclass
class Card:
    poster_ref: str
    poster_name: str
    group_name: Optional[str] = None
    group_url: Optional[str] = None
    post_id: Optional[str] = None
    link_resolution_hint: Optional[str] = None  # which signal matched, NOT verified evidence
    timestamp_label: Optional[str] = None
    post_text_guess: Optional[str] = None
    reaction_count: Optional[int] = None
    comment_count: Optional[int] = None
    share_count: Optional[int] = None
    media_urls: list = field(default_factory=list)
    comment_parent_ids_seen: list = field(default_factory=list)
    missing_fields: list = field(default_factory=list)
    needs_detail_gate: bool = False
    confidence: str = 'low'
    card_fingerprint: Optional[str] = None
    raw_block_chars: int = 0

    def finalize(self):
        # group_url/group_name are NOT counted as missing: the capture loop
        # already knows which single group it opened (URL known from the
        # scrape target), so per-card group extraction is a bonus signal,
        # not a requirement, for confidence purposes.
        missing = []
        if not self.post_id:
            missing.append('post_id')
        if not self.post_text_guess:
            missing.append('post_text_guess')
        self.missing_fields = missing
        self.needs_detail_gate = self.post_id is None
        if not missing:
            self.confidence = 'high'
        elif len(missing) <= 1 and self.post_id:
            self.confidence = 'medium'
        else:
            self.confidence = 'low'
        basis = f"{self.group_name}|{self.poster_name}|{self.timestamp_label}|{(self.post_text_guess or '')[:200]}"
        self.card_fingerprint = hashlib.sha256(basis.encode('utf-8', 'ignore')).hexdigest()


def _parse_int(s: Optional[str]) -> Optional[int]:
    if not s:
        return None
    s = s.replace('.', '').replace(',', '')
    try:
        return int(s)
    except ValueError:
        return None


def _clean_quoted(line: str):
    m = re.search(r'"((?:[^"\\]|\\.)*)"', line)
    if not m:
        return None
    return m.group(1).replace('\\"', '"')


def extract_cards(text: str, lookback_lines: int = 20):
    """Split on the 'Hành động đối với bài viết này của <poster>' marker,
    which is present once per post in every layout observed so far. A card's
    forward content runs until the next such marker or the next comment
    block start (whichever comes first); backward context (for group name)
    is looked up within a bounded window before the marker, to avoid pulling
    in an unrelated earlier post's group heading."""
    lines = text.splitlines()
    markers = []
    comment_starts = []
    for i, line in enumerate(lines):
        m = POST_MARKER_RE.search(line)
        if m:
            markers.append((i, m.group(1).strip(), m.group(2)))
        elif COMMENT_BLOCK_START_RE.match(line):
            comment_starts.append(i)

    cards = []
    for idx, (marker_i, poster_name, poster_ref) in enumerate(markers):
        # forward bound: next post marker, or next comment block, whichever first
        next_marker_i = markers[idx + 1][0] if idx + 1 < len(markers) else len(lines)
        next_comment_i = min((c for c in comment_starts if c > marker_i), default=len(lines))
        end_i = min(next_marker_i, next_comment_i)

        # backward bound for group-name lookup only: previous marker OR the
        # nearest preceding comment block (whichever is closer), so we never
        # pull context from a DIFFERENT post's comment thread. Capped by
        # lookback_lines so we don't walk arbitrarily far back either.
        prev_marker_i = markers[idx - 1][0] if idx > 0 else -1
        prev_comment_i = max((c for c in comment_starts if c < marker_i), default=-1)
        prev_boundary_i = max(prev_marker_i, prev_comment_i)
        start_i = max(marker_i - lookback_lines, prev_boundary_i + 1, 0)

        block_lines = lines[start_i:marker_i]
        block_text = '\n'.join(block_lines)  # backward-only: group-name lookup
        forward_text = '\n'.join(lines[marker_i:end_i])

        card = Card(poster_ref=poster_ref, poster_name=poster_name,
                    raw_block_chars=len(block_text))

        m = GROUP_LINK_RE.search(block_text)
        if m:
            card.group_name = m.group(1).strip()
            card.group_url = m.group(2).strip()

        m = POST_PERMALINK_RE.search(forward_text)
        if m and 'comment_id=' not in m.group(2):
            label, _href, *id_groups = m.groups()
            post_id = next((g for g in id_groups if g), None)
            if post_id:
                card.post_id = post_id
                card.link_resolution_hint = 'a11y_permalink_or_multi_permalinks'
            if label:
                card.timestamp_label = label.strip()

        if not card.post_id:
            # look at the immediately-following comment block(s) for this post,
            # up to the NEXT post marker — a comment's parent post id is valid
            # link evidence per SKILL.md.
            following_text = '\n'.join(lines[marker_i:next_marker_i])
            cm = COMMENT_PARENT_RE.search(following_text)
            if cm:
                card.post_id = cm.group(1)
                card.comment_parent_ids_seen.append(cm.group(1))
                card.link_resolution_hint = 'comment_parent_path'

        m = REACTION_RE.search(forward_text)
        if m:
            card.reaction_count = _parse_int(m.group(1))
        m = COMMENT_COUNT_RE.search(forward_text)
        if m:
            card.comment_count = _parse_int(m.group(1))
        m = SHARE_COUNT_RE.search(forward_text)
        if m:
            card.share_count = _parse_int(m.group(1))

        for pm in PHOTO_MEDIA_RE.finditer(forward_text):
            if pm.group(1) not in card.media_urls:
                card.media_urls.append(pm.group(1))

        # Post text guess: longest quoted `generic`/`heading` string strictly
        # after the marker line and before end_i, excluding UI chrome and the
        # poster's own name.
        best = None
        for line in lines[marker_i + 1:end_i]:
            if 'generic "' not in line and 'heading "' not in line:
                continue
            q = _clean_quoted(line)
            if not q:
                continue
            ql = q.strip().lower()
            if ql in UI_NOISE:
                continue
            if q.strip() == poster_name:
                continue
            if card.group_name and q.strip() == card.group_name:
                continue
            if len(q) < 15:
                continue
            if best is None or len(q) > len(best):
                best = q
        card.post_text_guess = best

        card.finalize()
        cards.append(card)
    return cards


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], 'r', encoding='utf-8') as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    cards = extract_cards(text)
    out = [asdict(c) for c in cards]
    print(json.dumps({
        'extractor_contract_version': 2,
        'note': (
            'Best-effort structural parse of read_page output, split on the '
            '"Hanh dong doi voi bai viet nay cua <poster>" action-button '
            'marker (stable across both article-wrapped and flat feed '
            'layouts observed so far). NOT verified link evidence. Agent '
            'must still follow SKILL.md capture rules before writing any '
            'listing/context_captured event. needs_detail_gate=true means '
            'the feed pass could not find a post_id; open the post or use '
            'Share->Copy link per SKILL.md detail-gate rule.'
        ),
        'card_count': len(out),
        'cards': out,
    }, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
