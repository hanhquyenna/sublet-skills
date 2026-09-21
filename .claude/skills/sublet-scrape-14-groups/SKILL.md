---
name: sublet-scrape-14-groups
description: "Scrape joined Facebook groups through the visible browser, resume from Supabase state, checkpoint each batch, and expose progress in dashboardkien_group."
---

# sublet-scrape-14-groups

Automation button: runs start-to-finish from the database alone, no briefing
from Kien. Every decision — where to resume, which group is next, when a
group is done — comes from `dashboardkien_group`, not conversation memory.

## Project and control surface

Supabase project `cteunhuxrghpozwbnehh`. Control view: `public.dashboardkien_group`.
Tables: `groups`, `group_metrics`, `posts`, `posters`, `events`, `scan_runs`,
`ops_state`. These are fixed facts, not something to rediscover each run.

If Supabase MCP isn't connected (or `scripts/db.py`'s RPC `sublet_exec`
fails), stop and ask Kien for the missing secret directly — that's allowed.
Not allowed: guessing a different project, printing a secret, or scraping
without a working DB connection (capture with no DB write is just data loss).

Capture and checkpoint only. No intent classification, link validation, or
outreach.

## Why the resume logic works this way

`dashboardkien_group` is a live view (recomputed every query), so the resume
decision below is always safe to re-derive from scratch. `recovery_required`
exists because a group's capture can be left broken (interrupted run, old
pre-contract capture rows, posts never linked to a poster) — those posts are
silently missing from `dashboardkien_outreach`, no error, just gone. Repair
always precedes starting a new group so this backlog doesn't grow unbounded.

`clean_for_outreach` needs zero capture gaps (this skill) **and** zero
unvalidated links (`validate-permalink`) **and** zero missing classification
(`intent-analyze`) on the same group — a clean scrape pass can still leave a
group `needs_recovery` because of the other two, and that's correct. Report
it as "capture-complete, waiting on validate-permalink/intent-analyze," not
as a stuck scrape. **This column is a data-hygiene signal only, not an
outreach precondition** (2026-09-21: `dashboardkien_outreach` no longer
requires it — see `docs/dashboard-source-of-truth.md`). A specific post can
already be a valid outreach candidate while its group still shows
`needs_recovery`, as long as that post itself is validated and classified.

`dashboardkien_outreach` only ever considers posts from the last 7 days
(`window_days`) — a post from 2 weeks ago can never become an outreach
candidate no matter how complete its data is. That's why chasing old,
pre-2026-09-17 broken records was pointless work: fixing them couldn't have
produced a single outreach candidate. Fresh capture is the only thing that
matters going forward — get it complete the first time (full raw text,
poster identity, link evidence) rather than relying on a later repair pass.

## Automatic resume contract

At the start of every run, decide in this order (don't skip ahead while an
earlier step applies):

1. **`open_scan_run_id` not null on any group** → resume it via `resume_cursor`.
2. **Else `recovery_required=true`** with a gap this skill owns
   (`invalid_unresolved_records`, `posts_without_context`, `posts_without_poster`,
   `failed_scan_run`, `capture_after_completion`) → repair it (below) before
   any other group. Multiple qualify → take highest `data_gap_count` first.
   If a group's only gaps are `unvalidated_posts`/`unclassified_posts`/
   `candidate_posts_without_confidence` (owned by other skills), report it as
   waiting on them and move to step 3.
3. **Else the stored batch** (`ops_state.key='scrape_14_groups_batch'`) — continue
   `current_group` if in progress, else pick up to 14 `joined=true`,
   `allows_sublet <> 'no'` groups ordered by `posts_per_day` desc.
4. **None of the above applies** → stop, report the ambiguity, don't invent a start.

One group at a time; don't move on until the current one is finished or blocked.

