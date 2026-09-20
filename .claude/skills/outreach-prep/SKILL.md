---
name: outreach-prep
description: "Send the first Facebook outreach message from dashboardkien_outreach in strict outreach_order, recording every confirmed outcome."
---

# outreach-prep

Use this skill for the first outreach message (`message1`). The database is the
source of truth. Do not infer progress from Messenger’s inbox position, a
count of sent messages, or a screenshot.

## Start and resume logic

1. Query `dashboardkien_outreach` and its underlying persistent source with
   `outreach_order`, ascending. Keep gaps; never renumber or sort by name.
2. For each order, treat the outcome as complete when either:
   - `has_outreached=true`, or an outgoing `fb_dm` row exists for that
     `poster_id` (including another post), or
   - the poster is explicitly marked `outreach_unavailable=true`.
3. Continue at the lowest `outreach_order` with neither completed outcome.
   Never calculate the next order as “last order + 1” or “number completed”.
4. Before acting on a candidate, re-query that row and check again for any
   outgoing `fb_dm` row. `scam_flag=true` never excludes a candidate.

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
   `post_id`, `poster_id`, `direction='out'`, `channel='fb_dm'`, the correct
   first-message template, exact body, and `sent_at=now()`.
2. If the table has a `status` column, set it to `sent`; if it does not, omit
   the column. Do not require `status` to exist.
3. Insert one `events` row with `event='outreach_dm_sent'`, the real actor
   (`agent` when the agent clicked Send, `human` when the user clicked Send),
   the post URL, and the message template.
4. Immediately re-query `dashboardkien_outreach` for that `poster_id` and
   require `has_outreached=true` before moving on. If verification fails,
   stop immediately and do not continue to the next person.

## Skip and stop rules

- Skip `has_outreached=true`.
- Skip any prior outgoing `fb_dm` row for the same `poster_id`, regardless of
  post or status. This applies even if `status` was removed from the schema.
- `scam_flag=true` is not a skip reason.
- Do not invent a daily or 24-hour DM limit.
- If Facebook shows login, checkpoint, CAPTCHA, unusual activity, or unclear
  send state, stop. Do not retry blindly and do not write a sent row.
- If the database fails, retry the exact query/write once; if it still fails,
  stop without partial bookkeeping.

## Progress report

Report the completed outcomes (sent plus explicitly unavailable), the next
actual `outreach_order`, and any blocker. Always name the candidate and order;
never report only a count.
