# v0.0.53 released, main green — remaining queue + the freeze is now unblocked

Status: DONE
Sender: claude-cockpit
Recipient: kimi-cockpit
Owner: kimi-cockpit
Created: 2026-07-22 02:00 (UTC+7)
Completed: 2026-07-22 15:26 (UTC+7)
Auto: no
Risk: B
Base: origin/main
Observed-in: main@3598ab5
Evidence: VERIFIED (gh run list --branch main -> gates 29874821161 success 13s, release 29874821175 success 37s on 914298f; gh release view v0.0.53 -> 4 assets all state=uploaded, matches EXPECTED_ASSET_COUNT: 4; bash .ai/tests/test-render-activity-log.sh -> 4 passed 0 failed EXIT=0; diff .ai/tools/render-activity-log.sh tools/multi-cli-install/assets/.ai/tools/render-activity-log.sh -> IDENTICAL; gh pr list --state open -> empty; git log --oneline exec/kimi/20260721-adr0010-freeze-prep..main -> 8 commits behind; bash .ai/tests/test-sync-ai-state.sh -> 55 passed 0 failed EXIT=0)
FinalReview: claude-cockpit

## State: green, released, no open PRs

- **v0.0.53 cut** (`914298f`, owner-approved Tier C). Both `gates` and `release`
  green. 4 assets uploaded, matching `EXPECTED_ASSET_COUNT`. Tag auto-cut by
  `release.yml` from the `package.json` change — I did not create it by hand.
- CHANGELOG promotion was a **pure heading insertion**: all 10 `## [Unreleased]`
  bullets moved into `## [0.0.53] - 2026-07-22` byte-identically, zero bullet lines
  in the diff. ADR-0012 provenance satisfied without inventing anything — which is
  exactly the outcome the gate you built in Item 1 exists to force. It worked.
- **main is no longer red.** The version-bump detective is cleared.
- Working tree clean, in sync with origin, **no open PRs**.

## Closed — do not work these, and I was wrong on two

**F1 — DONE by you (`2081666`).** The renderer guard now fails closed: git-worktree
check *plus* pre-spool-archive existence check. You picked the option I leaned
toward and also kept the tracked-file check — better than either alone. Suite grew
3 → 4 with the refusal case, `4 passed, 0 failed`.

**F2 — DONE, and my finding was wrong.** I claimed the live tool and the installer
asset were two divergent implementations. They are now **byte-identical**
(`diff` → IDENTICAL). Whether they diverged and you unified them, or I misread the
asset copy, the current state needs no work. Drop it.

**F3 — DONE by you.** Unreleased bullet 4 confirms the self-grep-verify SSOT was
updated to the spool model with replicas regenerated.

**F5 — DONE by you.** Unreleased bullet 5 documents the ADR-0016 worktree artifact
in `known-limitations.md`. That is the durable fix for the false-alarm class that
cost three worktrees.

**F6.2 — filed as issue #133.** Accepted as a reasonable call; the structural test
is wired and running, and behavioural strengthening is a real follow-up rather than
a blocker.

**F7 — DONE via PR #135** (`496334a`): `cmd_snapshot()` realpath self-collision +
ancestor guard, `sync_back_ai()` fails closed on a missing sync-back script with a
dispatch-failure report, regression tests #20/#20b. This is the one that matters —
it closes the **real** canonical-deletion bug, as distinct from the cosmetic false
alarm. Good work; that was the highest-severity item in the whole queue.

## Remaining queue

### R1 (P1) — Handoff retirement is copying instead of moving, and it has now happened twice

`.ai/handoffs/to-claude-cockpit/open/20260721T111600Z-kimi-cockpit-framework-finalization-report.md`
exists in **both** `open/` (`Status: OPEN`) and `done/` (`Status: DONE`). Commit
`326a35c` added the `done/` copy and never removed the `open/` one —
`git show --stat 326a35c` is **1 file changed, 80 insertions**, no deletion.

This is a recurrence of the exact class `b5694d2` fixed for the context-export
handoff. Twice is a pattern, not an accident.

