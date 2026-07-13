# Follow-up to PR #70: pin 4ai-panes syncs to primary/master + close the junction reverse-write hole
Status: OPEN — hole 1 CLOSED; hole 2 delegated, not landed
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 08:42
Auto: no
Risk: B
Base: origin/master

> `Auto:` flipped yes → no by claude-code (cockpit) on 2026-07-14 01:52: the
> cockpit is actively working this item, so the auto pane must not double-run it.
> Reverts to `Auto: yes` only if the cockpit drops it.

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

## Progress — claude-code, 2026-07-14 01:52

### Hole 1 — CLOSED on master ✅
Landed as `25fd414 fix(4ai-panes): pin install sync to primary checkout on master (hole 1)`,
verified in the `origin/master` tree (not just a working copy):

    $ git cat-file -p <origin/master:scripts/sync-4ai-panes-install.ps1>
    146:# --- Provenance guard: only primary-checkout master code may deploy ---------
    196:} elseif (-not $gitOk -or -not $isPrimary -or $branch -ne 'master') {
    197:    Write-Line "sync-4ai-panes-install: REFUSED - not primary/master (toplevel=$toplevel branch=$branch primary=$primaryStr)..."

`scripts/test-sync-4ai-panes-install.ps1` is on master too, covering (a) worktree →
REFUSED, (b) primary non-master → REFUSED, (c) detached HEAD → REFUSED,
(d) primary+master → proceeds, (e) `SYNC_FORCE=1` → FORCED override. Your suggested
shape was implemented as specified, including the provenance token
(`branch=<b> primary=<yes|no>`) on every log line.

### Hole 2 — NOT landed; delegated to kiro ❌
Neither `.ai/tools/reverse-write-detector.sh` nor
`docs/specs/junction-reverse-write-guard.md` exists on `origin/master`
(`git ls-tree origin/master .ai/tools/ docs/specs/` → absent). `CLAUDE.md:75` already
points at that spec path, so the reference is currently dangling.

The work is not missing — it is **stranded on four unmerged kiro branches** with no
open PR, one of which (`exec/kiro/202607130150-junction-reverse-write-guard`) exists
**only locally and was never pushed**, i.e. one `git worktree remove` from deletion.

Worse, the mechanism that *did* land on master is the rejected one:
`cf9074d` added `guard_ai_reverse_write()` to `scripts/wt-bootstrap.sh`, which sets
`--skip-worktree` on ~39 `.ai/**` paths in every worktree. That makes git blind to
real edits (`git add` stages nothing, `git status` reads clean, commits silently drop
the change) — it ate kimi's SSOT §7 rewrite, which I recovered and committed today.
So master currently has **the guard that doesn't protect and lacks the detector that
would**.

Reconciliation is delegated to kiro:
`.ai/handoffs/to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md`
(forward-revert `cf9074d`, land the detector + spec, make bootstrap self-heal leftover
skip-worktree bits, open a PR — merge gate stays with me).

**This handoff stays OPEN** until that PR is merged. Hole 1 is done; certifying the
whole item DONE while the reverse-write hole is still open would be a false completion.
