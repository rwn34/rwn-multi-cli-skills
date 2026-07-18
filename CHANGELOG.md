# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org).

<!--
Release convention (ADR-0012 — version assigned at merge, not on feature branches):
a feature PR adds its notes as bullets under "## [Unreleased]" below. It does NOT
add a versioned "## [x.y.z]" heading and does NOT bump
tools/multi-cli-install/package.json — that would collide with every other open
PR on the same two lines. At the single serialized merge point the
release-engineer assigns ONE version, promotes the accumulated "## [Unreleased]"
bullets into a new "## [x.y.z]" heading, and bumps the version SSOT once. The
push:master version-bump gate (scripts/check-version-bump.sh) then verifies that
promotion happened.
-->

## [Unreleased]

### Added

- [TODO]

### Changed

- Reduced GitHub Actions minute usage: `gates` now runs the full suite only on pull requests and the version-bump detective on `push:main`; `framework-check` is reduced to the handoff lint that `gates` does not cover; `release` only triggers on `push:main` when `tools/multi-cli-install/package.json` changes.

### Deprecated

- [TODO]

### Removed

- [TODO]

### Fixed

- [TODO]

### Security

- [TODO]

## [0.0.41] - 2026-07-18

### Added

- ADR-0014: enforcement-layer (`.claude/hooks/**`) changes land via peer-reviewed
  PR (author ≠ reviewer, required CI gates, no self-merge) instead of
  owner-apply-only, replacing the hand-applied-patch escape hatch that made the
  owner a relay rather than a gate.
- Fleet supervisor (`tools/4ai-panes/fleet-supervisor.ps1`): OS-level scheduled
  task that detects dead pane-runners via persistent heartbeat files, alerts the
  owner via Telegram, and relaunches the fleet. Two-level health model: L1
  (liveness — heartbeat file mtime) and L2 (capability — last CLI invocation
  outcome distinguishes auth/quota failure from idle-with-empty-queue).
  ALIVE-but-NOT-CAPABLE alerts only (never relaunches — a dead API key is not
  fixed by restarting the process). DEAD + open handoffs alerts and relaunches.
  DEAD + empty queue alerts only (deduped, once per incident).
