# Enforce framework version bump in gates.yml (gap D1) so the drift-check can't erode
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-11 (UTC filename 202607101910)
Auto: yes
Risk: B

## Why
This session shipped an on-open framework **drift-check** (PR #5,
`docs/specs/framework-install-drift-check.md` + `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md`
gap D1): when an onboarded project's `.ai/.framework-version` is older than the
template's `tools/multi-cli-install/package.json` `.version`, the launcher warns
the operator to adopt updates.

**The load-bearing weakness:** that check is only as good as the version number.
If framework *content* changes but `package.json` `.version` is NOT bumped, every
onboarded project's version still equals the template's → the drift warning stays
silent → drift ships undetected. The spec's top Open question names the fix: a CI
check that FAILS a PR which touches framework-installed content without bumping the
version. You authored `gates.yml` (the P2 gate workflow), so this is your lane.

## Task
Add a **framework version-bump check** to the gate (either a new step in the
existing `gates` job in `.github/workflows/gates.yml`, or a small
`scripts/check-version-bump.sh` the workflow calls — your call; keep it legible
as its own named check). Behavior:

1. Run **only on `pull_request`** events (`if: github.event_name == 'pull_request'`).
   On push-to-master it is meaningless (no base to compare) — skip.
2. Determine the PR's changed files vs the base branch. (You'll need the base:
   `actions/checkout` with `fetch-depth: 0`, then diff
   `origin/${{ github.base_ref }}...HEAD`, or fetch the base ref explicitly.)
3. Decide whether any **versioned framework content** changed. Trigger set
   (installed/versioned framework files):
   - `.ai/instructions/`, `.ai/tools/`, `.ai/config-snippets/`, `.ai/sync.md`,
     `.ai/known-limitations.md`, `.ai/cli-map.md`, `.ai/handoffs/README.md`,
     `.ai/handoffs/template.md`
   - `.claude/` (hooks, agents, skills, `settings.json`), `.kimi/` (hooks, agents,
     steering, resource, `config.toml`), `.kiro/` (hooks, agents, steering, skills,
     settings), `.opencode/` (`contract.md`, `plugin/`)
   - `scripts/git-hooks/`, `scripts/install-template.sh`
   - `CLAUDE.md`, `AGENTS.md`, `opencode.json`, `.codegraph/config.json`,
     `.github/workflows/framework-check.yml`, `.github/workflows/gates.yml`
   **Exclusions** (runtime/non-versioned — must NOT trigger a required bump):
   `.ai/activity/`, `.ai/handoffs/to-*/` (queues), `.ai/reports/`, `.ai/research/`,
   `.ai/.claim*`, `.ai/.scratch/`, `docs/`, `.claude/settings.local.json`.
   (A path allowlist + denylist in the script is more maintainable than a regex.)
4. If versioned framework content changed **AND** the `.version` in
   `tools/multi-cli-install/package.json` did **not** change between base and HEAD
   (compare `git show origin/<base>:tools/multi-cli-install/package.json` version
   vs HEAD version) → **FAIL** with a clear message:
   "Framework content changed but tools/multi-cli-install/package.json version was
   not bumped — onboarded projects won't see the drift. Bump the version." Else PASS.
5. Keep it dependency-light (bash + sed/grep + git; no new npm deps in the job).

## Verify (in your report)
- A PR that touches a framework file WITHOUT a version bump FAILS the check
  (simulate locally: craft the base-vs-head diff and run your script).
- A PR that touches the SAME file WITH a version bump PASSES.
- A PR that touches ONLY an excluded path (e.g. `.ai/activity/log.md`, `docs/`)
  PASSES with no bump required.
- The step is skipped on push-to-master.

## Rules
- `.github/workflows/gates.yml` + any `scripts/check-version-bump.sh` are shared
  project source — you may edit them directly (this is your CI lane, ADR-0007 P2).
  Do NOT touch `.claude/`/`.kimi/` config beyond reading.
- Prepend an activity entry via `bash .ai/tools/activity-append.sh`. Self-retire
  (Status DONE + move to `.ai/handoffs/to-kiro/done/`) per protocol v3. Blocked →
  leave OPEN as BLOCKED with a verbatim `## Blocker`.
- Note: this is a NEW gate step — once merged, it will run on subsequent PRs. If it
  needs the base fetched (`fetch-depth: 0`), make sure that doesn't break the other
  steps in the job.

## Report
The check design (step vs script), the trigger/exclusion logic, and the three
verification outcomes above (no-bump→fail, bump→pass, excluded-only→pass).
