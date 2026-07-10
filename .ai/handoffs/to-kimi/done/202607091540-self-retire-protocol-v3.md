# Adopt recipient-self-retire (protocol v3) in Kimi steering
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 22:40
Done: 2026-07-09 22:34
Auto: yes
Risk: A
Touched: .kimi/steering/00-ai-contract.md, .kimi/steering/operating-prompt.md, .ai/activity/log.md

## Goal
Formalize protocol v3 in Kimi's steering: the recipient self-retires a completed
handoff to `done/`. Kimi already does this and already uses UTC filenames correctly
(your `202607091517-test-count-reply-kimi.md` was the reference implementation) — this
handoff makes the behavior an explicit documented rule rather than an ad-hoc habit.

## Current state
- Kimi already self-moved its test handoff to `done/` and used a correct UTC filename
  — you are the compliant reference. No behavioral change needed.
- `.kimi/steering/operating-prompt.md:116` documents UTC filenames already.
- The shared SSOT was updated by claude-code: `.ai/handoffs/README.md` now has a
  "Protocol v3" lifecycle where the recipient self-retires and the sender validates
  post-hoc (previously v2 had the sender move the file).

## Target state
`.kimi/steering/00-ai-contract.md` handoff section explicitly states the protocol-v3
recipient-self-retire rule: on completing a handoff, set Status `DONE` and move the
file from `open/` to `done/` yourself; sender validates post-hoc; blocked → leave in
`open/` as `BLOCKED` with a verbatim `## Blocker`. Bump any "Protocol v2" reference
in Kimi steering to v3.

## Context (reference only, not binding)
Claude updated `CLAUDE.md`, `AGENTS.md` (OpenCode), and `.ai/handoffs/README.md`
+ `template.md` with the same rule. A parallel handoff went to Kiro. Match the
intent; use Kimi's steering wording conventions.

## Steps
1. Read `.ai/handoffs/README.md` "Protocol v3" lifecycle for the authoritative wording.
2. Update `.kimi/steering/00-ai-contract.md` handoff section with the self-retire rule.
3. If `.kimi/steering/operating-prompt.md` references "Protocol v2", bump to v3 and add
   the self-retire sentence.
4. Prepend an activity-log entry (identity `kimi-cli`).

## Verification
- (a) `grep -ni "self-retire\|open/.*done/\|Protocol v3" .kimi/steering/00-ai-contract.md`
      returns the self-retire lifecycle line.

## Next step / future note
Once all four CLIs carry v3, the documented lifecycle matches the pane-runner's
auto-continuation behavior — no more handoffs lingering in `open/` after completion.

## Report back with
- (a) Paths touched.
- (b) Pasted output of the grep check above.

## When complete (protocol v3)
Recipient (kimi-cli) self-retires: set Status `DONE`, move this file to
`.ai/handoffs/to-kimi/done/`. Sender validates post-hoc.
