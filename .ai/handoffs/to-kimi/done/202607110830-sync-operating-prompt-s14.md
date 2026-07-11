# Sync operating-prompt §14 (delegation economics) into Kimi steering
Status: DONE
Completed: 2026-07-11 22:24 — kimi-cli. Touched: .kimi/steering/operating-prompt.md
(byte-identical copy of SSOT), .ai/activity/log.md (entry prepended). Committed
on branch kimi/sync-operating-prompt-s14 @ 4c924ec. Drift check: 0/24.
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 15:30
Auto: yes
Risk: A

## Goal
The SSOT `.ai/instructions/operating-prompt/principles.md` gained a new **§14 —
Delegation economics** (owner directive 2026-07-11) plus a pointer bullet in §4.
Your steering replica `.kimi/steering/operating-prompt.md` is now drift-flagged
against it. Regenerate the replica so `.ai/tools/check-ssot-drift.sh` passes.

## Current state
- SSOT (updated, authoritative): `.ai/instructions/operating-prompt/principles.md`
  — now ends with `## 14. Delegation economics — route by capacity, not by convenience`
  before the closing `**Remember:**` block, and §4 has a new final bullet
  beginning `- **Lanes say who MAY do the work; §14 ...`.
- Your replica (stale): `.kimi/steering/operating-prompt.md`.
- Claude's replica is already regenerated (`.claude/skills/operating-prompt/SKILL.md`)
  — Kiro is regenerating theirs in parallel via a sibling handoff.

## Target state
`.kimi/steering/operating-prompt.md` is byte-identical to the SSOT body per
`.ai/sync.md` (your steering file is a straight full-file copy — no frontmatter
to preserve, unlike Claude's SKILL.md).

## Steps
1. Read `.ai/instructions/operating-prompt/principles.md` (the SSOT).
2. Regenerate your replica, exactly as `.ai/sync.md` prescribes:
   `cp .ai/instructions/operating-prompt/principles.md .kimi/steering/operating-prompt.md`
3. Do NOT edit the SSOT, and do NOT touch `.claude/**` or `.kiro/**`.
4. Commit on a feature branch (`kimi/sync-operating-prompt-s14`) via your
   `infra-engineer`. Do not merge to main (Tier C — Claude gates).

## Verification
- (a) EXECUTE `bash .ai/tools/check-ssot-drift.sh` and paste the output — it must
      report no drift for `operating-prompt` (other entries, if any, are not yours
      to fix here; report them but do not touch them).
- (b) EXECUTE `grep -n "14. Delegation economics" .kimi/steering/operating-prompt.md`
      and paste the matching line.
- (c) Confirm the §4 pointer bullet landed:
      `grep -n "Lanes say who MAY do the work" .kimi/steering/operating-prompt.md`

## What §14 means for you (read it, it changes your workload)
You are the **default executor** of this fleet — highest token cap ($200 plan).
Claude's budget is the smallest, so it will now route bulk implementation, test
authoring/execution, mechanical refactors, and sweeps to you by default instead
of using its own subagents. Expect more inbound handoffs. Lane boundaries are
unchanged: no merges to main, no ADR authorship, no deploys.

## Next step / future note
After this, every SSOT edit means three replica syncs (Claude self-serves; Kimi
and Kiro get handoffs). What breaks first: this is manual and drift is only
caught by the gate *after* the fact — if SSOT edits get frequent, the durable fix
is a sync script that regenerates all three replicas in one pass, with the gate
as backstop rather than as the discovery mechanism.

## Activity log template
    ## 2026-07-11 HH:MM — kimi-cli
    - Action: Synced operating-prompt §14 (delegation economics) into .kimi/steering per handoff 202607110830-sync-operating-prompt-s14
    - Files: .kimi/steering/operating-prompt.md
    - Decisions: —

## Report back with
- (a) the replica path you wrote
- (b) pasted `check-ssot-drift.sh` output (not a summary)
- (c) pasted grep evidence for (b) and (c) above
- (d) the branch name + commit sha

## When complete (protocol v3)
Self-retire: set Status to `DONE` and move this file to
`.ai/handoffs/to-kimi/done/`. If blocked, leave it in `open/` as `BLOCKED` with a
verbatim `## Blocker` section.
