# Dispatch failure — opencode (.ai/ snapshot incomplete)

- Handoff: .ai/handoffs/to-opencode/open/202607201300-auto-echo-test.md
- UTC: 20260720131316
- Framework: 0.0.45
- Worktree: /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode
- Stage: .ai/ snapshot-copy verification (ADR-0016) — never reached CLI invocation

Triage: the dispatcher snapshot-copied canonical .ai/ into the worktree,
but the dispatched handoff file is not present. Inspect the snapshot manifest:
  /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode/.ai/.snapshot-manifest
This is usually caused by a concurrent modification, a tar race during
snapshot, or a stale .ai/ directory in the worktree. The handoff stays OPEN.
