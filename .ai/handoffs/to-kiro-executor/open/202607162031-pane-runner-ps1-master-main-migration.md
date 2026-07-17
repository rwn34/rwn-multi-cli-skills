# pane-runner.ps1 master→main migration

Status: OPEN
Sender: opencode-auto
Recipient: kiro-executor
Created: 2026-07-16 20:31 (UTC+7)
Auto: yes
Risk: B

## Goal

Update `tools/4ai-panes/pane-runner.ps1` for master→main migration:
- §1A: Doc comment updates (lines 1269, 1278, 1283, 1285)
- §1C + §2: Refactor Assert-WorktreeFresh to fail CLOSED (line 1278)

## Work to do

### 1. Doc comment updates (§1A)

**Lines 1269, 1283, 1285:** Update `origin/master` references to "resolved default branch"

```powershell
# Line 1269 (approximate location in synopsis or error messages):
# Old: ...origin/master...
# New: ...[resolved default branch]...

# Line 1283:
# Old: ...origin/master...
# New: ...[resolved default branch]...

# Line 1285:
# Old: ...origin/master...
# New: ...[resolved default branch]...
```

**Context:** These are in the synopsis and STALE messages. Replace with generic "resolved default branch" since the function now uses Resolve-DefaultBase.

---

### 2. Refactor Assert-WorktreeFresh (§1C + §2)

**Location:** Line ~1278 (inside Assert-WorktreeFresh function)

**Current code (FAIL OPEN):**
```powershell
$behind = git rev-list --count HEAD..origin/master 2>$null
if ($behind -match '^\d+$') {
    if ($behind -gt 0) {
        Write-Warning "Worktree behind origin/master by $behind commit(s)."
        $ExitCode = 100
    }
}
```

**Problem:** On a `main` repo, `git rev-list --count HEAD..origin/master` returns nothing (fails silently), `$behind` is `$null`, the guard passes (FAIL OPEN), defeating ADR-0004 reverse-write guard.

**New code (FAIL CLOSED):**

```powershell
# Use offline-first resolution (same logic as Get-DeclaredBase lines 380-421)
# This extracts the shared default-branch resolution so both sites work on both main and master
$base = Resolve-DefaultBase -ProjectDir $ProjectDir  # -> e.g. 'origin/main'
$behind = git rev-list --count "HEAD..$base" 2>$null

# FAIL CLOSED: if base cannot be resolved, refuse to start the pane
if (-not $behind -match '^\d+$') {
    throw "Assert-WorktreeFresh: cannot resolve default branch for $ProjectDir"
}

if ($behind -gt 0) {
    Write-Warning "Worktree behind $base by $behind commit(s)."
    $ExitCode = 100
}
```

**Implementation steps:**

1. Implement `Resolve-DefaultBase` helper function (extract logic from Get-DeclaredBase lines 380-421):
   ```powershell
   function Resolve-DefaultBase {
       param([string]$ProjectDir)

       $remoteDefault = $null

       # Try offline-first resolution first (no network needed)
       try {
           $remoteDefault = git -C $ProjectDir symbolic-ref refs/remotes/origin/HEAD 2>$null
           if ($LASTEXITCODE -eq 0 -and $remoteDefault) {
               # Output: refs/remotes/origin/main
               $remoteDefault = $remoteDefault.Trim() -replace '^refs/remotes/origin/', ''
               return $remoteDefault
           }
       } catch {
           # Silently continue
       }

       # Fallback: ask origin for HEAD ref (network call)
       try {
           $remoteDefault = git -C $ProjectDir ls-remote --symbolic-refs origin HEAD 2>$null
           if ($LASTEXITCODE -eq 0 -and $remoteDefault) {
               # Output: refs/heads/main (or refs/heads/master)
               $remoteDefault = $remoteDefault.Trim() -replace '^refs/heads/', ''
               return $remoteDefault
           }
       } catch {
           # Silently continue
       }

       # If we reach here, base cannot be resolved
       throw "Resolve-DefaultBase: unable to determine remote default branch"
   }
   ```

2. Replace hardcoded `origin/master` in Assert-WorktreeFresh with call to Resolve-DefaultBase
3. Add fail-closed throw on unresolvable base
4. Update doc comments (lines 1269, 1283, 1285) as specified above
5. **Do NOT change** Get-DeclaredBase (it's already migrated and working)

---

## Keep intact (§1C)

- **Lines 502–510** in test-pane-runner.ps1: regression test for master-default repos
  - Do NOT touch these lines
  - The test should still pass and still expect origin/master for master-default repos
  - This tests adopter repos on master

---

## Verification

After changes:

1. Read pane-runner.ps1 to verify doc comments updated
2. Verify Resolve-DefaultBase is correctly implemented
3. Verify Assert-WorktreeFresh calls Resolve-DefaultBase
4. Verify fail-closed throw exists
5. Verify Get-DeclaredBase unchanged

Then run:
- `pwsh tools/4ai-panes/test-pane-runner.ps1` → should pass, including preserved case 502–510

---

## Activity log (to be prepended after completion)

## 2026-07-16 20:31 (UTC+7) — kiro-executor
- Action: pane-runner.ps1 doc comment updates + Assert-WorktreeFresh refactor for master→main migration
- Files: tools/4ai-panes/pane-runner.ps1
- Decisions: extracted Resolve-DefaultBase helper to fail CLOSED on unresolvable base

## When complete

Self-retire: move this file from `open/` to `done/`
