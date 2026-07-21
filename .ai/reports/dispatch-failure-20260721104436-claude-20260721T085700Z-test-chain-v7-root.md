# Dispatch failure — claude (evidence-base mismatch)

- Handoff: .ai/handoffs/to-claude/open/20260721T085700Z-test-chain-v7-root.md
- UTC: 20260721104436
- Framework: 0.0.45
- Worktree: /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude
- Resolved base: origin/main
- Resolved base SHA: 9797a1f16f70eff2edc9b714945db6ff31f20218
- Observed-in SHA: 54698c2 (54698c278cd9c2452b1528050c93cdebf08deec7)
- Stage: evidence-base mismatch (protocol v4)

The handoff asserts evidence was observed in commit 54698c2,
but that commit is not an ancestor of the resolved dispatch base.
The sender should re-verify the evidence in the current tree or
update Observed-in:. The handoff stays OPEN until corrected or
retired manually.
