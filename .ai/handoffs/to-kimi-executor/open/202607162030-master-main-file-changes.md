# Complete file changes for master→main migration

This handoff contains ONLY the file changes (no GitHub operations), which are routed to the appropriate CLIs per their lanes. GitHub operations (branch rename, PR, refs) remain in opencode's lane.

Status: OPEN
Sender: opencode-auto
Recipient: kimi-executor + kiro-executor
Created: 2026-07-16 20:30 (UTC+7)
Auto: yes
Risk: B

## Goal

Execute plan §1A, §1B, §1D (file changes only) for master→main migration. Use separate files for:
- **Kimi-executor**: `scripts/` files (sync-4ai-panes-install.ps1, check-version-bump.sh)
- **Kiro-executor**: `tools/4ai-panes/` files (pane-runner.ps1, test-pane-runner.ps1)
- **Claude**: Documentation files (README.md, scripts/README.md, specs, guides, .github/release.yml)

Do NOT touch any §1C files (deliberate master references that must survive). Do NOT edit ADRs or `.claude/`.

## Work in progress

### OpenCode changes (already applied):

#### `.github/workflows/gates.yml`
- Line 17: `      - master` → `      - main`
- Line 20: `      - master` → `      - main`
- Line 10 comment: branch name updated
- Lines 97-98, 104: comments updated

#### `.github/workflows/framework-check.yml`
- Line 14: `      - master` → `      - main`
- Line 5 comment: branch name updated

#### `.github/workflows/release.yml`
- Line 35: `      - master` → `      - main`
- Lines 9, 24, 42, 44, 109, 120, 187: comments updated

---

## Remaining work to delegate

### For kimi-executor: scripts/

#### 1. `scripts/sync-4ai-panes-install.ps1` (item 1A, lines 9-11, 14, 26-27, 146, 196-197)

**Section 14 (doc comments):** lines 14, 26-27
```
Line 14: "off-master" → "off-main"
Lines 26-27: "branch 'master'" → "branch 'main'" and "master code" → "main code"
```

**Section 146-150 (doc comment):** update wording to match section 14
```
"only primary-checkout master code may deploy" → "only primary-checkout main code may deploy"
```

**Section 196 (provenance guard):**
```powershell
$branch -ne 'master'  # Change 'master' → 'main'
```

**Section 197 (provenance guard error message):**
```powershell
"not primary/master" → "not primary/main"
"Only merged master code may reach the live install" → "Only merged main code may reach the live install"
```

**Implementation details:**
- Read the full 340-line file to understand context
- Keep all other logic unchanged
- Only update the 5 master→main strings

---

#### 2. `scripts/check-version-bump.sh` (item 1A, lines 14, 15, 61-62)

**Section 14 (doc comments):** lines 14, 15
```
Line 14: "push: master" → "push: main"
Line 15: "previous master tip" → "previous main tip"
```

**Section 61-62 (script usage):**
```bash
BASE_REF=origin/master  # Change → BASE_REF=origin/main
```

**Implementation details:**
- Read the file to find exact context around lines 61-62
- Update only the `BASE_REF` variable assignment
- Update doc comments only
- Keep all other logic unchanged

---

### For kiro-executor: tools/4ai-panes/

#### 3. `tools/4ai-panes/pane-runner.ps1` (item 1A line 12, 1C item 12 + §2 fix)

**Section 1A (lines 1269, 1278, 1283, 1285):** update doc comments
```
Lines 1269, 1283, 1285: "origin/master" in synopsis + STALE messages → resolved default branch
```

**Section 1C + §2 (lines 1278):** refactor Assert-WorktreeFresh
```
Current (FAIL OPEN):
    $behind = git rev-list --count HEAD..origin/master 2>$null
    if ($behind -match '^\d+$') { ... }

Proposed (FAIL CLOSED):
    # Extract offline-first resolution from Get-DeclaredBase (lines 380-421)
    $base = Resolve-DefaultBase -ProjectDir $ProjectDir
    $behind = git rev-list --count "HEAD..$base" 2>$null
    # Guard must FAIL CLOSED if base cannot resolve
```

**Implementation requirements:**
- Implement `Resolve-DefaultBase` helper function following Get-DeclaredBase's logic
- Call it from both Assert-WorktreeFresh and the existing site
- Fail CLOSED on unresolvable base (exit/throw, don't silently pass)
- Keep Get-DeclaredBase unchanged (already migrated)
- Add test in test-pane-runner.ps1 for fail-closed path (item 1B line 18)
- Preserve existing test case 502–510 (deliberate master reference)

---

#### 4. `tools/4ai-panes/test-pane-runner.ps1` (item 1B, lines 17-21)

**Section 1B (lines 17-21):** test file updates
```
Line 171: Mock GetDeclaredBase returns 'origin/master' → 'origin/main'
Lines 591, 596: git branch -M master / git push -u origin master → main
Line 44: Comment "defaults to origin/master" → either fix or remove (becomes inaccurate either way)
```

**Keep intact (item 1C):**
- Lines 502–510: regression test for master-default repos
- No changes to these lines

---

### For Claude: documentation files

#### 5. Documentation files (item 1D, lines 11-15)

**Files to update:**
- `README.md` (lines 55, 76, 195, 199)
- `scripts/README.md` (lines 74, 86)
- `docs/specs/4ai-panes-install-sync.md` (lines 18, 207)
- `docs/specs/framework-install-drift-check.md` (line 340)
- `docs/guides/framework-upgrade-runbook.md` (line 1)
- `docs/guides/contributing.md` (line 1)
- `.github/release.yml` (line 7)

**Change pattern:** `git checkout master` → `git checkout main`

**Keep intact (item 1C):**
- No documentation files are in §1C
- All are low-risk prose updates

---

## Verification (after all changes applied)

Run verification suite per plan §7:

- `pwsh tools/4ai-panes/test-pane-runner.ps1` → passes, including preserved 502–510
- `bash scripts/test-check-version-bump.sh` → passes
- `pwsh scripts/test-sync-4ai-panes-install.ps1` → passes
- `bash .ai/tests/test-dispatch-worktree.sh` → passes (esp. case 4c)
- `grep -rn "origin/master" tools/ scripts/ .github/ --include=*.ps1 --include=*.sh --include=*.yml` → only §1C-sanctioned hits

---

## Activity log (to be prepended after completion)

## 2026-07-16 20:30 (UTC+7) — opencode-auto
- Action: routed file-change portion of master→main migration to kimi-executor + kiro-executor
- Files: —
- Decisions: split work by lane (scripts→kimi, tools→kiro, docs→Claude) to respect framework guard

## When complete

1. Each recipient self-retires by moving their handoff to `done/`
2. After all files changed, notify OpenCode via handoff to execute GitHub operations (branch rename, refs, worktree rebase)