**Resume is channel-agnostic.** Default channel is browser-panel; the Apify
channel (below) only turns on when Kien gives a token for this session, and
only for that session — it's not a sticky setting. Which group/gap to work
next always comes from `dashboardkien_group`/`ops_state` alone, never from
which channel handled the group last. A group half-scraped by browser-panel
and finished later by Apify (or the reverse — started with Apify, continued
by browser-panel once the token runs out or the session ends) resumes
correctly with no extra handshake, because completion criteria
(`window_days` boundary + full raw data) and gap detection never look at
`capture_methods`/`source_surface`. See "Switching channels mid-group" under
the Apify section for the one thing that does need explicit handling
(closing an open run before switching mode).

## Repairing a recovery_required group

- `posts_without_context`: post exists, no `context_captured` event. Re-open
  it (permalink or group search below) and write the missing v2 event —
  never fabricate the payload from the bare row.
- `invalid_unresolved_records`: a `capture_unresolved` event missing
  `capture_contract_version=2`, exact `unresolved_reason`, `card_fingerprint`,
  or raw text. Use group search (below) to resolve it into a real post or a
  complete v2 event. **2026-09-21 (Kien decision): only events created on or
  after 2026-09-17 count here** — everything older is pre-contract legacy
  debt, permanently written off. Do not spend page-load budget chasing it;
  `dashboardkien_group` already excludes it from `recovery_required`. This
  is exactly why new capture must be complete on the first pass (see below)
  — nothing "gets fixed later" anymore.
- `posts_without_poster`: run the poster upsert (below) from the post's
  captured `poster.display_name`/`profile_url`, then `update posts set
  poster_id = <id>`.
- `failed_scan_run`: latest `scan_runs` row has a `stopped_reason` newer than
  the last completion check — resume like an open run, or close it cleanly
  with an accurate reason.
- `capture_after_completion`: new capture happened after `posts_14d_complete`
  was set — re-run the completion check and re-set or clear the flag.

Never touch `unvalidated_posts`/`unclassified_posts`/`candidate_posts_without_confidence`
— those belong to `validate-permalink`/`intent-analyze`. Fixing this skill's
share and reporting the rest is a complete outcome.

## Browser automation channel

Use Kien's already-open Chrome via the host's visible browser panel, reading
live DOM/accessibility state. No separate profile, headless automation,
HTTP/API calls, Selenium, or outside cookies. No join/form/notification/post/
comment/like/DM/donate. On login/checkpoint/CAPTCHA/unusual-activity: stop
immediately, record it, no retry for 24h.

Page-load budget: ≤4 per run. Human-plausible scroll pace; don't use delay to
evade rate limiting.

## Apify channel (khi Kien cung cấp token)

Chỉ dùng khi Kien đưa `APIFY_TOKEN` **và** group đang xử lý có
`is_private=false` trong `dashboardkien_group`/`groups`. Group
`is_private=true`/`null` (chưa xác minh) vẫn bắt buộc qua browser-panel ở
trên — tự kiểm tra `is_private` trước khi gọi, không suy đoán. Actor duy
nhất được phép: `apify/facebook-groups-scraper`. Gọi thẳng REST sync
endpoint (không cần dashboard Apify):

```
POST https://api.apify.com/v2/acts/apify~facebook-groups-scraper/run-sync-get-dataset-items?token=<APIFY_TOKEN>
Content-Type: application/json
```

### Input

Field xác nhận thật từ input schema của actor (2026-09-21) — verify lại
trên Apify console nếu actor cập nhật, đừng tin mù theo tài liệu này mãi:

```json
{
  "startUrls": [{ "url": "https://www.facebook.com/groups/<slug>/" }],
  "resultsLimit": 150,
  "viewOption": "CHRONOLOGICAL",
  "onlyPostsNewerThan": "7 days"
}
```

- `startUrls`: URL group public, lấy đúng từ `groups.url`. Xác nhận shape
  thật của field này (string thô hay object `{url}`) trong Input tab của
  actor trước lần chạy đầu tiên — mô tả public không ghi rõ 100%.
- `onlyPostsNewerThan`: đặt đúng bằng `window_days` hiện tại (7 ngày) —
  actor tự lọc theo ngày phía Apify, không cần scrape dư rồi tự cắt.
