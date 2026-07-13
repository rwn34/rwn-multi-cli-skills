# Junction Reverse-Write Guard — Spec

## Summary

A git operation run inside a linked executor worktree (ADR-0004) can see the
worktree's junctioned `.ai/` — which is really the PRIMARY checkout's live
`.ai/`, reached through a Windows directory junction — as its own
uncommitted local edit, and "discarding" that phantom edit writes the
worktree's stale committed blob back through the junction onto the primary's
real file. This spec documents the reproduced mechanism and a detector
(`.ai/tools/reverse-write-detector.sh`, wired warn-only into
`scripts/git-hooks/post-merge`/`post-checkout`) that flags a clobber after
the fact.

**A prevention layer (`git update-index --skip-worktree` on the stable `.ai/`
subset, `guard_ai_reverse_write()` in `scripts/wt-bootstrap.sh`) was
prototyped, landed on master (commit `cf9074d`, 2026-07-13), and then
REVERTED (2026-07-14) after the missing test this spec had flagged as a
precondition was finally run for real and failed.** `guard_ai_reverse_write()`
applied `--skip-worktree` on every dispatch, not only on a fresh worktree, and
the mechanism that blocks the clobber makes git blind to real edits on the
guarded paths by the same stroke: `git add`/`git status` on a stable
`.ai/instructions/**`/`.ai/tools/**` path from a guarded worktree silently
staged nothing. This is not hypothetical — it happened to real fleet work: a
kimi-authored SSOT edit to `.ai/instructions/operating-prompt/principles.md`
went invisible to `git status` for a full session under the guard, and only
surfaced when a different investigation happened to compare on-disk content
against the worktree's index by hand. **Status: prevention is REMOVED,
permanently pending a fundamentally different design** (see "Prevention —
REMOVED" below for the post-mortem and the reasoning against re-attempting the
same shape). Detection (the warn-only detector) remains the only guard layer.
A new self-heal step in `wt-bootstrap.sh` clears any leftover `--skip-worktree`
bits it finds on every run, so worktrees created under the old, reverted
guard converge back to visibility without manual intervention.

## Motivation

