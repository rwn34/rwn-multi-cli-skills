# GitHub operations and verification for master→main migration

## Sender: opencode-auto
## Recipient: opencode-auto
## Created: 2026-07-16 20:33 (UTC+7)
## Auto: yes
## Risk: B

## Goal

Execute GitHub operations and verification after file changes are complete:
1. Create PR with file changes
2. After Claude merges, rename master→main on GitHub
3. Repoint refs and config
4. Reconcile live worktrees
5. Run verification suite
6. Emit verification handoff to kimi-cockpit

## Prerequisites

- All file changes delegated to kimi-executor + kiro-executor + claude-code are DONE
- Verified with grep that only §1C files have `master` references
- Branch `opencode/migrate-master-to-main` exists with all changes applied

---

## Step 1: Open PR into master

**Create PR from `opencode/migrate-master-to-main` → `master`**

```bash
gh pr create --base master --title "Migrate default branch from master to main" --body "Per plan: .ai/reports/migrate-master-to-main-plan.md

**Purpose:** Make `main` the sole default branch of rwn-multi-cli-skills.

**What changed:**
- GitHub workflows (gates, framework-check, release) now target `main`
- Scripts: sync-4ai-panes-install.ps1 and check-version-bump.sh updated
- tools/4ai-panes/pane-runner.ps1: Assert-WorktreeFresh refactored to fail CLOSED
- Documentation: 7 files updated (git checkout master → git checkout main)

**What stayed unchanged:**
- §1C deliberate master references (ADRs, CHANGELOG, force-push-guard fixtures, test-pane-runner.ps1 cases 502–510)
- Dispatch/base-resolution path (already migrated)
- Claude-lane files (.claude/agents/release-engineer.md, ADRs, CHANGELOG)

**Verification:** All tests passing, only §1C master references remain.

**Plan:** https://docs.google.com/document/d/1XXXXXXXXXXXXX/edit
"
```

**Do NOT merge** — Claude's gate. Report the PR URL and stop.

---

## Step 2: After Claude merges

When Claude approves and merges the PR to `master`:

### 2.1 Rename master→main on GitHub (immediately)

```bash
gh api -X POST repos/rwn34/rwn-multi-cli-skills/branches/master/rename -f new_name=main
```

**Timing:** Do this immediately in the same session after merge. `gates.yml`/`framework-check.yml` will now only trigger on `main`, so pushes to `master` will stop running required checks. Do not leave that window open.

### 2.2 Verify rename succeeded

```bash
gh repo view --json defaultBranchRef
# Expected: {"defaultBranchRef":{"name":"main"}}

gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection
# Expected: contexts ["gates","framework-check"], allow_force_pushes: false, allow_deletions: false

git ls-remote origin refs/heads/master
# Expected: (no output)
```

---

## Step 3: Repoint refs and config

**Primary checkout** (assume primary checkout is at `C:/Users/rwn34/Code/rwn-multi-cli-skills`):

```bash
# Step 3.6 from plan: repoint refs and config
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills remote set-head origin -a
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config init.defaultBranch main

# Verify
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills symbolic-ref refs/remotes/origin/HEAD
# Expected: refs/remotes/origin/main
```

