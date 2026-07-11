# Sync operating-prompt §14 (delegation economics) into Kiro steering
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-11 15:31
Auto: yes
Risk: A

## Goal
The SSOT `.ai/instructions/operating-prompt/principles.md` gained a new **§14 —
Delegation economics** (owner directive 2026-07-11) plus a pointer bullet in §4.
Your steering replica `.kiro/steering/operating-prompt.md` is now drift-flagged
against it. Regenerate the replica so `.ai/tools/check-ssot-drift.sh` passes.

## Current state
- SSOT (updated, authoritative): `.ai/instructions/operating-prompt/principles.md`
  — now ends with `## 14. Delegation economics — route by capacity, not by convenience`
  before the closing `**Remember:**` block, and §4 has a new final bullet
  beginning `- **Lanes say who MAY do the work; §14 ...`.
- Your replica (stale): `.kiro/steering/operating-prompt.md`.
- Claude's replica is already regenerated (`.claude/skills/operating-prompt/SKILL.md`)
  — Kimi is regenerating theirs in parallel via a sibling handoff.

## Target state
`.kiro/steering/operating-prompt.md` is byte-identical to the SSOT body per
`.ai/sync.md` (your steering file is a straight full-file copy — no frontmatter to
preserve; that caveat applies only to `.kiro/skills/*/SKILL.md`, which this
handoff does not touch).

## Steps
1. Read `.ai/instructions/operating-prompt/principles.md` (the SSOT).
2. Regenerate your replica, exactly as `.ai/sync.md` prescribes:
   `cp .ai/instructions/operating-prompt/principles.md .kiro/steering/operating-prompt.md`
3. Do NOT edit the SSOT, and do NOT touch `.claude/**` or `.kimi/**`.
4. Commit on a feature branch (`kiro/sync-operating-prompt-s14`) via your
   `infra-engineer`. Do not merge to main (Tier C — Claude gates).

## Verification
- (a) EXECUTE `bash .ai/tools/check-ssot-drift.sh` and paste the output — it must
      report no drift for `operating-prompt` (other entries, if any, are not yours
      to fix here; report them but do not touch them).
- (b) EXECUTE `grep -n "14. Delegation economics" .kiro/steering/operating-prompt.md`
      and paste the matching line.
- (c) Confirm the §4 pointer bullet landed:
      `grep -n "Lanes say who MAY do the work" .kiro/steering/operating-prompt.md`

## What §14 means for you (read it, it changes your workload)
You are the fleet's **premium-reasoning executor** ($200 plan; Opus 4.8 / Sonnet 5).
Claude's budget is the smallest in the fleet, so it will now route complex
debugging, root-cause analysis, and design-constrained implementation to you by
default instead of using its own subagents. Expect more inbound handoffs. Lane
boundaries are unchanged: no merges to main, no ADR authorship, no deploys.

Known gap that matters to you (`.ai/known-limitations.md`): your subagents do not
inherit hooks (platform bug). As you take on more delegated work, that means the
git pre-commit backstop — not per-write hooks — is what actually protects the
tree. Keep commits going through `infra-engineer`.

## Next step / future note
After this, every SSOT edit means three replica syncs (Claude self-serves; Kimi
and Kiro get handoffs). What breaks first: this is manual and drift is only caught
by the gate *after* the fact — if SSOT edits get frequent, the durable fix is a
sync script that regenerates all three replicas in one pass, with the gate as
backstop rather than as the discovery mechanism.

## Activity log template
    ## 2026-07-11 HH:MM — kiro-cli
    - Action: Synced operating-prompt §14 (delegation economics) into .kiro/steering per handoff 202607110831-sync-operating-prompt-s14
    - Files: .kiro/steering/operating-prompt.md
    - Decisions: —

## Report back with
- (a) the replica path you wrote
- (b) pasted `check-ssot-drift.sh` output (not a summary)
- (c) pasted grep evidence for (b) and (c) above
- (d) the branch name + commit sha

## When complete (protocol v3)
Self-retire: set Status to `DONE` and move this file to
`.ai/handoffs/to-kiro/done/`. If blocked, leave it in `open/` as `BLOCKED` with a
verbatim `## Blocker` section.

## Completion report

- (a) Replica path: `.kiro/steering/operating-prompt.md` (full-file copy of the
  SSOT, no frontmatter to preserve).
- (b) `bash .ai/tools/check-ssot-drift.sh` output:
  ```
  Checked: 24 replicas, Drift: 0
  ```
- (c) Grep evidence:
  ```
  212:## 14. Delegation economics — route by capacity, not by convenience
  75:- **Lanes say who MAY do the work; §14 (delegation economics) says who SHOULD.**
  ```
- (d) Branch `kiro/sync-operating-prompt-s14`, commit `07d97dcc3a943071f90979c9d94ef433d35eab48`,
  pushed to `origin/kiro/sync-operating-prompt-s14`. No merge to main performed.
