# Review cockpit/auto workflow docs and hand off follow-up to kimi-cockpit
Status: OPEN
Sender: kimai-cockpit
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-18 20:58 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@fd519aa
Evidence: VERIFIED (ls docs/specs/saja-akun-cli-workflow.md docs/guides/example-handoff-chain.md -> both exist)
Next: kimi-cockpit

## Goal
Review the new six-actor cockpit/auto handoff documentation from a consumer
perspective and produce a concrete follow-up handoff to `kimai-cockpit`.

## Files to review
1. `docs/specs/saja-akun-cli-workflow.md`
2. `docs/guides/example-handoff-chain.md`
3. `.ai/handoffs/README.md` (the new six-actor section)
4. `.ai/handoffs/template.md`

## Steps
1. Read the four files above.
2. Check for inconsistencies, unclear routing, or missing cases from a
   frontend/auto pane point of view.
3. Decide whether the docs are ready to use as-is, need corrections, or need
   a worked frontend-only example.
4. Create a handoff in `.ai/handoffs/to-kimai/open/` that routes back to
   `kimai-cockpit`.

   The handoff should be one of:
   - **APPROVED with no changes** — `Status: DONE` in your own
     `.ai/handoffs/to-kiro/done/` plus a `to-kimai/open/` handoff that says
     "docs approved, no follow-up work".
   - **REQUEST changes** — `Status: DONE` in your own `done/` plus a
     `to-kimai/open/` handoff listing exact corrections needed.
   - **BLOCKED** — leave this file in `to-kiro/open/` with `Status: BLOCKED`
     and a `## Blocker` section, and do NOT create a follow-up handoff until
     unblocked.

5. Self-retire this handoff to `.ai/handoffs/to-kiro/done/` once the
   `to-kimai/open/` handoff exists.

## Verification
- (a) You can paraphrase the routing table in `docs/specs/saja-akun-cli-workflow.md`.
- (b) The follow-up handoff file exists in `.ai/handoffs/to-kimai/open/`.

## Report back with
- (a) Your verdict (approved / changes-requested / blocked)
- (b) Path to the follow-up handoff you created
- (c) Any specific corrections, if changes-requested

## When complete
Recipient self-retires this handoff to `to-kiro/done/`.
