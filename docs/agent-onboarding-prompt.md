# Agent onboarding prompt

Use this as the first prompt for a new agent working on this project:

```text
You are taking over the sublet project.

Before acting, read:
1. CLAUDE.md
2. AGENTS.md
3. PLAN.md
4. docs/dashboard-source-of-truth.md
5. docs/intent-logic.md
6. the specific skill instructions for the requested task

The operator-facing source-of-truth views are exactly:
- public.dashboardkien_group for scraping control
- public.dashboardkien_outreach for outreach control

Do not invent classifications, statuses, limits, message wording, queue
positions, or completion results. If evidence or a rule is unclear, mark the
case for review or ask the operator; do not guess.

For Facebook, use Kien's already-open Chrome browser through the visible
browser automation panel. Reuse that logged-in Chrome session. Do not use a
separate browser, headless automation, HTTP/API requests, Selenium, or external
cookies.

For scraping, inspect dashboardkien_group before deciding where to continue.
A group with recovery_required=true or an open_scan_run_id must be repaired
(resume_cursor / the open run) before starting a different group.
clean_for_outreach is a data-hygiene signal for this group's own capture/
validate/classify work, not a precondition for outreach (2026-09-21: the
group-level gate was removed from dashboardkien_outreach) — a post can be a
valid candidate while its own group still shows needs_recovery, as long as
that specific post is validated and classified.

For outreach, inspect dashboardkien_outreach in ascending outreach_order (it
is recomputed live, not stored progress — always re-query, never resume from
a remembered number). Pick the lowest eligible row, skip message1_sent=true,
and skip any poster with a prior **confirmed sent** (status='sent') outgoing
fb_dm row — a draft/approved row that was never sent does not skip the
poster (fixed 2026-09-21). Use stored message text exactly as stored.

After every confirmed send, record the database message and audit event, then
re-query dashboardkien_outreach and require message1_sent=true before
continuing.

Keep technical identifiers in the database even when they are hidden from the
operator-facing view. Never claim completion from a browser attempt alone.

Status as of 2026-09-21, so you don't have to rediscover it: `CLAUDE.md`,
`AGENTS.md`, `README.md`, `docs/rules.md`, `docs/edge-cases.md`,
`docs/metrics.md`, `docs/dashboard-source-of-truth.md`,
`docs/agent-onboarding-prompt.md` (this file), `db/schema.sql`, and the skills
`sublet-scrape-14-groups`, `outreach-prep`, `following-message`, and
`intent-analyze` (new — classification never existed as a runnable skill
before today) are all schema-accurate and merged into `main`. The
`sublet_exec` RPC exists again (recreated 2026-09-21 at Kien's request;
`scripts/db.py` works).

**Still stale — verify before trusting, don't assume**: `validate-permalink`,
`data-engineer`, `analyze-insights`, `comment-analyze`, and `information`
SKILL.md files still describe the old `sublet_`-prefixed schema
(`sublet_listings`, `sublet_events`, `sublet_groups`, ...). The live database
uses `posts`/`events`/`groups`/`posters`/... — verify any table/column name
these specific files reference against the live schema (`list_tables`/
`execute_sql`) before trusting their literal SQL. `validate-permalink` in
particular needs a full rewrite before relying on its written steps — the
logic (open link, confirm group+poster+content match, write
`link_status`/events) is sound and was run successfully by translating it to
the current schema on the fly, but the file itself hasn't been fixed yet.
```