- `resultsLimit`: tính = `posts_per_day` (từ `dashboardkien_group`) × 7 ×
  1.3 (buffer), làm tròn lên, tối thiểu 30, tối đa 300/group. Group
  `posts_per_day` còn `null` → dùng 50 cho lần đầu, điều chỉnh theo dữ liệu
  quan sát được sau đó.
- `viewOption: "CHRONOLOGICAL"` để khớp newest→oldest như nhánh
  browser-panel.

### Chi phí và batch size

Giá thật: **~$2.60/1000 post trích xuất** (~$0.0026/post), tính theo **số
post lấy được**, không theo số group hay số run — batch to/nhỏ không tự
quyết định giá, tổng `resultsLimit` cộng dồn mới quyết định.

Trước khi chạy > 1 group/lần (bắt buộc theo `CLAUDE.md` #6): cộng
`resultsLimit` từng group trong batch, nhân $0.0026, báo số tiền ước tính
cho Kien trước khi gọi API. Ví dụ 5 group trung bình 20 post/ngày →
resultsLimit ≈ 182/group → 910 post → ≈ $2.4/batch.

Pilot lần đầu với 1 group, xác nhận link/poster/intent hợp lệ trước khi mở
rộng — 2 lần test thật 2026-09-21 đều lẫn nhiều spam (xem phần lọc bên
dưới), đừng chạy batch lớn trước khi pipeline lọc thật sự chạy đúng.

### Map kết quả vào raw contract

**Không nhầm `facebookUrl` (link group) với `url` (link post thật)** — lỗi
thật đã gặp khi đọc nhanh output lần đầu:

| Field Apify | Map vào |
|---|---|
| `url` | `posts.url` (permalink post thật — dùng field này, không phải `facebookUrl`) |
| `time` | absolute timestamp thật cho `posted_at` — không cần ước lượng như label tương đối bên browser-panel |
| `text` | `post_text`/`posts.body` |
| `user.name` | `poster.display_name` |
| `user.id` | `poster.profile_url` — ID số (vd `"61587509753606"`) dùng thẳng `facebook.com/profile.php?id=<id>`; ID dạng `pfbid0...` giữ nguyên trong payload và đánh dấu `profile_url_type="pfbid"` (không tự chuyển sang profile.php — sai định dạng) |
| `groupTitle`/`facebookId` (group) | `group.name`/`group.id` — verify khớp `group_id` đang xử lý |
| `attachments[].url`/`.image.uri` | `media` |
| `likesCount`/`sharesCount`/`commentsCount` | `reaction_count`/`share_count`/`comment_count` |
| `topComments[]` | `comments` (raw, giữ `commentUrl`/`author`, vẫn ≤100/post) |

Item không có field `url` (hiếm) → **không tự dựng lại permalink từ
`attachments[].url` bằng cách suy ra `gm.<id>`** — pattern đó chưa được
verify thật bằng browser, chỉ là quan sát cấu trúc chưa xác nhận. Ghi
`capture_unresolved` như card không có link, giữ nguyên rule không đoán.

### Lọc bắt buộc trước khi ghi DB (không optional)

Dữ liệu thô Apify **không tự động trust** — đo được thật ~50–85% là
rác/trùng qua 2 lần test 2026-09-21:

1. **Loại duplicate row y hệt** — Apify tự trả trùng nguyên văn (cùng
   `user.id` + `text` + group lặp lại trong cùng array), gặp thật ở test đầu.
2. **Loại cụm cross-poster cùng nội dung** — group theo `body_hash` chuẩn
   hóa trên toàn batch (không chỉ trong 1 group); cùng text dưới ≥2
   `user.id` khác nhau → nghi mạng spam xoay account, không ghi như N post
   độc lập. Case thật: `luceguemon06@gmail.com` xuất hiện dưới 3 tên khác
   nhau (Jennifer/Postine/Eliza Harthoorn) trên 9 group — phải chặn tay
   bằng `posters.outreach_unavailable` sau khi đã lọt vào DB.
3. **Loại off-topic rõ ràng** — đồ nội thất/thực phẩm/dịch vụ chuyển nhà/
   quảng cáo bên thứ 3 không phải housing. `RentHunter` và
   `Student Housing Amsterdam` là 2 account bot repost affiliate đã xác
   nhận thật (không phải suy đoán) — loại nội dung của 2 account này mặc
   định.
4. **Dedupe với DB hiện có** — check `posts.url` đã tồn tại trước khi
   insert, skip nếu trùng.

Chỉ sau 4 bước lọc trên mới đến find-or-create poster + insert post + ghi
`context_captured`, y hệt luồng ở phần "Capture per group" trên — khác mỗi
nguồn dữ liệu.

### Provenance bắt buộc

- `capture_methods: ["apify_api"]` — không giả làm `detail_dom_a11y`/
  `feed_dom_a11y` dù nội dung giống hệt output browser-panel.
- `source_surface: "apify_api"`.
- `posts.link_status = 'unvalidated'` như bình thường — Apify không thay
  `validate-permalink`.
- `scan_runs(mode='apify', group_id=<id>)` — giá trị `mode` mới, đã thêm
  vào constraint DB 2026-09-21 (trước đó chỉ có `group_page` cho
  browser-panel; dùng nhầm là tự giả provenance).
- `intent` vẫn để `null` — Apify chỉ thay bước đọc raw text,
  `intent-analyze` vẫn là bước phân loại chính thức duy nhất, không tắt
  qua được bằng kênh này.

### Switching channels mid-group

Browser-panel is the default; Apify is opt-in per session when Kien gives a
token, and only for `is_private=false` groups. Nothing about the resume
state is channel-specific except one thing: `scan_runs`. Handle the switch
exactly like this, in either direction:

1. Before opening a new run in the *other* channel's mode for a group, check
   `open_scan_run_id`/`resume_cursor` as usual. If it's open in the mode
   you're **not** about to use (e.g. an open `mode='group_page'` run exists
   but only an Apify token is available this session, or vice versa), close
   it cleanly first: `update scan_runs set finished_at = now(),
   stopped_reason = 'switched_to_apify'` (or `'switched_to_browser_panel'`).
   Never leave two open runs for the same group — `dashboardkien_group`
   collapses `open_scan_run_id` to one row per group (latest by
   `started_at`), so a stray second open run just goes silently stale, not
   safely ignored.
