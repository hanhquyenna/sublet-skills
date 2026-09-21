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
(resume_cursor / the open run) before starting a different group. Only
clean_for_outreach=true groups feed the outreach queue.

For outreach, inspect dashboardkien_outreach in ascending outreach_order (it
is recomputed live, not stored progress — always re-query, never resume from
a remembered number). Pick the lowest eligible row, skip message1_sent=true,
and skip any poster with a prior outgoing fb_dm row. Use stored message text
exactly as stored.

After every confirmed send, record the database message and audit event, then
re-query dashboardkien_outreach and require message1_sent=true before
continuing.

Keep technical identifiers in the database even when they are hidden from the
operator-facing view. Never claim completion from a browser attempt alone.

Warning: several SKILL.md files in this repo (sublet-scrape-14-groups,
data-engineer, validate-permalink, analyze-insights, comment-analyze,
information) and CLAUDE.md/AGENTS.md still describe the old sublet_-prefixed
table names (sublet_listings, sublet_events, sublet_groups, ...). The live
database was renamed to posts/events/groups/posters/... without those docs
being updated, and the sublet_exec RPC that scripts/db.py relies on no longer
exists. Verify a table/column/RPC name against the live schema (list_tables /
execute_sql) before trusting a skill's literal SQL reference; do not assume
the skill text matches the database.
```
