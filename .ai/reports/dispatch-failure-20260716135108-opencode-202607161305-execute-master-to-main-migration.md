# Dispatch failure — opencode (worktree setup)

- Handoff: .ai/handoffs/to-opencode/open/202607161305-execute-master-to-main-migration.md
- UTC: 20260716135108
- Stage: worktree-per-CLI setup (ADR-0004 amendment) — never reached CLI invocation

Triage: run 'bash /mnt/c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode/scripts/wt-bootstrap.sh /mnt/c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode opencode' manually to see the failure.
The handoff stays OPEN — the dispatcher will retry it on the next --exec run.
This dispatch was deliberately NOT run in the primary checkout — falling back
to shared-HEAD execution is the exact bug ADR-0004's amendment forbids.
