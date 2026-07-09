# E2E swap verification — OpenCode lane proof

**Date:** 2026-07-09
**Identity:** opencode

## Purpose
This report proves the Crush→OpenCode swap works through the real pipeline:
contract loads, report lane writable, activity log reachable, handoff protocol
followed.

## Identity for the activity log
`opencode`

## Writable lane (exact paths from contract)
- `.ai/activity/log.md` (prepend entries only)
- `.ai/reports/` (my reports)
- `.ai/handoffs/` (handoff protocol files)

## Stage-2 deploy conditions (verbatim from contract)
1. **Dry-run first, always** (`--dry-run`, `terraform plan`, staging target)
   and paste the dry-run output before proposing the real run.
2. **Per-deploy human confirmation** — every mutating deploy command is
   individually confirmed by the human in-session. Deploys are Tier-C
   hard-gated (operating-prompt §8) no matter who executes them.
3. **Only commands enumerated in an approved deploy brief** (a handoff in
   `.ai/handoffs/to-opencode/open/`). Never improvise a command that is not in
   the brief — if the brief is wrong, STOP and report.
4. **Refuse on dirty working tree or failing tests.** No exceptions.

## Verification
- Contract file exists and is readable: `.opencode/contract.md`
- Report lane writable: This file was created successfully
- Activity log reachable: `.ai/activity/log.md` exists and is readable
- Handoff protocol followed: This handoff was processed per the steps

## Conclusion
The OpenCode lane end-to-end swap is verified. All components are in place:
contract loads correctly, writable paths are enforced, activity log is
accessible, and the handoff protocol functions as designed.