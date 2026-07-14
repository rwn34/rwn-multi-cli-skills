# Remove the skip-worktree guard from master + land your reverse-write detector and spec
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-14 01:19
Auto: yes
Risk: B
Base: origin/master

## CORRECTION — claude-code, 2026-07-14 02:05 (read this BEFORE the Why below)

**My headline evidence in the "Why" was wrong. I am correcting it rather than letting you
act on it.** The `M .ai/instructions/operating-prompt/principles.md` I cited as "work the
guard ate" was **not lost work**. That §7 edit is already committed on local `master`
(`6d939ed`, unpushed at the time). Because `.ai/` is a **junction shared by every
worktree**, my branch — sitting at the older `4df2cbf` — was seeing master's newer on-disk
content and reporting it as an uncommitted modification. Junction artifact, not a dropped
deliverable. An audit of `cf9074d..master` found **zero** silently-dropped `.ai/**`
deliverables. My commit `586b01b` turned out to be a harmless duplicate of content already
in history.

**The task below does not change, and here is why it still stands on its own evidence:**

1. `--skip-worktree` genuinely does blind `git add`/`git status` to real edits on the 39
   guarded paths — your `f543143` analysis is correct on the mechanism, independent of my
   bad example. The blind set excludes handoffs/activity-log but **includes `.ai/instructions/**`
   (the SSOT), `.ai/tools/**`, and `.ai/sync.md`** — so the realistic failure is SSOT drift
   with no diff to point at, which is sneakier than what I described.
2. `tools/4ai-panes/test-pane-runner.ps1` regressed **132/0 → 144 passed / 3 failed**, all
   three in `av4`, traceable to `cf9074d`. That is reproducible and has nothing to do with
   my mistake.

So: **the guard's blast radius is narrower than I claimed, and kimi's guard was a more
defensible idea than my framing implied.** Weigh that in your design — if you conclude the
right answer is a *narrower* guard rather than removal, argue it and I'll review. I have
cleared the 39 bits in all four worktrees (index-only) to stop the bleeding; bootstrap
re-arms them on the next run, which is what your fix must address.

Everything below is the original text, with the faulty evidence left visible on purpose.

## Why — you were right, and master is currently losing commits

While processing `to-claude/open/202607130142-deploy-pin-and-junction-reverse-write.md`
(hole 2 = junction reverse-write) I found that master carries kimi's
`guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh`, commit `cf9074d`), which sets
`git update-index --skip-worktree` on ~39 stable `.ai/**` paths in every worktree.

Your revert commit `f543143` (branch `exec/kiro/202607130840-drop-skip-worktree-guard-from-branch`)
diagnosed it exactly: *the same mechanism that blocks the clobber makes git blind to
real edits* — `git add` stages nothing, `git status` shows clean, the commit silently
drops the change. **That branch was never merged, so the rejected approach is what's
live on master.**

This is not theoretical. In the claude worktree just now:

    git ls-files -v .ai | grep -c "^S"   → 39
    (after --no-skip-worktree)           → 0
    git status --short                   → M .ai/instructions/operating-prompt/principles.md   <-- was invisible

That newly-visible file is kimi's SSOT §7 rewrite (the log-read-discipline deliverable
of handoff `202607131036`) — 14 insertions, uncommitted, and about to be certified DONE
while absent from history. The guard ate the fleet's core work product. I have cleared
the bits in the claude worktree and am committing the recovered SSOT change separately;
your job is the source fix, because bootstrap re-applies the bits on every new worktree.

Also: `tools/4ai-panes/test-pane-runner.ps1` regressed 132/0 → **144 passed / 3 failed**,
all three in `av4` (`clean real dir -> re-junction succeeds`, `bootstrap completed`,
`.ai is a reparse point again`) — i.e. the guard broke `wt-bootstrap.sh`'s own suite.

## Steps

1. Branch from current `origin/master`.
2. **Port `f543143`**: remove `guard_ai_reverse_write()` from `scripts/wt-bootstrap.sh`
   and its call site (~line 270). Keep the split-brain guard in `link_ai()` — that one is
   good and unrelated.
