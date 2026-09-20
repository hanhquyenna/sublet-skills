# Dashboard source of truth

This document describes the operator-facing control surfaces for the current
Supabase project. It does not replace the database schema or invent
classification rules.

## Operator-facing views

The operator controls the workflow through exactly these two views:

- `public.dashboardkien_group` — scraping control.
- `public.dashboardkien_outreach` — outreach control.

Other tables are implementation data. Agents may read them when needed, but
their decisions and results must be explainable from one of these two views.

## `dashboardkien_outreach` visible shape

The visible view intentionally hides technical join and classification-detail
columns. The underlying data is not deleted.

The current visible columns are:

```text
poster_name
poster_profile_url
post_link
post_text
intent
link_status
message1
scam_flag
has_outreached
outreach_order
availability_answer
answer1
answer2
message2
message2_sent
use_of_service_agreement
```

The hidden columns include the technical identifiers and fields removed from
the view by the operator: `poster_id`, `poster_type`, `post_id`, `group_id`,
`group_name`, `subtype`, `confidence`, `areas`, `price_eur`,
`available_from`, `available_to`, `requirements`, `registration_allowed`,
`canonical_post_id`, `seen_at`, `analyzed_at`, `language`, `poster_url_kind`,
and `answer2_at`.

These fields remain available internally for joins, deduplication, ordering,
and audit history.

## Outreach resume rule

`outreach_order` is the queue order. It must be read in ascending order.

The next first-message candidate is the lowest-order row that:

1. is not already marked `has_outreached=true`; and
2. has no prior outgoing `fb_dm` row for the same `poster_id`.

The agent must not resume from a count or from conversation memory. It must
query the view and the outgoing-message history again at the start of every
run.

After a confirmed Facebook send, the agent records the message and audit event
and immediately re-queries the view. It continues only when the expected
outreach result is visible in the database.

If profile identity, message availability, send confirmation, or a data
classification is unclear, the agent must not guess. It must leave the case for
review rather than silently changing the queue.

## Message sequence

The conversation fields have different meanings:

- `message1`, `message2`, and any later message field are outgoing messages.
- `answer1` and `answer2` are incoming replies.
- `availability_answer` is a separate existing field and must not be silently
  reinterpreted.

The exact conditions for sending a later message are not defined here unless
they are explicitly approved in the outreach rules.

## Scraping control

`dashboardkien_group` is the control view for scraping. Before changing or
resuming a group, the agent must inspect its current row and use the recorded
database state rather than assume the group is complete or incomplete.

The following are facts to report from the view when available:

- last scan time
- captured-post counts
- unresolved count
- classification counts
- scrape status
- resolution percentage

If the data does not establish where to continue, the agent must report the
ambiguity and ask for clarification. It must not manufacture a checkpoint.

## Classification rule ownership

Classification rules are maintained in version-controlled project documents,
not only in SQL and not only in an agent prompt. Existing project documents
remain authoritative where they are consistent with the live schema. Conflicts
with the live schema must be reported before changing behavior.

Rules that are uncertain or not explicitly approved are `needs_review`; they
are not silently converted into a new status or automatic decision.
