# Verify master→main migration
Status: OPEN
Sender: opencode-auto
Recipient: kimi-cockpit
Created: 2026-07-17 06:15 (UTC+7)
Auto: yes
Risk: A

## Goal

Independently verify that the master→main default-branch migration completed successfully and correctly.

## Context

- Plan: `.ai/reports/migrate-master-to-main-plan.md`
- Migration handoff: `.ai/handoffs/to-opencode/done/202607161305-execute-master-to-main-migration.md`
- GitHub-ops handoff: `.ai/handoffs/to-opencode/done/202607162033-github-ops-master-main-migration.md`

## Verification checklist

Run ALL verification items from plan §7 and confirm each passes:

- [ ] `gh repo view --json defaultBranchRef` → `{"defaultBranchRef":{"name":"main"}}`
- [ ] `gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection` → contexts `["gates","framework-check"]`, `allow_force_pushes: false`, `allow_deletions: false`
- [ ] `git ls-remote origin refs/heads/master` → empty
- [ ] `git symbolic-ref refs/remotes/origin/HEAD` → `refs/remotes/origin/main`
- [ ] `bash .ai/tests/test-dispatch-worktree.sh` → passes (esp. case 4c)
- [ ] `bash scripts/test-check-version-bump.sh` → passes
- [ ] `powershell.exe -ExecutionPolicy Bypass -File scripts/test-sync-4ai-panes-install.ps1` → passes
- [ ] `bash .ai/tools/dispatch-handoffs.sh` (dry-run, no `--exec`) → no base-resolution errors
- [ ] Grep `grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml` → only §1C-sanctioned hits
- [ ] PR into `main` triggers both `gates` and `framework-check`

## Known issues to validate

1. `tools/4ai-panes/test-pane-runner.ps1` currently reports **3 failures** in the `av4` junction-degradation guard case (clean real dir → re-junction). The rest of the suite (159 passed) is green. Please confirm whether this is environmental or a real regression, and whether it blocks declaring the migration done.
2. During worktree reconciliation the old executor worktrees (`claude`, `kimi`, `kiro`, `opencode`, `kimi-202607131945`) were removed and recreated from `origin/main` because the stale `exec/*/init` branches and skip-worktree flags made in-place rebase impossible. Any **untracked** files that lived only inside `.ai/` in those worktrees were lost when the old worktrees were removed. Tracked `.ai/` files were restored from `HEAD` and are intact.
3. The four primary executor worktrees are now on fresh `exec/<cli>/init` branches pointing at `e187045` (`main`). Confirm they are clean and that `Assert-WorktreeFresh` no longer refuses to start.

## Specific focus

- Verify that the §1C deliberate `master` references survived intact:
  - ADRs (0012, 0013, 0014, 0004)
  - `CHANGELOG.md`
  - Force-push guard fixtures in `.opencode/plugin/test-guard.mjs` and `tools/multi-cli-install/test/installer.test.ts`
  - `test-pane-runner.ps1` cases 502–510
- Verify that `test-pane-runner.ps1` still passes for both `master` and `main` repos (502–510 preserved, new fail-closed test added).
- Spot-check that no `origin/master` hardcoding remains in runtime scripts/workflow files outside the §1C exceptions.

## Expected outcome

All verification items pass, confirming:
- `main` is the default branch
- Protection rules migrated intact
- `master` does not exist on origin
- Base resolution auto-follows `origin/HEAD`
- Tests pass, including the preserved master-default regression test
- Only §1C `master` references remain in the codebase

## Activity log

## 2026-07-17 06:15 (UTC+7) — opencode-auto
- Action: emitted verification handoff to kimi-cockpit for master→main migration
- Files: `.ai/handoffs/to-kimi/open/202607162315-verify-master-to-main-migration.md`
- Decisions: left the `av4` pane-runner failures and the lost-untracked-.ai note for independent verification rather than declaring done unilaterally