- Persistent heartbeat in `pane-runner.ps1`: each pane writes a JSON heartbeat
  file to `%LOCALAPPDATA%\rwn-auto\fleet-heartbeat\` on every poll (idle, running,
  claim-blocked) carrying project, CLI, PID, timestamp, state, and last CLI
  invocation outcome. Outside the repo to avoid `.ai/` coordination-plane churn.
- CLI output capture (`Tee-Object`) in `pane-runner.ps1`'s `$script:InvokeCli`:
  tees child CLI output to a temp file so `Get-LastCliOutcome` can classify
  auth/quota/error patterns for the L2 capability signal.
- Install/uninstall scripts (`install-fleet-supervisor.ps1` /
  `uninstall-fleet-supervisor.ps1`): scripted, reversible Task Scheduler
  registration. Runs "only when user is logged on" + Interactive so the task
  CAN open Windows Terminal panes (verified empirically).
- Safety: exponential backoff + max-attempts circuit breaker on relaunch
  failure; alert dedupe on state transition (not per-poll); a live fleet is
  NEVER relaunched (false-positive guard — the worst outcome is two fleets
  racing the same handoff queue).
- `test-fleet-supervisor.ps1`: 33-test Pester-free harness covering liveness
  (fresh/stale/missing), false-positive guard, down+handoffs, down+empty-queue,
  alive-but-not-capable, backoff/circuit-breaker, alert dedupe, install/uninstall.
- ADR-0016: `.ai/` durability contract — dispatcher commits canonical `.ai/`
  after every executor sync-back, so handoff retirements, activity-log appends,
  reports, and steering changes are durable in git history instead of existing
  only in the working tree.
- `fleet-health.sh` worktree-hygiene checks: detect junctioned/symlinked `.ai/`
  (ADR-0016 violation), stale worktrees behind `origin/main`, and shared-state
  encoding corruption before they cause silent data loss.
- `test-fleet-health.sh`: 14-test harness covering OK/down-idle, STALL, WEDGED,
  missing queue dirs, junctioned `.ai/`, stale worktree, and encoding problems.

### Changed

- **Activity log is now an entry-per-file spool (ADR-0010, Waves 1–2 of 3).**
  Each CLI writes its own new file in `.ai/activity/entries/` (UTC filename +
  random suffix); the whole-file prepend race — confirmed with real data loss on
  2026-07-13 when a `kiro-cli` entry header was clobbered — becomes structurally
  impossible: unique filename ⇒ no shared write ⇒ no lock ⇒ no clobber.
  Concurrency demonstrated, not asserted: 40/40 same-second writers survived
  with intact content. `.ai/activity/log.md` becomes a generated view rendered
  on demand by the new `.ai/tools/render-activity-log.sh`. The Wave-3 freeze
  (`git mv` of `log.md` to `archive/log-pre-spool.md` + `.gitignore`) is gated
  on all three CLIs' inject hooks landing dual-mode on `master`, and is NOT in
  this release.
- Kimi hooks (`activity-log-inject`, `activity-log-remind`, `git-dirty-remind`)
  are dual-mode: read the spool when it has entries, fall back to `log.md` so
  pre-migration clones keep working.
- Installers (`scripts/install-template.sh`, `tools/multi-cli-install`)
  sanitize to an empty spool (`.ai/activity/entries/.gitkeep`) instead of a
  seeded `log.md`; the manifest already excludes the whole `.ai/activity/`
  subtree, so spool entries never enter adopter manifests.
- Dispatch prompts (`dispatch-handoffs.sh`, `pane-runner.ps1`) instruct
  recipients to "write an activity-log entry" instead of "prepend".
- `.fleet/activity/log.md` (`scripts/fleet-init.sh`) deliberately stays a
  single prepended file — one writer per project, so the race does not apply;
  the decision is documented in the script per ADR-0010 § Migration.
- Archival protocol (`.ai/activity/archive/README.md`) is now a `git mv` of
  entry files into `archive/YYYY-MM/`; the cut-and-regroup rollup (itself a
  whole-file rewrite racing live writers) is retired.

### Removed

- `.ai/tools/activity-append.sh` and `.ai/tests/test-activity-append.sh` — the
  serializing writer with zero callers (ADR-0010 § Alternatives (A)).

### Fixed

- `pane-runner.ps1` now refuses to start if its worktree branch is behind
  `origin/main`. A stale branch combined with a junctioned `.ai/` was the
  reverse-write weapon that caused the 2026-07-13 primary `.ai/` clobber; the
  guard exits cleanly (supervisor does not respawn) and prints the rebase/recreate
  fix steps.
- `wt-bootstrap.sh` now pins each executor worktree's committer identity
  (`user.name`/`user.email` per `--worktree` config) on every run, create or
  skip. Worktrees previously inherited the shared repo config's `user.name` —
  which flips with whichever CLI last set it (observed: 3 of 4 pane worktrees
  carrying `claude-code`) — and the ADR-0005 pre-commit gate trusts that
  identity, so a mislabeled commit could inherit another CLI's territory
  exception. The re-pin is idempotent and repairs drifted trees.
- Remaining `master`→`main` references in live operational docs/scripts:
  `.github/workflows/release.yml` comments, `.ai/known-limitations.md`,
  `tools/4ai-panes/run-pane-supervised.ps1` drift-reminder message, and
  `CHANGELOG.md`'s own stale `origin/master` reference.
- `reconcile-done-handoffs.sh` now runs `lint-handoff.sh` before moving a
  terminal-status handoff to `done/`; a handoff that fails lint (e.g.
  `Status: DONE` with no evidence) stays in `open/` instead of being retired.

## [0.0.39] - 2026-07-13

### Added

- **Cockpit handoff ownership — the `Auto:` tag is the claim boundary.** New
  `.ai/tools/claim-handoff.sh` + `.ai/tools/release-handoff.sh`: a cockpit
  (interactive session) takes an `Auto: yes` handoff ONLY by atomically flipping
  `Auto:` to `no` and writing a claim sidecar under `.ai/handoffs/.claims/`, so
  the auto pane skips it on its next poll; the inverse restores pane ownership
  for "claimed it, changed my mind". Staleness mirrors
  `pane-runner.ps1 Test-HandoffClaimed` exactly (same-host dead pid → reclaim;
  15-minute window otherwise; fail-closed on ambiguity). Rule documented in
  `.ai/handoffs/README.md` (Polling section); the operating-prompt SSOT
  one-liner and CLAUDE.md/AGENTS.md contract wording route through claude-code
  (only claude-code may commit cross-CLI SSOT replicas atomically per the
  ADR-0005 pre-commit policy). Covered by the new sibling suite
  `tools/4ai-panes/test-claim-handoff.ps1`, which drives the real
  `Get-QualifyingHandoff` gate. Symmetric across all four CLIs.
- Fleet pane liveness watchdog (dead-man's switch): `pane-runner.ps1` writes an atomic heartbeat sidecar (`.ai/.heartbeat-<cli>.json`) once per poll cycle; `.ai/tools/fleet-health.sh` cross-checks heartbeat freshness against each pane's open queue and classifies `OK` / `STALL` (queue with nobody watching) / `WEDGED` (polling but not picking up) / `DOWN (idle)` (informational) — exit 1 on STALL/WEDGED so CI and hooks can gate, fail-open on its own errors. Surfaced in `stop-reminder.sh` (STALL/WEDGED lines at session end) and the 4AI-panes Selector badge (`stall:<cli>` marker). Detection and alerting only — no auto-restart. Staleness mirrors the pane-runner claim-lock policy (15-min window, same-host dead pid = stale, foreign host = time window only).
- `sync-replicas.sh --check` — the replica generator is now the ONE SSOT drift
  authority (detects **and** repairs); wired into both CI workflows
  (`framework-check.yml`, `gates.yml`) so an SSOT-changing PR without
  regenerated replicas fails with a copy-pasteable fix command. In-place
  regeneration is junction-safe: it refuses writes through any symlink or
  Windows-junction ancestor and any registry destination under `.ai/`
  (ADR-0004 reverse-write class).

### Changed

- `check-ssot-drift.sh` is now a thin compatibility shim that execs
  `sync-replicas.sh --check` (identical output contract and exit codes); the
  manual copy commands in `.ai/sync.md` are demoted to reference material in
  favor of the generator.

## [0.0.38] - 2026-07-13

### Added

- Tests for the branch-cut fix below, in the failure class that burned the fleet
  all night: `test-pane-runner.ps1` (av)–(av4) reproduce the landmine in a REAL
  sandbox worktree with a REAL `mklink /J` junction — a raw `git checkout -b`
  is asserted to FAIL in the stale-HEAD + live-`.ai/` state (prove-the-bug, so
  the test can never pass vacuously), then both dispatch paths are asserted to
  cut the declared-base branch and preserve the live `.ai/` byte-for-byte
  (prove-the-fix). Non-`.ai/` dirt still refuses the cut; a degraded real-dir
  `.ai/` fails `wt-bootstrap.sh` loud. The bash twin is driven end-to-end
  through a real `dispatch-handoffs.sh --exec` invocation (stub CLI binary),
  keeping the two implementations in behavioral lockstep.

### Fixed

- **Fleet outage: the shared `.ai/` junction broke every executor worktree
  branch cut.** `.ai/` is a single directory junctioned into every worktree
  (ADR-0004), so a worktree whose HEAD is stale relative to `origin/master`
  sees the live coordination-plane churn (`.ai/activity/log.md` and friends)
  as "local changes". The dispatchers' dirty-check filters `.ai/` BY DESIGN —
  concluding the tree is clean — but `git checkout -b exec/<cli>/<slug>
  origin/master` then REFUSES to overwrite those same files. One rule with two
  contradictory surfaces: every auto-dispatch hit `WORKTREE_FAIL`, three
  strikes, quarantine — kimi, kiro, and opencode all stalled within hours.
- `tools/4ai-panes/pane-runner.ps1` `Ensure-DeclaredBaseBranchReal` and
  `.ai/tools/dispatch-handoffs.sh` `ensure_declared_base_branch()` (kept 1:1):
  the branch cut no longer uses `git checkout` at all. `symbolic-ref` moves
  HEAD without rewriting a single file; `git restore --source=<branch>
  --staged --worktree -- . ':!.ai'` converges everything EXCEPT the junctioned
  `.ai/` onto the branch tip, and a second index-only restore for `.ai/`
  leaves `git status` showing genuine plane churn instead of staged phantoms.
  The live `.ai/` is never written by git in a worktree — the append-only
  coordination plane cannot be clobbered by a dispatch again.
- `scripts/wt-bootstrap.sh` `link_ai()`: a worktree `.ai/` degraded from a
  junction into a real directory used to be silently `rm -rf`'d and replaced —
  destroying any fleet state that existed only there. A real dir now dies loud
  when it holds uncommitted content (split-brain guard), re-junctions cleanly
  when it matches the index (fresh `worktree add` state), and the link is
  verified post-creation. **Deployment: pane-runners hold the script in
  memory — the owner must restart the panes after this merges, then clear
  `.ai/handoffs/.quarantine/` so the stalled queue retries.**

## [0.0.37] - 2026-07-12

### Fixed

- **Fleet outage: the panes' `bash` was WSL's `C:\Windows\System32\bash.exe`, not
  Git Bash.** The panes launch from a plain Windows context (vbs -> PowerShell)
  whose persisted PATH puts `C:\WINDOWS\system32` first and contributes Git only
  as `C:\Program Files\Git\cmd` — which holds `git.exe` but **no `bash.exe`**. So
  `Get-Command bash` resolved to the WSL launcher, which re-parses its arguments
  as a shell string and eats the backslashes of the Windows path it is handed
  (`C:\Users\...\wt-bootstrap.sh` -> `C:Users...wt-bootstrap.sh`, exit 127). Every
  headless dispatch failed worktree setup, tripped three strikes, and the whole
  fleet quarantined itself.
- `tools/4ai-panes/pane-runner.ps1`: new `Resolve-GitBash` — probes the well-known
  Git for Windows locations, then derives `bash.exe` from `git.exe`'s install root,
  and only then accepts a PATH hit; **rejects** any candidate under
  `%WINDIR%\System32` or `WindowsApps` (WSL / Store launchers). Fails loud and
  returns `$false` when nothing resolves — it never silently proceeds, and never
  falls back to the primary checkout.
- `tools/4ai-panes/Selector.ps1`: `Find-Bash` had the identical defect (trusted
  `Get-Command bash` first) and is hardened the same way.
- **Not** fixed by path conversion: Git Bash executes the same backslash Windows
  path correctly. Running `wt-bootstrap.sh` under WSL would be wrong regardless —
  `git worktree` and `mklink /J` junctions are Windows-side operations.

### Added

- Tests for the above, closing the gap that let this ship green: the hazard was
  already documented in `test-pane-runner.ps1` (the suite *skipped* on WSL bash)
  but the production resolver never got the same guard. Now covered by
  resolver-rejection cases, anti-rot source guards, and — critically — **real,
  non-stubbed bash invocations** (`wt-bootstrap.sh --help` via the resolved Git
  Bash; a backslash-path execution probe under the reconstructed pane `PATH`).
  `test-pane-runner.ps1`'s own bash probe now uses `Resolve-GitBash`, so its
  real-worktree tests no longer silently skip in the environment the panes run in.

## [0.0.36] - 2026-07-12

### Changed

- OpenCode's model switched from `zhipu-coding/glm-4.7` to
  `zhipu-coding/glm-4.7-flash` (`opencode.json`, both the top-level `model` and
  the `opencode` agent's `model`) — owner-requested, for pane responsiveness.

## [0.0.35] - 2026-07-12

### Fixed

- OpenCode enforcement guard restored: `.opencode/plugin/framework-guard.js` no
  longer fails to load. PR #45 had added a non-function top-level export
  (`export const WRITABLE_LANE = []`), which OpenCode's plugin host rejects with
  `TypeError("Plugin export is not a function")` — killing the entire plugin, so
  at runtime NOTHING was lane-restricted (project source, secrets, other CLIs'
  territory were all writable). The lane data moved to `.opencode/lib/lane.js`
  (outside the host's `{plugin,plugins}/*.{ts,js}` discovery glob), so the guard
  module now exports only functions. Added load-path tests to `test-guard.mjs`
  that reproduce the host's export invariant and drive the initialized hook
  end-to-end, so a total load failure can never ship green again.

## [0.0.34] - 2026-07-12

### Fixed

- **Fleet still down after 0.0.33: the declared-base branch cut threw on a
  successful `git fetch` (`pane-runner.ps1` `Ensure-DeclaredBaseBranchReal`).**
  Second-order regression, unmasked by the 0.0.33 flat-install fix. git writes
  ordinary progress to **stderr** — `git fetch` emits `From <remote>` whenever it
  actually retrieves refs, `git checkout` emits `Switched to a new branch`. The
  runner sets `$ErrorActionPreference = 'Stop'`, and PS 5.1 promotes a native
  command's stderr record to a **terminating** `NativeCommandError`; `*> $null`
  does **not** suppress that promotion (the throw precedes the redirect). So a
  perfectly successful fetch blew up the whole branch cut, surfacing as an opaque
  `WORKTREE_FAIL` and re-quarantining every handoff. `$script:InvokeCli` and
  `$script:InvokeWtBootstrap` already guard against exactly this hazard and
  document it; `Ensure-DeclaredBaseBranchReal` was simply missing the guard. It
  stayed hidden because the wt-bootstrap path failed *first* (0.0.33's bug), so the
  branch cut was never reached — and it is intermittent by nature: a fetch with
  nothing new writes no stderr and never throws, so it only fires when the remote
  has actually moved. Now forces `EAP='Continue'` around the native git calls and
  restores the prior value in `finally`. No failure signal is lost: every call's
  outcome is judged by `$LASTEXITCODE`, never by whether it threw.
- **Regression test for it (`test-pane-runner.ps1`, cases `au`–`au3`).** The
  existing real-git test `(ac)` has a genuine origin but **never advances it**, so
  its fetches had nothing to report, wrote no stderr, and never threw — the bug was
  structurally unreachable by the suite. The new case advances the bare origin
  behind the worktree's back, then cuts a branch under a real `EAP='Stop'`, so it
  reproduces the live `RemoteException` against the unguarded function and passes
  against the guarded one, plus anti-rot guards that the EAP guard stays put.

## [0.0.33] - 2026-07-12

### Fixed

- **Total auto-fleet outage: `pane-runner.ps1` could not find `wt-bootstrap.sh` in
  the deployed launcher (regression from PR #51).** The worktree-bootstrap resolver
  had a single candidate, `$PSScriptRoot/../../scripts/wt-bootstrap.sh`, on the
  assumption that `$PSScriptRoot` is always `<repo>/tools/4ai-panes/`. That is true
  in the repo tree and **false in the shape we actually deploy**:
  `scripts/sync-4ai-panes-install.ps1` installs the pane tools FLAT into
  `~/.rwn-auto/rwn-4AI-panes/`, where `../../scripts/` resolves to `~/scripts/` —
  which does not exist. Every pane-runner took that path, so **all four CLIs**
  (kimi, kiro, opencode, claude-auto) failed worktree setup and quarantined every
  handoff they picked up. Sibling dot-sources (`fleet-clis.ps1`, `notify.ps1`) were
  unaffected because they ARE installed flat beside the runner; only the
  repo-relative path broke. `wt-bootstrap.sh` belongs to the **project being operated
  on**, not to the tool's install location, so it is now resolved through an ordered
  multi-candidate resolver (`Resolve-WtBootstrapPath`): (1) `$ProjectDir/scripts/`,
  (2) `$PSScriptRoot/../../scripts/` (repo-tree/dev), (3) `$RWN_FRAMEWORK_REPO/scripts/`
  (same env var + default as `Selector.ps1`). If none exist it fails loud, listing
  every path tried. The never-fall-back-to-the-primary-checkout contract is
  unchanged — that behavior is what turned this into a visible quarantine instead of
  four CLIs silently trampling each other in the primary checkout.
- **`scripts/wt-bootstrap.sh` is now shipped to onboarded projects
  (`scripts/install-template.sh`).** The already-shipped `.ai/tools/dispatch-handoffs.sh`
  resolves it as `<project>/scripts/wt-bootstrap.sh`, so without this copy that
  reference dangled in **every adopted project** and worktree setup could never
  succeed there — the same class of break as the pane-fleet outage above, latent in
  the adopter path.
- **The deployed topology is now under test (`tools/4ai-panes/test-pane-runner.ps1`,
  cases `an`–`at`).** The suite passed all through this outage because every worktree
  test mocks `$script:GetCliWorktreePath` (so the resolver was never reached) and the
  suite only ever ran *from the repo tree*, where the broken path happens to resolve.
  A test that only runs in the repo tree is not testing what we ship. The new cases
  build a synthetic flat-install sandbox and drive the resolver directly with
  `$ScriptRoot` as a parameter: they reproduce the outage against the old
  single-candidate expression, assert the new resolver survives it via the project
  copy and via `RWN_FRAMEWORK_REPO`, assert the repo-tree case still works, assert
  fail-loud when nothing resolves, and add an anti-rot guard so nobody "simplifies"
  the resolver back to one hardcoded path.

## [0.0.32] - 2026-07-12

### Added

- **Tier-restatement drift gate (`.ai/tools/check-tier-restatements.sh`).** The
  autonomy-tier table lives in six places: the SSOT (operating-prompt §8), three
  generated replicas, and two HAND-WRITTEN restatements — `CLAUDE.md` and
  `.claude/agents/orchestrator.md`. The replicas are byte-diffed by
  `check-ssot-drift.sh`, but the two restatements paraphrase the tiers in their own
  voice, so a byte-diff structurally cannot cover them. They had no mechanical check
  at all and silently drifted through PR #54. The new gate asserts the load-bearing
  tier concepts (`deploy to PRODUCTION`, `deploy to STAGING`, merge-to-main, ADR
  authorship, worktree cleanup, the two no-auto-deploy couplings, …) appear in both
  restatements, and — critically — that each concept is still present in the SSOT
  §8 section it is tracking, so moving or deleting a tier item upstream fails the
  build instead of leaving the check quietly tracking a stale copy. Placement
  assertions additionally pin staging-deploy to Tier B and production-deploy to
  Tier C. Wired into `gates`, with a hermetic self-test
  (`.ai/tools/test-check-tier-restatements.sh`) that proves the check goes red on
  each failure mode.

### Changed

- **Full git/GitHub authority to the fleet.** Operating-prompt §8 now states
  that ALL git/GitHub mechanics are fleet-executed — commit, branch, push
  (Tier A); open PR, merge to main, branch deletion, repo/tree/worktree cleanup
  (Tier B). None of them is an owner ask. Per owner directive 2026-07-12:
  *"Committing tree, merge, cleanup, push, or any activity related to GitHub is
  yours to make."* Previously §8 named only commits and pushes, leaving cleanup
  and PR/branch hygiene in an unclassified grey zone that drifted toward asking.
- **Deploy split into STAGING (Tier B) and PRODUCTION (Tier C).** This
  distinction did not previously exist anywhere in the framework — §8,
  `.opencode/contract.md` and ADR-0002 all treated every deploy as an
  undifferentiated Tier-C gate. Staging deploys are now the fleet's call
  (act-then-notify) while keeping every operational guardrail: dry-run first,
  brief-only commands, refuse on a dirty tree or failing tests. **Production
  deploys are unchanged and no guardrail is weakened** — per-deploy human
  confirmation on every mutating command, all four Stage-2 conditions intact.
  New prohibited coupling: a staging deploy must never auto-promote to
  production (sibling of the existing merge-never-auto-deploys rule).
- **ADR authorship/amendment moved Tier C → Tier B**, resolving a live
  contradiction: §4 says Claude Code *owns* ADRs (architect lane) while §8
  required owner pre-approval before writing one. Authorship is now
  act-then-notify; the requirement to surface it prominently (PR + summary +
  activity log) is retained — only the pre-approval gate is removed.
- Files: `.ai/instructions/operating-prompt/principles.md` (§4, §8, §13),
  `.claude/skills/operating-prompt/SKILL.md` (replica),
  `docs/architecture/0011-git-ops-execution-to-opencode.md` (Amendment
  2026-07-12b), `docs/architecture/0002-cli-role-topology.md` (deploy language
  aligned), `.opencode/contract.md` + `AGENTS.md` (OpenCode is the deploy
  executor: staging fleet-authorized, production human-confirmed),
  `CLAUDE.md`, `.claude/agents/orchestrator.md`.
- **Implementation subagents are now FALLBACK-ONLY, and using one requires a
  written reason** (operating-prompt §14.2a, owner directive 2026-07-12). §14
  already said "hand off as much as you can", but it stated that as an economic
  preference with no mechanism — so it held while Claude was calm and collapsed
  the moment it was busy. §14.2a converts it into a rule with a visible failure
  mode: Claude MUST NOT reach for `coder`, `tester`, `refactorer`, `debugger`,
  `doc-writer`, or `release-engineer` for work Kimi, Kiro, or OpenCode could do,
  and any invocation must name one of exactly four legitimate exceptions in the
  activity log — **(a)** Claude-exclusive territory (`.claude/**`, which the
  cross-CLI guard and the ADR-0005 backstop put out of every other CLI's reach),
  **(b)** recipient genuinely unavailable (say which, and how you know),
  **(c)** the owner waiting live on a small fix, **(d)** the final review + merge
  gate (Claude's by definition — author ≠ reviewer). An unexplained invocation is
  a protocol violation, not a convenience. This mirrors ADR-0011's
  `infra-engineer` fallback-logging rule and for the same reason: an activity log
  filling with unexplained subagent use is the tell that the reflex has returned.
- **The version gate now asserts the CHANGELOG section is SUBSTANTIVE, not just
  present.** `scripts/check-version-bump.sh` previously proved only that a
  `## [x.y.z]` heading EXISTED. ADR-0012 moved version assignment to merge time
  and made the release-engineer *manually* promote the `## [Unreleased]` bullets
  into that heading — so an empty section, or one holding nothing but the
  Keep-a-Changelog scaffolding (`[TODO: …]`, TBD, WIP, `...`, an empty `-`
  bullet, comments only), sailed through and shipped a version documented by
  nothing. The gate now requires at least one real content line between the
  heading and the next `## `, fails closed on a section it cannot parse, and
  says which promotion did not happen. `## [Unreleased]` is exempt by
  construction (the gate only inspects the section named by the new semver
  version), so an empty Unreleased right after a promotion is fine. Scope: this
  closes the EMPTY/PLACEHOLDER hole, **not** the WRONG-CONTENT one — bullets
  describing a different PR than the one that bumped the version still pass, and
  a human still reads the entry at release.

## [0.0.31] - 2026-07-12

### Added

- **`sync-replicas.sh` — one deterministic generator for every SSOT replica.**
  `.ai/tools/sync-replicas.sh` reads the `.ai/sync.md` registry and regenerates
  each CLI-native replica from its `.ai/instructions/**` source: byte-copy for
  pure replicas, preamble-preserving body-replace for `SKILL.md` files (the exact
  inverse of the drift checker's `strip_preamble`). LF-normalized, idempotent,
  fails closed on an unreadable/malformed registry.

### Changed

- **The drift checker now regenerates-and-diffs instead of re-implementing the
  transform.** `.ai/tools/check-ssot-drift.sh` invokes `sync-replicas.sh` into a
  temp dest-root and diffs the committed replicas against that fresh output —
  same code for generate and check, so they can never disagree. Output format,
  exit codes, and the `Checked: N replicas, Drift: M` summary are unchanged.
- **Pre-commit now lands SSOT changes atomically (ADR-0005 second amendment).**
  When a staged change touches `.ai/instructions/**`, `scripts/git-hooks/pre-commit`
  runs the generator; committer `claude-code` (the fleet git operator) auto-stages
  the regenerated replicas into the same commit, while a human/other identity is
  refused with a hint (never a silently-mutated commit). The ADR-0005 territory
  exception widens from steering-only to ANY `.ai/sync.md`-registered replica
  (adds `.kimi/resource/*` and `.kiro/skills/*/SKILL.md`), still replica-only and
  fail-closed. `.gitattributes` pins `*.md` to `eol=lf` so byte-diffs are stable
  cross-OS. This closes the drift-gate throttle that red-lit CI whenever an SSOT
  edit outran the Kimi/Kiro replica syncs.

## [0.0.30] - 2026-07-12

### Changed

- **Framework version is now assigned at MERGE, not on feature branches
  (ADR-0012).** `scripts/check-version-bump.sh` moves from a `pull_request` gate
  that forced EVERY content-changing PR to bump `package.json` `.version` + add a
  CHANGELOG heading — colliding N concurrent PRs on the same two lines and
  hand-serializing the merge train — to a DETECTIVE check on `push: master` that
  compares the previous master tip to the new one. `.github/workflows/gates.yml`
  runs the check LAST (after drift / hooks / backstop / installer) and only on
  push-to-master, so a missing bump can never mask a real test failure (the old
  PR-time placement did). All PR#44 hardening is preserved verbatim: strict
  semver increase (equal + downgrade rejected), fail-closed on an unparseable or
  unresolvable ref, and the matching `## [<new-version>]` CHANGELOG requirement.
  Adopter drift-detection is unchanged — one increment per merge still moves the
  template `.version` that `Selector.ps1` `Test-FrameworkDrift` and the installer
  compare against `.ai/.framework-version`. Feature PRs now add bullets under
  `## [Unreleased]`; the release-engineer promotes them to a versioned heading at
  the single serialized merge point. Resolves the "how is the version-bump
  discipline enforced?" open question in
  `docs/specs/framework-install-drift-check.md` and amends the version-bump-gate
  discipline referenced in ADR-0007 P2.

