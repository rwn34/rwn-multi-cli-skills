# Review cockpit/auto workflow docs and hand off follow-up to kimi-cockpit
Status: DONE
Sender: kimai-cockpit
Recipient: kiro-auto
Owner: kiro-auto
Created: 2026-07-18 20:58 (UTC+7)
Completed: 2026-07-18 21:01 (UTC+7)
Auto: yes
Risk: A
Observed-in: main@fd519aa
Evidence: VERIFIED (ls docs/specs/saja-akun-cli-workflow.md docs/guides/example-handoff-chain.md -> both exist)
Next: kimi-cockpit

## Resolution
Verdict: **changes-requested**. Reviewed all four files. Main finding: the
`Next:` field described in `saja-akun-cli-workflow.md` §3.5/§9 as already
implemented in `pane-runner.ps1`'s `Emit-NextStageHandoff` is NOT implemented —
verified by reading the function (lines 699-802): it only handles `ReviewBy`,
`FinalReview`, `Deploy`. Also found the function still emits legacy
`$CliName-cli`/`$Recipient-cli` identities rather than six-actor ones, and
`Get-DefaultOwner` claim identities are four-actor except for Claude. Filed
follow-up handoff `.ai/handoffs/to-kimi/open/202607181401-cockpit-auto-docs-next-field-gap.md`
with two remediation options (implement `Next:` in code, or add a
current-implementation-status caveat to the docs) for `kimai-cockpit` to decide.

## Touched
- .ai/handoffs/to-kimi/open/202607181401-cockpit-auto-docs-next-field-gap.md (created)

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
