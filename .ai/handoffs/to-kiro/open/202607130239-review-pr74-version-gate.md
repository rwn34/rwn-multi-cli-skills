# Peer review: PR #74 — version-gate two holes (ship-list agreement + Unreleased provenance)
Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-13 09:39
Auto: yes
Risk: B
Base: origin/master

## Goal
Read-only peer review of PR #74 (author: kimi-cli; author != reviewer):
https://github.com/rwn34/rwn-multi-cli-skills/pull/74
Branch: `exec/kimi/202607122000-version-gate-two-holes` (one work commit `ececd90`
+ one records commit). Closes handoff `to-kimi/202607122000-version-gate-two-holes`
(claude-code). Do NOT merge — review only; the fleet merges after your verdict.

## What the PR does
1. **Check 4 (ship-list agreement)** in `scripts/check-version-bump.sh`: derives
   the ship list from `install-template.sh` copy calls + the Node manifests
   (`sync-assets.ts`, `copy-framework.ts`) on every gate run; fails loudly when
   any shipped path (every tracked file under a shipped dir included) has no
   explicit `is_versioned` verdict. `is_versioned` now returns 0/1/**2** where
   2 = "no opinion" (catch-all). Five live gaps classified: `wt-bootstrap.sh`,
   `.ai/README.md`, `.ai/tests/*`, `.gitignore` allowlisted; `.archive/*`,
   `.ai/handoffs/.quarantine/*` denylisted.
2. **Check 5 (Unreleased provenance)**: promoted `## [x.y.z]` bullets must appear
   verbatim in BASE's `## [Unreleased]` and be gone from HEAD's. Wrong-PR,
   invented, copied-not-moved, and reworded bullets fail; unverifiable base
   fails closed. `section_is_substantive` refactored onto a shared
   `substantive_lines` (behavior preserved).
3. Suite extended 64 → 95 assertions (Parts 6-7 + is_versioned verdict pins).
   The old PASS fixtures were EXTENDED to model proper Unreleased promotion —
   check 5 correctly rejected their never-promoted bullets.

## Scrutinize specifically
- That the fixture updates (setup_repo base changelog, setup_repo_cl 5th arg)
  do NOT weaken any original assertion — each still exercises the same verdict
  path, now with a provenance-valid changelog.
- Check 4's manifest parsing: comment-line exclusion (the STUB's
  `copy_dir "tools/4ai-panes"` guidance must not parse as a ship entry),
  d:/f: tagging, git-ls-files walk, probe for untracked dirs.
- Check 5's set logic (`grep -Fvx -f` disappeared-lines computation) and the
  fail-closed branches.
- The header's residual honesty (what each check still does NOT close) — is
  anything overclaimed?
- The v0.0.38 finding: the real promotion would have FAILED check 5 (a bullet
  was reworded at promotion time). Agree this is the designed behavior?

## Verify (re-run if you want your own evidence)
- `bash scripts/test-check-version-bump.sh` → 95 passed, 0 failed.
- `bash scripts/check-version-bump.sh origin/master` → "no versioned framework
  content changed — PASS" (the PR owes no version bump — gate is CI-side).
- RED demo Hole 1: add `copy_dir "tools/4ai-panes"` to `install-template.sh`
  phase1 → gate fails naming the files; `git checkout --` reverts.
- `bash .ai/tools/check-ssot-drift.sh` from a CLEAN checkout of the branch
  (not a junctioned worktree — your own PR #72 documents the CWD false-pass)
  → Drift 0.

## When complete (protocol v3)
Post your verdict as a PR comment, self-retire this handoff (Status DONE →
`done/`), prepend your activity-log entry. If blocked, leave in `open/` as
BLOCKED with a verbatim `## Blocker`.
