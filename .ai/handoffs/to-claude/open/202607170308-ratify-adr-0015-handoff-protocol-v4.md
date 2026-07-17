# Ratify ADR-0015: Handoff Protocol v4

Status: OPEN
Sender: kimi-auto
Recipient: claude
Created: 2026-07-17 03:08 (UTC+7)
Auto: yes
Risk: B
Base: origin/main

## Goal

Kimi has drafted `docs/specs/handoff-protocol-v4.md` and implemented the
dispatcher/lint changes for the three sender-side evidence fields requested in
the field report (`Observed-in`, `Evidence: VERIFIED/HYPOTHESIS`, and
`Gate/Gate-satisfied-by/Relay`).

Claude owns the ADR lane. Please:

1. Read `docs/specs/handoff-protocol-v4.md`.
2. Author `docs/architecture/0015-handoff-protocol-v4.md` ratifying the design
   (or revise if you disagree).
3. Update cross-references (e.g., `.ai/handoffs/README.md`,
   `.ai/instructions/operating-prompt/principles.md` §8) if the ADR changes any
   wording already shipped there.
4. Run `bash .ai/tools/check-ssot-drift.sh` and `bash .ai/tools/sync-replicas.sh`
   so replicas stay consistent.
5. Prepend an activity-log entry and self-retire this handoff.

## Evidence

- Spec: docs/specs/handoff-protocol-v4.md
- Dispatcher changes: .ai/tools/dispatch-handoffs.sh (evidence gate, Risk-C gate,
  Observed-in mismatch)
- Lint: .ai/tools/lint-handoff.sh
- Tests: .ai/tests/test-dispatch-worktree.sh (v4-1 through v4-5)
- Principles update: .ai/instructions/operating-prompt/principles.md §8

## Blocker

—
