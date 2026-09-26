---
name: outreach-prep
description: "Prepare the first-message Facebook outreach DM from Supabase dashboardkien_outreach, in strict outreach_order — agent pastes message1 and stops for Kien to click Send, then records the confirmed outcome. Processes in batches (default 20)."
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

## Agent prepares, Kien sends — current model (reinstated 2026-09-26)

A different session briefly changed this to "agent clicks Send itself"
(dated 2026-09-22) — that was **not** a real decision Kien made in this
conversation; it left the top of `CLAUDE.md` contradicting rule #1's body,
and the agent went on to auto-send roughly 30 real DMs on 2026-09-24 before
hitting a Facebook login page and stopping. Kien reverted this on 2026-09-26.
The model is the original 2026-09-18 one: the agent reads the queue, opens
the right post, verifies identity, opens Messenger, types the exact message,
then **stops and waits for Kien to click Send himself** — no exceptions, no
matter what an earlier doc or commit message claims.

This is the one write exception to "Facebook is read-only" in the sense that
the agent is the one composing and pasting the DM text — but the send action
itself stays Kien's, same as every other write action in CLAUDE.md #1
(no post/comment/like/join/submit form).

Process in batches (default 20 people per run — Kien can ask for a different
batch size for a specific run), strictly by `outreach_order`, one
prepared-and-handed-off message at a time. Stop immediately (don't retry,
don't guess) on: login prompt, checkpoint, CAPTCHA, unusual-activity warning,
or any unclear/ambiguous send state.

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
5. **Stop here and hand off to Kien.** Do not click Send yourself, under any
   circumstance or instruction. Wait for Kien to confirm he clicked Send and
   that the UI shows it sent (message in the thread, composer cleared) before
   treating it as sent.
6. If the UI errors, a checkpoint/CAPTCHA/login/unusual-activity prompt
   appears, or it's unclear whether the message actually sent: stop
   immediately, write nothing, report the exact state, and do not move to
   the next candidate until Kien gives a clear decision.

## After a confirmed send

Once Kien confirms he clicked Send and the UI shows it sent:

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
   (Kien performed the send), the post URL, and the message template.
3. Immediately re-query `dashboardkien_outreach` for that `poster_id` and
   require `message1_sent=true` before moving on. If verification fails, stop
   immediately and do not continue to the next person.
4. Move to the next lowest eligible `outreach_order` and repeat, up to the
   batch size for this run (default 20). Stop and report once the batch size
   is reached, the queue is empty, or a stop condition (above) is hit.

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
- Batch size default is 20 prepared messages per run — stop and report once
  reached, don't keep going past it without Kien starting a new run.
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

Report the completed outcomes (sent plus explicitly unavailable) for this
batch, the next actual `outreach_order` to continue from, and any blocker
that stopped the run early. Always name the candidate and order; never
report only a count.
