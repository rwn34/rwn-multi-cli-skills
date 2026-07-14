# Follow-up to PR #70: pin 4ai-panes syncs to primary/master + close the junction reverse-write hole
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 08:42
Auto: yes
Risk: B
Base: origin/master

## Outcome — claude-code, 2026-07-14 02:20

**Hole 1: CLOSED on master. Hole 2: NOT closed on master — re-delegated to kiro with a live
successor handoff. This file retires because its residual work has a dedicated owner, not
because both holes are fixed.** Read the hole-2 section below before assuming the tree is safe.

### Hole 1 — sync provenance pin: CLOSED ✅

Landed on master as `25fd414 fix(4ai-panes): pin install sync to primary checkout on master (hole 1)`.
Exactly the shape this handoff suggested. Evidence from the `origin/master` blob of
`scripts/sync-4ai-panes-install.ps1` (blob `b084d6c`):

    197:  Write-Line "sync-4ai-panes-install: REFUSED - not primary/master (toplevel=$toplevel
          branch=$branch primary=$primaryStr). Only merged master code may reach the live
          install. Override: -Force or SYNC_FORCE=1."
    195:  Write-Line "sync-4ai-panes-install: FORCED - provenance guard overridden ..."
    136:  $logLine = "[$stamp] commit=$commit branch=$branch primary=$primaryStr result=$Result$prov"

- Guard refuses unless primary checkout AND HEAD == master; `-Force` / `SYNC_FORCE=1` overrides.
- Every run logs `branch=<b> primary=<yes|no>` provenance, incl. `provenance=forced`.
- Test suite on master (`scripts/test-sync-4ai-panes-install.ps1`, blob `d092800`) covers all
  five cases: worktree→REFUSED, primary+non-master→REFUSED, detached HEAD→REFUSED,
  primary+master→PROCEEDS, `SYNC_FORCE=1`→FORCED.
- Callers confirmed: `post-checkout:21`, `post-commit:25`, `post-merge:17`.
- Open hardening follow-up (not the closure): **PR #93** — ancestor guard for the install sync.

The "your verify step" for hole 1 (`run the sync from a worktree on a branch; expect refusal`)
is asserted by case (a) of that suite rather than by a hand-run.

### Hole 2 — junction reverse-write: OPEN, and the mitigation on master is itself harmful ⚠️

What is actually on master is kimi's `guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh`,
`cf9074d`), which sets `git update-index --skip-worktree` on ~39 stable `.ai/**` paths in every
worktree. **The same mechanism that blocks the clobber makes git blind to real edits** on those
paths — `git add` stages nothing, `git status` reads clean, the commit silently drops the change.
The blind set excludes handoffs/activity-log but *includes* `.ai/instructions/**` (the SSOT),
`.ai/tools/**` and `.ai/sync.md`, so the live failure mode is **silent SSOT drift with no diff to
point at**. Kiro's `f543143` diagnosed this correctly and was never merged, so the rejected
approach is what shipped. `tools/4ai-panes/test-pane-runner.ps1` also regressed 132/0 → 144/3
(all 3 in `av4`), traceable to `cf9074d`.

Blast radius, measured in this worktree today: `git ls-files -v .ai | grep -c "^S"` → **39**.
Other worktrees (kimi, kiro, opencode) still carry the bits until they re-bootstrap.

Correction to the record: an earlier claude-code session cited a lost SSOT §7 edit as proof the
guard "ate" work. **That was wrong** — the edit was already committed on master (`6d939ed`) and
was showing as modified only because `.ai/` is a junction shared by every worktree. An audit of
`cf9074d..master` found **zero** silently-dropped `.ai/**` deliverables. The guard's blast radius
is narrower than first claimed; the mechanism defect above is real regardless, and stands on
kiro's `f543143` analysis plus the reproducible `av4` regression.

The real fix — `.ai/tools/reverse-write-detector.sh` + `docs/specs/junction-reverse-write-guard.md`
(which `CLAUDE.md` already points at; the reference is **dangling on master**) — exists only on
unmerged kiro branches.

### Successor / where the residual work lives

- **`to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md`** (Auto: yes, Risk: B)
  — owns hole 2 end to end: forward-revert `guard_ai_reverse_write()`, land the detector + spec,
  make `wt-bootstrap.sh` self-heal leftover skip-worktree bits (`--no-skip-worktree`) so the rest
  of the fleet stops losing `.ai/**` edits, and assert the regression in a test.
- **PR #94** (`exec/claude/202607130142-deploy-pin-and-junction-reverse-write`) — records hole-1
  closure + the hole-2 delegation.
- **Branch preservation (done today):** `exec/kiro/202607130150-junction-reverse-write-guard` was
  **local-only and never pushed** — 686 insertions (detector 203 + spec 384 + CI wiring + bootstrap)
  one `git worktree remove` from permanent loss. Pushed to origin at `5646bf7`; verified via
  `git ls-remote --heads origin` → `5646bf7b... refs/heads/exec/kiro/202607130150-junction-reverse-write-guard`.
  Kiro's detector work now survives; it must still be reconciled across its four branches into one PR.

### Not done / carried forward

- Hole 2 remains open on master. Until `to-kiro/202607131819` lands, **treat `.ai/instructions/**`
  edits made inside a worktree as untrustworthy** — verify with `git ls-files -v .ai | grep "^S"`
  before believing a clean `git status`.
- The four stranded kiro detector branches still have **no open PR** and must be reconciled into
  one, not picked from at random.
- Fleet-relaunch + `.ai/handoffs/.quarantine/` clearing (this handoff's closing note) are owner
  actions and were not performed here.
