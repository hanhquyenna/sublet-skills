# Dashboard source of truth

Kien controls the project through exactly two Supabase views. Everything else
(`posts`, `posters`, `groups`, `events`, `scan_runs`, `outreach_messages`,
`outreach_availability_answers`, `poster_duplicate_posts`, ...) is
implementation data: agents may query it to execute or verify work, but
progress must reconcile back to these two views.

- `public.dashboardkien_group` — scraping, recovery, and data-readiness control.
- `public.dashboardkien_outreach` — first-message (`message1`) outreach control.

This document is generated from the live view definitions (`pg_views`) on
2026-09-21. If the view changes, re-derive this document from the database —
do not hand-edit it out of sync with `pg_views`.

## Scraping control — `dashboardkien_group`

One row per `groups` row. Live columns, in view order:

```text
group_id                            groups.id
group_name                          groups.name
city, tier, member_count, is_private, joined
last_scanned_at
posts_per_day                       latest group_metrics row
posts_14d_count, posts_14d_checked_at   legacy column names; the active
                                     capture window is 7 Amsterdam calendar
                                     days (see sublet-scrape-14-groups),
                                     the "14d" in the name is historical
listings_with_permalink             posts with this group_id
unresolved_no_permalink             capture_unresolved events for this group
total_posts_captured                the two counts above, summed
offering_count / seeking_count / other_count / unclassified_count
distinct_posters
scrape_status                       'complete' | 'needs_recovery' | 'partial' | 'not_started'
pct_resolved                        listings_with_permalink /
                                     total_posts_captured * 100, null if 0 captured
posts_14d_complete                  stored completion flag (see skill)
recovery_required                   true if ANY gap below is nonzero/open
recovery_reason                     comma-joined human-readable list of which
                                     gap(s) triggered recovery_required
data_gap_count                      sum of all the gap counts below
posts_without_permalink             url is null/blank
posts_without_context               no context_captured event for the post
invalid_unresolved_records          capture_unresolved events missing
                                     capture_contract_version=2, the exact
                                     unresolved_reason, card_fingerprint, or raw text
open_scan_run_id                    a scan_runs row for this group with
                                     finished_at is null (should be at most one
                                     open run per group+mode by design)
resume_cursor                       that open run's cursor, if any
latest_capture_at                   most recent context_captured/capture_unresolved event
clean_for_outreach                  posts_14d_complete AND NOT recovery_required
unvalidated_posts                   link_status = 'unvalidated'
posts_without_poster                poster_id is null
candidate_posts_without_confidence  intent in (offering,seeking) and confidence is null
```

`scrape_status='complete'` and `clean_for_outreach=true` require: the
completion flag is set, no open scan run, no blocked-batch state, and every
gap column above is zero, AND nothing was captured more recently than the
completion timestamp (otherwise the completion flag is stale relative to new
capture). Browser scrolling alone never sets these — only a write to
`group_metrics.posts_14d_complete` after the skill's completion check passes.

`recovery_required=true` means: do not hand this group to outreach, and the
next scrape run must repair the listed gap(s) — resume the open run if
`open_scan_run_id` is set, otherwise use `resume_cursor` / the skill's normal
resume logic — before starting a different group.

Only groups with `clean_for_outreach=true` (checked per-post via a join in
`dashboardkien_outreach`) can produce outreach candidates. A group stuck in
`needs_recovery` silently removes its posts from the outreach queue — this is
by design, not a bug, but it means outreach volume drops whenever recovery
work is not being done.

## Outreach control — `dashboardkien_outreach`

One row per **poster**, from their most recent qualifying post (`offering` or
`seeking`, `status='new'`, `canonical_post_id is null`, `link_status='validated'`,
poster `type='individual'`, poster has a name, post from the last 7 Amsterdam
calendar days, not flagged as a duplicate in `poster_duplicate_posts`, and the
post's group has `clean_for_outreach=true`). Live columns, in view order:

```text
poster_name
poster_profile_url    stored profile_url, else derived from fb_uid, else a
                       Facebook search-in-group/search-people URL as a fallback
post_link
post_text
intent                 'offering' | 'seeking'
link_status
message1                the exact stored first-message text (EN/NL by post language)
scam_flag                heuristic only; never a skip reason
message1_sent            true only if a confirmed outgoing fb_dm row exists
                          with status='sent' and template in
                          ('message1','availability_check_offerer',
                          'availability_check_offering','availability_check_seeker',
                          'availability_check_seeking') — the availability_check_*
                          names are legacy template names for the same stage
outreach_order           see "Resume rule" below; null when not in the active queue
availability_answer      'yes' | 'no' | 'unclear', defaults to 'no' if unanswered
answer1                  incoming reply text (never write outgoing text here)
answer2                  incoming reply text after message2 (never outgoing text)
message2                 stored second-message text, when a variant was selected
message2_sent            true only if a confirmed outgoing fb_dm row exists with
                          status='sent' and template='message2'
use_of_service_agreement
```

There is no `message3` column, template, or workflow anywhere in the schema
or skills today. If a third message stage is wanted, it needs to be designed
and approved before any skill references it.

### Resume rule (live LIFO, per poster)

`outreach_order` is recomputed on every query — it is not stored progress.
Only rows that are still eligible get a non-null order:

- poster is not `outreach_unavailable`;
- poster has no prior outgoing `fb_dm` row at all (any post, any status);
- the post's group has `clean_for_outreach=true`.

Eligible rows are numbered:

1. newest `Europe/Amsterdam` calendar day first;
2. within the day, confidence `high` before `medium` before `low`;
3. within that, newest `posted_at`/`seen_at` first;
4. post UUID as the final deterministic tie-break.

**The next candidate is always the row with the current lowest `outreach_order`
— row `1`.** Never resume from a remembered number, a sent-count, a Messenger
scroll position, `max(outreach_order)+1`, or the previous agent's report. Every
run re-queries the view from scratch.

`message1_sent=true` and `outreach_order is null` after a confirmed send is
the only valid "done" signal for that poster. `scam_flag=true` is never a skip
reason.

## Message sequence

- `message1` is the only default stage. It runs from `outreach-prep`.
- `message2` is a separate stage (`following-message`) that only runs when
  Kien explicitly asks, and only for posters with `availability_answer='yes'`.
- `answer1`/`answer2` are incoming replies; `message1`/`message2` are outgoing.
  These must never be cross-written.

## Classification rule ownership

Approved classification rules (offering/seeking, subtype, confidence,
scam heuristics, duplicate detection) live in version-controlled project
documents and the skills that own them (`docs/intent-logic.md`,
`analyze-insights`, `data-engineer`), with SQL implementing only deterministic
derivations of already-approved rules. When a rule or a specific
classification is not explicit, the agent preserves the raw evidence and
raises it to Kien instead of inventing a label or silently changing queue
behavior.

## Known open gap (2026-09-21)

158 `posts` rows share a `body_hash` with at least one other post, have no
`canonical_post_id`, and are **not** covered by `poster_duplicate_posts`. The
outreach view's duplicate filter only excludes rows that already have a
`poster_duplicate_posts` entry, so these 158 are not guaranteed to be
deduplicated before reaching `dashboardkien_outreach`. This needs an owner and
a rule (what counts as a true duplicate vs. a legitimate repost) before it can
be closed — see the open items raised alongside this document.
