---
name: following-message
description: "Verify Facebook replies, record answer1 and availability, and send the correct message2 to eligible posters."
---

# following-message

Use this skill after first outreach to process replies and follow-up message2.
The database is authoritative for identity, order, intent, language, and
whether a follow-up was sent. Messenger is evidence only when the correct
conversation and sender are visibly verified.

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

Before sending, skip anyone who already has an outgoing `fb_dm` row with
`template='message2'` for that `poster_id`. If the schema has a `status`
column, any prior outgoing row still counts as existing; if not, use row
existence.

After visible send confirmation:

1. Insert one outgoing `outreach_messages` row with `template='message2'`,
   exact body, `post_id`, `poster_id`, `direction='out'`, `channel='fb_dm'`,
   and `sent_at=now()`.
2. Insert one `events` audit row with `event='outreach_dm_sent'` and the real
   actor (`agent` or `human`).
3. Re-query `dashboardkien_outreach` immediately and require both
   `has_outreached=true` and `message2_sent=true` before continuing.

If sending is unclear, do not insert anything. If DB verification fails, stop
before the next person. Do not invent a daily or 24-hour limit.

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