2. Open the new run in the new mode (`group_page` or `apify`) for the same
   `group_id`, then resume exactly like a cold start on that group: read
   latest `group_metrics` + `max(posted_at)` from `posts` (step 2 of "Batch
   state and resume" below) — this already reflects everything the other
   channel captured, regardless of which channel wrote it.
3. **`posts.url` has a real DB `unique` constraint** — this is the actual
   safety net, not just the "dedupe with DB hiện có" filter step. Overlap
   between channels (both capturing the same post) can never double-insert;
   insert with `on conflict (url) do nothing` (or check-then-skip) so a
   naturally overlapping resume never hard-errors the run instead of just
   skipping the already-captured post.
4. Completion (`posts_14d_complete`) is decided purely by the two conditions
   in "Completion and avoiding false reporting" below — it doesn't care
   which channel produced which post, so a group can finish its `window_days`
   boundary with some posts from browser-panel and some from Apify with zero
   special-casing.

## Batch state and resume

`ops_state` key `scrape_14_groups_batch`:

```json
{"batch_id":"...","window_days":7,"group_ids":[],"current_index":0,
 "current_group":null,"completed":[],"blocked":[],"status":"running"}
```

`dashboardkien_group.batch_blocked` checks `(batch.value->'blocked') @>
to_jsonb(groups.id)` — entries must be `groups.id` values, not names.

Before opening the browser for `current_group`:
1. Open `scan_runs` row (`finished_at is null`) for this group → resume its
   `cursor` (`window_days`, `last_verified_post_at`, `last_source_url`,
   `posts_verified`, `unresolved_cards`, `phase`).
2. No open run → read latest `group_metrics` + `max(posted_at)` from `posts`.
   `max(seen_at)` is only "last DB observation," never post time.
3. `posted_at` null → resume by verified `url`/cursor, don't reset to top of feed.
4. Already `posts_14d_complete=true` (no `capture_after_completion` gap) →
   mark `completed`, skip.

## Capture per group

1. Create/continue `scan_runs(mode='group_page', group_id=<id>)`.
2. Open the chronological feed. Read cards newest→oldest from the panel's live
   DOM/a11y tree — poster, timestamp, text, media, counters — before any
   processing. No LLM card-boundary guessing, no reading a raw page dump by eye.
3. Take a direct permalink if exposed, else the card's **Share → Copy link**.
   Either is sufficient link evidence. Keep the exact Facebook URL in
   `posts.url` — never infer an ID from a share token/media URL/tracking
   param. New posts: `link_status='unvalidated'` (only `validate-permalink`
   sets `validated`). A comment permalink with parent path `/posts/<id>/` is
   valid evidence too.

   No permalink and no Share link obtainable → don't drop the card: write
   `events(event='capture_unresolved', entity_type='fb_card', entity_id=null,
   source_url=<feed url>)` with poster, timestamp label, media/counters,
   `card_fingerprint`, `missing_fields`, `unresolved_reason='no_link_evidence'`.
   **DB-enforced**, not just a rule: constraint `capture_unresolved_reason_check`
   rejects any other `unresolved_reason` value on insert. Poster shown as
   "Anonymous participant"/no profile URL → record `poster.visibility='anonymous'`,
   never infer identity from a comment/photo/other profile.

4. **Find-or-create the poster, then write the post** — not optional.
   `dashboardkien_outreach` inner-joins `posts` to `posters`; a post with
   `poster_id is null` is invisible to outreach forever and keeps
   `posts_without_poster` (and `recovery_required`) open indefinitely.

   ```sql
   insert into posters (name, profile_url, type)
   values ($display_name, $profile_url, 'individual')
   on conflict (fb_uid) do update set last_seen_at = now()
   returning id;
   ```

   `fb_uid` (generated: `fb_identity(profile_url, name)`) extracts the
   numeric FB ID from `profile_url`, falls back to slug, then to
   `'name:'||lower(name)` — the DB's own dedup key (unique index
   `posters_fb_uid_key`); use as-is. No name and no profile URL → no
   `fb_uid`, leave `posts.poster_id` null and let it surface as
   `posts_without_poster` rather than guessing identity.

   ```sql
   insert into posts (source, url, group_id, poster_id, body, posted_at,
                       seen_at, link_status)
   values ('fb_feed', $url, $group_id, $poster_id, $body, $posted_at,
           now(), 'unvalidated');
   ```

   `intent` stays null (that's `intent-analyze`'s job). Relative label only
   ("2 weeks ago") → compute an estimate (see below) but never write it into
   `posted_at`; keep the label as evidence.

