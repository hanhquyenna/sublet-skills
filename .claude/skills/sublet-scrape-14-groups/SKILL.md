---
name: sublet-scrape-14-groups
description: "Scrape joined Facebook groups through the visible browser, resume from Supabase state, checkpoint each batch, and expose progress in dashboardkien_group."
---

# sublet-scrape-14-groups

This is an automation button: it must run start-to-finish from the database
alone, with no briefing from Kien. Every decision it needs — where to resume,
which group is next, when a group is done — is derived from
`dashboardkien_group` and the tables behind it, not from conversation memory
or a previous agent's report.

## Project and control surface

Supabase project ref `cteunhuxrghpozwbnehh`
(`https://cteunhuxrghpozwbnehh.supabase.co`). The operator-facing control view
is `public.dashboardkien_group`. You already know this — the project,
the tables (`groups`, `group_metrics`, `posts`, `posters`, `events`,
`scan_runs`, `ops_state`), and the view are fixed facts about this project,
not something to rediscover each run.

The only thing that can be missing is the *connection*: if Supabase MCP is not
connected to `cteunhuxrghpozwbnehh`, or `scripts/db.py` (which calls RPC
`sublet_exec`, service_role only) fails to authenticate, stop and ask Kien
directly for the missing secret (database password, service-role token,
connection string — whatever the specific failure needs). That is explicitly
allowed here; what is not allowed is guessing a different project, printing a
secret back into the conversation, or inventing a workaround that touches
Facebook without a working DB connection (raw capture with no DB write is
just data loss).

This skill captures and checkpoints raw scraping progress only. It does not
classify intent, validate links, or send outreach.

## Why the resume logic works this way

`dashboardkien_group` is a live view, recomputed from `posts`/`events`/
`scan_runs`/`group_metrics` on every query — it is not a cache and cannot go
stale on its own. That means the resume decision below is always safe to
re-derive from scratch at the start of a run, and never needs to be
remembered between sessions.

`recovery_required=true` exists because a group's capture can be left in a
genuinely bad state (an interrupted run, old capture rows that predate the
current raw-contract version, posts that never got linked to a poster) and
those posts are silently excluded from `dashboardkien_outreach` until
repaired — with no error, just missing rows. If new groups are scraped while
older groups sit broken, the backlog of unusable captured content only grows.
That is why repair always comes before starting a new group.

