---
name: outreach-prep
description: "Run the approved first-message Facebook outreach workflow from Supabase dashboardkien_outreach, resuming from the database and recording each confirmed outcome."
---

# outreach-prep

## Project and control surface

This is an automation button: it must run start-to-finish from the database
alone, with no briefing from Kien about who's next or what to send.

Supabase project ref `cteunhuxrghpozwbnehh`
(`https://cteunhuxrghpozwbnehh.supabase.co`). The operator-facing control view
is `public.dashboardkien_outreach`. You already know this — the project, the
view, and the underlying tables (`posts`, `posters`, `outreach_messages`,
`outreach_availability_answers`) are fixed facts about this project, not
something to rediscover each run. Do not substitute another Supabase project,
an old `sublet_*` table name, or a different view.

The only thing that can be missing is the *connection*. If Supabase MCP is
not connected to `cteunhuxrghpozwbnehh`, stop and ask Kien directly for the
missing secret — database password, service-role token, connection string,
whatever the specific failure needs. That is explicitly allowed. What is not
allowed is guessing a different project, printing a secret back into the
conversation, committing one to the repo, or sending a message without first
confirming the database connection is real (a send with no DB write behind it
is unverifiable and risks messaging the same person twice later).

This skill is for `message1` only. It must not send `message2` or a later
stage unless Kien explicitly requests that separate stage — see
`following-message` for `message2`.

## Why the resume logic works this way

`outreach_order` is not stored progress — `dashboardkien_outreach` recomputes
it on every query from live eligibility (no prior outgoing DM, poster not
`outreach_unavailable`, post's group `clean_for_outreach=true`). That is why
"the lowest current order" is always the correct next candidate and can never
drift: there is no counter to lose, no state to hand off between agents, and
no way for two different sessions to disagree about who's next as long as
both query fresh. Resuming from a remembered number or a Messenger scroll
position is the actual risk here — it can silently skip someone whose order
shifted (a group just went `clean_for_outreach=true`, or another poster
became ineligible) or double-message someone.

Right now the live queue can be entirely empty (`outreach_order is null` for
every row) whenever no group has both fully finished capture **and**
`validate-permalink` **and** `intent-analyze`. That is expected, not a
failure of this skill — report it plainly ("no eligible group yet, N groups
in `needs_recovery`") rather than treating an empty queue as an error to
work around.

## Browser automation channel

All Facebook actions in this skill must use Kien's already-open Chrome browser
through the host's visible browser automation panel. Reuse that logged-in
Chrome session and inspect its DOM/accessibility state before acting. Do not
open a separate browser profile, use headless automation, HTTP/API requests,
Selenium, or cookies outside Kien's Chrome session.

Use this skill for the first outreach message (`message1`). The database is the
source of truth. Do not infer progress from Messenger’s inbox position, a
count of sent messages, or a screenshot.

## Start and resume logic

1. Query `dashboardkien_outreach` and its internal source tables with
   `outreach_order`, ascending. Keep gaps; never renumber or sort by name.
2. For each order, treat the outcome as complete when either:
   - `message1_sent=true`, or an outgoing `fb_dm` row exists for that
     `poster_id` (including another post), or
   - the poster is explicitly marked `outreach_unavailable=true`.
3. Continue at the lowest `outreach_order` with neither completed outcome.
   Never calculate the next order as “last order + 1” or “number completed”.
4. Before acting on a candidate, re-query that row and check again for any
   outgoing `fb_dm` row. `scam_flag=true` never excludes a candidate.

The resume decision is always recalculated from the database at the start of a
run. Never use the previous agent's message, a Messenger inbox count, or
`max(outreach_order)+1`. The lowest eligible order is the next row.

## Send procedure

1. Open the stored `poster_profile_url` in the visible logged-in Facebook
   browser panel. Use the profile URL; do not navigate to the post unless the
   profile URL is missing or unusable.
2. Verify the displayed identity matches `poster_name`. Close the previous
   Messenger chat with its `X` before opening the next chat.
3. If the profile cannot be verified, the profile URL is unusable, or there is
   no usable Message/Nhắn tin action, write
   `posters.outreach_unavailable=true` and a concise
   `outreach_unavailable_reason`. Do not create an outreach row; continue in
   order.
4. Paste `dashboardkien_outreach.message1` exactly. Do not rewrite,
   personalize, translate, or substitute text.
5. Send only when the configured premessage/auto-send permission and the
   user's explicit authorization allow it. The UI must visibly show the
   message as sent. A pasted draft, loading state, or ambiguous composer is
   not a send.

## After a confirmed send

Only after visible send confirmation:

1. Insert one outgoing row into `outreach_messages` with the current
   `post_id`, `poster_id`, `direction='out'`, `channel='fb_dm'`,
   `template='message1'`, exact body, and `sent_at=now()`. `message1_sent` is
   computed from `template in ('message1', 'availability_check_offerer',
   'availability_check_offering', 'availability_check_seeker',
   'availability_check_seeking')` — the `availability_check_*` names are
   legacy values from before this stage was renamed; always write the current
   name, `message1`, for a new send.
2. If the table has a `status` column, set it to `sent`; if it does not, omit
   the column. Do not require `status` to exist.
3. Insert one `events` row with `event='outreach_dm_sent'`, the real actor
   (`agent` when the agent clicked Send, `human` when the user clicked Send),
   the post URL, and the message template.
4. Immediately re-query `dashboardkien_outreach` for that `poster_id` and
   require `message1_sent=true` before moving on. If verification fails,
   stop immediately and do not continue to the next person.

## Skip and stop rules

- Skip `message1_sent=true`.
- Skip any prior outgoing `fb_dm` row for the same `poster_id`, regardless of
  post or status. This applies even if `status` was removed from the schema.
- `scam_flag=true` is not a skip reason.
- Do not invent a daily or 24-hour DM limit.
- If Facebook shows login, checkpoint, CAPTCHA, unusual activity, or unclear
  send state, stop. Do not retry blindly and do not write a sent row.
- If the database fails, retry the exact query/write once; if it still fails,
  stop without partial bookkeeping.

## Stage boundary

The first-message workflow ends after the confirmed `message1` database
verification. A later-message workflow is a separate run and requires Kien's
explicit instruction. Do not infer that a reply means `message2` or `message3`
should be sent.

## Progress report

Report the completed outcomes (sent plus explicitly unavailable), the next
actual `outreach_order`, and any blocker. Always name the candidate and order;
never report only a count.