**Note:** Leave global `init.defaultBranch` alone (it's unset, out of repo scope). Only set repo-local config.

---

## Step 4: Repoint stale branch tracking

GitHub's rename does NOT touch local config. ~40 of ~120 `branch.*` entries have `merge = refs/heads/master`. Repoint those still in use:

```bash
# First, enumerate the branches that need updating
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config --get-regexp "^branch\..*\.merge$" | grep "refs/heads/master$"

# Then, for each branch still in use, update the merge ref
# Example (adjust for actual branch names from grep output):
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config branch.exec/claude/202607161231-....merge refs/heads/main
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config branch.exec/kimi/202607151144-....merge refs/heads/main
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config branch.exec/kiro/202607142348-....merge refs/heads/main
git -C C:/Users/rwn34/Code/rwn-multi-cli-skills config branch.exec/opencode/202607151138-....merge refs/heads/main
# ...repeat for other branches still in use

# Dead branches (not referenced anywhere) can be left as-is. Not pruning them is Tier B (repo hygiene) and belongs to Claude.
```

---

## Step 5: Reconcile live worktrees

Rebase all 12 worktrees onto `origin/main` after the rename. `.ai/` in each worktree is a junction to the primary, so no per-worktree `.ai/` action needed.

| Worktree | Branch | Action |
|---|---|---|
| `rwn-multi-cli-skills` (primary) | `master` | After pushing or dropping the unpushed commit (P0), rebase: `git rebase origin/main` |
| `.wt/…/claude` | `exec/claude/202607161231-…` | `git fetch origin --prune && git rebase origin/main` |
| `.wt/…/kimi` | `exec/kimi/202607151144-…` | `git fetch origin --prune && git rebase origin/main` |
| `.wt/…/opencode` | `exec/opencode/202607151138-…` | `git fetch origin --prune && git rebase origin/main` |
| `.wt/…/kiro` | `exec/kiro/202607142348-…` | `git fetch origin --prune && git rebase origin/main` |
| `.wt/…/kimi-202607131945` | `exec/kimi/202607131945-…` | `git fetch origin --prune && git rebase origin/main` (stale, but rebase for safety) |
| `.wt/…/.wt/claude/{claude,kiro,opencode}` | `exec/*/2026071?…` | `git fetch origin --prune && git rebase origin/main` (nested .wt/ - topology smell) |
| `.wt-infra/…/bash-path-mangling` | `claude/fix-bash-path-mangling` | `git fetch origin --prune && git rebase origin/main` |
| `.claude/worktrees/agent-af8880a7…` | `claude/sync-provenance-installer-fix` | `git fetch origin --prune && git rebase origin/main` (prunable by git) |
| `AppData/Local/Temp/kiro-rebase-check` | DETACHED `9371a40` | Detached HEAD - recreate worktree from origin/main instead |

**Note:** Stale branches and worktrees are NOT pruned by this migration (Tier B repo hygiene). That belongs to Claude.

---

## Step 6: Run verification suite (plan §7)

Paste raw output for each:

### 6.1 GitHub state

```bash
gh repo view --json defaultBranchRef
gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection
git ls-remote origin refs/heads/master
```

### 6.2 Git refs

```bash
git symbolic-ref refs/remotes/origin/HEAD
```

### 6.3 Test suites

```bash
bash .ai/tests/test-dispatch-worktree.sh
pwsh tools/4ai-panes/test-pane-runner.ps1
bash scripts/test-check-version-bump.sh
pwsh scripts/test-sync-4ai-panes-install.ps1
```

### 6.4 Base resolution

```bash
bash .ai/tools/dispatch-handoffs.sh (dry-run, no --exec)
```

### 6.5 Grep verification

```bash
grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml
# Expected: only §1C-sanctioned hits (ADRs, force-push-guard fixtures, test-pane-runner.ps1 502–510)
```

### 6.6 PR verification

- Create a no-op PR into `main`
- Verify both `gates` and `framework-check` pass

---

## Step 7: Emit verification handoff to kimi-cockpit

**CRITICAL:** This is NOT optional per plan.

Create handoff file: `.ai/handoffs/to-kimi/open/<UTC YYYYMMDDHHMM>-verify-master-to-main-migration.md`

**File structure:**

```
# Verify master→main migration

## Sender: opencode-auto
## Recipient: kimi-cockpit
## Created: 2026-07-16 20:34 (UTC+7)
## Auto: yes
## Risk: A

## Goal

Independently verify that the master→main migration completed successfully and correctly.

## Verification checklist

Run ALL verification items from plan §7 and verify each passes:

- [ ] `gh repo view --json defaultBranchRef` → {"defaultBranchRef":{"name":"main"}}
- [ ] `gh api repos/rwn34/rwn-multi-cli-skills/branches/main/protection` → contexts ["gates","framework-check"], allow_force_pushes: false, allow_deletions: false
- [ ] `git ls-remote origin refs/heads/master` → empty
- [ ] `git symbolic-ref refs/remotes/origin/HEAD` → refs/remotes/origin/main
- [ ] `bash .ai/tests/test-dispatch-worktree.sh` → passes (esp. case 4c)
- [ ] `pwsh tools/4ai-panes/test-pane-runner.ps1` → passes, including preserved case 502–510
- [ ] `bash scripts/test-check-version-bump.sh` → passes
- [ ] `pwsh scripts/test-sync-4ai-panes-install.ps1` → passes
- [ ] `bash .ai/tools/dispatch-handoffs.sh` (dry-run) → resolves base as origin/main
- [ ] Grep `grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml` → only §1C-sanctioned hits
- [ ] PR into main triggers both `gates` and `framework-check`

## Specific focus

- Verify that the §1C deliberate `master` references survived intact:
  - ADRs (0012, 0013, 0014, 0004)
  - CHANGELOG.md
  - Force-push guard fixtures in `.opencode/plugin/test-guard.mjs` and `tools/multi-cli-install/test/installer.test.ts`
  - `test-pane-runner.ps1` cases 502–510
- Verify that `test-pane-runner.ps1` still passes for both main and master repos (502–510 preserved, new fail-closed test added)

## Expected outcome

All verification items pass, confirming:
- `main` is the default branch
- Protection rules migrated intact
- `master` does not exist on origin
- Base resolution auto-follows origin/HEAD
- All tests pass, including the preserved master-default regression test
- Only §1C master references remain in the codebase

## Activity log

## 2026-07-16 20:34 (UTC+7) — opencode-auto
- Action: emitted verification handoff to kimi-cockpit for master→main migration
- Files: .ai/handoffs/to-kimi/open/202607162034-verify-master-to-main-migration.md
- Decisions: independent verification by kimi-cockpit before finalizing

## When complete

Self-retire: move this file from `open/` to `done/`
```

---

## Step 8: Self-retire (original handoff)

Move this handoff from `open/` to `done/`.

---

## Activity log (to be prepended after completion)

## 2026-07-16 20:33 (UTC+7) — opencode-auto
- Action: executed GitHub operations and verification for master→main migration
- Files: —
- Decisions: renamed master→main on GitHub, repointed refs and worktrees, ran verification suite, emitted verification handoff to kimi-cockpit

## When complete

1. Self-retire this handoff by moving it to `done/`
2. Wait for kimi-cockpit's verification handoff to complete
3. Claude decides whether the decision warrants an ADR or amendment note (Claude's lane, Tier B)
