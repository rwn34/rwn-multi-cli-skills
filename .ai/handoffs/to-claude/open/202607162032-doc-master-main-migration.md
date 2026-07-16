# Documentation updates for master→main migration

## Sender: opencode-auto
## Recipient: claude-code (code-reviewer)
## Created: 2026-07-16 20:32 (UTC+7)
## Auto: yes
## Risk: B

## Goal

Update documentation files for master→main migration per plan §1D (low-risk prose updates). Change `git checkout master` → `git checkout main`.

## Files to update

### 1. `README.md` (lines 55, 76, 195, 199)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 55:** Phase-6 example
**Line 76:** Substitution guidance
**Line 195:** Example command
**Line 199:** "substitute if yours differs"

---

### 2. `scripts/README.md` (lines 74, 86)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 74:** Example in troubleshooting or installation
**Line 86:** "substitute if yours differs"

---

### 3. `docs/specs/4ai-panes-install-sync.md` (lines 18, 207)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 18:** References to the guard
**Line 207:** Usage example

---

### 4. `docs/specs/framework-install-drift-check.md` (line 340)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 340:** "detective check on `push: master`"

---

### 5. `docs/guides/framework-upgrade-runbook.md` (line 1)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 1:** Prose, example usage

---

### 6. `docs/guides/contributing.md` (line 1)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 1:** Prose, example usage

---

### 7. `.github/release.yml` (line 7)

**Change pattern:** `git checkout master` → `git checkout main`

**Line 7:** Comment "direct-to-master commits"

---

## Keep intact

- **No documentation files are in §1C** (deliberate master references that must survive)
- All are low-risk prose updates
- No ADRs (those are Claude's lane)
- No CHANGELOG.md (historical record, immutable)

---

## Change pattern

Simple text replacement:
```
git checkout master
git checkout -b feature origin/master
git checkout master
```

→
```
git checkout main
git checkout -b feature origin/main
git checkout main
```

Also update guidance text: "substitute if yours differs" is still valid for adopters, but the default changes from master to main.

---

## Verification

After changes:

1. Verify all 7 files have been updated
2. Verify no other files in the repository incorrectly have master→main changes (only §1C files should have master)
3. Run `grep -rn "git checkout master" --include=*.md --include=*.ps1 --include=*.sh --include=*.yml .` to catch any missed

---

## Activity log (to be prepended after completion)

## 2026-07-16 20:32 (UTC+7) — claude-code
- Action: documentation updates for master→main migration (7 files)
- Files: README.md, scripts/README.md, docs/specs/4ai-panes-install-sync.md, docs/specs/framework-install-drift-check.md, docs/guides/framework-upgrade-runbook.md, docs/guides/contributing.md, .github/release.yml
- Decisions: only low-risk prose updates, no ADR or CHANGELOG edits

## When complete

Self-retire: move this file from `open/` to `done/`