## [0.0.28] - 2026-07-12

### Changed

- **Merge-to-main reclassified Tier C → Tier B (fleet act-then-notify); deploy
  stays the owner's Tier-C gate.** Per owner directive 2026-07-12 ("merge doesn't
  have to be my part, it can be the fleet — the one thing I should decide is
  deploy"), landing a peer-reviewed, CI-green PR into `main` is now a fleet
  action the fleet performs and notifies the owner about after the fact, not an
  owner-gated ask-before step. Deploy remains owner-gated Tier C with its Stage-2
  guardrails intact. A merge must **never** auto-trigger a deploy — if that
  coupling is introduced, merge re-tightens to Tier C. Amends
  `docs/architecture/0011-git-ops-execution-to-opencode.md` (Amendment
  2026-07-12) and operating-prompt §8; stale Tier-C merge language swept from
  `CLAUDE.md` and `.claude/agents/orchestrator.md`.

## [0.0.27] - 2026-07-12

### Security

- **Closed the Bash side-door around the Write/Edit territorial guard.**
  `.claude/hooks/pretool-bash.sh` did no path checking, so `cp`/`mv`/`install`/
  `ln`/`dd`/`tee`/`sed -i` and shell redirections (`>`, `>>`, `>|`) could write
  into `.kimi/**`, `.kiro/**`, `.claude/hooks/**`, `.env`, or non-allowlisted root
  files — defeating the guard PR #50 had just fixed on the Write/Edit surface. The
  bash hook now extracts each write TARGET and routes it through the SAME policy
  classifier the Write/Edit hook uses.
