# CRITICAL: the shared .ai/ junction breaks every worktree branch cut
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-12 23:30
Auto: yes
Risk: B
Base: origin/master

## Why this is the most important handoff in the queue
**Any merge that touches tracked `.ai/**` silently re-breaks every executor worktree
and re-quarantines the entire fleet queue.** It happened three times tonight. It
happened to a release-engineer *during its own task* — its PRs changed `.ai/`, which
re-broke the very worktrees it had just repaired.

The owner starts real project work tomorrow. **The first `.ai`-touching merge will kill
the fleet unless you fix this.** Everything else in the queue is secondary.

## Root cause (proven — do not re-diagnose, verify then fix)
1. `.ai/` is a **junction** (ADR-0004 `wt-bootstrap.sh` `link_ai()`): every executor
   worktree points at the **same physical `.ai/`** in the primary checkout.
2. When a worktree's HEAD is stale relative to master, git sees those shared `.ai/`
   files as **modified / untracked** in that worktree.
3. `pane-runner.ps1`'s `Ensure-DeclaredBaseBranchReal` runs
   `git checkout -b exec/<cli>/<slug> origin/master` — and **git ABORTS**, because the
   checkout would clobber those "local changes".
4. But the runner's **dirty-check deliberately filters out `.ai/` lines**
   (`grep -v ' \.ai/'` — added precisely because `.ai/` is shared). So it concludes the
   worktree is CLEAN, proceeds to the branch cut, and git refuses. -> `WORKTREE_FAIL`
   -> 3 retries -> quarantine.

**The asymmetry that hid it for hours:** a worktree with *non-`.ai/`* dirt takes the
"reuse as-is" path and never cuts a branch — so the `claude` pane never failed. The
otherwise-*clean* kimi/kiro worktrees always tried the cut and always failed. That is
exactly the observed 4-kimi + 3-kiro quarantine pattern.

**Two independent bugs live in the same place:** the dirty-check *ignores* `.ai/`, and
the branch cut *is blocked by* `.ai/`. One hand says "clean", the other says "not
clean". Same file. That is the "two surfaces, one rule" pattern this project keeps
hitting — fix it as one coherent rule, not two patches.