5. Write one `events(event='context_captured', entity_type='post',
   entity_id=<post id>)` row with the raw context contract (below). Skip if
   the post already has a complete v2 event, unless new capture has better evidence.
6. After **each batch**: posts/posters/events + run cursor/progress + group
   metric row + `update groups set last_scanned_at = now() where id =
   <group_id>`. Don't wait for the whole group/batch. (`last_scanned_at` is
   what Kien reads as "last touched" — it does not update itself;
   `dashboardkien_group.latest_capture_at` is separately computed from
   `events` and stays accurate either way.)

### Default feed-first hybrid capture

1. **Feed pass:** after each scroll chunk, enumerate cards from the DOM/a11y
   tree (permalink if present, poster, timestamp, text, media, counters).
   Dedupe by permalink/body hash before writing. Don't eyeball raw `read_page`
   output for card boundaries — pipe through `python3 scripts/extract_cards.py`
   first (below); it's a structure hint, every capture rule still applies.
2. **Detail gate:** open a card's own permalink only when missing/needs
   verification, text collapsed, comments needed, or detail-only metadata.
   Merge into feed values; a detail-view null never erases feed evidence.
3. **Source precedence:** `detail_dom_a11y` > `feed_dom_a11y` >
   `screenshot_fallback`; record sources in `capture_methods`.
