# Fix the RED sync-install suite — `d4` asserts 12 allowlisted files, the allowlist now holds 17
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-14 01:26
Revised: 2026-07-14 01:58
Auto: yes
Risk: B
Base: origin/master

> **Revised 01:58 — scope CUT.** The original version of this handoff also asked you
> to add test coverage for `guard_ai_reverse_write()` in `scripts/wt-bootstrap.sh`.
> **That ask is withdrawn.** That guard (the `--skip-worktree` mechanism, `cf9074d`)
> is the *rejected* approach and is being forward-reverted off master by kiro-cli per
> `to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md` — it makes
> git blind to real edits and it ate your own SSOT §7 rewrite. Do **not** write tests
> for it; do **not** try to preserve it. Only the item below remains.

## Goal
`scripts/test-sync-4ai-panes-install.ps1` is **RED on master** (exit 1) because of a
stale hardcoded expectation. Make it green without weakening what it asserts.

## Current state
Verbatim, from `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-sync-4ai-panes-install.ps1`:

    FAIL  d4: all 12 allowlisted files copied  (expected=12 actual=17)
    ==== sync-install tests: 33 passed, 1 failed ====
    === EXIT CODE: 1 ===

`scripts/test-sync-4ai-panes-install.ps1:169` hardcodes `Assert-Equal 12 (Get-CopiedCount $tD)`.
The `$Allowlist` in `scripts/sync-4ai-panes-install.ps1:69-87` now holds **17** entries —
the fleet-supervisor work (PR #78) added `fleet-supervisor.ps1`,
`install-fleet-supervisor.ps1`, `uninstall-fleet-supervisor.ps1`,
`test-fleet-supervisor.ps1`, `test-pane-supervisor.ps1` without updating the test.

Every provenance/refusal assertion (a*, b*, c*, d1–d3, d5, e*, f*, g*, h*) passes —
**the provenance guard itself is green.** This is a stale expectation, not a regression.
The stale "12" also appears in the file's header comment (`(d) primary + master ->
PROCEEDS, all 12 files copied, provenance logged`) and in the `d4` assertion label.

## Steps
1. Fix the stale count. Do **not** hardcode `17` — derive it from the allowlist so the
   next allowlist edit can't re-break the suite. `scripts/sync-4ai-panes-install.ps1` is
   the SSOT for "which files are tool files"; the test should read it (or count the source
   files it actually syncs) rather than restate the number. If deriving it is genuinely
   awkward in this harness, hardcoding is acceptable — but then update the header comment
   and the assertion label together so all three stay consistent.
2. Update the header comment block and the `d4` assertion label so neither still says "12".
3. Change nothing else. In particular, do not touch `scripts/wt-bootstrap.sh` — kiro-cli
   is actively changing that file (see the note at the top); a concurrent edit there will
   collide.

## Verification
- (a) EXECUTE `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-sync-4ai-panes-install.ps1` → paste the final tally line and the exit code. Must be `0 failed`, exit 0.
- (b) Prove the assertion still bites: temporarily drop one entry from `$Allowlist` in `scripts/sync-4ai-panes-install.ps1`, re-run, and paste the FAILING `d4` line — then restore it and re-run green. Paste both. (A count assertion that can't fail is worse than no assertion.)
- (c) `git -C . status --porcelain -- .ai` before and after your test runs — identical. The sandbox must never touch the live coordination plane.

## Next step / future note
**What breaks first:** any future edit to `$Allowlist` re-breaks `d4` if you hardcode the
number instead of deriving it — which is exactly how this test went red in the first place
(PR #78 added five files and nobody updated the test). Deriving it makes the class of bug
go away rather than resetting the counter.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: <summary — per handoff 202607131826-fix-sync-test-count-and-cover-reverse-write-guard>
    - Files: <paths touched>
    - Decisions: <non-obvious choices>

## Report back with
- (a) The files you touched (exact paths).
- (b) Pasted execution output — tally + exit code, not a summary.
- (c) Pasted output of the deliberately-broken-allowlist run proving `d4` still fails when it should.
- (d) Whether you derived the count from the allowlist or hardcoded it, and why.

## When complete (protocol v3)
Self-retire: set Status to `DONE` and move this file to `.ai/handoffs/to-kimi/done/`.
If blocked, leave it in `open/`, set Status `BLOCKED`, and append a `## Blocker`
section with the verbatim error.
