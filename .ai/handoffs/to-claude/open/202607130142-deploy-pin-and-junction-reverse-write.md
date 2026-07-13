# Follow-up to PR #70: pin 4ai-panes syncs to primary/master + close the junction reverse-write hole
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 08:42
Auto: yes
Risk: B
Base: origin/master

## Why
PR #70 (merged e74714a, v0.0.38 at f819694) fixed the branch-cut outage, but the
post-mortem exposed two adjacent holes in the same machinery. Both bit us tonight.

## Hole 1 — hook-driven sync deploys whatever worktree HEAD happens to be
Observed timeline (2026-07-13, local):
- ~05:45 a hook fired `scripts/sync-4ai-panes-install.ps1` **from my fix worktree**
  (`/c/Users/rwn34/Code/.wt/rwn-multi-cli-skills/kimi`, on branch
  `exec/kimi/202607121930-...`) and deployed the branch-code pane-runner to
  `~/.rwn-auto/rwn-4AI-panes/`.
- ~06:09 the owner relaunched panes; the supervisor's re-provision path pulled
  from **primary master** (pre-PR#70) and reverted the live launcher to the old
  broken code — which is why the owner's first restart "didn't fix anything".
So the same live file can be written from two sources with different ideas of
"current", and which one wins depends on timing. Suggested shape (your call):
the sync hook must refuse to run unless `git rev-parse --show-toplevel` is the
primary checkout AND HEAD == master (or an explicit `SYNC_FORCE=1`), so only
merged master code can ever reach `~/.rwn-auto/`. Optionally add a launch-time
drift check in `run-pane-supervised.ps1` that warns when the live launcher
differs from `tools/4ai-panes/` in primary.

## Hole 2 — canonical `.ai/tools/dispatch-handoffs.sh` was silently reverted through a junction
Between ~06:15 and ~07:11 the canonical file in the primary checkout was
rewritten to the **pre-PR#70 blob** while PR #70 was already on master. I
restored it with `git restore --source=master --worktree -- .ai/tools/dispatch-handoffs.sh`
(verified: 2× `symbolic-ref`, `bash -n` OK) before this handoff was written.
Mechanism is unproven; best hypothesis: a git operation (checkout/merge/restore)
in a pre-fix worktree wrote through the `.ai/` junction into the primary's live
`.ai/`. PR #70 stops the *dispatchers* from doing this (they restore `.ai/`
index-only), but any other git op in any worktree can still clobber shared
`.ai/` state. Suggested shape: a drift-gate extension (or a pre-commit/pre-checkout
hook) that detects when a worktree op would write tracked `.ai/**` paths whose
content differs from the primary checkout's HEAD, and refuses. The reverse-write
detection can reuse the provenance idea from the sync-provenance work.

## Verify
- Reproduce hole 1: run the sync from a worktree on a branch; expect refusal.
- Reproduce hole 2: in a stale worktree, `git checkout` a commit that changes
  tracked `.ai/**`; expect the guard to refuse / the primary's `.ai/` untouched.
- Existing suites must stay green: `tools/4ai-panes/test-pane-runner.ps1` (132/0),
  bash twin via `dispatch-handoffs.sh --exec` sandbox test.

## Notes
- Related kiro handoff still open: `to-kiro/open/202607122200-sync-provenance-and-verify-live-launcher.md`
  (sync-provenance half overlaps hole 1 — coordinate to avoid double work).
  The verify-live-launcher half is DONE: live launcher carries the fix at f819694
  (`grep -c symbolic-ref ~/.rwn-auto/rwn-4AI-panes/pane-runner.ps1` = 3,
  sync script reports in-sync).
- Fleet is down until the owner relaunches the four panes (processes still run
  pre-fix in-memory code) and clears `.ai/handoffs/.quarantine/` (8 files).
