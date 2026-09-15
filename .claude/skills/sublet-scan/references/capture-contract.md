# Capture contract — Facebook group history

This is the shared raw-capture contract for `sublet-scan` and
`sublet-backfill`. It records what the panel visibly exposes; it does not decide
intent, scam, deal quality, or contactability.

## Operating order

1. Select one joined group at a time, starting with the highest fresh
   `posts_per_day` metric. The metric is a volume signal, not proof of housing
   offerings. Re-rank when metrics are stale; do not open every group in one
   run.
2. Use the ChatGPT/Codex in-app browser panel with the user's manually
   logged-in real browser session. Facebook is read-only: no join,
   membership-form submit, notification change, post, comment, reaction, DM,
   send, donation, or profile interaction.
3. Read the group's chronological feed from newest to oldest for **14 calendar
   days**, using absolute timestamps in `Europe/Amsterdam` when Facebook exposes
   them. Preserve the original relative label as an additional raw field; never
   replace an unknown timestamp with a guessed one.
4. Capture and persist each verified post/context batch before continuing. A
   browser boundary such as “2 weeks ago” proves only that the boundary was
   reached; it does not prove that every post in the window was captured.

## Browser and safety budget

- Browser reads may use only the visible accessibility tree/DOM in the panel.
  No HTTP/API, CLI scraper, Selenium, headless browser, cookie export, or other
  browser session.
- Respect the applicable Facebook page-load budget (normally no more than 4 per
  scan run; the worker also enforces the daily budget). Scrolling is paced with
  small human-like waits, but pacing is not a way around a checkpoint or rate
  limit.
- Stop immediately on login, checkpoint, captcha, “unusual activity”, a
  verification request, an unreadable layout, or a database outage after the
  one retry. Leave the run open/incomplete and record the stop reason; do not
  claim that the group is complete.

## Post record (`sublet_listings`)

For every post whose group and permalink are verified by the panel, store:

- `source='fb_feed'`
- canonical `source_url` (query/hash removed), required for provenance
- `group_key`, `poster_name`, and full visible `raw_text` after expanding a
  visible collapse; do not mix comments into `raw_text`
- `posted_at` only when an absolute post timestamp is actually exposed;
  otherwise `null`
- `seen_at` set at capture time and `kind=null`
- let the database generate `text_hash`; never insert that generated column

Never invent a permalink from a card, photo-set id, text hash, or label. A card
without a verified source URL is an unresolved observation in the run, not a
listing row. Keep its progress note so the operator can inspect it later.

## Raw context event (`sublet_events`)

Write one `event='context_captured'`, `actor='agent'`, linked to the listing,
with the same keys on every event (use `null`, `[]`, or `false`; do not omit a
key to mean “not observed”). The event must also carry provenance for the exact
browser observation:

- `capture_contract_version=2`
- `scan_run_id` = the numeric `sublet_scan_runs.id`
- `page_load` = the page-load ordinal within that run (or `null` when no new
  page was loaded)
- `source_surface='codex_in_app_browser'`
- `capture_quality='complete'` for a new event; use `legacy_unknown` only when
  documenting an older event that cannot be reconstructed

These fields belong in the event payload even though `sublet_events` has no
dedicated columns for them. Never use `detail_audit` as a substitute for this
raw event.

```json
{
  "capture_contract_version": 2,
  "scan_run_id": 7,
  "page_load": 1,
  "source_surface": "codex_in_app_browser",
  "capture_quality": "complete",
  "post_text": "...",
  "timestamp_label": "2 weeks ago",
  "posted_at_observed": null,
  "poster": {
    "display_name": "...",
    "profile_url": "https://www.facebook.com/...",
    "visibility": "public"
  },
  "post_url": "https://www.facebook.com/groups/.../posts/.../",
  "reaction_count": null,
  "comment_count": null,
  "media": [],
  "comments": [
    {
      "commenter_name": "...",
      "commenter_profile_url": "https://www.facebook.com/...",
      "comment_url": "https://www.facebook.com/...",
      "commented_at": null,
      "original_time_label": "3 days ago",
      "raw_text": "...",
      "reply_to": null,
      "visibility": "public"
    }
  ],
  "poster_public_activity": [],
  "commenter_public_activity": [],
  "truncated": false
}
```

Capture all comments/replies that are visible without unsafe or unbounded
expansion, up to 100 comments/replies per post. For poster/commenter public
activity, follow only visible public links tied to this captured housing post,
up to 10 recent posts or 30 days. Store raw text, verified URL, absolute date if
shown, relative label if shown, and `visibility`; use `partial` when the panel
shows a person but not a usable public link. Do not harvest friend lists,
private posts, albums, DMs, separate phone/email fields, or sensitive
attributes. Never infer identity or relationship from a display name.

## 14-day completion and database checkpoints

Use `sublet_scan_runs.mode='group_page'` with `group_key`. Keep a resumable
cursor/progress object containing at least:

```json
{
  "window_days": 14,
  "sorting": "CHRONOLOGICAL",
  "last_verified_post_at": null,
  "last_source_url": null,
  "posts_verified": 0,
  "unresolved_cards": 0,
  "phase": "capturing"
}
```

After each successful batch, atomically write the listing rows, their context
events, and the run progress. Update the group's latest metric/status after
each group batch; do not wait until all groups are done. The run remains open
until the 14-day boundary is reached **and** every verified card in the window
has been processed. Only then set:

- `sublet_group_metrics.posts_14d_count` to the deduplicated verified count
- `sublet_group_metrics.posts_14d_complete=true`
- `sublet_group_metrics.posts_14d_checked_at=now()`

If the feed is virtualized, cards lack permalinks, text is collapsed and cannot
be expanded, or a browser/DB stop interrupts the work, keep the count null (or
the known count with `posts_14d_complete=false`) and explain the reason in the
run cursor/stopped reason. `posts_seen` is not automatically the 14-day total.

Capture is separate from analysis: leave `kind=null`, then run
`intent-analyze` later on the saved raw records.

## Legacy event repair

Existing `context_captured` events that lack these keys are **legacy/incomplete
provenance**, not evidence that Facebook showed no value. A DB-only repair may
add the required keys with `null`, `[]`, or `false` and set
`capture_quality='legacy_unknown'`, but must not invent timestamps, counts,
media, run ids, page ordinals, or surface names. Keep `detail_audit` events
separate and exclude them from the analyzer input. Re-audit the repaired rows
before treating them as contract-complete.