- **Scope (not overclaimed).** This shuts the door that is open by default:
  accidental and casual-deliberate territorial writes via ordinary `cp`/`mv`/
  `sed -i`/`tee`/redirects, plus the trivial self-modification path. It does NOT
  stop a determined self-evader (`$(...)`, backticks, `eval`, `sh -c`/`bash -c`,
  base64/hex-decoded or variable-assembled paths and command names) — those either
  fail CLOSED as unparseable ("blocked for safety") or remain out of scope for a
  static pre-execution guard. Read-side exfiltration (`cp .env /tmp/x`) is out of
  scope by design: the policy classifies write TARGETS, asserted by an explicit
  ALLOW test. The durable complement is narrowing which subagents get an
  unrestricted Bash tool at all (follow-up ADR).

### Changed

- Extracted path normalization AND territorial/sensitive/root policy into a shared
  `.claude/hooks/lib/path-policy.sh`, sourced by BOTH hooks. Neither hook
  re-implements normalization or policy; a cross-hook divergence test fails loudly
  if they ever disagree. This closes the recurring "two enforcement surfaces, one
  rule, nothing keeping them in lockstep" pattern for path policy.
- Added Rule 1.5 (enforcement-layer self-protection): `.claude/hooks/**` guard
  scripts are owner-apply-only on BOTH surfaces — no agent edits its own guard via
  a tool. (`test_hooks` t87 retargeted to `.claude/agents/`; t96–t99 added.)