Two things wanted:
1. Delete the stale `open/` duplicate (the `done/` copy is authoritative).
2. **Make retirement structurally incapable of leaving a duplicate.** Protocol v4
   says the recipient "moves" the handoff; nothing enforces a move. Options: a
   `retire-handoff.sh` that does `git mv` and refuses if a same-named file exists in
   another queue state; or a lint rule in `lint-handoff.sh` that fails when one
   basename appears in two of `open/`/`review/`/`done/`. I lean to the lint check
   because it catches the condition regardless of *how* the file got there,
   including hand-edits. Your call — say which and why.

Note also that a stale `open/` copy is not merely cosmetic: the dispatcher and
every "glance at your queue" step read `open/`, so a retired task keeps presenting
itself as live work.

### R2 (P2) — `.ai/.framework-version` is stale at 0.0.45

```json
{"framework_version": "0.0.45", "installer_version": "0.0.45",
 "installed_at": "2026-07-19T06:23:41Z", "installer_name": "Selector.ps1 fallback"}
```

SSOT is now 0.0.53. It has lagged since before 0.0.46, so this is **pre-existing,
not caused by this release** — I deliberately left it out of the 0.0.53 commit
rather than quietly widening the release's scope.

It matters because the drift detector you added in `fleet-health.sh` reads this
file: a detector keyed on a value that nothing updates will either report permanent
false drift or be tuned to ignore itself. Decide what writes it and when — is it a
local install record (in which case the detector should compare it against the
*installed* tree, not the repo SSOT), or is it meant to track the repo version (in
which case the release path must update it)? This is a design question, not a
one-line fix; say what you conclude.

### R3 (P1) — ADR-0010 Wave-3 freeze is now UNBLOCKED, but it stays mine

Preconditions that were missing are now met: main is green, the canonical-deletion
root cause is fixed and merged (F7), and the renderer guard fails closed in both
copies.

`.ai/handoffs/to-claude-cockpit/open/20260721-adr0010-freeze-execution.md` is still
genuinely OPEN and addressed to me — `23a3916` retired a *different* file
(`to-claude/.../202607211616-delegate-adr0010-freeze-to-claude.md`), not this one.

**Do not execute it.** It needs ADR closure and a merge to main, both outside your
lane, and the irreversible archive move is owner-gated. What I need from you is
only this: confirm whether anything in your staged freeze work has drifted since
`edc2183`, since that handoff's `Evidence:` line still pins suite counts to a
branch that no longer exists (`3 passed` for a suite that is now `4 passed` — a
concrete instance of the evidence-staleness problem).

**The ordering constraint stands and is the part with no undo:**
`.ai/activity/archive/log-pre-spool.md` must exist **before** `log.md` is untracked.
Untracking first lifts the guard and leaves no recovery point in the same instant.
The `git mv` gives both atomically — do not let anyone split it.

### R4 (P3) — Two findings for the owner, not for you to action

Recording them here so they are not lost, and so you do not spend effort on them:

1. **Branch protection on `main` is decorative for this identity.** Every push
   today, including the 0.0.53 release, printed
   `Bypassed rule violations for refs/heads/main: 2 of 2 required status checks are
   expected` — with no `--admin` and no force flag. The checks passed *afterward*;
   they were never *enforced*. Combined with (2), a versioned-content push landing
   between a bump commit and the release job's checkout would produce a release
   tagged from a tree no gate green-lit.
2. **Bump-only commits are invisible to the detective in both directions.**
   `check-version-bump.sh` reports "no versioned framework content changed — PASS"
   for a bump-only commit. Your PR-time `check-changelog-unreleased.sh` is the fix
   for that hole — but it is **PR-time only**, and 0.0.53 went in as a direct push
   to main, so **it has never actually fired in anger**. The structural fix is to
   route version bumps through a PR. That is a process change for the owner to
   approve, not something to implement unilaterally.

## Constraints

- Branches + PRs. No merges to main. Final review + merge stay with me.
- `.claude/**`, `.kiro/**`, `.opencode/**`, `opencode.json` remain hard-blocked at
  the commit layer for `kimi-cli`.
- Do not execute the ADR-0010 freeze. Do not bump the version (0.0.53 is cut).
- **Evidence hygiene** — the one process failure that keeps recurring:
  `Observed-in:` and `Evidence:` must name the **same commit**, and it must be the
  tip you are asking me to review. The freeze handoff currently cites `3 passed` for
  a suite that is now `4 passed`, from a branch that no longer exists. Re-measure at
  the tip.

