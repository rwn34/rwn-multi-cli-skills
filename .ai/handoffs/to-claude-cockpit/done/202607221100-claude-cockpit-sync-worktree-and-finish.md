# Claude-cockpit: sync your stale worktree, then finish everything

Status: DONE
Sender: kimi-cockpit
Recipient: claude-cockpit
Owner: claude-cockpit
Created: 2026-07-22 18:00 (UTC+7)
Auto: no
Risk: B
Base: origin/main
Observed-in: main@487bd81
Evidence: VERIFIED (git -C C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude log --oneline -1 -> cac7166, which is behind main@487bd81; git ls-tree -r main --name-only | grep to-claude-cockpit/open -> contains 202607221032-finish-remaining-post-0053.md and 20260721-adr0010-freeze-execution.md)
FinalReview: claude-cockpit

## Why you see "no handoff"

Your worktree is stale:

- Worktree path: `C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude`
- Current branch/HEAD: `exec/claude/202607211616-delegate-adr0010-freeze-to-claude` at `cac7166`
- Canonical main: `487bd81` (8+ commits ahead)
- The handoffs in `to-claude-cockpit/open/` exist in `main` but are not in your
  worktree because it has not been refreshed.

## Step 1 — Sync your worktree to main

From your worktree (or from the cockpit supervisor), run:

```bash
cd C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude
git fetch origin
git checkout main
git reset --hard origin/main
```

Then refresh the `.ai/` snapshot from canonical:

```bash
bash C:/Users/rwn34/Code/rwn-multi-cli-skills/.ai/tools/sync-ai-state.sh snapshot \
  C:/Users/rwn34/Code/rwn-multi-cli-skills \
  C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude
```

After this, `ls .ai/handoffs/to-claude-cockpit/open/` must show:

- `20260721-adr0010-freeze-execution.md`
- `202607221032-finish-remaining-post-0053.md`
- `202607221100-claude-cockpit-sync-worktree-and-finish.md` (this file)

## Step 2 — Finish the remaining work

1. **PR #140 is already merged** — no action needed.
2. **Process `202607221032-finish-remaining-post-0053.md`** — it asks you to rebase
   the ADR-0010 freeze branch onto `main` and execute the freeze.
3. **Process `20260721-adr0010-freeze-execution.md`** — the original freeze
   handoff. Remember: `git mv .ai/activity/log.md` to archive **before** untracking.
4. **Address the GitHub ruleset bypass** if you conclude it must change — route to
   the owner.

## Full paths

- Your worktree: `C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/claude`
- Canonical repo: `C:/Users/rwn34/Code/rwn-multi-cli-skills`
- This handoff: `C:/Users/rwn34/Code/rwn-multi-cli-skills/.ai/handoffs/to-claude-cockpit/open/202607221100-claude-cockpit-sync-worktree-and-finish.md`
- Previous handoff to finish: `C:/Users/rwn34/Code/rwn-multi-cli-skills/.ai/handoffs/to-claude-cockpit/open/202607221032-finish-remaining-post-0053.md`
- ADR-0010 freeze handoff: `C:/Users/rwn34/Code/rwn-multi-cli-skills/.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md`

## Report back when

- Your worktree is on `main@487bd81` or later.
- You have read all three handoffs in `to-claude-cockpit/open/`.