## Target
`pane-runner.ps1`'s branch cut must succeed in a worktree whose only "dirt" is the
shared junctioned `.ai/`. Candidate approaches — pick one, justify it, and state what
it breaks:
- Make the branch cut tolerate the shared `.ai/` the same way the dirty-check does
  (e.g. cut the branch in a way that does not require a clean `.ai/`, or explicitly
  exclude the junctioned path from the checkout's cleanliness requirement).
- Bring the worktree's HEAD up to `origin/master` *before* cutting, so the shared `.ai/`
  files stop reading as modified in the first place. **Careful:** this must never
  destroy real work in the worktree — refuse and report if there is non-`.ai/` dirt.
- Something better. **You own this domain** (you wrote the worktree parity in PR #51 and
  the dispatcher's worktree logic) — if there is a cleaner structural answer, take it.

**Non-negotiable:** keep the **fail-loud, never-fall-back-to-primary** contract. That
behavior is what turned tonight's total outage into a clean, recoverable, fully-recorded
halt instead of four CLIs trampling the shared tree. Do not weaken it.

## Also fix — the junction silently degrades
Kimi's worktree `.ai/` had **degraded from a junction into a real directory**, divorcing
its handoff view from the fleet (it would have been reading a *different* queue). A
release-engineer re-junctioned it by hand. **Nothing detects this.**
Add a check: the runner (or `wt-bootstrap.sh`) must verify `.ai/` in a worktree is
actually the junction and not a real directory — and **fail loud** if it isn't. A CLI
silently reading the wrong `.ai/` is a coordination-plane split-brain, which is far
worse than a failed branch cut.

## Tests — this is the failure class that has burned this project all night
**Every bug tonight was code never exercised in the state it actually runs in.** Do not
repeat it:
- **Reproduce the bug FIRST**: a worktree with a stale HEAD and a junctioned `.ai/`
  containing modified/untracked files -> show the branch cut FAILS today. Paste it.
- Then show your fix makes it PASS.
- A worktree with genuine non-`.ai/` dirt -> still refuses (do not weaken the safety).
- A worktree whose `.ai/` is a real directory instead of a junction -> **fails loud**.
- The existing `test-pane-runner.ps1` suite still green (it was 103).
- **The test must exercise a REAL worktree with a REAL junction** — not a mock. Mocking
  the worktree path is exactly how PR #51 shipped this bug.

## ADDENDUM (claude-code, 2026-07-13 07:05) — reproduced live; scope is BIGGER than pane-runner
The landmine fired again this morning and took down the **bash dispatcher** too. Two
new facts, both confirmed by execution, both in scope for your fix:

**(1) `dispatch-handoffs.sh` has the SAME two-surface bug — fix both files, one rule.**
The handoff above names only `pane-runner.ps1`, but `.ai/tools/dispatch-handoffs.sh`
carries a byte-equivalent version of the identical defect:
- `:260` — dirty-check *excludes* `.ai/`: `dirty="$(git ... status --porcelain | grep -v ' \.ai/')"` -> concludes "clean"
- `:293` — then cuts: `git checkout --quiet -b "$branch" "$base"` -> git *enforces* `.ai/` and refuses

Verbatim repro from this morning (opencode worktree, HEAD `c1337d5`, origin/master `fadefea`):
```
$ git -C .../.wt/rwn-multi-cli-skills/opencode read-tree -m -u -n HEAD origin/master
error: Entry '.ai/activity/log.md' not uptodate. Cannot merge.

$ bash .ai/tools/dispatch-handoffs.sh --exec --only opencode
ERROR: could not cut exec/opencode/202607122316-... from origin/master in .../opencode
FAIL  [opencode] ... — could not establish declared-base branch (base=origin/master)
```
Both OpenCode handoffs failed **before the CLI was ever invoked**. This is not a
PowerShell bug and not an opencode bug — it is one rule implemented twice and broken in
both. **Whatever rule you land, land it in both files** (or, better, in one place both
call). The "two surfaces, one rule" note above was more right than it knew.

Consequence worth stating plainly: **the dispatcher cannot dispatch the handoff that
fixes the dispatcher.** This handoff had to be hand-relayed. That is the definition of a
landmine — treat the bootstrap path (how does this get fixed when the fixer is also
broken?) as part of the deliverable.

**(2) NEW, separate defect — `gh pr merge` cannot run from a detached-HEAD worktree.**
When OpenCode was finally hand-relayed into its worktree, the merge still failed:
```
$ gh pr merge 71 --merge --delete-branch
could not determine current branch: failed to run git: not on any branch
```
`gh pr merge <N>` **still resolves the current branch even when handed an explicit PR
number** — so it cannot run from a detached HEAD, which is exactly the state executor
worktrees sit in. Fix: pass `--repo`, which skips branch resolution entirely:
```
gh pr merge 71 --merge --delete-branch --repo rwn34/rwn-multi-cli-skills
```
This would have merged with **zero git mutation** in the worktree. Any code path (or
handoff template) that has an executor run `gh pr merge`/`gh pr review` from a worktree
must use `--repo`. Please sweep for bare `gh pr` calls while you are in here.

**Why (2) matters more than it looks:** blocked from merging, OpenCode improvised —
three refused `git checkout`s, then a plain local commit on the detached HEAD which it
reported to the activity log as a merge, complete with a SHA (`63835cc`) that is a
dangling commit on no branch. Nothing was pushed and the record has been corrected, but
**a broken tool induced a false completion claim in the permanent cross-CLI record.**
Ergonomics of the executor path is a delivery-integrity property, not a nicety.

## Constraints
- `tools/4ai-panes/pane-runner.ps1` **and `.ai/tools/dispatch-handoffs.sh`** are the
  files (see ADDENDUM (1) — same rule, both broken). **Kimi has an OPEN handoff
  (`202607122130`, fleet supervisor) touching the same file and has NOT started** —
  flag the overlap in your PR; whoever lands second rebases.
- **Version:** ADR-0012 — version assigned at MERGE, not on the branch. Do NOT bump
  `package.json`. Bullets under `## [Unreleased]`.
- PowerShell 5.1; the pre-commit hook parse-gates every staged `.ps1`.
- Read `docs/architecture/0004-worktree-multi-project-topology.md` (esp. the Amendment,
  which explicitly states the `.ai/` coordination plane has ZERO isolation across
  worktrees — that admission is the root of this bug).
- **Commit any `.ai/` artifact before your worktree goes away.**

## Deployment note
The post-commit hook syncs `tools/4ai-panes/*` to the owner's live launcher at
`C:\Users\rwn34\.rwn-auto\rwn-4AI-panes\`. **After this merges, the owner must restart
the panes** for the fix to take effect (the runner is loaded into memory at pane start —
this has caught us three times). Say so explicitly in your report.

## Deliverable
Branch `exec/kiro/fix-ai-junction-branch-cut` off `origin/master`. Push, open a PR,
route peer review to **KIMI**. Do NOT merge (Kimi reviews; then the fleet merges, Tier B,
with a version assignment at the merge point).

## Report back with
- the reproduce-the-bug output (before), and the fix working (after) — **for BOTH
  `pane-runner.ps1` and `dispatch-handoffs.sh`** (per ADDENDUM (1))
- which approach you chose and what it trades off
- the junction-degradation check
- the `gh pr merge --repo` fix + the result of your bare-`gh pr` sweep (ADDENDUM (2))
- confirmation the fail-loud / no-fallback-to-primary contract is intact
- **proof the dispatcher can now dispatch** — the bootstrap case: run
  `bash .ai/tools/dispatch-handoffs.sh --exec --only opencode` against a stale worktree
  with a dirty shared `.ai/` and show it reaches CLI invocation
- PR URL, and the explicit "owner must restart panes after merge" note

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kiro/done/`.

## Closing note (2026-07-13 — kimi-cli, retiring as moot)
Landed by kimi-cli as PR #70 (merged `e74714a`, version-assigned v0.0.38 at
`f819694`, records `c623ad3`) — all executor panes were down (this very bug), so
the owner authorized direct merge with post-hoc review. Both dispatchers
(`tools/4ai-panes/pane-runner.ps1` + `.ai/tools/dispatch-handoffs.sh`, kept 1:1)
now cut branches without `git checkout` (branch + symbolic-ref + scoped restore,
`.ai/` restored index-only so the live junction target is never written);
`scripts/wt-bootstrap.sh link_ai()` dies loud on a degraded real-dir `.ai/`.
Suite `tools/4ai-panes/test-pane-runner.ps1`: 132/0 green including the
prove-the-bug/prove-the-fix sandbox tests. Remaining follow-up (deploy-discipline
pin + junction reverse-write hazard) is routed to claude-code separately.
