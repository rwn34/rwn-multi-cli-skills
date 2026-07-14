# Verify + merge PR #92 (stale allowlist-count assertion in the sync test)
Status: DONE
Sender: claude-code
Recipient: opencode
Created: 2026-07-14 01:19
Auto: yes
Risk: B
Base: origin/master

## Why

Hole 1 of handoff `to-claude/202607130142-deploy-pin-and-junction-reverse-write` (pin the
4ai-panes install sync to primary-checkout/master) is **already shipped and merged**
(`25fd414`), including the optional launch-time drift warning in
`tools/4ai-panes/run-pane-supervised.ps1`. The provenance guard works — every provenance
assertion in the suite passes.

The only loose end is a stale test constant:

    powershell.exe -File scripts/test-sync-4ai-panes-install.ps1
    ==== sync-install tests: 33 passed, 1 failed ====
    FAIL  d4: all 12 allowlisted files copied  (expected=12 actual=17)

`scripts/test-sync-4ai-panes-install.ps1:169` hardcodes `12`; the allowlist has grown to 17.
PR #92 is already open for exactly this fix. A red suite here is what let hole 2's
regression hide, so I want it green.

## Steps

1. `gh pr view 92 --json title,state,mergeable,statusCheckRollup` and `gh pr diff 92`.
2. **Scope check — this is the gate, not a rubber stamp.** The diff must be confined to the
   stale count assertion in `scripts/test-sync-4ai-panes-install.ps1` (and, at most, a
   comment). If it touches `scripts/sync-4ai-panes-install.ps1`, any guard logic, or any
   other file — **STOP, do not merge, report back with the diff.**
3. If the scope check passes AND CI is green AND it is mergeable: merge it (squash, per
   `git-conventions`), then delete the branch.
4. Re-run `powershell.exe -File scripts/test-sync-4ai-panes-install.ps1` on master and
   confirm **34 passed / 0 failed**.

## Do not

- Do not "fix" the test by loosening the assertion to a range or removing it. The count is
  the point — it catches allowlist drift. It should be 17, or derived from the allowlist.
- Do not touch the provenance guard. It is correct and merged.

## Report back with

- The PR #92 diff, verbatim.
- Merge commit SHA (or the reason you refused).
- The post-merge test tail showing 34/0.

## Blocker

**Working tree is dirty in sibling worktree** — prevents merging per contract rule 4 ("Refuse on dirty working tree or failing tests. No exceptions, either environment").

Sibling worktree at `C:/Users/rwn34/Code/rwn-multi-cli-skills` shows:

```
M tools/4ai-panes/fleet-supervisor.ps1
?? .ai/handoffs/to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md
?? .ai/handoffs/to-opencode/open/202607131819-merge-pr92-stale-sync-test-count.md
```

The PR diff is correct and scoped as expected (only line 169 changed from 12 to 17 in `scripts/test-sync-4ai-panes-install.ps1`), and CI is green. Merge cannot proceed until the sibling worktree is clean.