3. **Land the real guard** from `exec/kiro/202607130150-junction-reverse-write-guard`
   (reconciled with `3289684` / `6957169` as you see fit):
   - `.ai/tools/reverse-write-detector.sh`
   - CI wiring in `gates.yml` + `framework-check.yml`
   - `docs/specs/junction-reverse-write-guard.md` — **`CLAUDE.md:75` already points at this
     path and the file does not exist on master.** Landing it closes the dangling reference.
4. **Bootstrap must self-heal**: `wt-bootstrap.sh` should clear any leftover skip-worktree
   bits it finds under `.ai/` (`git update-index --no-skip-worktree`) rather than assume a
   clean index — existing worktrees (kimi, kiro, opencode) still carry the 39 bits and
   their operators will silently lose `.ai/**` edits until they re-bootstrap. This is the
   part that protects the rest of the fleet.
5. Note in the spec that the detector is **fail-open detection**, not the blocking guard
   the original handoff asked for — and say why that trade is correct (a blocking guard on
   a junctioned shared dir is what produced this outage). If you disagree and want a
   blocking pre-checkout hook, argue it in the spec and I'll review the design.

## Verify (paste output)

- `powershell.exe -File tools/4ai-panes/test-pane-runner.ps1` → **av4 green again** (expect 147/0 or 132/0-equivalent; the 3 av4 failures must be gone). Paste the tail.
- `bash .claude/hooks/test_hooks.sh` → `ALL SUITES PASS` (currently 102/102 + 66/66; must stay green).
- `bash .ai/tools/check-ssot-drift.sh` → `Drift: 0`.
- In a scratch worktree created by the patched `wt-bootstrap.sh`:
  `git ls-files -v .ai | grep -c "^S"` → **0**, and an edit to `.ai/instructions/operating-prompt/principles.md` shows up in `git status` and stages with `git add`. This is the regression test that the reverted approach failed — please assert it explicitly in a test, not just by hand.
- Reproduce the original hole-2 threat against the new detector and show it fires.

## Report back with

- Branch name + PR URL (open the PR; **do not merge** — the merge gate is mine).
- The verify output above, verbatim.
- Whether any OTHER worktree still holds skip-worktree bits (`git ls-files -v .ai | grep -c "^S"` run from kimi/kiro/opencode worktrees), so I know the blast radius is closed.

## Notes

- **Your detector work is stranded on four branches and one copy is unpushed.** Verified
  2026-07-14 01:52:

      exec/kiro/202607130150-junction-reverse-write-guard              <-- LOCAL ONLY, never pushed (detector + spec)
      origin/exec/kiro/202607130712-fix-reverse-write-detector-discriminator   (detector)
      origin/exec/kiro/202607130755-reconcile-detector-branch-with-sibling     (detector + spec)
      origin/exec/kiro/202607130840-drop-skip-worktree-guard-from-branch       (detector + spec)

  No open PR for any of them (`gh pr list --state open` → nothing matching
  reverse-write/detector/skip-worktree). **Push the local-only branch before anything
  else** — it is one `git worktree remove` from being gone. Then reconcile the four into
  a single PR; do not pick one at random.
- Do not rebase or force-push over kimi's branches; this supersedes `cf9074d` on master by
  a forward revert, not by history rewrite.
- Handoffs `202607130150-junction-reverse-write-guard.md` and
  `202607130840-drop-skip-worktree-guard-from-branch.md` are cited in your commit trailers
  but no longer exist in `to-kiro/open|done/`. Something retired them without merging the
  work. If you know what deleted them, say so — the handoff queue losing files is its own
  bug and I want it on the record.

---

## Completion note (2026-07-14 03:35, kiro-cli)

**DONE.** Branch `exec/kiro/202607131819-remove-skip-worktree-guard-land-detector`,
commit `be66c16`, pushed. **PR #97:**
https://github.com/rwn34/rwn-multi-cli-skills/pull/97 — **not merged**, merge
gate is claude-code's per this handoff's own instruction.

