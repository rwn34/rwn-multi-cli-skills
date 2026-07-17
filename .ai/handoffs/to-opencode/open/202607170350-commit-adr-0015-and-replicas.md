# Commit ADR-0015 + SSOT §8 amendment + regenerated replicas as one PR

Status: BLOCKED

## Blocker

The opencode worktree's framework guard (ADR-0004) restricts writes to:
- Only `.ai/` (activity log, handoffs, reports) within the opencode worktree
- No access to files in other worktrees (e.g., primary tree at `C:\Users\rwn34\Code\rwn-multi-cli-skills`)
- No direct commit operations from the opencode worktree

This blocks the task at multiple levels:

1. **Commit coordination across trees:** The exec tree (`C:\Users\rwn34\Code\.wt\rwn-multi-cli-skills\claude`) contains the ADR + 3 replicas (docs/architecture/0015-handoff-protocol-v4.md, .claude/skills/operating-prompt/SKILL.md, .kimi/steering/operating-prompt.md, .kiro/steering/operating-prompt.md) but cannot commit `.ai/instructions/operating-prompt/principles.md` due to skip-worktree bits set by `guard_ai_reverse_write()`.

2. **Primary tree access:** The primary tree (`C:\Users\rwn34\Code\rwn-multi-cli-skills`) holds `.ai/instructions/operating-prompt/principles.md`, `.ai/handoffs/to-kimi/open/202607170335-implement-adr-0015-v4-fixes.md`, and `.ai/handoffs/to-claude/done/202607170308-ratify-adr-0015-handoff-protocol-v4.md`, but I cannot stage or edit these files from the opencode worktree.

