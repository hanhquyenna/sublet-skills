---
name: following-message
description: "Verify Facebook replies, record answer1 and availability, and send the correct message2 to eligible posters."
---

# following-message

## Project and control surface

Supabase project ref `cteunhuxrghpozwbnehh`
(`https://cteunhuxrghpozwbnehh.supabase.co`). The operator-facing control view
is `public.dashboardkien_outreach`, same as `outreach-prep`. You already know
the project and the view; the only thing that can be missing is the
connection. If Supabase MCP is not connected to `cteunhuxrghpozwbnehh`, stop
and ask Kien directly for the missing secret (password/token/connection
string) rather than guessing a project or proceeding without a working DB
write path.

Use this skill only after first outreach, and only when Kien explicitly asks
for the `message2` follow-up stage — it is never triggered automatically by a
reply arriving. The database is authoritative for identity, order, intent,
language, and whether a follow-up was sent. Messenger is evidence only when
the correct conversation and sender are visibly verified.

`message2_sent` is computed the same way `message1_sent` is: a confirmed
outgoing `outreach_messages` row with `status='sent'` and the right
`template`. Always write `template='message2'` for a new send — that is the
only value the view currently recognizes for this stage.

## Find and verify replies

1. Read `dashboardkien_outreach` in `outreach_order` order. Use the stored
   `poster_profile_url` and the Messenger conversation linked to that person.
2. Close the previous chat before opening another one. Verify the visible
   profile/thread identity against `poster_name`; do not match by a display
   name alone when it is ambiguous.
3. A reply counts only when the incoming message is visibly from that person.
   Do not treat our own outgoing message, a preview snippet, an unread dot,
   stale accessibility text, or a screenshot from another thread as a reply.
4. If database data and Messenger evidence conflict, do not guess. Preserve
   the database record, report the conflict, and do not send message2 until a
   fresh matching conversation resolves it.

## Record answer1, answer2, and availability

For each verified incoming reply, determine its sequence in the matching
thread before writing. The first incoming reply after `message1` belongs in
`answer1`; an incoming reply that is visibly after our sent `message2` belongs
in `answer2`. Never overwrite `answer1` with a later reply and never use the
conversation-list preview alone to infer sequence.

Upsert `outreach_availability_answers` by `poster_id` with:

- the exact visible first reply in `answer1`, or the exact later reply in
  `answer2` with `answer2_at=now()`;
- preserve existing verified `answer1` and `answer2` values unless a fresh
  thread view proves the stored text is wrong;
- `availability_answer='yes'` only when the reply clearly confirms current
  availability or intent to continue;
- `availability_answer='no'` only when it clearly declines, is no longer
  looking, or is not offering the relevant place;
- otherwise use the schema's `unclear` value and do not force yes/no;
- `message2` copied from the dashboard’s selected variant;
- `updated_at=now()`.

Replies after `message2` must not change the original availability decision
unless they explicitly correct it. They are follow-up content for `answer2`.

Never overwrite a verified answer with an unverified inbox preview. A message
like “hello, yes” is evidence of yes only when it is visibly an incoming
message in the matching conversation.

## Choose and send message2

Only `availability_answer='yes'` candidates qualify.

- `intent='seeking'`: use the stored seeker message2.
- `intent='offering'`: use the stored offerer message2.
- Match the stored language. Do not infer a different language from the
  browser UI.
- Paste the exact stored `message2`; do not rewrite or personalize it.

Before sending, skip anyone who already has a **confirmed sent**
(`status='sent'`) outgoing `fb_dm` row with `template='message2'` for that
`poster_id`. A draft/approved row that was never actually sent does not skip
the poster — same standard `message2_sent` itself uses, and the same
2026-09-21 fix applied to `outreach-prep`'s message1 logic.

**Same send model as `outreach-prep`: the agent pastes `message2` into
Messenger and stops — it never clicks Send.** Tell Kien it's ready and wait
for Kien's own click. Only after Kien has visibly clicked Send and the UI
confirms it:

1. Insert one outgoing `outreach_messages` row with `template='message2'`,
   exact body, `post_id`, `poster_id`, `direction='out'`, `channel='fb_dm'`,
   `status='sent'`, and `sent_at=now()`.
2. Insert one `events` audit row with `event='outreach_dm_sent'`,
   `actor='human'` (Kien performed the send; the agent only prepared it).
3. Re-query `dashboardkien_outreach` immediately and require both
   `message1_sent=true` and `message2_sent=true` before continuing.

If Kien doesn't click, or sending is unclear, do not insert anything —
report the state and stop on that candidate. If DB verification fails, stop
before the next person. Do not invent a daily or 24-hour limit — Kien clicks
every send personally, there's no agent-volume to cap.

## Inbox scanning

When scanning Messenger, move from newest toward the requested date and stop
only at a clearly identified already-recorded boundary if the user asks for
that. A conversation-list row showing “You:” or our message2 is not proof of
an incoming reply; open the conversation when classification matters. Facebook
“missing chat history”, loading placeholders, or a stale thread is a blocker,
not evidence of no reply.

Report separately:

- verified replies recorded;
- yes/no/unknown classifications;
- message2 sends confirmed and verified;
- conversations not verifiable because Messenger history or identity was
  unavailable.
