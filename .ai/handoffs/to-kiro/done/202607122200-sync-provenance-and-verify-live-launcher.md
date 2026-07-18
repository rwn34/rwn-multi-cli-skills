# Live-launcher sync: add a provenance check + verify the deployed copy
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-12 22:00
Auto: yes
Risk: B
Base: origin/master

## Completion (2026-07-14 01:34, kiro-cli)

**Task 1 — live launcher verification: NO, it did not match master.** Byte
comparison of all 17 allowlisted files in `~/.rwn-auto/rwn-4AI-panes/` against
`origin/master`'s `tools/4ai-panes/`: 14 differ, 3 identical (`README.md`,
`icon.ico`, `Launch4Panes.vbs`). The live install's `.sync-provenance.json`
recorded commit `4e743c7`; `git merge-base --is-ancestor 4e743c7 origin/master`
returns false (exit 1) — the primary checkout's local `master` was 3 commits
ahead of `origin/master` (unpushed) at the moment its git hooks last deployed.
This is the exact provenance bug the handoff describes, caught live during
execution, not hypothesized.

**Task 2 — ancestor guard: implemented.** Chose option (b) — master-only by
default, explicit opt-in escape hatch `RWN_4AI_ALLOW_UNMERGED=1` (separate from
`-Force`/`SYNC_FORCE`) for pre-merge dogfooding. Finished a prior interrupted
session's uncommitted work in this worktree: the sync script's guard logic was
complete but the test file had a stale header (documented the ancestor-guard
scenarios) with an incomplete body (no `origin` remote in the sandbox, 8 of 12
scenarios implemented) — added the bare-origin-remote setup and scenarios
(i)/(j)/(k)/(l). 52/52 assertions pass, including the RED proof.

PR: https://github.com/rwn34/rwn-multi-cli-skills/pull/93 (branch
`exec/kiro/sync-provenance-check`). Peer review routed to Kimi via
`.ai/handoffs/to-kimi/open/202607131834-review-pr93-sync-ancestor-guard.md`.
Not merged (per the handoff's explicit "Do NOT merge" instruction).

**What this does NOT cover:** the primary checkout's own copy of the sync
script still lacks the guard until this PR merges and someone re-pulls there —
a worktree cannot reach that machine-local checkout. Flagged in the PR body and
the Kimi review handoff as a follow-up.

## Why (owner asked, and the hazard is real)
The owner asked whether the live launcher at `C:\Users\rwn34\.rwn-auto\rwn-4AI-panes\`
is actually up to date. Spot-checks say **yes** (the heartbeat, worktree parity,
`AI_HANDOFF_DISPATCH`, `--dangerously-skip-permissions`, `[v SRC]`, and the pane/tab
pacing knobs are all present). But that was a marker check, not a byte check — and it
surfaced a hazard that has been flagged **twice tonight and never fixed**.

**`scripts/sync-4ai-panes-install.ps1` has NO PROVENANCE CHECK.** The post-commit hook
deploys to the live launcher on **any commit touching `tools/4ai-panes/`** — including
commits on **UNMERGED branches**. It happened twice tonight (see the activity log). It
is only correct right now because those branches later merged.

The hook already parse-gates the `.ps1` (refuses to deploy a non-parsing file) and
hash-verifies the copy. So it proves **fidelity** — "the bytes I copied are the bytes I
read" — but it never asks the question that matters: **"is this commit actually on
master?"** A verified copy of the wrong thing.

**The live blast radius:** an experimental, abandoned, or failed-review branch can
deploy straight into the launcher the owner uses to run the whole fleet.

## Task 1 — Verify the deployed copy (answer the owner's question properly)
Byte-compare every file in `C:\Users\rwn34\.rwn-auto\rwn-4AI-panes\` against
`origin/master`'s `tools/4ai-panes/`:
- Report per-file: identical / differs / present-only-in-one-place.
- If ANY file differs from master, say exactly how and **which commit it appears to
  come from** (check whether it matches an unmerged branch — that would be the
  provenance bug caught in the act).
- State plainly whether the launcher the owner is running right now is master's code.

## Task 2 — Add the provenance check
`scripts/sync-4ai-panes-install.ps1` must refuse to deploy a commit that is not on
`master`. Design notes:
- The check is essentially: **is `HEAD` (the committed sha being deployed) an ancestor
  of `origin/master`?** (`git merge-base --is-ancestor <sha> origin/master`).
- **Fail closed and LOUD**: refuse the deploy, exit non-zero, leave the previously
  deployed (known-good) files **INTACT** — never half-deploy. That matches the existing
  parse-gate's behavior; mirror it.
- Keep the existing parse-gate and hash-verify — this ADDS a third property
  (provenance), it does not replace fidelity or validity.
- **Think about the developer-workflow cost and say what you chose:** a strict
  master-only rule means an in-development branch never reaches the live launcher, so
  the owner cannot dogfood a pane-runner change before merge. Options: (a) strict
  master-only; (b) master-only by default with an explicit opt-in env var (e.g.
  `RWN_4AI_ALLOW_UNMERGED=1`) that prints a loud warning; (c) something better.
  **Recommend one and justify it.** Do not silently pick the permissive one.
- Consider: `origin/master` may be stale locally. Does the check need a `git fetch`
  first? If it fetches, what happens offline? **Fail closed on an unresolvable
  `origin/master`** rather than assuming the deploy is fine.

## Constraints
- **Version:** ADR-0012 is live — the version is assigned **at merge**, not on the
  branch. **Do NOT bump `package.json`.** Bullets under `## [Unreleased]`. Confirm by
  grepping `.github/workflows/gates.yml` for `if: github.event_name == 'push'`.
- PowerShell 5.1 compatible; a pre-commit hook parse-gates every staged `.ps1`.
- Do NOT touch `tools/4ai-panes/pane-runner.ps1` — Kimi is building a fleet supervisor
  on top of it (handoff `202607122130`). Coordinate: your change is in `scripts/`, its
  change is in `tools/4ai-panes/`. Flag any overlap rather than resolving it silently.
- **Commit any `.ai/` artifact before your worktree goes away** — a design doc was
  destroyed twice tonight by living uncommitted in a removed worktree.

## Tests (the deliverable — this gates what runs on the owner's machine)
- A commit that IS an ancestor of `origin/master` -> deploy PROCEEDS.
- A commit that is NOT (an unmerged branch) -> deploy REFUSED, exit non-zero, and the
  **previously deployed files are unchanged** (assert this explicitly — a half-deploy
  is worse than no deploy).
- Unresolvable/absent `origin/master` -> **fail closed**, refuse.
- The existing parse-gate still works (a non-parsing `.ps1` is still refused).
- The opt-in escape hatch (if you add one) works AND prints its warning.
- **Prove the check can actually go RED** — construct the unmerged-branch case and show
  the refusal. A gate that cannot fail is not a gate.

## Verify (EXECUTE — inspection is not evidence)
- Paste the Task-1 per-file byte-comparison result.
- Paste the full test output.
- Paste the live RED proof (unmerged commit -> refused, prior deploy intact).

## Deliverable
Branch `exec/kiro/sync-provenance-check` off `origin/master`. Push, open a PR, route
peer review to **KIMI**. Do NOT merge (Kimi reviews; then the fleet merges — Tier B).

## Report back with
- whether the owner's live launcher currently matches master (the direct answer)
- the provenance-check design + which workflow option you chose and why
- the RED proof, verbatim
- what this still does NOT cover, stated plainly
- PR URL

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kiro/done/`.