## [0.0.26] - 2026-07-12

### Fixed

- **`tools/4ai-panes/pane-runner.ps1`: pane-consumed handoffs no longer run in
  the primary checkout.** This closed the SECOND, more heavily-used dispatch
  path for the ADR-0004 shared-HEAD race — `.ai/tools/dispatch-handoffs.sh`
  (headless `--exec` dispatch) got worktree-per-CLI in 0.0.21, but the
  self-driving pane-runner (the auto panes that actually consume most
  handoffs day to day) still ran every CLI directly in `$ProjectDir`. This
  was proven live: a Kimi interactive session with an unpushed commit sat in
  the primary checkout while a concurrently dispatched pane came within one
  `git checkout -b` of reverting its uncommitted work. `Invoke-HandoffRun` now
  resolves (creates or reuses) that CLI's own worktree via
  `scripts/wt-bootstrap.sh` — the same script the dispatcher already calls —
  before invoking the CLI, and cuts/reuses a `exec/<cli>/<slug>` branch from a
  declared base (`origin/master`, or the handoff's `Base:` field), mirroring
  `dispatch-handoffs.sh`'s `ensure_declared_base_branch()`. **Fail-loud, never
  fall back:** if the worktree or branch cannot be established, the pane
  returns `WORKTREE_FAIL`, the CLI is never invoked, and the handoff stays
  `OPEN` for retry — it never silently degrades to running in the primary
  checkout. `$script:InvokeCli` now runs the CLI child process with `cwd` set
  to the resolved worktree instead of the caller's location. New regression
  coverage in `tools/4ai-panes/test-pane-runner.ps1` (tests y-ad, incl. a
  live two-worktree sandbox proof mirroring `.ai/tests/test-dispatch-worktree.sh`
  that asserts the primary checkout's HEAD is unchanged after two concurrent
  dispatches). See handoff 202607121130-pane-runner-worktree-parity.
- **Headless Claude dispatch now uses `--dangerously-skip-permissions` instead of
  `--permission-mode acceptEdits`** in both `tools/4ai-panes/pane-runner.ps1`
  (`Get-HeadlessCmd`) and `.ai/tools/dispatch-handoffs.sh` (`headless_cmd`).
  `acceptEdits` auto-approved only Edit/Write, so a Bash call outside
  `.claude/settings.local.json`'s allow-list was auto-denied with no human
  available headless to approve it — the headless Claude lane was strictly
  weaker than every other fleet CLI's headless invocation, and weaker than
  Claude's own interactive pane. Verified empirically that the `PreToolUse`
  guard hooks still fire under the new flag (permissions and hooks are
  separate layers) — see F2 handoff 202607120023.
- **Rebased onto master's `AI_HANDOFF_DISPATCH` nested-dispatch-guard fix
  (0.0.25's `a140807`, "pane-runner: idle heartbeat (F1) + AI_HANDOFF_DISPATCH
  child env (F3)") — the two `$script:InvokeCli` changes are a genuine
  behavioral interleave, not a pick-one conflict.** Worktree confinement
  (`Push-Location $Cwd`) now wraps the WHOLE call as the outermost scope; the
  dispatch-guard-env set/restore is innermost, immediately around the native
  child invocation, so it is acquired last and released first — matching the
  nesting of the two `try/finally` blocks exactly. Both effects now apply to
  every child the pane-runner launches: it runs in its own worktree AND signals
  `AI_HANDOFF_DISPATCH=1` at the same time. New test (am) proves the interleave
  directly: a single `$script:InvokeCli` call with an explicit non-default
  `$Cwd` AND the env-guard child probe, asserting both effects landed on the
  same invocation and both are torn down afterward. See handoff
  202607121500-rebase-f2-pane-parity.

## [0.0.25] - 2026-07-12

### Security

- **The Claude territorial guard never fired on absolute paths — and the test suite was
  certifying the bypass.** `.claude/hooks/pretool-write-edit.sh` computed
  `project_root=$(pwd)`, which under Git Bash yields the MSYS form (`/c/Users/...`),
  while the Write/Edit tools emit the Windows form (`C:\Users\...`). The prefix test
  never matched, so `rel` stayed **absolute** and every territorial `case "$rel" in
  .kimi|.kimi/*)` arm silently missed. A subagent — which under the orchestrator pattern
  is who does all the writing — could write into any other CLI's territory just by using
  an absolute path:

      SUBAGENT + relative   .kimi/foo.md            -> exit=2  BLOCKED
      SUBAGENT + absolute   C:\...\.kimi\foo.md     -> exit=0  ALLOWED

  Reproduced against the pre-fix hook in a **normal (non-worktree) checkout**, which is
  what every onboarded project has. Inside a `.wt/` executor worktree the escape was
  *incidentally* caught by the later ADR-0004 worktree-confinement arm (with a misleading
  "escaping the worktree" reason) — which is why the bug survived: it looked blocked
  wherever the executors actually ran.
- **Paths are now normalized before any rule runs**, by a deliberately **lexical**
  converter (no `realpath`, no `cygpath`). `realpath`/`cygpath -a` resolve symlinks and
  Windows junction reparse points — which would *reintroduce* an escape, since `.ai/` is
  a junction. `cygpath -u` was tried and **fails open**: it canonicalizes the two shapes
  we deliberately refuse (bare drive `C:`, drive-relative `C:foo`) instead of erroring.
- **Normalization fails CLOSED.** An un-canonicalizable `file_path` (bare drive,
  drive-relative, unrecognized shape) is now `exit 2`. A guard that cannot understand its
  input must deny.

### Fixed

- **`test_hooks.sh` fixtures only ever used RELATIVE paths**, so the tests and the runtime
  disagreed about the input domain and the suite had been green *because* it never fed the
  hook what the tools actually send. Fixture set now covers relative, Windows-absolute
  (forward- **and** back-slash), MSYS `/c/` form, mixed case, and the fail-closed shapes.
  **17 → 98 assertions.**
- **`.claude/hooks/README.md` documented the broken behavior.** It advertised
  `PASS: 17/17`, omitted normalization entirely, and — load-bearing — instructed hook
  authors to *"prefer **fail-open** (exit 0 on unexpected input)"*, which is precisely the
  guidance that produced this bug class. Enforcement hooks are now documented as
  fail-**closed**; only advisory hooks may fail open.

### Known gap

- **The Bash tool is NOT path-checked.** `pretool-bash.sh` screens for destructive command
  *shapes* but does no path matching, so `cp`/`mv`/`sed -i`/`tee`/`>` can still write any
  protected path. This change raises the wall; the door beside it is still open. Tracked
  separately — do not treat protected paths as unreachable.

## [0.0.24] - 2026-07-12

### Fixed

- **Onboarded projects received OpenCode with NO mechanical guard layer.** The
  installer manifests (`scripts/sync-assets.ts` and
  `src/installer/copy-framework.ts`) shipped `opencode.json` — which points
  OpenCode at `.opencode/contract.md` — but never shipped `.opencode/` itself.
  Every adopted project therefore ran OpenCode on prompt-level rules alone: no
  write-lane enforcement, no sensitive-file guard, no destructive-command
  guard. This is exactly the no-hook-layer situation ADR-0002's 2026-07-09
  amendment rejected when Crush was replaced. Both manifests now include
  `.opencode`, and a new installer test (`installed OpenCode guard actually
  blocks out-of-lane writes`) imports the guard OUT OF A FRESH INSTALL TARGET
  and proves it blocks `src/`, `.opencode/contract.md`, `.env`, and
  `git push --force` — presence is no longer assumed, it is exercised.
- **Nothing gated the installer asset tree, so it rotted invisibly.** A stale
  generated `assets/` tree (protocol-v2 `AGENTS.md`, dozens of drifted files)
  lingered undetected. New gate `.ai/tools/check-asset-drift.sh`, wired into
  the `gates` workflow after asset regeneration: (1) enforces parity between
  the two ship manifests plus required coverage (`.opencode`, `AGENTS.md`,
  `opencode.json`) — the 2026-07-12 defect class fails here even on a clean
  checkout; (2) rejects any committed file under
  `tools/multi-cli-install/assets/` (a build artifact that goes stale the
  moment its source changes); (3) glob-walks every file of any on-disk asset
  tree and fails on any byte-divergence from its source — no hardcoded file
  list, so new files are covered automatically. Proven both directions:
  53 failures on the real stale tree, PASS once regenerated.

## [0.0.23] - 2026-07-12

### Added

- **OpenCode's two enforcement layers now accept `.ai/activity/entries/**`** — the
  entry-per-file activity-log spool of ADR-0010. Both layers hardcoded the log path
  as an **exact string** (`scripts/git-hooks/pre-commit` L96
  `case "$p" in .ai/activity/log.md|…`; `.opencode/plugin/framework-guard.js`
  `WRITABLE_LANE`), so the first spool entry OpenCode ever wrote would have been
  **blocked by its own guard** and its commit **rejected by the hook** — silently,
  with no error a human would see. This is **permission plumbing only**: it makes the
  spool landable later. Nothing is migrated, `entries/` is not created, no contract's
  logging prose changed, and `.ai/tools/activity-append.sh` is untouched.
  `.ai/activity/log.md` keeps working exactly as before — it is still the live log.

### Fixed

- **OpenCode could write `.github/**` but not commit it.** The 0.0.22 repo-ops
  widening (PR #45) added `.github/**` to the *write* guard and to the contract
  ("you own … CI config/workflow fixes … opening PRs"), but never to the *commit*
  hook's OpenCode whitelist. The result was the same defect class it set out to fix,
  one layer down: OpenCode could produce the workflow fix and then be rejected at
  `git commit`. `.github/*` is now in the pre-commit lane too, so the two layers agree.

### Security

- The spool widening is asserted **not to leak**: the guard suite grew 96 → 133
  assertions and the pre-commit backstop suite 54 → 86, covering relative,
  Windows-absolute, backslash, `./`-prefixed, MSYS `/c/…`, traversal-escape and
  mixed-case forms. Project source, `.claude/**`, `.kimi/**`, `.kiro/**`,
  `.opencode/**`, `.ai/instructions/**` (SSOT), `docs/architecture/**` (ADRs),
  `scripts/**` and secrets remain blocked from OpenCode, and rule 5 (secrets) still
  outranks the lane *inside* the spool (`.ai/activity/entries/id_rsa` is denied).
  `.ai/activity/archive/**` was deliberately **not** granted.
- **Documented, not fixed:** the pre-commit hook matches the lowercased path (`_lc`),
  which makes OpenCode's *whitelist* branch case-INSENSITIVE (fail-**open**) while
  the guard's lane is case-SENSITIVE (fail-**closed**) — the two disagree on
  `.AI/Activity/Entries/x.md`. The leak **cannot escalate** (no case variant reaches
  another CLI's territory, source, or a secret — now asserted), and tightening it
  risks false-blocking a real entry, which is the exact "OpenCode goes silent"
  failure this change prevents. The assertions pin the contract for whoever revisits it.

## [0.0.22] - 2026-07-12

### Fixed

- **OpenCode's guard denied the job its contract assigns it.** `.opencode/contract.md`
  gives OpenCode a "GitHub / repo-ops lane" (PRs, release chores, **CI config/workflow
  fixes**) and operating-prompt §14 routes GitHub work to it — but
  `.opencode/plugin/framework-guard.js` enforced a writable lane of `.ai/activity/log.md`,
  `.ai/reports/**`, `.ai/handoffs/**` only. The first real ops handoff
  (`202607120021-gates-required-check-and-step-order`, a `.github/workflows/gates.yml`
  edit) was therefore mechanically impossible; OpenCode correctly refused and reported
  BLOCKED (`.ai/reports/opencode-2026-07-12-gates-blocked.md`). The lane now includes
  `.github/**` — and nothing else. `infra/`, `scripts/`, `Dockerfile`, `docker-compose*`
  were deliberately NOT added: widening a security guard is a one-way ratchet, and only
  `.github/**` is needed for the documented job.
- **`AGENTS.md` never mirrored the repo-ops lane.** The paragraph was added to
  `.opencode/contract.md` on 2026-07-11 and never propagated, so OpenCode's shipped
  contract did not say it owns GitHub/CI work at all — a contributing cause of the lane
  starvation, not just a symptom (ADR-0011 Context). `AGENTS.md` now carries an
  OpenCode-only lane section.

### Added

- **`WRITABLE_LANE` is now a single exported constant** in `framework-guard.js`, and the
  guard suite **fails loudly if it drifts from the `LANE:BEGIN`/`LANE:END` block in
  `.opencode/contract.md` or `AGENTS.md`.** The doc/enforcement divergence *is* the bug
  above; its recurrence is now a test failure, not a comment.
- **Guard rule 5 (secrets) is enforced mechanically, ahead of every allow rule.** A
  sensitive basename (`.env*`, `*.key`, `*.pem`, `id_rsa*`, `secrets.*`, `credentials*`)
  is denied everywhere — including inside the newly-widened `.github/**` and inside
  `.ai/reports/**`. Previously secrets were blocked only incidentally, by default-deny.
- **OpenCode guard suite: 45 → 96 assertions.** New coverage: `.github/**` allowed in
  relative/absolute/backslash/`./`-prefixed/traversal forms; source, `.claude/`, `.kimi/`,
  `.kiro/`, `.ai/instructions/` (SSOT), `docs/architecture/` (ADRs) and `.opencode/` still
  denied in relative **and absolute and backslash** forms; mixed-case variants fail closed;
  secrets denied inside the lane; doc/guard lane drift.

### Security

- **Project-root prefix comparison is now case-insensitive only on Windows.** It was
  unconditionally case-insensitive, so on a case-sensitive filesystem a sibling directory
  differing only in case (`/PROJ/` next to `/proj/`) would have been folded *inside* the
  project root and its lane paths allowed. Legitimate paths always match case exactly, so
  the strict compare costs nothing and closes the fold.

## [0.0.21] - 2026-07-12

### Fixed

- **`.ai/tools/dispatch-handoffs.sh`: headless dispatch no longer runs every CLI in the
  shared primary checkout.** The dispatcher used to `cd` into the repo root and launch the
  recipient CLI there, so two concurrently dispatched CLIs shared one HEAD and one working
  tree — either could clobber the other's in-flight files with a `git checkout` (the
  ADR-0004 "2026-07-11 near-miss"). Each dispatched CLI now runs inside its **own git
  worktree** at `<parent>/.wt/<project>/<cli>/`, resolved by `worktree_path_for()` and
  created/reused by `ensure_cli_worktree()`. Worktree creation reuses
  `scripts/wt-bootstrap.sh` (single implementation); a healthy existing worktree is reused,
  never destroyed. Worktree setup failure **fails that dispatch** — the handoff stays
  `OPEN` and a failure report is written. Falling back to the primary checkout is forbidden,
  so the race cannot silently reappear.
- **`.ai/tools/dispatch-handoffs.sh`: per-handoff branches are cut from a declared base, not
  ambient HEAD.** A dispatch used to branch from whatever HEAD happened to be, so a handoff
  could inherit unrelated in-flight work from a previous dispatch. `ensure_declared_base_branch()`
  now cuts (or reuses) `exec/<cli>/<slug>` from an explicitly declared base: the handoff's
  optional `Base:` field, else `origin/master`. This is a second, independent defect from the
  shared-HEAD one and is fixed independently.

### Added

- **`.ai/handoffs/` `Base:` field (optional).** A handoff may declare the branch its exec
  branch is cut from; read by `base_for()` from the status block. Absent, dispatch falls back
  to `origin/master`.
- **`.ai/tests/test-dispatch-worktree.sh` — 24 assertions** covering worktree path resolution,
  create-vs-reuse, the no-fallback-to-primary-checkout contract, declared-base branch cuts
  (`Base:` honored, `origin/master` default), and the failure path leaving the handoff `OPEN`.

### Changed

- **`docs/architecture/0004-worktree-multi-project-topology.md` amended (2026-07-11)** to make
  worktree-per-CLI the dispatch contract rather than a manual convention, and to record the
  near-miss that motivated it.

## [0.0.19] - 2026-07-11

### Fixed

- **`tools/4ai-panes/Selector.ps1`: the framework source repo no longer badges itself
  `[! OLD]`.** `Get-ProjectBadges` decided staleness from `.ai/.framework-version` — a
  marker the installer writes *into target projects*. The source repo never carries one
  (its version is `tools/multi-cli-install/package.json` `.version`), so the repo that IS
  the framework reported itself stale against itself. It now badges **`[v SRC]`**: the
  resolved dir is compared to `$frameworkRepo` (`RWN_FRAMEWORK_REPO`-overridable) as
  canonicalized full paths — case-insensitive, trailing-slash and separator tolerant, and
  safe on paths that do not exist. The `[H:n]` handoff badge still applies to it
  unchanged. The one-line badge legend documents `[v SRC]` and stays within its 70-char
  box budget (68).
- **`Selector.ps1`: batch launches no longer race Windows Terminal.** Marking N projects
  used to pack ALL of their `new-tab` groups into as few `wt` invocations as a 7000-char
  budget allowed — WT applies each chained subcommand against whatever pane is focused
  when it reaches it, so ~7 projects dumped dozens of splits at once and the layout came
  out scrambled. Each project now gets **its own `wt` invocation (one tab)**, fired
  sequentially with a settle delay between projects; the cross-project char-budget packing
  is gone.
- **`Selector.ps1`: pane splits within a tab no longer race either.** `Build-FleetTabCmd`
  returned one string chaining `new-tab ; split-pane ; … ; move-focus up ; split-pane`,
  fired as a single atomic `wt` call, so even a lone project could land messy. It is
  replaced by `Build-FleetTabStages`, which returns the tab as a structured `[string[]]`
  of stages (built at the KNOWN boundaries rather than by splitting a chained string on
  `' ; '`, which a quoted CLI payload could otherwise corrupt). Each stage is issued as
  its own `wt -w rwn4ai <stage>` invocation with a delay between. Every stage acts on the
  active pane of the active tab in the `rwn4ai` window — exactly the pane the atomic chain
  acted on — so **the layout is identical; only the timing changes**. `--title` / `-d` /
  `-w rwn4ai` semantics are byte-identical. Applied to the batch path AND both
  single-project (6pane/5pane) paths.

### Added

- **Two pacing knobs (documented in `tools/4ai-panes/README.md`):**
  `RWN_4AI_PANE_DELAY_MS` (default `250`) between pane stages within a tab, and
  `RWN_4AI_TAB_DELAY_MS` (default `1200`) between project tabs in a batch. Setting either
  to `0` restores the legacy **atomic single-invocation** behavior for that dimension
  (escape hatch): pane `0` collapses a project's tab to one chained call; tab `0` collapses
  the whole batch to one chained call. Values are parsed defensively — non-numeric,
  negative or empty fall back to the default and never crash the launcher. An
  over-long atomic invocation (> 7000 chars) is now warned about rather than silently
  truncated by Windows.
- **`tools/4ai-panes/test-selector-e2e.ps1`: four new suites (Tests 3-6), 46 new
  assertions (35 -> 81).** Badge resolution (`[v SRC]` for the source repo including
  trailing-slash / forward-slash / case / non-existent-path tolerance and the retained
  `[H:n]`; `[v OK]` / `[! OLD]` / `[- none]` for temp targets; the legend's 70-char
  budget); staged emission of a 6-pane group asserted **stage-by-stage equal** to the
  legacy atomic chain, with a guard that no stage contains a literal `' ; '`; a batch of N
  projects producing exactly N `new-tab` launches and no packed invocation; and the delay
  knobs (default when unset, honored when set, default on garbage/negative/empty, `0`
  restoring atomic behavior), including contract guards that the production assignments
  still read those env names with those defaults. The plan builders
  (`Build-FleetTabStages`, `Get-FleetLaunchPlan`) are pure, so the suite asserts on the
  constructed `wt` command/stage arrays and never launches Windows Terminal.

## [0.0.18] - 2026-07-11

### Added

- PowerShell syntax gate in `scripts/git-hooks/pre-commit`: a `.ps1` that does not parse
  can no longer enter history. For every staged `.ps1`, the hook extracts the **staged
  blob** (`git show ":$file"`) — not the working tree — and runs it through
  `[System.Management.Automation.Language.Parser]::ParseFile`. Any syntax error rejects
  the commit, naming the file, the first error message and its line number. Reading the
  index rather than the disk is deliberate: a file that is valid on disk but broken in the
  staged version (a partial `git add`) is still caught. This complements the 0.0.17 sync
  gate, which is the *last* line of defense — deploy-time. The commit is the *first*: a
  broken `Selector.ps1` was committed and then carried toward the owner's live launcher by
  the post-commit sync hook, gated only by a copy-hash check that proves fidelity, not
  validity. The gate is a graceful no-op where no PowerShell host exists (`pwsh` and
  `powershell` both absent — i.e. Linux CI), so it can never break commits or CI on
  ubuntu; it enforces on the Windows box, the only place a `.ps1` actually runs. It blocks
  only on a *definitive* parse error, never on a PowerShell host that failed to answer.
  All other guards (territory, sensitive-file, tombstone, root-file) are unchanged; test
  coverage in `scripts/git-hooks/test-pre-commit.sh` goes 50 -> 54 cases.

## [0.0.17] - 2026-07-11

### Added

- Syntax gate in `scripts/sync-4ai-panes-install.ps1`: every `.ps1` source file is now
  parsed (`[System.Management.Automation.Language.Parser]::ParseFile`) before it is
  deployed into the live launcher install (`~/.rwn-auto/rwn-4AI-panes`). A file with
  syntax errors is REFUSED — not copied — the previously deployed known-good version is
  left untouched, the failure is printed loudly (file, first error message, line number),
  and the script exits 1 so the calling git hook surfaces it. The pre-existing hash-verify
  only proves *fidelity* (the bytes that landed are the bytes from source); it cannot
  detect a broken file, so a `Selector.ps1` with an unbalanced brace used to deploy
  cleanly and hash-verify green. The parse gate is an additional precondition, not a
  replacement, and runs BEFORE the atomic move so the target is never half-updated.
  Non-`.ps1` files (README.md, icon.ico, Launch4Panes.vbs) keep hash-verify-only behavior.

## [0.0.16] - 2026-07-11

### Fixed

- Telegram emoji arrived as mojibake (`??` / `?`) from the headless bash notify path.
  `.ai/tools/notify.sh` built the robot/check/warning emoji as raw UTF-8 byte
  sequences (`printf '\xf0\x9f\xa4\x96'`) and shipped them through curl
  `--data-urlencode`; the shell/locale/urlencode chain mangled the bytes before they
  reached Telegram. The request is now sent as a JSON body
  (`Content-Type: application/json`, `--data-binary @-`) with the emoji encoded as
  JSON `\uXXXX` escapes (U+1F916 as a UTF-16 surrogate pair, U+2705 and U+26A0 as
  single escapes), so the payload is pure ASCII on the wire and no locale or
  encoding step can corrupt it. Interpolated values (project, handoff, owner,
  chat_id, thread_id) are JSON-escaped, so a quote or backslash in a name can no
  longer break the request body. The PowerShell path was already correct and is
  unchanged in this respect.

### Added

- Notifications now carry a local wall-clock `HH:MM:SS` timestamp on a third line
  (`_HH:MM:SS_`), so the owner can see when a pick-up / finish / alert actually
  happened. Applied identically to both notify paths (`.ai/tools/notify.sh` and
  `tools/4ai-panes/notify.ps1`) so the bash and PowerShell messages stay in lockstep.

## [0.0.15] - 2026-07-11

### Changed

- Version bump to detect adopter drift for the CLAUDE.md owner-interaction-preference
  directive that landed in the prior commit (7eff945) direct-to-master without a bump.
  The directive tells CLIs to act-and-inform on reversible Tier-A/B work (act, then
  report what was done and how to verify) rather than pausing to ask the owner to
  confirm low-level steps — questions are reserved for genuine blockers and Tier-C
  gates (reinforcing operating-prompt SSOT §8). CLAUDE.md is versioned framework
  content shipped to adopters, but the direct-to-master push bypassed the PR-only
  `check-version-bump.sh` gate, so onboarded projects comparing their
  `.ai/.framework-version` against the template `package.json` .version would not
  have seen the change. This bump versions that framework change so drift detection
  fires.

## [0.0.14] - 2026-07-11

### Added

- Headless dispatch now notifies Telegram (notification coverage gap): the bash
  auto-dispatch path (`.ai/tools/dispatch-handoffs.sh`) was silent — only the
  PowerShell pane-runner loop notified, so `Auto:yes` Risk-A/B handoffs dispatched
  headless never reached the owner. New `.ai/tools/notify.sh` mirrors
  `tools/4ai-panes/notify.ps1` (env-first config resolution, the same 2-line
  bold-project Markdown format, robot/check/warning emoji, 5s curl timeout,
  fail-open) and is wired into the dispatcher at three lifecycle points — `picked`
  before launch, `done` on exit 0, `alert` on a non-zero exit. Both paths share the
  throttle file `.ai/handoffs/.claims/.fleet-notify-throttle.json` (60s dedup on
  `kind|project|handoff`) so they never double-send. `dispatch-own-queue.sh`
  variants inherit this by delegating to `dispatch-handoffs.sh`.

## [0.0.13] - 2026-07-11

### Security

- pre-commit guards failed OPEN on case-insensitive filesystems (latent-issue
  audit #4): the sensitive-file, removed-graph-tombstone, and cross-CLI territory
  checks in `scripts/git-hooks/pre-commit` matched staged paths case-SENSITIVELY,
  so on Windows/macOS a file committed as `.ENV`, `ID_RSA`, or `.Kimi/x` — the SAME
  file — slipped past the backstop. `_is_sensitive`, `_is_tombstone`, and
  `_territory_violation` now match on the lowercased path (new `_lc` helper),
  restoring fail-CLOSED behavior without changing which patterns/territories are
  blocked.

### Fixed

- `install-template.sh` update mode wiped gitignored local state (latent-issue
  audit #6): `.ai/research/` and `.claude/settings.local.json` were destroyed by the
  `rm -rf`+copy path on a framework update of an onboarded project. `.ai/research/`
  is now stashed/restored alongside `.ai/activity` and `.ai/reports`, and a new
  `preserve_local_state`/`restore_local_state` pair carries `.claude/settings.local.json`
  across the destructive `.claude` copy.
- `check-version-bump.sh` version-gate allowlist omitted two shipped scripts
  (latent-issue audit #5): `scripts/fleet-init.sh` and
  `scripts/sync-4ai-panes-install.ps1` are copied into every adopter by the
  installer but changes to them required no version bump, so drift shipped silently.
  Both are now in the `is_versioned` allowlist (`tools/4ai-panes/**` stays excluded —
  it is intentionally not shipped that way).

## [0.0.12] - 2026-07-11

### Security

- Handoff-dispatch command injection (two CRITICAL findings, latent-issue audit
  #1/#2): a crafted handoff **filename** (e.g. `x$(touch pwned).md` or one with
  backticks) could execute arbitrary code when a handoff was auto-processed. Both
  the dispatcher (`.ai/tools/dispatch-handoffs.sh`) and the pane runner
  (`tools/4ai-panes/pane-runner.ps1`) built a shell/PowerShell command STRING with
  the handoff path embedded, then ran it via `eval` / `Invoke-Expression`. Both now
  invoke the recipient CLI with a native argv array (`"${cmd[@]}"` in bash, the call
  operator `& $exe @args` in PowerShell); the handoff path is a single inert argv
  element that is never re-parsed by a shell. The interactive pause hatch was
  likewise converted off `Invoke-Expression`.

### Fixed

- Cross-consumer claim-write race (latent-issue audit #10): the dispatcher created
  the per-handoff claim empty (`:>`) and filled it in a separate `printf`, leaving a
  0-byte window in which the PowerShell pane runner would read it as *unclaimed* and
  double-process the handoff. The claim is now written to a temp file and published
  atomically (hard-link on the common path, atomic rename to overwrite a stale
  claim), mirroring the PowerShell `Write-Claim` pattern — the claim name never
  points at an empty file.

## [0.0.11] - 2026-07-11

### Added

- `install-template.sh` now copies the full `docs/architecture/` ADR set (0001–0009,
  not just 0001) plus the concrete files copied guards/hooks reference
  (`scripts/fleet-init.sh`, `scripts/sync-4ai-panes-install.ps1`,
  `docs/specs/4ai-panes-install-sync.md`), so no governance/automation link dangles
  in an adopted project. The `tools/4ai-panes/` pane fleet is intentionally left
  unshipped by default (labeled STUB/owner-decision flag in the installer).

### Fixed

- `install-template.sh` Kimi-hook idempotency: `wire_kimi_hooks` now strips any
  legacy `# ADDED BY install-template.sh kimi-hooks` block (pre-sentinel append-once
  format) before reconciling, so re-runs converge to exactly one sentinel-fenced
  managed block instead of appending a third block on machines wired before the
  sentinel scheme. Only the four clearly-marked legacy guard stanzas are removed;
  unrelated hooks (safety-check.ps1, activity-log-remind.sh, user hooks) are preserved.
