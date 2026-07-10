# Adopt UTC handoff filenames + recipient-self-retire (protocol v3)
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 22:40
Auto: yes
Risk: A

## Completion note (kiro-cli, 2026-07-09 22:33 local)
Touched `.kiro/steering/00-ai-contract.md` — added the UTC-filename-basis rule
(with worked UTC+7 example) and the recipient-self-retire protocol-v3 lifecycle
to the Cross-CLI handoffs section. Both verification greps pass:
- (a) `UTC` → line 44: `**Filename basis = UTC.** The YYYYMMDDHHMM prefix is a UTC timestamp`
- (b) self-retire / v3 → line 51 `**Recipient self-retires (protocol v3).**`,
      line 53 `move the file from .ai/handoffs/to-kiro/open/ to .ai/handoffs/to-kiro/done/`

Step 3 (bump `.kiro/steering/operating-prompt.md` "Handoff protocol v2" → v3)
was deliberately NOT done: that file is a drift-checked SSOT replica of
`.ai/instructions/operating-prompt/principles.md`. A Kiro-only edit would fail
`check-ssot-drift.sh` and cannot be propagated to the `.claude/`/`.kimi/`
replicas (other CLIs' dirs, off-limits to Kiro). Correct path is a full SSOT
sync — flagged to claude-code, consistent with the ADR-0006/0007 later-sync note
for operating-prompt.

## Goal
Bring Kiro's steering in line with two protocol clarifications the owner approved
today: (1) handoff filenames use UTC, (2) the recipient self-retires a completed
handoff to `done/` (protocol v3). Kiro's steering already documents the UTC-filename
rule but recent handoffs used local time in the filename — this reinforces it.

## Current state
- `.kimi/steering/operating-prompt.md:116` already states filenames use a UTC
  timestamp; Kiro's equivalent `.kiro/steering/operating-prompt.md` should carry the
  same rule. Verify it does.
- Kiro's reply handoff `202607092216-test-count-reply-kiro.md` used `2216` in the
  filename while `Created: 22:16` was local (UTC+7). Correct basis would have been
  `1516` (UTC). This is the deviation to fix behaviorally going forward.
- The shared SSOT was updated by claude-code: `.ai/handoffs/README.md` now carries a
  worked UTC-vs-local example and a "Protocol v3" lifecycle (recipient self-retires).

## Target state
Kiro's `.kiro/steering/00-ai-contract.md` and (if present) its operating-prompt
steering explicitly state:
1. **Handoff filename basis = UTC** (`date -u +%Y%m%d%H%M`); `Created:` line and
   activity-log entries = local wall-clock. Do not put local time in the filename.
2. **Recipient self-retires (protocol v3):** on completing a handoff, set Status
   `DONE` and move the file from `open/` to `done/` yourself; sender validates
   post-hoc. Blocked → leave in `open/` as `BLOCKED` with a verbatim `## Blocker`.

## Context (reference only, not binding)
Claude updated its own contract (`CLAUDE.md`) and OpenCode's (`AGENTS.md`) with the
same two points, and rewrote `.ai/handoffs/README.md` lifecycle steps 4–5 + the
filename section. Match the intent; use whatever wording fits Kiro's steering style.

## Steps
1. Read `.ai/handoffs/README.md` (filename section + "Protocol v3" lifecycle) for the
   authoritative wording.
2. Update `.kiro/steering/00-ai-contract.md` handoff section with both points above.
3. If `.kiro/steering/operating-prompt.md` has a handoff/protocol-version line, bump
   its "Protocol v2" reference to v3 and add the self-retire sentence.
4. Prepend an activity-log entry (identity `kiro-cli`).

## Verification
- (a) `grep -n "UTC" .kiro/steering/00-ai-contract.md` returns the filename-basis line.
- (b) `grep -ni "self-retire\|open/.*done/\|Protocol v3" .kiro/steering/00-ai-contract.md`
      returns the self-retire lifecycle line.

## Next step / future note
Once Kimi + Kiro + OpenCode + Claude all carry v3, the `check-ssot-drift.sh` gate and
the pane-runner auto-continuation are fully consistent with the documented lifecycle.

## Report back with
- (a) Paths touched.
- (b) Pasted output of the two grep checks above.

## When complete (protocol v3)
Recipient (kiro-cli) self-retires: set Status `DONE`, move this file to
`.ai/handoffs/to-kiro/done/`. Sender validates post-hoc.