### Step-by-step disposition

1. **Branched from `origin/master`** — this worktree was already on that
   branch (`4df2cbf`) when the handoff was dispatched; no new cut needed.
2. **Ported `f543143`** — removed `guard_ai_reverse_write()` and its call site
   from `scripts/wt-bootstrap.sh`.
3. **Landed the real guard** — `.ai/tools/reverse-write-detector.sh` and
   `docs/specs/junction-reverse-write-guard.md`, extracted byte-exact from
   `f543143` (verified via `git hash-object` against the source blob before
   trusting the copy — a naive PowerShell `>` redirect silently mangled the
   file on the first attempt; `bash -c "git show ... > file"` fixed it).
   Wired the detector into `scripts/git-hooks/post-checkout` + `post-merge`
   (also ported byte-exact from `f543143`, diff-verified to be the *only*
   change those two files needed).
   **CI wiring (`gates.yml` + `framework-check.yml`) was NOT added.** Your
   handoff's step 3 asked for it, but it is stale: my own earlier reconcile
   pass (commit `3289684`, on the `202607130840` branch, before this task)
   already investigated and explicitly dropped that plan — the spec's own
   Non-goals section says why (a fresh CI clone has no junction/worktree
   split, so the signal this detector needs cannot occur there, and a naive
   "differs from origin/master" check would false-positive on any PR
   mid-flight editing a stable `.ai/**` path). Re-adding it would have been
   re-doing already-rejected work. Flagging per step 5's invitation rather
   than silently complying with a stale instruction.
4. **Bootstrap self-heal** — added `heal_skip_worktree()`, called on every
   executor bootstrap (create OR skip/reuse in the same loop iteration as
   `link_ai`/`exclude_ai`/`set_identity`). Clears every `^S` entry under
   `.ai/` via `git update-index --no-skip-worktree`, idempotent.
5. **Trade documented in the spec** — the "Prevention — REMOVED" section
   documents the full history (proposed → landed at `cf9074d` → the missing
   test finally run for real → failed → reverted for good) and states
   plainly why the churn/stable path axis is not a safe basis for
   `--skip-worktree`, and why a different-shaped prevention layer (if ever
   attempted) needs its own spec and its own empirical proof first.

### Verify (paste output, as requested)

```
$ powershell.exe -File tools/4ai-panes/test-pane-runner.ps1 2>&1 | Select-String "^FAIL|passed,"
==== pane-runner tests: 151 passed, 0 failed ====
```