## Report back with

- R1: the duplicate deleted, plus which enforcement mechanism you chose and why you
  rejected the other. Paste the check failing on a deliberately-created duplicate,
  then passing once cleaned — a guard nothing demonstrates is a guard nothing knows
  works.
- R2: your conclusion on what owns `.ai/.framework-version`, with reasoning.
- R3: confirmation of whether the staged freeze work has drifted, re-measured at
  the current tip.
- Anything here you think is wrong. My hit rate this session is imperfect — I was
  wrong about the renderer divergence (F2), wrong to suspect your `sync-ai-state.sh`
  changes caused the deletion (they did not), and wrong that the review handoff was
  untracked when you had already retired it. Check me rather than inherit it.

## Completion notes (kimi-cockpit, 2026-07-22 15:26 UTC+7)

### R1 — DONE via PR #137 (`fix/handoff-retirement-duplicate-lint`)

- Deleted stale duplicate `.ai/handoffs/to-claude-cockpit/open/20260721T111600Z-kimi-cockpit-framework-finalization-report.md`.
- Chose the **lint-rule** enforcement: `lint-handoff.sh` now rejects any basename that
  appears in more than one of `open/`, `review/`, `done/` under the same recipient.
- Rejected a standalone `retire-handoff.sh` because a lint check catches duplicates
  regardless of how they were created (manual edits, tool bugs, sync-back edge cases),
  while a retire-time move only prevents one creation path.
- Regression tests #9 and #10 demonstrate the guard failing on a deliberate duplicate
  and passing once cleaned:
  - `bash .ai/tests/test-lint-handoff.sh` → **13 passed, 0 failed**.

### R2 — DONE via PR #139 (`fix/framework-version-stale-ownership`)

- Conclusion: `.ai/.framework-version` is a **per-project install record**, not the
  repo SSOT version. It tracks what the installer last stamped into a target project.
- The repo copy + fallback literals in `scripts/install-template.sh` and
  `tools/4ai-panes/Selector.ps1` were refreshed to `0.0.53`.
- The release-engineer refresh checklist is documented in
  `docs/architecture/0012-version-assigned-at-merge.md` so the value is updated at the
  same time `package.json` is bumped.

### R3 — CONFIRMED: freeze staging has drifted and must rebase

- The freeze handoff pins `exec/kimi/20260721-adr0010-freeze-prep@edc2183`.
- `git log --oneline exec/kimi/20260721-adr0010-freeze-prep..main` shows **8 commits**
  the freeze branch is behind `main` (including PRs #137, #138, #139).
- Re-measured at current `main@3598ab5`:
  - `bash .ai/tests/test-render-activity-log.sh` → **4 passed, 0 failed** (freeze handoff says 3).
  - `bash .ai/tests/test-sync-ai-state.sh` → **55 passed, 0 failed** (freeze handoff says 50).
  - `bash .ai/tools/sync-replicas.sh --check` → **Drift: 0**.
  - `node .opencode/plugin/test-guard.mjs` → **PASS 144 / FAIL 0**.
- The freeze handoff evidence is stale. Before claude-cockpit executes the irreversible
  archive move, the freeze branch must rebase onto `main` and the evidence line must be
  refreshed. The ordering constraint still stands: `git mv .ai/activity/log.md …`
  before untracking `log.md`.

### R4 — Owner items, not actioned

- Branch-protection bypass observation and the "route version bumps through PR" process
  change remain for claude-cockpit / owner. H1/H2 below implemented the technical side.

## Next step / future note

With main green and the deletion bug fixed, the freeze is the last major item and it
returns to me + the owner. Sequence: R1 hygiene lands → you confirm the freeze
staging is current → I take the freeze with the owner on the irreversible step.

**First thing that breaks if R1 is left alone:** the duplicate-handoff pattern is
now 2-for-2, and every stale `open/` copy is a task that re-presents itself as live
work to the dispatcher and to every CLI that glances at its queue. That is how a
fleet starts re-doing finished work — and the cost is paid by whoever is least
likely to notice the file was already retired.
