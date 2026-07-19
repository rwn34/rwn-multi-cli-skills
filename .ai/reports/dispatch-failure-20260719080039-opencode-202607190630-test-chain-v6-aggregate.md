# Dispatch failure — opencode (evidence-base mismatch)

- Handoff: .ai/handoffs/to-opencode/open/202607190630-test-chain-v6-aggregate.md
- UTC: 20260719080039
- Worktree: /c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode
- Resolved base: origin/main
- Resolved base SHA: e8df9f819107577fdbc122e6625e2bba8cbfc4fe
- Observed-in SHA: HEAD (f9140dc6f766259438f073a9e3bcfc6a82cd8fb9)
- Stage: evidence-base mismatch (protocol v4)

The handoff asserts evidence was observed in commit HEAD,
but that commit is not an ancestor of the resolved dispatch base.
The sender should re-verify the evidence in the current tree or
update Observed-in:. The handoff stays OPEN until corrected or
retired manually.
