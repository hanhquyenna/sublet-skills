---
name: outreach-prep
description: "Prepare the first-message Facebook outreach DM from Supabase dashboardkien_outreach, in strict outreach_order — agent pastes message1 and stops, Kien clicks Send, agent then records the confirmed outcome."
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
conversation, committing one to the repo, or preparing a message without
first confirming the database connection is real (a prepared message with no
way to record its outcome risks messaging the same person twice later).

This skill is for `message1` only. It must not prepare `message2` or a later
stage unless Kien explicitly requests that separate stage — see
`following-message` for `message2`.

## Agent prepares, Kien sends — the definitive model (2026-09-18)

The agent never clicks Send. It automates everything time-consuming — reading
the queue, opening the right post, verifying identity, opening Messenger,
typing the exact message — then stops with the message sitting in the
composer and hands off. There is no `auto_dm` flag and no "agent sends the
whole queue autonomously" mode; that idea is retired. This is not a
config toggle, it is a hard rule of this skill: no request, however phrased,
enables the agent to click Send itself. If asked to, refuse and point back to
this section.

Paste-and-wait-for-Kien is the *only* write exception to "Facebook is
read-only" — and even that exception still requires Kien's own click.

## Why the resume logic works this way

`outreach_order` is not stored progress — `dashboardkien_outreach` recomputes
it on every query from live, per-post eligibility (post itself validated +
classified + recent + not a duplicate, poster not `outreach_unavailable`, no
prior confirmed-sent DM). That is why "the lowest current order" is always
the correct next candidate and can never drift: there is no counter to lose,
no state to hand off between agents, and no way for two different sessions to
disagree about who's next as long as both query fresh. Resuming from a
remembered number or a Messenger scroll position is the actual risk here — it
can silently skip someone whose order shifted (a post just got validated or
classified, or another poster became ineligible) or double-message someone.

**Eligibility is per-post, not per-group** (2026-09-21 — the group-level
`clean_for_outreach` requirement was removed from the view). A post from a
group that's still `needs_recovery` can be a perfectly valid candidate the
moment that specific post is validated and classified; don't wait for or
report on the group's overall completion as a precondition for outreach. If
the queue is empty, the real blocker is almost certainly `validate-permalink`/
`intent-analyze` backlog on individual posts, not unfinished groups — report
the actual unvalidated/unclassified counts, not "N groups in needs_recovery."

There is a separate `posts.outreach_order` column — a legacy stored field,
kept permanently `null`, not the same thing as `dashboardkien_outreach.outreach_order`
above. Never read it, never write to it. Only the computed view column means
anything.

## Browser automation channel

All Facebook actions in this skill must use Kien's already-open Chrome browser
through the host's visible browser automation panel. Reuse that logged-in
Chrome session and inspect its DOM/accessibility state before acting. Do not
open a separate browser profile, use headless automation, HTTP/API requests,
Selenium, or cookies outside Kien's Chrome session.

Use this skill for the first outreach message (`message1`). The database is
the source of truth. Do not infer progress from Messenger's inbox position, a
count of sent messages, or a screenshot.

## Start and resume logic

1. Query `dashboardkien_outreach` with `outreach_order`, ascending. Keep gaps;
   never renumber or sort by name.
2. For each order, treat the outcome as complete when either:
   - `message1_sent=true` (a confirmed `status='sent'` row already exists for
     this poster, on this post or another), or
   - the poster is explicitly marked `outreach_unavailable=true`.
3. Continue at the lowest `outreach_order` with neither completed outcome.
   Never calculate the next order as "last order + 1" or "number completed."
4. Before acting on a candidate, re-query that row and check again for a
   confirmed-sent row. `scam_flag=true` never excludes a candidate.

The resume decision is always recalculated from the database at the start of
a run. Never use the previous agent's message, a Messenger inbox count, or
`max(outreach_order)+1`. The lowest eligible order is the next row.

## Preparing a DM

1. Open the stored `poster_profile_url` in the visible logged-in Facebook
   browser panel. Use the profile URL; do not navigate to the post unless the
   profile URL is missing or unusable.
2. Verify the displayed identity matches `poster_name`. Close the previous
   Messenger chat with its `X` before opening the next chat.
3. If the profile cannot be verified, the profile URL is unusable, or there
   is no usable Message/Nhắn tin action, write `posters.outreach_unavailable=true`
   and a concise `outreach_unavailable_reason`. Do not create an outreach row;
   continue in order.
4. Open Messenger and paste `dashboardkien_outreach.message1` exactly. Do not
   rewrite, personalize, translate, or substitute text.
5. **Stop here.** Tell Kien: "Ready to send to `<poster_name>` — message is
   pasted, click Send when ready." The agent does not click Send, does not
   assume Kien will, and does not move on by itself.
6. Wait for Kien to confirm the click (Kien says so, or the agent observes
   the UI change after Kien's click — but the click itself is always Kien's).
   If Kien doesn't click (changed their mind, paused, no response), or the UI
   errors, or a checkpoint/CAPTCHA/login/unusual-activity prompt appears, or
   it's unclear whether it sent: stop, write nothing, report the state, and
   do not move to the next candidate without a clear decision from Kien.

## After a confirmed send

Only after Kien has visibly clicked Send and the UI confirms it sent:

1. Insert one outgoing row into `outreach_messages` with the current
   `post_id`, `poster_id`, `direction='out'`, `channel='fb_dm'`,
   `template='message1'`, exact body, `status='sent'`, `sent_at=now()`. One
   insert per send — never a draft-then-update. `message1_sent` is computed
   from `status='sent'` and `template in ('message1', 'availability_check_offerer',
   'availability_check_offering', 'availability_check_seeker',
   'availability_check_seeking')` — the `availability_check_*` names are
   legacy values from before this stage was renamed; always write the current
   name, `message1`, for a new send.
2. Insert one `events` row with `event='outreach_dm_sent'`, `actor='human'`
   (Kien performed the send; the agent only prepared it), the post URL, and
   the message template.
3. Immediately re-query `dashboardkien_outreach` for that `poster_id` and
   require `message1_sent=true` before moving on. If verification fails, stop
   immediately and do not continue to the next person.

## Skip and stop rules

- Skip `message1_sent=true`.
- Skip a poster with a prior **confirmed sent** (`status='sent'`) outgoing
  `fb_dm` row, regardless of which post it was attached to. **A draft or
  approved row that was never actually sent does NOT skip the poster** —
  2026-09-21 fix: 11 real posters were previously stuck forever behind a
  stale, abandoned draft with no real message ever sent. Only `status='sent'`
  counts as "already outreached," the same standard `message1_sent` itself
  uses.
- `scam_flag=true` is not a skip reason — prepare it like any other candidate.
- Do not invent a daily or 24-hour DM cap. None exists, and none is needed:
  Kien clicks every single send personally, so there is no runaway-agent
  volume to throttle.
- If Facebook shows login, checkpoint, CAPTCHA, unusual activity, or unclear
  send state, stop. Do not retry blindly and do not write a sent row.
- If the database fails, retry the exact query/write once; if it still fails,
  stop without partial bookkeeping.

## Stage boundary

The first-message workflow ends after the confirmed `message1` database
verification. A later-message workflow is a separate run and requires Kien's
explicit instruction. Do not infer that a reply means `message2` or a
`message3` (no such stage exists in the schema) should be prepared.

## Progress report

Report the completed outcomes (sent plus explicitly unavailable), any
candidate currently waiting on Kien's click, the next actual
`outreach_order`, and any blocker. Always name the candidate and order; never
report only a count.
