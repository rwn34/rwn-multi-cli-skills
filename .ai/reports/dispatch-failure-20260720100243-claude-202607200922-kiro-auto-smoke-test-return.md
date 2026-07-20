# Dispatch failure — claude (.ai/ snapshot incomplete)

- Handoff: .ai/handoffs/to-claude/open/202607200922-kiro-auto-smoke-test-return.md
- UTC: 20260720100243
- Framework: 0.0.45
- Worktree: /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude
- Stage: .ai/ snapshot-copy verification (ADR-0016) — never reached CLI invocation

Triage: the dispatcher snapshot-copied canonical .ai/ into the worktree,
but the dispatched handoff file is not present. Inspect the snapshot manifest:
  /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude/.ai/.snapshot-manifest
This is usually caused by a concurrent modification, a tar race during
snapshot, or a stale .ai/ directory in the worktree. The handoff stays OPEN.