3. **Cross-tree cherry-pick blocked by pre-commit hook:** Attempting to cherry-pick commit d5d35a7 (exec tree's ADR + replicas) into the primary tree fails at the pre-commit hook because the exec tree's commit attempts to include `.kiro/steering/operating-prompt.md`, which violates the per-CLI boundary enforced by the guard.

4. **Manual file coordination blocked:** The handoff's three options for resolving the skip-worktree blocker require:
   - Option 1: Clear skip-worktree bits in the exec tree, but I cannot run `git update-index` from the opencode worktree (command blocked by framework guard).
   - Option 2: Cut a branch in the primary tree and cherry-pick, but cherry-pick fails due to pre-commit hook violations.
   - Option 3: Any other mechanism to get all seven paths into one commit, but any operation that touches files in both trees is blocked by the guard.

**What I can do from this worktree:**
- Read files via `.ai/` junction (but only what's already in this worktree)
- Run shell commands via bash (MSYS) that target files in this worktree
- Write to `.ai/` and `.github/` within the opencode worktree

**What I cannot do:**
- Stage/edit files in the primary tree
- Stage/edit files in the exec tree's `.ai/**` (skip-worktree bits)
- Run `git update-index` or other git index operations that touch `.ai/**`
- Use git to copy files between worktrees or preserve committer identities across cherry-picks

**Conclusion:** The task requires a human (or a CLI with broader write permissions) to either:
- Complete the commit/PR from a worktree that has permission to write all seven files (e.g., the primary tree or exec tree with skip-worktree bits cleared), or
- Resolve the skip-worktree configuration (remove `guard_ai_reverse_write()` and let the primary tree handle all commits), or
- Implement a framework-change handoff to modify ADR-0004 to allow cross-tree coordination.

The handoff is blocked. No work has been completed on this task.
Sender: claude-cockpit
Recipient: opencode-auto
Owner: opencode-auto
Created: 2026-07-17 10:50 (UTC+7)
Auto: yes
Risk: B
Base: origin/main
Observed-in: main@536d0a72bf1b08a17ac4dfd69a0fcf5389c824a0
Evidence: VERIFIED

## Goal

ADR-0015 was authored this session and its SSOT/replica cross-references updated.
All of it is **uncommitted**, and it cannot be committed from one tree — see the
Blocker-in-waiting below, which is the actual reason this is your task and not
mine.

Land it as a **single PR** to `main`. Do not merge — I hold the merge gate
(author ≠ reviewer).

## What must land, atomically

`check-ssot-drift.sh` requires an SSOT change and its regenerated replicas in the
**same commit**, and it is wired into CI (`framework-check.yml`, `gates.yml`). A
partial commit fails CI with drift.

**In exec worktree `C:\Users\rwn34\Code\.wt\rwn-multi-cli-skills\claude`,
branch `exec/claude/202607170308-ratify-adr-0015-handoff-protocol-v4` (cut from `bb3ee4a`):**

- `docs/architecture/0015-handoff-protocol-v4.md` (new)
- `.claude/skills/operating-prompt/SKILL.md` (regenerated)
- `.kimi/steering/operating-prompt.md` (regenerated)
- `.kiro/steering/operating-prompt.md` (regenerated)

**In primary worktree `C:\Users\rwn34\Code\rwn-multi-cli-skills` (`main` @ `536d0a7`):**

- `.ai/instructions/operating-prompt/principles.md` (§8 rewritten — the SSOT the
  three replicas above were generated from)
- `.ai/handoffs/to-kimi/open/202607170335-implement-adr-0015-v4-fixes.md` (new)
- `.ai/handoffs/to-claude/done/202607170308-ratify-adr-0015-handoff-protocol-v4.md`
  (moved from `open/`, `Status: DONE`)
- `.ai/activity/log.md` (entry prepended)

The `.ai/` paths appear only in the primary's `git status` — that is the whole
problem.

## The blocker in waiting — read before starting

`guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh:229`) sets the git
skip-worktree bit on 39 `.ai/**` paths in every bootstrapped worktree. So:

- The **exec tree cannot stage `principles.md`** — `git add` stages nothing and
  `git status` reads clean. Verify with `git ls-files -v -- .ai/` (`S` prefix).
- The **primary tree has no such bits** and can stage `.ai/**`, but it is on
  `main`, and the ADR + replicas live on the exec branch.

So the atomic commit is not directly expressible from either tree. That is a real
design snag, not you doing it wrong — `sync-replicas.sh` writes replicas into the
tree it runs in while its input lives behind a junction that tree cannot stage.

Pick whichever of these is cleanest; I am not prescribing the mechanism:

1. Clear the skip-worktree bit for the specific path in the exec tree
   (`git update-index --no-skip-worktree .ai/instructions/operating-prompt/principles.md`),
   stage everything on the exec branch, commit, then restore the bit. This is
   effectively what `heal_skip_worktree()` in **unmerged PR #97** does.
2. Cut a branch in the primary tree, commit the `.ai/**` changes there, and
   cherry-pick or merge with the exec branch's ADR + replicas.
3. Anything else that gets all seven paths into one commit on one branch.

**Do not silently drop `principles.md` from the commit to make CI pass** — that
lands replicas describing an SSOT that isn't there and inverts the check's
purpose. If none of the options work, leave this OPEN with `Status: BLOCKED` and
a verbatim `## Blocker`. A blocked handoff is a fine outcome here; a green CI run
that hides drift is not.

## Steps

1. Get all seven paths into one commit on
   `exec/claude/202607170308-ratify-adr-0015-handoff-protocol-v4`.
2. Run `bash .ai/tools/check-ssot-drift.sh` and confirm `Drift: 0` **from a clean
   checkout of the branch**, not just this disk.
3. Push and open a PR to `main`. Title:
   `docs(adr): ADR-0015 ratify handoff protocol v4 with required modifications`.
   In the body, state plainly that the ADR finds a **live defect in the Risk-C
   gate on `main`** (`dispatch-handoffs.sh:548`) and that the fix is tracked in
   `.ai/handoffs/to-kimi/open/202607170335-implement-adr-0015-v4-fixes.md`.
4. Request review from **kiro** (not kimi — kimi authored v4 and is implementing
   the fixes; author ≠ reviewer).
5. **Do not merge.** Report the PR number back to me.

## Constraints

- Commit as your own identity (ADR-0005 per-CLI committer identity).
- No `--no-verify`. If a hook blocks you, that is a finding — report it verbatim
  rather than bypassing it. (`kimi-auto` used `--no-verify` on `53c1ff4`; that is
  part of why a live gate defect reached `main` unreviewed.)
- Do not touch `.ai/tools/dispatch-handoffs.sh` — it is enforcement layer per
  ADR-0015 Decision 3.4 and kimi is fixing it under a separate handoff.

## Report back with

- The commit SHA and the PR number.
- Raw output of `check-ssot-drift.sh` from the pushed branch showing `Drift: 0`.
- Which of the three options you used for the skip-worktree problem, and whether
  you restored the bit afterward.

## Blocker

—
