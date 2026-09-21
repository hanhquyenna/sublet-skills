---
name: intent-analyze
description: "Classify captured posts into offering/seeking/other per docs/intent-logic.md, writing intent/subtype/confidence/poster_type onto the live schema. DB-only, no Facebook."
---

# intent-analyze

DB-only classification pass. Reads `posts` where `intent is null`, writes
`intent`/`subtype`/`confidence` on `posts`, `type` on `posters`, and the
structured fields (`room_type`/`price_eur`/`available_from`/...) on
`post_details`. Never opens Facebook, never sends outreach.

## Rules live in one place

All classification judgment (offering vs seeking, subtype, confidence) is
defined in `docs/intent-logic.md` — read it before classifying, don't
improvise from memory. This skill only maps that already-approved logic onto
the current schema; it does not invent new rules. If a post doesn't clearly
fit the documented signals, follow §3/§10's explicit fallback (`other`,
`confidence='low'`) rather than guessing.

## Scope (current schema, 2026-09-21)

Only classify and write these — everything else in `docs/intent-logic.md` is
either out of scope by standing decision or doesn't have a column yet:

- `posts.intent`, `posts.subtype`, `posts.confidence` — §0–§6, §10.
- `posters.type` (`individual`/`company`/`anonymous`) — §6's `poster_type`,
  renamed. Note: the old `proxy` value merges into `individual`; `agency`
  renamed to `company` (2026-09-17 decision, already reflected in the
  `posters.type` check constraint).
- `post_details.room_type`, `price_eur`, `deposit_eur`, `available_from`,
  `available_to`, `registration_allowed`, `sublet_permission`, `max_people`,
  `bills_included`, `requirements` (was `poster_constraints`) — §11.
- `posts.status='dead'` when the post text itself says so — §6.

**Do not compute `scam_score`/`scam_flags`** (§8) or `deal_score` (§7) —
standing Kien decision, left at their defaults (`scam_score=0`,
`scam_flags='{}'`). `deal_score` has no column in the current schema at all.
**Do not create seeker rows** (§5's "Tạo seeker?" column) — no seekers/demand
table exists yet; that's a future WhatsApp-intake feature, out of scope until
Kien builds it. Just set `subtype` for seeking posts as documented; skip the
seeker-creation half of §5.

## Read

```sql
select p.id, p.body, p.language, p.seen_at, po.id as poster_id, po.name as poster_name
from posts p left join posters po on po.id = p.poster_id
where p.intent is null
order by p.seen_at;
```

A post with `poster_id is null` (anonymous or unrecoverable) can still be
classified — `intent`/`subtype`/`confidence` live on `posts`, not on the
poster. Just skip the `posters.type` write for those.

## Classify and write

Per post, apply `docs/intent-logic.md` §0–§2 to decide `offering`/`seeking`/
`other`, then the matching subtype table (§4 offering, §5 seeking — subtype
only, no seeker row), then §10 for confidence, then §11 for field
normalization (dates, price, area). Write:

```sql
update posts set intent = $intent, subtype = $subtype, confidence = $confidence,
  status = case when $post_says_dead then 'dead' else status end,
  analyzed_at = now()
where id = $post_id;

update posters set type = $poster_type where id = $poster_id;  -- skip if poster_id null

insert into post_details (post_id, room_type, price_eur, deposit_eur,
  available_from, available_to, registration_allowed, sublet_permission,
  max_people, bills_included, requirements)
values ($post_id, ...)
on conflict (post_id) do update set
  room_type = excluded.room_type, price_eur = excluded.price_eur, ...,
  updated_at = now();
```

A field with no evidence in the text is `null`/`unknown` per §11 — never a
guessed default. `requirements` (was `poster_constraints`) is stored verbatim,
never scored — §9's rule against ranking by gender/age/nationality/language
applies here directly: this field is for Kien to read, not for any skill to
filter candidates on.

## Do not

- Guess intent from a name, photo, or unrelated context — only the post text.
- Backfill `scam_score`, `deal_score`, or a seeker row (out of scope, see above).
- Re-classify a post that already has `intent` set, even to "improve" it —
  a correction needs an explicit reason and should be a deliberate edit, not
  a routine re-run silently overwriting a prior classification.
- Open Facebook for any reason — this is DB-only, same boundary as
  `data-engineer`/`analyze-insights`.

## After classifying

Report per post: `poster_name` (or "anonymous"), `intent`, `subtype`,
`confidence`, and one line of why (which signal from `docs/intent-logic.md`
triggered it) — not just a count. If DB write fails, retry once after 5s;
still failing, stop and report which posts are done vs. still pending.
