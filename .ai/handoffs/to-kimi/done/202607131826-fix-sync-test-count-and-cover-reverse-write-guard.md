# Make the sync-test allowlist count self-maintaining (it has now gone stale twice)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-14 01:26
Revised: 2026-07-14 02:05
Completed: 2026-07-14 07:20
Auto: yes
Risk: A
Base: origin/exec/kiro/sync-provenance-check (rebased on PR #93 per coordination note)

> **Revised twice — read this before you start; the original was wrong on the facts.**
>
> v1 asked you to (a) fix a "RED on master" `d4` assertion and (b) add test coverage
> for `guard_ai_reverse_write()`. **Both asks are withdrawn:**
>
> - **(a) master is NOT red.** `origin/master` already fixed `d4` to `17` in `5d8812f`.
>   The failure I saw (`33 passed, 1 failed`) came from my own *stale worktree*, which
>   still had `Assert-Equal 12`. My error — I read a checked-out branch as if it were
>   master. Nothing to fix there.
> - **(b) the reverse-write guard is being deleted, not tested.** `guard_ai_reverse_write()`
>   (`cf9074d`, the `--skip-worktree` mechanism) is the *rejected* approach — it makes git
>   blind to real edits and it ate your own SSOT §7 rewrite. kiro-cli is forward-reverting
>   it per `to-kiro/open/202607131819-remove-skip-worktree-guard-land-detector.md`. Do not
>   test it, do not preserve it, do not touch `scripts/wt-bootstrap.sh`.
>
> What remains is one small, real hardening. That's this handoff.

## Goal
`scripts/test-sync-4ai-panes-install.ps1` asserts the number of synced files with a
**hardcoded literal**. That literal has already gone stale once (`12` while the allowlist
had grown to `17`, after fleet-supervisor PR #78 added five files) and it is *still*
hardcoded on both `master` and PR #93. Make the assertion derive its expectation from the
allowlist so it cannot go stale a third time.

## Current state
`origin/master`, `scripts/test-sync-4ai-panes-install.ps1:169`:

    Assert-Equal 17 (Get-CopiedCount $tD) 'd4: all 17 allowlisted files copied'

`Get-CopiedCount` (~line 123) counts files on disk in the target dir; nothing anywhere in
the harness reads `$Allowlist` from `scripts/sync-4ai-panes-install.ps1:69-87` (17 entries,
the SSOT for "which files are tool files"). Correct today, stale on the next addition.

Note PR #93 (`exec/kiro/sync-provenance-check`, OPEN, MERGEABLE) also hardcodes `17` at its
line 192 and adds 18 assertions (52 total). **Coordinate:** if #93 is still unmerged when you
start, rebase on it or wait — do not race kiro on the same file and force a conflict on a
line you're both touching.

## Steps
1. Derive the expected count from the allowlist rather than restating it. The sync script is
   the SSOT; the test should read it. Reasonable approaches (your call — you know the harness):
   dot-source or parse `$Allowlist` out of `scripts/sync-4ai-panes-install.ps1` and assert
   `$Allowlist.Count`, or assert set-equality of allowlisted names against the files that
   actually landed in the target (stronger — it catches "17 files copied, but the wrong 17").
   Prefer the stronger form if it's clean to write.
2. Update the assertion label and the header comment (`(d) primary + master -> PROCEEDS, all
   17 files copied`) so no stale number survives anywhere in the file.
3. Change nothing else. Do not touch `scripts/wt-bootstrap.sh` (kiro is mid-flight there).

## Verification
- (a) EXECUTE `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-sync-4ai-panes-install.ps1` → paste the final tally + exit code. Must be `0 failed`, exit 0.
- (b) Prove the assertion still bites — this is the whole point, so don't skip it: **add** a fake 18th entry to `$Allowlist` (a file that doesn't exist), re-run, paste the output showing the suite FAILS; then remove it and re-run green. Paste both. A count assertion that auto-adjusts to anything is worse than no assertion — it must track the allowlist, not the disk.
- (c) `git -C . status --porcelain -- .ai` before and after your runs — identical.

## Next step / future note
**What breaks first:** if you derive the count by *parsing* the sync script's source text
(regex over `$Allowlist = @(...)`), the test silently breaks the day someone reformats that
array (one entry per line → single line, or a comment inside the block). Dot-sourcing or
otherwise evaluating the real array is more robust than scraping it. Say which you chose and
why.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: <summary — per handoff 202607131826-fix-sync-test-count-and-cover-reverse-write-guard>
    - Files: <paths touched>
    - Decisions: <non-obvious choices>

## Report back with
- (a) The exact file(s) touched.
- (b) Pasted execution output — tally + exit code, not a summary.
- (c) Pasted output of the fake-18th-entry run proving the assertion fails when it should.
- (d) How you derived the count (dot-source / parse / set-equality) and why.
- (e) Whether you rebased on PR #93 or waited for it.

## When complete (protocol v3)
Self-retire: set Status to `DONE` and move this file to `.ai/handoffs/to-kimi/done/`.
If blocked, leave it in `open/`, set Status `BLOCKED`, and append a `## Blocker` section
with the verbatim error.

## Completion
- Rebased on PR #93 (`origin/exec/kiro/sync-provenance-check`) and committed to new branch `exec/kimi/sync-test-allowlist-count` (`5e89217`).
- Changed `scripts/test-sync-4ai-panes-install.ps1` to derive `$Allowlist` from `scripts/sync-4ai-panes-install.ps1` via PowerShell AST, assert exact set-equality of copied files, and remove hardcoded `17` / `seventeen` references.
- Green run: `==== sync-install tests: 52 passed, 0 failed ====` (exit 0).
- RED proof (fake 18th allowlist entry `fake-entry-that-does-not-exist.ps1`): `FAIL d1`, `FAIL d4: copied files exactly match $Allowlist (18 entries) (missing=fake-entry-that-does-not-exist.ps1)`.
- `.ai` status unchanged by test runs.
- Activity log entry prepended at `2026-07-14 07:20 — kimi-cli`.