4. **Screenshot fallback:** only when a11y can't read visible text — never
   sufficient alone to verify a group or permalink (virtualized cards, OCR errors).
5. **Acceptance:** complete-contract when merged fields have no unexplained
   gaps outside `missing_fields` and any comment has a valid parent-post URL.

### Post extractor (`scripts/extract_cards.py`)

Runs locally on already-fetched `read_page` output — no extra Facebook
request, doesn't affect page-load budget.

```sh
python3 scripts/extract_cards.py < read_page_output.txt
```

Splits cards on the marker `button "Hành động đối với bài viết này của
<Poster>"` (stable across layouts). Don't use `article`/`dialog` as the
boundary — an earlier version did and silently dropped real posts.

Returns per card: `poster_name`, `post_id` (if found), `timestamp_label`,
`post_text_guess`, `reaction_count`, `comment_count`, `media_urls`,
`missing_fields`, `confidence`, `needs_detail_gate` (true when no `post_id`
at feed layer — open detail/Share, don't drop the card).

Structure hint only — never write its `post_id` straight into
`posts`/`context_captured` without the real permalink/Share step.
`post_text_guess` can be wrong on unusual layouts; low-confidence cards still
need a real read. `card_count=0` on output with visible posts → Facebook's
DOM likely changed, report to Kien, don't assume data is missing.

### Raw context contract v2

Every `context_captured` payload carries every key below, `null`/`[]` when unknown:

`capture_contract_version`(=2), `capture_quality`, `scan_run_id`, `page_load`,
`source_surface`, `capture_now`, `capture_methods`, `group{id,name,url}`,
`post_id`, `link_resolution_method`, `post_title`, `post_text`,
`language_label`, `visibility`, `edited_label`, `shared_post`,
`timestamp_label`, `posted_at_observed`, `poster{display_name,profile_url,visibility}`,
`post_url`, `posted_at_estimated`, `posted_at_estimate_basis`,
`posted_at_estimate_uncertainty_hours`, `reaction_count`, `reaction_breakdown`,
`comment_count`, `share_count`, `media`, `comments`, `comments_captured_count`,
`comment_capture_status`, `poster_public_activity`, `commenter_public_activity`,
`missing_fields`, `truncated`.

An unresolved card uses a minimal payload instead (no fake `post_url`):
`capture_contract_version`(=2), `capture_quality`(="unresolved"),
`source_surface`, `capture_now`, `group_id`, `post_id`(=null), `post_url`(=null),
`link_resolution_method`, `raw_card_text`, `poster{display_name,profile_url}`,
`timestamp_label`, `media`, `reaction_count`, `comment_count`,
`card_fingerprint` (`sha256(normalized group+poster+time+text)`),
`missing_fields`, `unresolved_reason`(="no_link_evidence").

On re-run, look up `capture_unresolved` by `card_fingerprint` before writing
a new event. When a card gets link evidence later, create the normal
post/event referencing the fingerprint and mark the old event resolved —
never duplicate.

### Recovery via group search

```
https://www.facebook.com/groups/<group-slug>/search/?q=<url-encoded query>
```

Use a short distinctive phrase (5–10 words) from the unresolved event's raw
text — faster and more reliable than the search-icon UI (icon position
shifts, refs go stale, autocomplete misses uncommon names/Dutch phrases). No
results → fall back to the manual search-in-group dialog.

1. Match against `card_fingerprint` (poster+timestamp+text, normalized) —
   only a clear match; a poster can have several similar posts.
2. Click the post's timestamp (not title) → detail modal → permalink from
   `window.location.href`.
3. Re-verify group + poster with `find("Bài viết của <name>")` before writing.
4. Success → create post/event normally, `link_status='unvalidated'` (still
   needs `validate-permalink`), link the fingerprint, mark the original event resolved.

"Anonymous participant" in an old event isn't automatically a true anonymous
case — some were capture shortcuts that skipped a publicly-shown name.
Re-open and confirm before keeping the label on recovery.

Comments: capture all visible, ≤100/post. Public profile/activity only if
directly attached to an already-captured post, ≤10 posts or 30 days/person.
Never DMs, private content, friend lists, private albums; never split
phone/email into a contact record; never infer a sensitive attribute.

**Anonymous gate:** not ready for profile follow-up, classification, or
outreach until `validate-permalink` confirms its permalink. Unvalidated share
URL or no link at all → not access-ready.

### Raw capture checklist

Capture every visibly-available field (missing ≠ zero/empty): identity
(group id/name/url, post id, permalink, poster name/profile URL), link
evidence (as above, never inferred from a share token), content (title, full
text, language shown, visibility/edited/shared label), time (`capture_now`,
absolute timestamp, relative label, estimate per rule below), engagement
(reactions/breakdown/comment/share count — `null` when not exposed, never
guessed), attachments (type, URL, alt text, position), discussion (comments
with raw text, commenter/profile URL, permalink, timestamp, visibility),
provenance (page load, surface, quality, truncation, `missing_fields`).

Expand comments/replies (read-only), ≤100/post. `comment_capture_status='complete'`
only once the thread is exhausted; else `not_loaded`/`partially_loaded`/`capped_100`
— never `comments=[]` to mean "none" when unloaded.

Integrity: strip query/hash from each comment URL, verify parent
`/posts/<post_id>` matches `post_url`; verify `comment_id` when exposed.
Mismatch → quarantine, don't attach. Text/name alone is never enough to assign.

`capture_quality`: `complete` = text fully expanded, metadata/thread exhausted
or explicitly unavailable; `partial` = collapse/virtualization/unexpanded
thread prevented that; `legacy_normalized` = DB-only normalization of an old
event, not a new capture.

### Relative timestamp estimate

Compute at capture time from `capture_now`, never later. Parse clear labels
(min/hour/day/week, VN/EN/NL); never infer from a comment's timestamp.
Minimum uncertainty: min/hour `±1h`, day `±24h`, week `±72h`, month `±168h`.
Vague/unparseable label → all three estimate keys `null`.

Estimates are sort/triage only — never decide `posts_14d_complete`, cross
`window_days`, count `posts_14d_count`, or replace `posted_at` in
dedupe/resume. Proving the window is covered needs an absolute timestamp or a
Facebook-verified boundary.

## Completion and avoiding false reporting

- Direct permalink, valid-parent comment permalink, or Share link = link
  evidence, `link_status='unvalidated'` — this skill never sets `validated`.
- A "2 weeks" label, a `posts_seen` count, or running out of time-box does
  **not** prove the `window_days` boundary was reached.
- Unresolved-card count does **not** block completion — a large active group
  will rarely reach zero within the 4-page-load budget; resolving links is
  `validate-permalink`'s job.
- Completion = exactly two conditions: (1) `window_days` boundary crossed
  (currently 7 Amsterdam calendar days), and (2) every card in that window
  has full raw data (linked → normal post; linkless → full `capture_unresolved`
  data). Link resolution is separate and later.
- Feed virtualized / DB down / browser reset → keep count null/incomplete,
  keep the run open or record a stop reason, don't switch groups. This is a
  "raw data not captured yet" reason, unrelated to unresolved-link count.
- Only when both hold: set `posts_14d_complete=true` + `posts_14d_count` +
  `posts_14d_checked_at`, move to `completed`. Blocker → `blocked`, batch stays incomplete.

(`posts_14d_*` are legacy names; the live window is `window_days` — currently
7 — read the actual value, don't infer from the column name.)

## Database and continuing the flow

- Prefer Supabase MCP. `python3 scripts/db.py` (RPC `sublet_exec`,
  service_role only) is the fallback, mainly for Codex.
- Capture tables: `posts`, `posters`, `events`, `scan_runs`, `group_metrics`,
  `groups`. State: `ops_state` (`scrape_14_groups_batch`).
- DB error → retry once after 5s; still failing → stop, keep
  group/run incomplete, report a warning. Never claim a write succeeded
  without a confirming read.
- After the batch, the operator (or `validate-permalink`/`intent-analyze`
  when explicitly run) does classification/validation — this skill never
  sends anything externally and never guesses intent.