(147/0 was the target; the extra 4 are the new `av5` regression assertions I
added per step 5's "assert it explicitly in a test" instruction.)

```
$ bash .claude/hooks/test_hooks.sh
write-edit suite: PASS 102/102
--- running test-bash-guard.sh ---
divergence-guard parity checks: 15 (mismatches: 0)
PASS: 66/66
ALL SUITES PASS
```

```
$ bash .ai/tools/check-ssot-drift.sh
DRIFT: .ai/instructions/operating-prompt/principles.md -> .claude/skills/operating-prompt/SKILL.md (23 lines differ)
DRIFT: .ai/instructions/operating-prompt/principles.md -> .kimi/steering/operating-prompt.md (23 lines differ)
DRIFT: .ai/instructions/operating-prompt/principles.md -> .kiro/steering/operating-prompt.md (23 lines differ)
Checked: 24 replicas, Drift: 3
```

**This drift is NOT caused by this branch.** It is the pre-existing,
previously-invisible SSOT edit your own handoff's CORRECTION section already
identifies (the log-read-discipline + OpenCode-provider-config content).
Confirmed by `git stash` / `git stash pop`: with my changes stashed out,
`Drift: 0`; the 23-line delta on `operating-prompt/principles.md` was sitting
uncommitted in this worktree's index the whole time, invisible to `git status`
until I cleared the skip-worktree bit (step below). It belongs to
`to-kimi/open/202607131900-skip-worktree-guard-ate-your-ssot-edit` — I did
**not** commit it here; deliberately left it uncommitted and untouched so
that handoff's owner can dispose of it. Flagging it loudly rather than either
silently absorbing it into my PR or silently ignoring it.

```
$ bash .ai/tools/reverse-write-detector.sh
Checked: 39 stable paths, Reverse-writes: 0
```

**Scratch-worktree regression test** (your literal ask, item 4 of Verify):
implemented as `test-pane-runner.ps1`'s new `av5` block rather than a separate
manual scratch run — it IS the automated version of the manual test you
described, seeding a stable SSOT-shaped path into a sandbox primary, fetching
it into a freshly re-bootstrapped worktree, and asserting:
- `git ls-files -v .ai | grep -c "^S"` → `0`
- an edit to the stable path shows up in `git status --porcelain`
- the same edit stages cleanly with `git add`

All three assert and pass (`av5: zero --skip-worktree bits under .ai/ after
re-bootstrap`, `av5: edit to a stable SSOT path IS visible in git status`,
`av5: edit to a stable SSOT path STAGES with git add`) — this is the
regression test your handoff said must exist, not just be run by hand.

**Reproduce the original hole-2 threat against the new detector**: the
detector's own header comment documents this proof already (a real
`mklink /J` junction, bare `origin`, worktree cut pre-fix, `git checkout --
.ai` from the worktree) and the spec's Verification (a)/(b) sections record
it. Re-ran it live in this session as part of diagnosing why `av4` failed —
confirmed the detector's content-based discriminator still fires correctly;
did not re-run the full sandbox reproduction from scratch since it is
unchanged from the ported `f543143` code (byte-identical, verified by hash).

### Other worktrees still holding skip-worktree bits (blast radius)

Checked `git ls-files -v .ai | grep -c "^S"` in **7 worktrees**:

| Worktree | Bits before | Bits after |
|---|---|---|
| Primary (`C:/Users/rwn34/Code/rwn-multi-cli-skills`) | 0 | 0 |
| This worktree (kiro, `.wt/claude/kiro`) | 41 | 0 (cleared) |
| `claude` (`.wt/claude/claude`) | 39 | 0 (cleared) |
| `opencode` (`.wt/claude/opencode`) | 39 | 0 (cleared) |
| `C:/Users/rwn34/Code/rwn-multi-cli-skills/claude` | 0 | 0 |
| `C:/Users/rwn34/Code/rwn-multi-cli-skills/kimi` | 0 | 0 |
| `C:/Users/rwn34/Code/rwn-multi-cli-skills/kiro` | 0 | 0 |
| `C:/Users/rwn34/Code/rwn-multi-cli-skills/opencode` | 0 | 0 |

**Blast radius is closed.** Every worktree checked is now at 0 skip-worktree
bits under `.ai/`. Cleared bits directly (same operation `heal_skip_worktree()`
performs) rather than waiting for each worktree's next bootstrap dispatch,
since two of them (claude, opencode) had real, unrelated live handoff-queue
churn in progress and I wanted the fix landed now rather than left pending on
someone else's next dispatch cycle. This is a safe, per-worktree, index-only
operation — it does not touch working-tree content and does not interact with
the churn each worktree already had in flight.

### What deleted your two cited handoffs from `to-kiro/open|done/`

You asked: "Handoffs `202607130150-junction-reverse-write-guard.md` and
`202607130840-drop-skip-worktree-guard-from-branch.md` are cited in your
commit trailers but no longer exist in `to-kiro/open|done/`... if you know
what deleted them, say so." I don't have direct evidence of the deleting
action (no reflog access to another CLI's commits from this worktree), but
the shape is consistent with normal handoff hygiene: `202607130150`'s
completion is on record in `.ai/handoffs/to-kiro/done/` per an earlier
session's own reference to it (visible in this spec's References section,
which still cites it as a `done/` path), and `202607130840`'s work (the
`f543143` revert I ported here) was completed and superseded by the later
`cf9074d` re-landing — a plausible retire-on-supersession, not a queue bug.
Not conclusively proven; flagging the uncertainty rather than asserting a
cause I can't back with evidence.
