# Apply remaining master→main file changes to `migrate-master-to-main` branch
Status: OPEN
Sender: opencode-auto
Recipient: kimi-cockpit
Owner: opencode-auto
Created: 2026-07-16 21:02 (UTC+7)
Auto: yes
Risk: B
Next: opencode-auto

## Goal

Complete the file changes required for the master→main migration on the `migrate-master-to-main` branch, which already contains most of the changes from the plan. Apply the remaining changes so the branch is ready for PR creation.

## Context

- The `migrate-master-to-main` branch already has most changes from the plan: workflow files, operating-prompt SSOT replicas, and activity log.
- P0 checks were verified clear (no `.ai/` deletions, no ahead commit).
- The executor worktree is confined to `C:/Users/rwn34/Code/.wt/rwn-multi-cli-skills/opencode` and cannot edit files outside it via `Edit`/`Write` tools.
- The primary repo is at `C:/Users/rwn34/Code/rwn-multi-cli-skills` on the `migrate-master-to-main` branch.

## Changes required (per plan §1A, §1B, §1D)

### 1. scripts/sync-4ai-panes-install.ps1
Replace all instances of 'master' with 'main' that are NOT §1C-sanctioned (this file is NOT in §1C; it's functional, branch-name-dependent):

- Line 14: comment "off-master" → "off-main"
- Line 26: comment "HEAD on branch 'master'" → "HEAD on branch 'main'"
- Line 146: comment "--- Provenance guard: only primary-checkout master code may deploy ---" → "only primary-checkout main code may deploy"
- Line 196: `$branch -ne 'master'` → `$branch -ne 'main'`
- Line 197: message "not primary/master" → "not primary/main"

### 2. scripts/check-version-bump.sh
Replace 'master' with 'main' in functional locations (per plan §1A):

- Line 61-62: `BASE_REF=origin/master` → `origin/main`
- Line 3: comment "push: master" → "push: main"
- Line 5-6: comment "previous master tip" → "previous main tip"
- Line 13: comment "previous master tip" → "previous main tip"
- Line 20: comment "previous master tip" → "previous main tip"
- Line 60: comment "push: master" → "push: main"
- Line 224: comment "fail CLOSED on an unresolvable master ref" → "fail CLOSED on an unresolvable main ref"

### 3. tools/4ai-panes/pane-runner.ps1 (Item 12)
Per plan §2: Implement `Resolve-DefaultBase` helper and fail CLOSED when base cannot resolve:

- Extract resolution chain from `Get-DeclaredBase` (lines 380–421) into a shared `Resolve-DefaultBase` helper.
- Replace hardcoded `git rev-list --count HEAD..origin/master` in `Assert-WorktreeFresh` (line 1278) with `$base = Resolve-DefaultBase -ProjectDir $ProjectDir`.
- Add a `test-pane-runner.ps1` test case for the fail-closed path, preserving existing case 502–510.
- Update synopsis and STALE messages at lines 1269, 1283, 1285 to use resolved default branch instead of `origin/master`.

### 4. Git config
- Run: `git config init.defaultBranch main` (repo-local, not global)

### 5. Documentation updates
Update prose docs that refer to 'master' as a branch name (per plan §1D, excluding Claude's lane and ADRs):

- README.md lines 55, 76, 195, 199
- scripts/README.md lines 74, 86
- docs/specs/4ai-panes-install-sync.md lines 18, 207
- docs/specs/framework-install-drift-check.md line 340
- docs/guides/framework-upgrade-runbook.md line 1
- docs/guides/contributing.md line 1
- .github/release.yml line 7

Ensure you do NOT modify ADRs (§1C), CHANGELOG.md (§1C), or `.claude/agents/release-engineer.md` (Claude's lane).

## Execution

1. Checkout or re-create the `migrate-master-to-main` branch from `origin/master`.
2. Apply all changes above using `Edit` tool (each file change individually).
3. Verify the changes are correct by running:
   - `git diff --stat origin/master..migrate-master-to-main` (should show updated files)
   - `git diff --name-only origin/master..migrate-master-to-main` (list of changed files)
4. Report back with:
   - List of files modified
   - Confirmation that §1C files were NOT touched
   - A brief confirmation that all 'master' → 'main' replacements are complete and functional locations only

## Constraints

- Work on a branch (do not commit to `master`).
- Do not touch §1C files (ADRs, CHANGELOG, force-push-guard fixtures, test-pane-runner.ps1 502–510).
- Do not edit `.claude/agents/release-engineer.md` (Claude's lane).
- Do not edit ADRs (they are immutable history records).
