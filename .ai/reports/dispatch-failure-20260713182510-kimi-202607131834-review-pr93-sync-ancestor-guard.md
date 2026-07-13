# Dispatch failure — kimi (worktree setup)

- Handoff: .ai/handoffs/to-kimi/open/202607131834-review-pr93-sync-ancestor-guard.md
- UTC: 20260713182510
- Stage: worktree-per-CLI setup (ADR-0004 amendment) — never reached CLI invocation

Triage: run 'bash /mnt/c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/kimi/.ai/tools/../../scripts/wt-bootstrap.sh /mnt/c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/kimi kimi' manually to see the failure.
The handoff stays OPEN — the dispatcher will retry it on the next --exec run.
This dispatch was deliberately NOT run in the primary checkout — falling back
to shared-HEAD execution is the exact bug ADR-0004's amendment forbids.
