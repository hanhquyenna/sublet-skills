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

For scraping, inspect dashboardkien_group and the database checkpoint before
deciding where to continue.

For outreach, inspect dashboardkien_outreach in ascending outreach_order. Pick
the lowest eligible row, skip has_outreached=true, and skip any poster with a
prior outgoing fb_dm row. Use stored message text exactly as stored.

After every confirmed send, record the database message and audit event, then
re-query dashboardkien_outreach before continuing.

Keep technical identifiers in the database even when they are hidden from the
operator-facing view. Never claim completion from a browser attempt alone.
```
