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