`clean_for_outreach=true` needs more than this skill can produce alone: it
requires zero capture gaps (this skill's job) **and** zero unvalidated links
(`validate-permalink`'s job) **and** zero missing classification/confidence
(`intent-analyze`'s job) on the same group. A group can finish a clean scrape
pass and still show `needs_recovery` afterward because `unvalidated_posts` or
`candidate_posts_without_confidence` is nonzero — that is correct, not a bug
in this skill. Report it as "capture-complete, waiting on validate-permalink/
intent-analyze," not as a stuck scrape.

## Automatic resume contract

At the start of every run, query `dashboardkien_group` and decide in this
order — do not skip ahead to step 3 while 1 or 2 apply:

1. **Any row with `open_scan_run_id` not null** → that group has an
   unfinished run (crash, stopped session, hard failure). Resume it using its
   `resume_cursor`. Do not start a fresh run for that group.
2. **Else, any row with `recovery_required=true`** whose `recovery_reason`
   includes a gap this skill can actually fix (`invalid_unresolved_records`,
   `posts_without_context`, `posts_without_poster`, `failed_scan_run`,
   `capture_after_completion`) → repair it (see "Repairing a recovery_required
   group" below) before touching any other group. When several groups qualify,
   take the one with the highest `data_gap_count` first — it clears the most
   stuck content per unit of browser effort. If every `recovery_required`
   row's reason is entirely gaps owned by other skills (`unvalidated_posts`,
   `unclassified_posts`, `candidate_posts_without_confidence` with nothing
   else), this skill has no more work on that group — report it as waiting on
   `validate-permalink`/`intent-analyze` and move to step 3.
3. **Else, the stored batch state** (`ops_state.key='scrape_14_groups_batch'`)
   — if it has a `current_group` still in progress, continue it. If the batch
   is exhausted or absent, select up to 14 groups with `joined=true`,
   `allows_sublet <> 'no'`, ordered by latest `posts_per_day` descending, and
   start a new batch.
4. **If none of the above establishes a safe next step** — stop and report
   the ambiguity to Kien. Do not invent a starting point.

Process exactly one group at a time; do not open multiple groups in parallel
and do not move to the next group until the current one is finished or
blocked.

## Repairing a recovery_required group

- `posts_without_context`: a `posts` row exists with no matching
  `context_captured` event. Re-open that post (permalink if still resolvable,
  or the group search fallback below) and write the missing event with a full
  v2 payload. Never fabricate the payload from the bare post row.
- `invalid_unresolved_records`: a `capture_unresolved` event exists but is
  missing `capture_contract_version=2`, the exact `unresolved_reason`, a
  `card_fingerprint`, or the raw text. Use the "Recovery via group search"
  method below to re-find the card and either resolve it into a real post or
  rewrite the event with a complete v2 payload.
- `posts_without_poster`: a `posts` row has `poster_id is null`. Run the
  poster upsert (below) using the `poster.display_name`/`profile_url` already
  captured in that post's `context_captured` event, then `update posts set
  poster_id = <id> where id = <post id>`.
- `failed_scan_run`: the most recent `scan_runs` row for the group has a
  `stopped_reason` newer than the last completion check. Resume it like an
  open run, or if it truly cannot continue, finish it cleanly with an
  accurate `stopped_reason` and let the batch move on.
- `capture_after_completion`: new capture happened after `posts_14d_complete`
  was set. Re-run the completion check (below) and re-set
  `group_metrics.posts_14d_complete`/`posts_14d_count`/`posts_14d_checked_at`
  if it still holds, or clear `posts_14d_complete` if it no longer does.

Do not touch `unvalidated_posts`, `unclassified_posts`, or
`candidate_posts_without_confidence` — those are `validate-permalink` and
`intent-analyze`'s fields respectively. Fixing this skill's share of a
group's gaps and reporting the rest is a complete, honest outcome.

## Browser automation channel

All Facebook scraping must use Kien's already-open Chrome browser through the
host's visible browser automation panel. Reuse that logged-in Chrome session
and read the live DOM/accessibility state before capture. Do not open a
separate browser profile, use headless automation, HTTP/API requests,
Selenium, or cookies outside Kien's Chrome session.

Do not join, submit a membership form, enable notifications, post, comment,
like, DM, send, donate, or otherwise interact with a profile. When Facebook
shows login, checkpoint, CAPTCHA, or "unusual activity": stop immediately,
record the stop, and do not retry for 24 hours.

Keep the page-load budget: at most 4 page loads per run. Scroll at a
human-plausible pace; do not use delay to try to evade rate limiting.

## Batch state and resume

State lives in `ops_state` key `scrape_14_groups_batch`:

```json
{
  "batch_id": "2026-09-21T22:00:00+02:00",
  "window_days": 7,
  "group_ids": [],
  "current_index": 0,
  "current_group": null,
  "completed": [],
  "blocked": [],
  "status": "running"
}
```

`dashboardkien_group.batch_blocked` reads `(batch.value->'blocked') @>
to_jsonb(groups.id)`, so entries in `blocked`/`completed` must be `groups.id`
values, not names or old `sublet_groups.key` slugs.

Before opening the browser for `current_group`:

1. Check `scan_runs` for the most recent row with this `group_id` and
   `finished_at is null`. If one exists, read its `cursor` JSON
   (`window_days`, `last_verified_post_at`, `last_source_url`,
   `posts_verified`, `unresolved_cards`, `phase`) and resume from there.
2. If no open run, read the latest `group_metrics` row for this group and
   `max(posted_at)` from `posts` with an absolute timestamp. Use `max(seen_at)`
   only to know when the DB last observed activity — never as the post time.
3. If `posted_at` is null for the relevant range, resume by verified
   `url`/cursor instead. Do not reset to the top of the feed just because a
   prompt or browser session was interrupted.
4. If the group already has `posts_14d_complete=true` (and no
   `capture_after_completion` gap), mark it `completed` in the batch and skip
   it — do not re-scrape.

## Capture per group

1. Create or continue `scan_runs(mode='group_page', group_id=<id>)`.
2. Open the group's chronological feed in the panel. Read each card newest to
   oldest, expand visible collapsed text, scroll in time-boxed chunks. Use
   the panel's live DOM/accessibility tree to separate cards and extract
   poster, timestamp, text, media, and counters before any further
   processing — do not use an LLM to guess card boundaries, and do not read
   a raw page dump by eye.
3. Capture does not open links purely to resolve them. For each card, take a
   direct permalink if the DOM/a11y tree exposes one; otherwise use that
   card's **Share → Copy link** action in the panel. Either is sufficient
   link evidence for a raw post row. Keep the exact URL Facebook produced in
   `posts.url` — never infer an ID from a share token, media URL, tracking
   parameter, commenter profile, or photo ID. New posts get
   `link_status='unvalidated'`; only `validate-permalink` sets `validated`.
   A comment permalink with parent path `/posts/<id>/` is still valid
   evidence — keep the parent URL in the event payload without opening the
   detail view just for that.

   If neither a direct permalink nor a Share→Copy link can be obtained, do
   **not** drop the card: write it to `events(event='capture_unresolved',
   entity_type='fb_card', entity_id=null, source_url=<group feed url>)` with
   poster, timestamp label, media/counters, `card_fingerprint`,
   `missing_fields`, and `unresolved_reason='no_link_evidence'`. The database
   rejects any other value for `unresolved_reason` on this event
   (`capture_unresolved_reason_check`, `NOT VALID` but still enforced on new
   inserts) — this is a hard DB-level block on skipping the link-evidence
   attempt to save time, not just a written rule. If a card's poster is shown
   as "Anonymous participant"/"Người tham gia ẩn danh" or otherwise has no
   exposed profile URL, record `poster.visibility='anonymous'` — do not infer
   identity from a comment, photo, or another profile. An anonymous card
   without a permalink stays `capture_unresolved`; with only a share URL it
   is `unvalidated` evidence, not yet access-ready.

4. **Find-or-create the poster, then write the post.** `dashboardkien_outreach`
   inner-joins `posts` to `posters` — a post with `poster_id is null` is
   invisible to outreach forever, and it also keeps the group's
   `posts_without_poster` gap (and therefore `recovery_required`) open
   indefinitely. This step is not optional:

   ```sql
   insert into posters (name, profile_url, type)
   values ($display_name, $profile_url, 'individual')
   on conflict (fb_uid) do update set last_seen_at = now()
   returning id;
   ```

   `fb_uid` is a generated column (`fb_identity(profile_url, name)`): it
   extracts the numeric Facebook ID from `profile_url` when present, falls
   back to the profile slug, and falls back to `'name:' || lower(name)` when
   there is no profile URL at all. This is the database's own existing dedup
   key (unique index `posters_fb_uid_key`) — use it as-is rather than
   inventing a different matching rule. An anonymous poster with no name and
   no profile URL has no `fb_uid` and cannot be inserted into `posters`;
   leave `posts.poster_id` null for that card and let it surface as
   `posts_without_poster` for manual review rather than guessing an identity.

   Then insert the post:

   ```sql
   insert into posts (source, url, group_id, poster_id, body, posted_at,
                       seen_at, link_status)
   values ('fb_feed', $url, $group_id, $poster_id, $body, $posted_at,
           now(), 'unvalidated');
   ```

   `intent` stays null (classification is `intent-analyze`'s job, not this
   skill's). If Facebook only exposes a relative label ("2 weeks ago"),
   compute an estimate from `capture_now` (see "Relative timestamp estimate"
   below) but do not write it into `posted_at` — keep the estimate in the
   event payload and the original label as evidence.

5. Write one `events` row with `event='context_captured'`,
   `entity_type='post'`, `entity_id=<post id>`, using the raw context
   contract below. Do not create a duplicate if the post already has a
   complete v2 `context_captured` event — only add one when new capture has
   genuinely better evidence.
6. After **each batch**, write posts/posters/events plus the run's
   cursor/progress plus the group metric row, and `update groups set
   last_scanned_at = now() where id = <group_id>`. Do not wait until the whole
   group (or all 14 groups) is done to update the database. `last_scanned_at`
   is what Kien reads as "when was this group last touched" — leaving it
   stale makes a group that was just worked on look untouched for days.
   (`dashboardkien_group.latest_capture_at` is computed independently from
   `events` and stays accurate either way, but `last_scanned_at` does not
   update itself.)

### Default feed-first hybrid capture

1. **Feed pass:** after each scroll chunk, enumerate cards from the panel's
   DOM/a11y tree and capture core fields (permalink if present, poster,
   timestamp, text, media metadata, counters). Dedupe by permalink/body hash
   within the batch before writing. Do not read raw `read_page` output by eye
   to find card boundaries — pipe it through
   `python3 scripts/extract_cards.py` first (see "Post extractor" below).
   The script is a structure hint, not verified link evidence; every capture/
   detail-gate/dedupe rule here still applies to its output.
2. **Detail gate:** only open a card's own permalink when it is missing a
   permalink and needs verification, has collapsed text, needs comments read,
   or has metadata only visible in the detail view. Merge detail fields into
   the feed-captured values; a null from the detail view never erases feed
   evidence.
3. **Source precedence:** when a field has two values, prefer
   `detail_dom_a11y` > `feed_dom_a11y` > `screenshot_fallback`. Record which
   sources were used in `capture_methods`.
4. **Screenshot fallback:** only when the accessibility tree cannot read
   visible text. Never treat a screenshot alone as enough to verify a group
   or permalink — Facebook can virtualize cards outside the viewport and OCR
   can misread text/URLs/timestamps.
5. **Acceptance:** a card counts as complete-contract when the merged field
   set has no unexplained gaps outside `missing_fields`, and any comment has
   a valid parent-post URL.

### Post extractor (`scripts/extract_cards.py`)

Runs entirely locally on already-fetched `read_page` output — it makes no
further request to Facebook, so it does not affect the page-load budget or
detection risk.

```sh
python3 scripts/extract_cards.py < read_page_output.txt
```

It splits cards on the marker `button "Hành động đối với bài viết này của
<Poster>"`, which has proven stable across both the single-post dialog and
multi-post feed layouts, with or without a wrapping `article` role. Do not use
`article`/`dialog` as the boundary — an earlier version did and silently
dropped real posts, catching only comments, because Facebook does not always
wrap a post in `article`.

Each card returns `poster_name`, `post_id` (if found via direct permalink or
a comment's parent path), `timestamp_label`, `post_text_guess`,
`reaction_count`, `comment_count`, `media_urls`, `missing_fields`,
`confidence` (`high`/`medium`/`low`), and `needs_detail_gate` (true when no
`post_id` was found at the feed layer — the exact moment to open the
detail/Share flow above, not to drop the card).

Known limits: it is a structure hint, not verified evidence — never write its
`post_id` straight into `posts`/`context_captured` while skipping the real
permalink/Share-link step. `post_text_guess` can be wrong on unusual post
structures; low-confidence or missing-text cards still need a human-equivalent
read. If it returns `card_count=0` on output that visibly has posts, Facebook's
DOM has likely changed — report it to Kien rather than assume the data is
missing.

### Raw context contract v2

Every `context_captured` payload has every key, even when the value is
unknown:

```json
{
  "capture_contract_version": 2,
  "capture_quality": "complete",
  "scan_run_id": 7,
  "page_load": 1,
  "source_surface": "user_browser_panel",
  "capture_now": "2026-09-21T23:00:00+02:00",
  "capture_methods": ["feed_dom_a11y"],
  "group": {
    "id": "amsterdam-housing-apartments-rooms-287563233830552",
    "name": "Amsterdam Housing, Apartments & Rooms",
    "url": "https://www.facebook.com/groups/287563233830552/"
  },
  "post_id": "1126264226627111",
  "link_resolution_method": "direct_permalink",
  "post_title": null,
  "post_text": "...",
  "language_label": null,
  "visibility": "public",
  "edited_label": null,
  "shared_post": null,
  "timestamp_label": "2 weeks ago",
  "posted_at_observed": null,
  "poster": {
    "display_name": "...",
    "profile_url": null,
    "visibility": "public"
  },
  "post_url": "https://www.facebook.com/groups/.../posts/.../",
  "posted_at_estimated": null,
  "posted_at_estimate_basis": null,
  "posted_at_estimate_uncertainty_hours": null,
  "reaction_count": null,
  "reaction_breakdown": null,
  "comment_count": null,
  "share_count": null,
  "media": [],
  "comments": [],
  "comments_captured_count": 0,
  "comment_capture_status": "not_loaded",
  "poster_public_activity": [],
  "commenter_public_activity": [],
  "missing_fields": [],
  "truncated": false
}
```

An unresolved card uses its own minimal payload (no fake `post_url`):

```json
{
  "capture_contract_version": 2,
  "capture_quality": "unresolved",
  "source_surface": "user_browser_panel",
  "capture_now": "2026-09-21T23:00:00+02:00",
  "group_id": "...",
  "post_id": null,
  "post_url": null,
  "link_resolution_method": "facebook_copy_link_failed",
  "raw_card_text": "...",
  "poster": {"display_name": "...", "profile_url": null},
  "timestamp_label": null,
  "media": [],
  "reaction_count": null,
  "comment_count": null,
  "card_fingerprint": "sha256(normalized group + poster + time + card text)",
  "missing_fields": ["post_url", "post_id"],
  "unresolved_reason": "no_link_evidence"
}
```

On re-run, look up `capture_unresolved` by `card_fingerprint` before writing
a new event. When a card later gets link evidence, create the normal
post/event, reference the fingerprint, and mark the unresolved event
resolved — never duplicate it.

### Recovery via group search

Instead of scrolling chronologically from the top to find one specific
unresolved card, use Facebook's in-group search:

```
https://www.facebook.com/groups/<group-slug>/search/?q=<url-encoded query>
```

Use a short distinctive phrase (5–10 words) from the `capture_unresolved`
event's raw text. This is faster and more reliable than the search-icon UI
flow (icon position shifts, refs can go stale, autocomplete sometimes never
appears for uncommon names or Dutch phrases). If the direct URL returns
nothing (common on some private groups), fall back to the manual
search-in-group dialog.

1. Match results against the `card_fingerprint` (poster + timestamp + text,
   normalized) — accept only a clear match; do not guess between multiple
   candidates. The same poster can have several similar posts in one group.
2. Click the post's timestamp (not its title text) to open the detail modal
   and read the permalink from `window.location.href`.
3. Re-verify group and poster with `find("Bài viết của <name>")` before
   writing to the database.
4. On success, create the post/event normally, `link_status='unvalidated'`
   (still needs `validate-permalink`, this only recovered evidence — it does
   not itself validate), link the `card_fingerprint`, and mark the original
   `capture_unresolved` event resolved.

A poster recorded as "Anonymous participant" in an old `capture_unresolved`
event is not automatically a true anonymous case — several were capture
shortcuts that skipped reading a name that was actually shown publicly. When
recovering such a card, re-open the real post and confirm before keeping the
anonymous label.

Capture all visible public comments/replies, up to 100 per post. Only read
public profile/activity directly attached to an already-captured post, up to
10 posts or 30 days per poster/commenter. Never read DMs, private content,
friend lists, or private albums; never split phone/email into a separate
contact record; never infer a sensitive attribute.

**Anonymous gate:** an anonymous card is not ready for profile follow-up,
official classification, or outreach until `validate-permalink` has opened
and confirmed its permalink. An unvalidated share URL is not enough, and a
card with no link at all cannot access the profile or post.

### Raw capture checklist

Capture every field that is visibly available; a missing value is different
from zero or an empty list: identity (group id/name/url, post id, canonical
permalink, poster name and public profile URL), link evidence (direct
permalink, comment permalink with valid parent path, or Share→Copy link with
method `facebook_copy_link` — never infer a post ID from a share token),
content (title, full expanded text, language as shown, visibility/edited/
shared label), time (`capture_now`, absolute timestamp if shown, relative
label, estimate fields only per the rule below), engagement (reactions,
breakdown, comment count, share count — `null` when not exposed, never a
guessed number), attachments (type, verified URL, alt text, position),
discussion (public comments/replies with raw text, commenter/profile URL,
permalink, timestamp, visibility), and provenance (page load, source surface,
capture quality, truncation, `missing_fields`).

Expand "view more comments" and visible replies as a read-only panel action,
up to 100 per post. Set `comment_capture_status='complete'` only once the
visible thread is exhausted; otherwise `not_loaded`, `partially_loaded`, or
`capped_100`. Never use `comments=[]` to mean "no comments" when the thread
was never loaded.

Integrity check: for every comment, strip query/hash from its URL and verify
its parent `/posts/<post_id>` matches the captured `post_url`; verify
`comment_id` when Facebook exposes it. If the parent doesn't match, do not
attach the comment to that post — hold it in a quarantine/review record. A
comment's text or commenter name alone is never enough to assign it.

`capture_quality='complete'` means the post text was fully expanded and the
visible metadata/thread were exhausted or explicitly marked unavailable;
`partial` means a collapse, virtualization, or unexpanded thread prevented
that; `legacy_normalized` is DB-only normalization of an older event, not a
new browser capture.

### Relative timestamp estimate

Compute the estimate at capture time from `capture_now`, never from when an
analyzer or DB insert runs later. Parse clear labels (minutes/hours/days/
weeks, in Vietnamese/English/Dutch); do not infer post time from a comment's
timestamp. Minimum uncertainty: minutes/hours `±1h`, days `±24h`, weeks
`±72h`, months `±168h`. If the label is vague ("recently") or unparseable,
leave all three estimate keys `null`.

Estimates are for sort/triage reference only — never use them to decide
`posts_14d_complete`, cross the `window_days` boundary, count
`posts_14d_count`, or replace `posted_at` in dedupe/resume logic. Proving the
window is fully covered still requires an absolute timestamp or a
Facebook-verified boundary.

## Completion and avoiding false reporting

- A card with a direct permalink, a comment permalink with valid parent path,
  or a Share→Copy link is link evidence and belongs in the raw queue with
  `link_status='unvalidated'` — this skill never sets `validated`.
- A "2 weeks" label, a `posts_seen` count, or running out of time-box does
  **not** by itself prove the `window_days` boundary was reached.
- The count of unresolved (link-missing) cards does **not** block completion.
  A large active group will almost never reach zero unresolved cards within
  the 4-page-load budget; resolving links is `validate-permalink`'s job, not
  a precondition for this skill finishing a group.
- Completion has exactly two conditions: (1) the `window_days` boundary
  (currently 7 Amsterdam calendar days) has been crossed, and (2) every card
  in that window has full raw data — a linked card becomes a normal post, a
  linkless card still gets full raw data via `capture_unresolved` (poster,
  timestamp/label, full raw text, media, counters, fingerprint). Link
  resolution happens later; raw data does not.
- If the feed is virtualized, text stays collapsed, the DB is down, or the
  browser resets: keep the count null/known-incomplete, keep the run open or
  record a stop reason, and do not move to another group. This is a
  "raw data not yet captured" reason, unrelated to how many cards lack a
  link.
- Only when both conditions hold: set `group_metrics.posts_14d_complete=true`
  with `posts_14d_count` and `posts_14d_checked_at`, and move the group to
  `completed` in the batch. A group with a blocker goes to `blocked` instead
  and the batch stays incomplete.

(`posts_14d_*` are legacy column names; the live window is `window_days`
calendar days, currently 7 — read the actual value, don't infer it from the
column name.)

## Database and continuing the flow

- Prefer Supabase MCP for reads/writes/migrations. `python3 scripts/db.py`
  (RPC `sublet_exec`, service_role only) is the fallback path, mainly for
  Codex.
- Capture tables: `posts`, `posters`, `events`, `scan_runs`, `group_metrics`,
  `groups`. State tables: `ops_state` (`scrape_14_groups_batch`).
- DB error: retry the exact operation once after 5 seconds; if it still
  fails, stop, keep the group/run incomplete, and report a warning. Never
  claim a write succeeded without a confirming read.
- After the raw capture batch finishes, the operator (or `validate-permalink`
  /`intent-analyze` when explicitly run) does classification and validation —
  this skill never sends anything externally and never guesses intent.