On 2026-07-13, between ~06:15 and ~07:11, the canonical
`.ai/tools/dispatch-handoffs.sh` in the primary checkout was silently
rewritten to its pre-PR#70 blob while PR #70 (which fixed it) was already
merged to master. Kimi restored it with `git restore --source=master
--worktree`. Nobody had proven what wrote it — the leading hypothesis was a
git operation (checkout/merge/restore/rebase/stash) executed in a pre-fix
worktree, writing tracked `.ai/**` paths that land on the canonical files
because every worktree's `.ai/` is a directory junction into the primary's
real `.ai/` (`scripts/wt-bootstrap.sh`'s `link_ai()`, per ADR-0004).

This spec is the result of `.ai/handoffs/to-kiro/done/202607130150-junction-
reverse-write-guard.md`, which asked for (1) a sandboxed reproduction before
any fix, (2) a detector regardless of what the reproduction found, and (3)
prevention guided by what the reproduction proved — explicitly ruling out
`git sparse-checkout` (would delete canonical files through the junction)
and asking `--skip-worktree`/`--assume-unchanged` to be tested empirically
rather than reasoned about, since it plausibly breaks legitimate `.ai/`
commits from a worktree.

**Discriminator correction (2026-07-13, per
`.ai/handoffs/to-kiro/open/202607130712-fix-reverse-write-detector-
discriminator.md`, landed as commit `e84284c`):** the detector's first
version (described in an earlier draft of this spec) skipped every path
`git status --porcelain` listed as dirty, on the theory that a dirty path is
"a real local edit in progress, not a reverse-write." That reasoning is
backwards for exactly the incident this spec exists to catch: the clobber
writes a stale *committed* blob into the primary's working tree through the
junction, and the primary's index does not know about it — so `git status`
reports that path as modified. Verified empirically in a sandbox reproducing
the real mechanism: the old dirty-skip version printed `Reverse-writes: 0`
on a live clobber of `.ai/tools/dispatch-handoffs.sh`. The shipped detector
uses a **content-based discriminator instead** — see Design below — and
needs no dirty/clean guess at all.

## Non-goals

- **A `pre-checkout` git hook.** Git has no such hook; prevention at the git
  layer is structurally limited to what index state can influence, not to
  intercepting the command itself.
- **Fixing the handoff-numbering race** or any other `.ai/handoffs/**`
  collision class — unrelated to this junction mechanism.
- **Recovering churn that a clobber destroyed.** If a reverse-write
  overwrites uncommitted live coordination-plane state (not just a stable
  tracked file), that state is gone; no historical commit ever had it to
  restore from. This spec's guard protects tracked *stable* files, which by
  definition always have a committed blob to fall back to. It does not and
  cannot protect uncommitted churn.
- **A GUI or interactive prompt.** The detector is a script with a plain-text
  contract; wiring a human-facing dashboard is out of scope.
- **Wiring the detector into CI.** A fresh CI clone has no junction and no
  primary/worktree split, so the failure mode this spec addresses cannot
  occur there — and wiring it in would false-positive on any PR that
  legitimately edits a stable `.ai/**` path, since "differs from
  `origin/master`'s current blob" is exactly what a normal in-flight edit
  looks like from CI's vantage point. The detector is warn-only, primary-
  checkout-only, wired into `scripts/git-hooks/post-merge` and
  `post-checkout` (guarded to run only when `--git-dir` equals
  `--git-common-dir`, i.e. never inside a linked worktree) and callable
  standalone. See Alternatives for the earlier (incorrect) CI-wiring plan
  and why it was dropped.

## Design

### The mechanism (reproduced, not hypothesized)

The handoff's own hypothesis — a worktree checking out `master` directly, or
merging/rebasing onto it — turned out to be the wrong half of the story.
Reproduced empirically (Git Bash, real `mklink /J` junctions, a bare
`origin` remote, exactly mirroring `wt-bootstrap.sh`'s topology):

1. **`git checkout master` / `git switch master` / `git merge master` /
   `git rebase master` from a worktree all fail immediately** — git's own
   "branch already checked out elsewhere" guard refuses them outright. This
   closes the handoff's original hypothesis: nobody's worktree can check out
   `master` while the primary holds it.
2. **The real mechanism is a phantom diff.** A worktree's git index records
   whatever commit its branch was cut from (e.g. a pre-fix commit). The
   *actual bytes on disk* at that path are the PRIMARY's live content,
   reached through the junction — which may already be newer (e.g.
   post-fix). Git compares on-disk content against the worktree's own index
   and reports this as an uncommitted local edit the worktree never made:

   ```
   $ git status --porcelain .ai/tools/dispatch-handoffs.sh
    M .ai/tools/dispatch-handoffs.sh
   $ git show HEAD:.ai/tools/dispatch-handoffs.sh   # the worktree's own commit
   STABLE-V1
   $ cat .ai/tools/dispatch-handoffs.sh              # actual disk content, via junction
   STABLE-V2-FIXED
   ```

3. **This phantom diff blocks the worktree's own attempt to catch up**:
   `git merge origin/master`, `git rebase origin/master`, and `git pull` all
   abort with *"Your local changes to the following files would be
   overwritten by merge. Please commit your changes or stash them."* — a
   real, escalating annoyance for an executor mid-task.
4. **The textbook way to clear that block is the clobber.** `git checkout --
   .ai` or `git reset --hard HEAD` — the standard "discard changes I don't
   understand" moves — silently rewrite the PRIMARY's live file back to the
   worktree's stale committed blob, through the junction:

   ```
   $ git checkout -- .ai        # "clearing" the phantom diff
   $ cat <primary>/.ai/tools/dispatch-handoffs.sh
   STABLE-V1                    # clobbered — was STABLE-V2-FIXED
   ```

   `git reset --hard HEAD` does the identical thing and does **not**
   self-heal afterward (the merge that incidentally re-fixed it in the
   `checkout --` case is not guaranteed).

The real hole, in one sentence: **git's own safety net for "your local
changes would be overwritten" misfires against a junctioned coordination
plane, and its standard remedy is the clobber.**

### API / interface

**Detector — `.ai/tools/reverse-write-detector.sh`**

```
bash .ai/tools/reverse-write-detector.sh [--base <ref>] [--history-depth N]
  --base <ref>          compare against this ref's HEAD blob instead of
                         origin/master (default: origin/master, falling
                         back to master if no "origin" remote exists)
  --history-depth N     how many commits of a path's own history to scan
                         for a matching stale blob (default: 20)
```

**Discriminator (shipped, content-based — see the Motivation correction
above).** For every tracked, non-churn path under `.ai/`, compare the
on-disk blob hash against three things:

1. HEAD's committed blob for that path → match = clean, skip.
2. Any *earlier* commit's blob for that path (scanned up to
   `--history-depth` commits back) → match = **REVERSE-WRITE**.
3. Neither → a genuine novel local edit in progress, not flagged (that is
   ordinary work-in-progress, indistinguishable from a reverse-write by
   content alone, and is not this detector's job to catch).

This needs no `git status` dirty/clean signal at all — the on-disk blob hash
is compared directly against committed blobs, so a clobber that a dirty-skip
check would silently pass through is caught.

Output contract:

```
REVERSE-WRITE: <path> (on-disk blob <sha> matches earlier commit <sha>, not
  <base>'s current blob <sha> — see 'git log -- <path>')
Checked: <N> stable paths, Reverse-writes: <M>
```

Always exits 0 (fail-open — a detector that can itself take the fleet down
is worse than no detector), except on a genuine internal setup error (script
unreadable, root unresolvable), matching `check-ssot-drift.sh` /
`sync-replicas.sh`'s existing fail-closed-on-setup / fail-open-on-check
split.

**Prevention — REMOVED (was PROPOSED, then landed, then reverted for good) —
`scripts/wt-bootstrap.sh`: `guard_ai_reverse_write()`**

Originally designed and prototyped as a function called once per executor
after `link_ai()` in the main bootstrap loop, applying `git update-index
--skip-worktree` to every tracked, non-churn `.ai/` path. This spec's first
version left it unshipped precisely because the test that would prove it
safe — that a bootstrapped worktree can still `git add`/`git commit` a real
edit to a tracked **stable** `.ai/` path after the guard is applied — had
never been run; only the churn half (`.ai/activity/log.md`) was verified.

**It was re-proposed and landed anyway.** Commit `cf9074d` (2026-07-13,
kimi-cli) added `guard_ai_reverse_write()` to `scripts/wt-bootstrap.sh` and
wired it into the per-executor bootstrap loop, applying `--skip-worktree` to
the stable subset on **every** dispatch (not gated to first-creation). It
shipped without the missing test ever being run.

**The missing test was finally run for real, 2026-07-14, and it failed
exactly as this spec's first version predicted.** Two independent lines of
evidence, both against real fleet state, not a synthetic sandbox:

1. A kimi-authored SSOT edit to
   `.ai/instructions/operating-prompt/principles.md` — the log-read-discipline
   fix from handoff `202607131036` — went **invisible to `git status`** in the
   worktree it was written in. `git ls-files -v .ai` showed the file marked
   `S` (skip-worktree). The edit existed on disk, was real, and was about to
   be certified done while absent from any commit. It was discovered only
   because a separate investigation happened to diff on-disk content against
   the worktree's index by hand — the exact silent-drop failure mode
   `--skip-worktree` is documented to cause, now observed in production rather
   than merely predicted.
2. `tools/4ai-panes/test-pane-runner.ps1`'s own regression suite went from
   132/0 (pre-`cf9074d` baseline shape) to 144 passed / 3 failed, all three in
   the `av4` sub-block that exercises `wt-bootstrap.sh`'s junction-degradation
   guard directly. (Root-cause note, added after a fuller investigation than
   the fixing commit had time for: the specific 3-failure signature is a
   *pre-existing test-isolation bug* in `av4` unrelated to
   `guard_ai_reverse_write()` — a prior test block leaves a stale staged diff
   on `.ai/activity/log.md` that `av4`'s own "clean real dir" setup step
   doesn't clear — and reproduces identically with `guard_ai_reverse_write()`
   removed. The regression's correlation with `cf9074d` was real but
   coincidental; item 1 above is the actual, load-bearing evidence against the
   guard.)

**Decision: prevention is removed, and this shape will not be re-proposed.**
Unlike the first pull (a precautionary revert before the evidence existed),
this is now a decision made *with* the missing test's answer in hand, and the
answer is negative. The churn/stable path-classification axis this guard used
is not a safe basis for `--skip-worktree`: any script, agent, or human that
legitimately edits a "stable" `.ai/` path from inside a guarded worktree loses
that edit with zero error and zero diff. A prevention layer along a different
axis (a `pre-commit`/`pre-checkout` hook that refuses ops touching tracked
`.ai/**` from a worktree; a read-only bind instead of a junction) remains a
theoretical option but is **not** designed here — it would need its own spec
and its own empirical proof before landing, given this guard's track record.
Detection (`.ai/tools/reverse-write-detector.sh`, unchanged by this revert) is
the only guard layer as of this writing.

**Self-heal for worktrees created under the old guard.** Removing
`guard_ai_reverse_write()` from `wt-bootstrap.sh` does not retroactively clear
bits it already set — a worktree bootstrapped or re-dispatched under `cf9074d`
keeps its `S` markers until something clears them. `wt-bootstrap.sh` now
calls a `heal_skip_worktree()` step for every executor on every run (create OR
skip/reuse), enumerating `git ls-files -v -- .ai` for `^S` entries and clearing
each with `git update-index --no-skip-worktree`. Idempotent — a worktree with
zero bits is a fast no-op — so it imposes no meaningful cost on the common
case and guarantees convergence for the fleet's existing worktrees on their
next bootstrap, without requiring anyone to remember to run a one-off cleanup
command.

### Data

**The churn/stable split** (identical classification used independently by
the detector and the prevention layer, on purpose — see Alternatives):

| Class | Patterns | Treatment |
|---|---|---|
| Churn | `.ai/activity/log.md`, `.ai/activity/entries/*`, `.ai/handoffs/*`, `.ai/reports/*`, `.ai/*/archive/*`, `.ai/.claim-*.json` | Never touched by either mechanism — legitimately differs from any historical commit at all times |
| Stable | everything else under `.ai/` (`.ai/tools/**`, `.ai/instructions/**`, etc.) | Detector compares on-disk blob against `origin/master`'s HEAD blob and recent history; prevention (PROPOSED, not shipped) would apply `--skip-worktree` |

This reuses ADR-0010's own two-way split of `.ai/**` verbatim (that ADR
defined "churn" vs "stable infrastructure" for the activity-log spool
design; this spec's classification is the same partition applied to a
different problem).

### UX / behavior

- **Detector, wired warn-only into `scripts/git-hooks/post-merge` and
  `post-checkout`** (never CI — see Non-goals). Guarded to run only in the
  PRIMARY checkout (a linked worktree's `--git-dir` differs from its
  `--git-common-dir`; a primary checkout's does not). A clean tree prints
  `Checked: N stable paths, Reverse-writes: 0` to stderr only if a hit is
  found — on a hit, both hooks print a loud banner naming the affected
  path(s) and pointing at this spec for the mechanism + recovery. Both
  hooks stay fail-open per their own post-event-hook contract: the detector
  can never block a merge or checkout, only warn after it completes.
- **Prevention (PROPOSED, then landed, then REMOVED for good)**: the design
  called for an operator or CLI running `wt-bootstrap.sh` to get the guard for
  free — no new flag, no opt-in — with every stable `.ai/` path in that
  worktree `--skip-worktree`'d before the function returns. **This shipped
  (`cf9074d`) and has been reverted.** `guard_ai_reverse_write()` does not
  exist in `scripts/wt-bootstrap.sh` as of this writing; running it applies no
  skip-worktree bits to anything. See "Prevention — REMOVED" above for why.
- **Self-heal, added with the revert**: every `wt-bootstrap.sh` run (create OR
  skip/reuse) now clears any leftover `--skip-worktree` bits it finds under
  `.ai/` in that worktree (`heal_skip_worktree()`). A worktree bootstrapped
  under the old, reverted guard converges back to full `git status`/`git add`
  visibility the next time it is bootstrapped or re-dispatched — no manual
  `git update-index --no-skip-worktree` sweep required.
- **What changed for an operator who runs `git checkout -- .ai` or
  `git reset --hard` today**: nothing new — those commands clobber exactly as
  described in Design → "The mechanism", same as before the guard was ever
  proposed. Only the detector's after-the-fact warning exists to catch it.
  (For the ~2026-07-13 window the guard WAS live on master, those commands
  instead failed loud — see "Prevention — REMOVED" for why that trade was
  rejected in favor of reverting to the pre-guard behavior.)
- **What does NOT change regardless of prevention's status**:
  `.ai/activity/log.md`, `.ai/handoffs/**`, `.ai/reports/**` commits from any
  worktree work exactly as before — the churn/stable split (which the removed
  guard used, and which the detector still uses) never touches churn paths.

- **Windows directory junctions** (`mklink /J`) via `wt-bootstrap.sh`'s
  existing `link_ai()` — this guard is meaningless without them; see the
  "what breaks first" note below.
- **`git update-index --skip-worktree`** — a standard git feature (no new
  binary, no new package), available in every git version this framework
  already requires.
- **Git Bash on Windows** — same requirement `wt-bootstrap.sh` already
  carries. `MSYS_NO_PATHCONV` awareness is required when writing any *new*
  script that runs `git show <ref>:<path>` in this codebase — see the
  landmine note below; it does not affect the shipped scripts (the detector
  avoids the syntax entirely — see the discriminator's own header comment
  for the `git ls-tree`/`git hash-object`/`git cat-file` pattern it uses
  instead; `wt-bootstrap.sh`'s new function never uses a colon-joined
  ref:path argument either).

### A landmine found and avoided while building this: MSYS path-conversion of `git show <ref>:<path>`

The detector's first draft used `git show "$BASE_REF:$path"` per file. Under
Git Bash on Windows, MSYS's automatic POSIX-to-Windows path conversion saw
the first `/` after the ref name and mangled the single argument
`origin/master:.ai/tools/dispatch-handoffs.sh` into the literal string
`origin\master;.ai\tools\dispatch-handoffs.sh`, which git then rejected as
an ambiguous revision. `MSYS_NO_PATHCONV=1` fixes it, but the more robust
fix — used in the shipped detector — is to never construct a colon-joined
`ref:path` token at all: `git ls-tree -r <ref> -- .ai` returns `<mode> blob
<sha>\t<path>` for every tracked file in one call, and `git hash-object` /
`git ls-tree <commit> -- <path>` read blob hashes by bare object id or by a
non-colon-joined commit+path pair, which has no slash-adjacent-to-colon for
MSYS to "helpfully" reinterpret. No prior script in `.ai/tools/` used the
`ref:path` syntax; this is the first, and the workaround is now the
established pattern for anything that needs to.

## Alternatives considered

- **`git sparse-checkout` to exclude `.ai/`.** Ruled out before
  implementation (per the handoff's own explicit constraint) and not
  re-tested: with a junction, git "removing" those paths from the worktree
  would delete the canonical files they point at. Actively dangerous.
- **`post-checkout` / `post-merge` / `post-rewrite` detect-and-restore
  hooks.** Considered as the fallback if prevention proved infeasible. Not
  needed: `--skip-worktree` is a strictly better fix where it applies — it
  prevents the clobber outright rather than detecting and repairing it after
  the fact, and it has none of a restore-hook's inherent risk (a hook that
  restores "the delta git just applied" is itself another git operation
  that could go wrong at the worst possible moment). Not implemented, but
  not dismissed either — if `--skip-worktree` is ever found to have a gap
  the detector doesn't cover, a narrow post-checkout restore targeting only
  the exact paths that just changed is the next thing to try.
- **A single shared churn/stable classification function, sourced by both
  the detector and `wt-bootstrap.sh`.** Deliberately rejected. The two
  copies are short (six `case` patterns each) and are kept in sync by a
  code comment in both files pointing at each other, rather than a shared
  library file. Rationale: prevention and detection are meant to be
  independent safety layers — if one has a bug, the other should not
  automatically inherit it. A shared helper would collapse that redundancy
  into a single point of failure for both mechanisms at once.
- **Fixing the phantom diff at its root** (e.g. by never letting a
  worktree's index diverge from origin/master for stable paths in the first
  place, via some form of forced sync on every bootstrap). Not pursued:
  `--skip-worktree` addresses the same symptom with less mechanism — it
  doesn't require keeping two trees' indexes in lockstep, it just tells git
  to stop comparing a specific worktree's disk content against its own
  index for the paths where that comparison is meaningless (because the
  "real" content is always primary's, reached through the junction).
- **A dirty/clean (`git status --porcelain`) discriminator for the
  detector.** This was the detector's *first shipped version* and is
  superseded, not merely considered — see the Motivation correction above.
  It is recorded here rather than deleted because the failure mode is
  instructive: it reasoned about the wrong asymmetry (local-edit-in-progress
  vs. not) instead of the one that actually distinguishes a reverse-write
  (matches an earlier committed blob vs. matches no historical blob at all),
  and it passed every test that didn't specifically reproduce the live
  clobber — it takes an adversarial-content sandbox test to catch it.
- **Wiring the detector into CI (`framework-check.yml` / `gates.yml`).**
  This was the *first shipped version's* plan and is also superseded — see
  Non-goals. A fresh CI clone has no junction and no primary/worktree split,
  so the signal this detector is tuned for cannot occur there, and comparing
  "differs from `origin/master`" alone (without the history-scan
  discriminator) would false-positive on any PR mid-flight editing a stable
  `.ai/**` path.

## Verification (executed, not just designed)

**Honest limit on what this section proves (added on review, 2026-07-13):**
**Honest limit on what this section proves (added on review, 2026-07-13):**
(a) and (b) below are proven and shipped. (c) and (d) were run against the
`guard_ai_reverse_write()` prototype **before** it was pulled from the
branch (see Design → "Prevention — REMOVED") — they show what
the prototype did in a sandbox, not evidence that the shipped code contains
it, because it does not. (d) in particular is incomplete on its own terms:
it proves churn commits still work under the guard, but the test the
originating handoff actually required — a real edit to a **stable** path,
staged and committed, under the guard — was never run. Kept below for the
record.

**Update (2026-07-14) — the missing test WAS eventually run, against a later
re-landing of this same prototype (`cf9074d`), and it failed.** See Design →
"Prevention — REMOVED" for the two pieces of evidence (a real SSOT edit going
invisible to `git status`, and the `test-pane-runner.ps1` regression). (c) and
(d) below are retained as historical record of what the *sandbox prototype*
demonstrated before that; they are not superseded so much as answered — the
sandbox showed the guard worked for the cases it was asked to protect, and the
real fleet showed the one case nobody asked it to protect against (a
legitimate edit to a guarded path) breaks silently. Both are true; only the
second is disqualifying.

**(a) Sandbox reproduction** — see Design §"The mechanism" above for the
exact commands and output. Ran against a real `mklink /J` junction (not a
POSIX symlink stand-in), a bare `origin` remote, and a worktree branch cut
from a pre-fix commit — mirroring `wt-bootstrap.sh` and
`ensure_declared_base_branch()`'s real topology.

**(b) Detector** — the content-based discriminator fires correctly on a
live clobber and returns `Reverse-writes: 0` on a clean tree:

```
Checked: 36 stable paths, Reverse-writes: 0
```

The predecessor dirty-skip discriminator was proven blind on the identical
live-clobber sandbox (`Reverse-writes: 0` on a real clobbered path) — the
exact defect the content-based rewrite (commit `e84284c`) exists to fix; see
the Motivation correction and the superseded Alternative above.

**(c) Prevention neutralizing the repro** — end-to-end against a freshly
`wt-bootstrap.sh`-bootstrapped worktree, forced onto a pre-fix branch, then
both round-3 clobber moves attempted:

```
-- attempt: git checkout -- .ai --
primary after checkout -- .ai attempt: STABLE-V2-FIXED
SAFE (unchanged)
-- attempt: git reset --hard HEAD --
error: Entry '.ai/tools/dispatch-handoffs.sh' not uptodate. Cannot merge.
fatal: Could not reset index file to revision 'HEAD'.
primary after reset --hard HEAD attempt: STABLE-V2-FIXED
SAFE (unchanged)
```

Also tested and confirmed refused (not silently bypassing the guard): the
bare `git checkout -- <path>` form, `git clean -fd .ai`, a `git stash` /
`git stash pop` round-trip, and an explicit-ref `git checkout <sha> --
<path>` — all either refuse cleanly or no-op; none clobber primary.

**Honest limit, found and kept**: `--skip-worktree` does not make an
*ordinary* `git merge origin/master` succeed when the base branch's own
history touches a guarded path — git can still refuse with "local changes
would be overwritten" for that specific path (merge has its own overwrite
check, independent of the phantom-diff mechanism `--skip-worktree`
silences). It is verified to interact **cleanly** with the actual production
flow this framework uses to advance a worktree's branch —
`ensure_declared_base_branch()`'s `symbolic-ref` + two-scoped-`restore`
pattern in `.ai/tools/dispatch-handoffs.sh` / `Ensure-DeclaredBaseBranchReal`
in `tools/4ai-panes/pane-runner.ps1` — which already restores `.ai/`
index-only (per PR #70) and everything else worktree+staged:

```
-- restore (worktree+staged) for everything except .ai --
restore(1) rc=0
-- restore (staged only) for .ai --
restore(2) rc=0
primary .ai/tools/dispatch-handoffs.sh after the mimic'd flow: STABLE-V2-FIXED
worktree .ai/tools/dispatch-handoffs.sh (via junction): STABLE-V2-FIXED
git status afterward: (clean)
```

This guard is a second, independent hardening layer for every *other* git
command a human or a CLI might run in that worktree — it does not replace
PR #70's fix to the dispatcher's own flow; it extends the same protection to
commands PR #70 never touched.

**(d) Legitimate churn commits still work** — confirmed at both the raw
sandbox level and end-to-end through a real `wt-bootstrap.sh` run: with
`--skip-worktree` active on the stable subset, `.ai/activity/log.md` edits
still `git add` and `git commit` cleanly from the worktree, with `rc=0` in
every trial.

**(e) Existing suites** — `tools/4ai-panes/test-pane-runner.ps1`:
**151 passed, 0 failed** as of the 2026-07-14 revert (adds a new `av5`
regression block asserting the exact inverse of the failed test above: after
a fresh re-bootstrap, zero `--skip-worktree` bits remain under `.ai/`, and a
real edit to a stable SSOT-shaped path shows up in `git status` and stages
with `git add`). `.ai/tests/test-dispatch-worktree.sh`:
**22 passed, 2 failed** — the same 2 failures reproduce identically with
this change's edits stashed out (a real `kiro-cli` binary installed on this
machine's PATH shadows the test's stub `kiro-cli`, an environment artifact
unrelated to the worktree/junction mechanism this spec addresses; not caused
or fixed by this change).

**(f) The reverse-write detector, re-verified after the revert** — run
standalone against this repo's own primary-checkout state:

```
Checked: 39 stable paths, Reverse-writes: 0
```

Detection is unaffected by the prevention layer's removal — it was never
coupled to `guard_ai_reverse_write()`'s presence.

## What breaks first if the surrounding system changes

Both the detector and the prevention layer assume `.ai/` in a worktree is a
**directory junction into the primary's real `.ai/`** — the exact hazard
this spec addresses only exists because of that indirection. If
`wt-bootstrap.sh` ever stops junctioning `.ai/` (e.g. moves to a real copy +
a separate sync step, as some other frameworks do), both mechanisms become
dead code: there would be nothing to reverse-write *through*, because a
worktree's `.ai/tools/dispatch-handoffs.sh` would simply be its own file
again, not a window onto primary's. `guard_ai_reverse_write()`'s
`--skip-worktree` calls would still be harmless in that world (they'd just
suppress status/diff noise for files that happen to be identical across
trees), but `reverse-write-detector.sh`'s entire premise — "a stable file's
on-disk content matches an earlier commit of that path, not the current
one" — would stop being a junction-specific signal and start being a
generic (much noisier) "this worktree is behind master" signal, which is
not what it is tuned for. Anyone making that architectural change should
revisit this spec, not just delete the two functions.

## Open questions

- **Should the detector ever be promoted from warn-only hooks to a
  soft-blocking CI annotation** once it has run clean in production for
  some period? Deferred, and now leaning against per the Non-goals
  correction above: CI has no junction and no primary/worktree split, so
  the signal this detector needs (comparison against recent commit history,
  not just `origin/master`'s current blob) has no meaningful CI analogue.
  Revisit only if a future architectural change gives CI an equivalent
  primary/worktree split to reason about.
- **Should `guard_ai_reverse_write()` be re-applied by anything other than
  `wt-bootstrap.sh`?** A worktree that already exists (created before this
  guard shipped) only gets the skip-worktree bits the next time
  `wt-bootstrap.sh` runs against it (which happens on every dispatch via
  `ensure_cli_worktree()`, so in practice this self-heals quickly) — but
  there is no explicit "re-guard all existing worktrees now" command.
  Deferred as unnecessary complexity unless a real gap surfaces.

## References

- `.ai/handoffs/to-kiro/done/202607130150-junction-reverse-write-guard.md` —
  the handoff this spec implements.
- `.ai/handoffs/to-kiro/done/202607130712-fix-reverse-write-detector-
  discriminator.md` — the discriminator correction (dirty-skip → content-
  based) landed as commit `e84284c` and folded into this spec.
- `.ai/handoffs/to-kiro/open/202607130755-reconcile-detector-branch-with-
  sibling.md` — the handoff that reconciled this spec onto the corrected
  detector's branch and removed the CI-wiring plan this earlier draft
  carried.
- `docs/architecture/0004-worktree-multi-project-topology.md` — the
  worktree/junction topology this spec's mechanism depends on entirely (see
  "What breaks first" above); its 2026-07-11 amendment already names the
  coordination-plane write race as unresolved.
- `docs/architecture/0010-activity-log-entry-spool.md` — source of the
  churn/stable classification this spec reuses verbatim for `.ai/**`.
- `scripts/wt-bootstrap.sh` — `link_ai()` (the junction this spec's mechanism
  depends on entirely (see "What breaks first" above), plus `heal_skip_worktree()`
  (the self-heal added with the 2026-07-14 revert). Does NOT contain
  `guard_ai_reverse_write()` — that function is PROPOSED, not shipped (see
  Design → "Prevention — REMOVED").
- `.ai/handoffs/to-kiro/open/202607131819-remove-skip-worktree-guard-land-
  detector.md` — the handoff that removed `guard_ai_reverse_write()` from
  master a second time (after commit `cf9074d` had re-landed it), added
  `heal_skip_worktree()`, and landed the detector + this spec on master for
  the first time.
- `.ai/tools/dispatch-handoffs.sh` — `ensure_declared_base_branch()`, whose
  existing `symbolic-ref` + two-scoped-`restore` pattern (PR #70) this
  spec's prevention layer is verified to coexist with cleanly.
- `.ai/tools/reverse-write-detector.sh` — the detector this spec documents.
- `scripts/git-hooks/post-merge`, `scripts/git-hooks/post-checkout` — the
  warn-only hooks the detector is wired into (never CI).
- `.ai/tools/check-ssot-drift.sh`, `.ai/tools/sync-replicas.sh` — the
  fail-open / CWD-independence conventions the detector follows.
- `.ai/handoffs/to-kiro/done/202607122030-drift-checker-cwd-false-pass.md` —
  the prior fix establishing the `$0`-string-based `$ROOT` resolution
  pattern this spec's detector reuses.
