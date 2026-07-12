# OpenCode capability self-test + root-cause — guard is DEAD (plugin fails to load)

Date: 2026-07-12 (session run `a460ec9b`, opencode 1.17.15)
Author: opencode
Trigger: owner-ordered capability self-test before real fleet work begins.
Verdict: **FAIL — do not trust OpenCode's lane enforcement. The framework-guard
plugin never loads in a fresh process, so NOTHING is mechanically lane-restricted
at runtime.** This is a third, distinct failure mode (not the attempt-1 legit
block, not the attempt-2 stale cache). Handoff `202607121900-gates-required-check`
was NOT executed; it is left `BLOCKED` per the owner's Phase-1-green gate.

---

## 1. The headline finding (verbatim evidence)

My own session log shows the plugin failing to load at boot:

```
timestamp=2026-07-12T14:01:58.796Z level=ERROR run=a460ec9b message="failed to load plugin"
  path=file:///C:/Users/rwn34/Code/rwn-multi-cli-skills/.opencode/plugin/framework-guard.js
  error="Plugin export is not a function"
timestamp=2026-07-12T14:05:29.078Z level=ERROR run=a460ec9b message="failed to load plugin"
  (same path, same error)
```

`run=a460ec9b` is THIS session — confirmed because my own later commands appear under
the same run id (e.g. log lines 2956 = my `node` decide() probe, 2997 = my `grep`,
3018 = my `Select-String`). There is **no** successful `framework-guard` load anywhere
in the current log (`Select-String 'loaded plugin.*framework-guard'` → no rows).

Because the plugin's `tool.execute.before` hook is never registered, the guard does
not fire. Proven empirically: I attempted a real `write` to `src/anything.js` (a path
that MUST be denied) and it **succeeded** (`Wrote file successfully`; file appeared on
disk as `?? src/anything.js`). I immediately deleted it and the `.github/.opencode-selftest`
probe I had also created; the tree is clean again (`git status` shows neither).

## 2. Source vs runtime — they disagree, and it is NOT a stale cache

Running the plugin's own pure decision function directly (fresh `node`, loads the
on-disk source) gives the CORRECT lane:

```
BLOCK  src/anything.js          :: write of 'src/anything.js' is outside the lane
ALLOW  .github/x.md
ALLOW  .ai/reports/r.md
ALLOW  .ai/activity/log.md
BLOCK  .ai/instructions/x.md    :: outside the lane
BLOCK  docs/architecture/x.md   :: outside the lane
BLOCK  .claude/agents/x.md      :: outside the lane
BLOCK  .env                     :: sensitive file — never write secrets
```

So the on-disk SOURCE is correct and fresh (`.github/**` and `.ai/activity/entries/**`
are present — PR #45 and PR #48 landed). The RUNTIME, however, enforces nothing at all.
Attempts 1–2 were "runtime holds an OLD lane while source is new" (stale cache). This is
worse: "runtime holds NO guard because the plugin cannot be imported."

## 3. Root cause — PR #45 made the plugin unloadable

`git log --oneline -- .opencode/plugin/framework-guard.js`:

```
5566f08 feat(guard): teach both enforcement layers the ADR-0010 activity-log spool path   (PR #48)
b88845d fix(opencode): normalize path separators before resolve, not after                  (PR #45)
6acadaa fix(opencode): grant .github/** write lane — docs promised CI work the guard blocked (PR #45)
406f2a9 feat(opencode): ... framework-guard plugin + tests — Crush replacement              (2026-07-09)
```

Export shape, then vs now:

```
ORIGINAL (406f2a9):        CURRENT (after 6acadaa):
  export function decide     export const WRITABLE_LANE = [ ... ]   <-- ARRAY, now leading
  export const FrameworkGuard  export function decide
                               export const FrameworkGuard
```

No version ever had `export default`. The original exported only functions; the current
file leads with a non-function export (`WRITABLE_LANE`, an array). OpenCode's plugin
loader rejects a non-function export (`"Plugin export is not a function"`).

This reconciles all three attempts:

- **Attempt 1** — process started while the file was the 2-export original → plugin
  loaded → correctly BLOCKED `.github/` (not yet in the lane). Legit block.
- **Attempt 2** — the SAME long-running process never restarted; it still held the
  in-memory 2-export plugin → BLOCKED again with the stale lane even though the disk
  already had `.github/**`. The "stale cache" diagnosis was CORRECT for that process.
- **Attempt 3 (this session)** — the owner restarted the panes, so a FRESH process
  finally tried to import the CURRENT 3-export file → `"Plugin export is not a function"`
  → guard dead. The restart did not yield a "fresh guard"; it exposed a latent load
  failure introduced by PR #45.

All runs today are opencode **1.17.15** (no version drift between attempt 2 and now).
The only thing that changed is the file's export shape.

## 4. Why the handoff sat unconsumed (queue visibility)

- I CAN see `.ai/handoffs/to-opencode/open/202607121900-gates-required-check.md`.
- It was not consumed because **the pane-runners are DOWN** — the fleet activity log
  says so twice (claude-code 19:35: "the fleet is IDLE: the owner restarted PowerShell,
  killing the pane-runners; no CLI has logged since 19:20 and the work queue sat
  unconsumed"; 20:35: "Fleet is DOWN — pane-runners not running after the PowerShell
  restart; 4 handoffs sit OPEN awaiting relaunch", explicitly listing
  `to-opencode/202607121900-gates-required-check`).
- I am running now ONLY because the owner typed at me interactively. I have no evidence
  any automated pane-runner invokes me or polls my queue. Even if one had, it would have
  hit the same dead guard.
- NOTE (fleet relaunching during this session): at 21:52 claude-code merged PR #63, the
  "second half of the fleet-down regression fix" to `tools/4ai-panes/pane-runner.ps1`
  (an `$ErrorActionPreference`/`git fetch`-stderr bug), and confirmed the deployed launcher
  carries it — but logged "Fleet still needs the owner to relaunch the panes." PR #63 fixes
  the RUNNER, NOT this guard bug. When the owner relaunches, a fresh opencode pane will
  start, try to load `framework-guard.js`, and fail the same way — so a relaunch alone does
  NOT restore OpenCode's enforcement. The plugin fix (handoff to Claude) is a prerequisite.

## 5. Phase-1 capability table

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1a | Activity-log identity = `opencode` | PASS | `.opencode/contract.md:8` "Your identity for the activity log: `opencode`" |
| 1b | Contract writable lane quoted | PASS | contract.md:82-88 LANE:BEGIN..END = `.ai/activity/log.md`, `.ai/activity/entries/**`, `.ai/reports/**`, `.ai/handoffs/**`, `.github/**` |
| 2 | Runtime guard == source | **FAIL (critical)** | Source correct (node decide() above); runtime dead — `src/anything.js` write SUCCEEDED; log `error="Plugin export is not a function"` |
| 3 | Queue visibility | PASS | `.ai/handoffs/to-opencode/open/` lists `202607121900-gates-required-check.md` |
| 4 | ALLOW paths (source lane) | PASS (source) / unenforced (runtime) | node decide(): `.github`, `.ai/reports`, `.ai/activity/log.md` all ALLOW |
| 5 | BLOCK paths must deny | **FAIL (critical)** | `src/anything.js` ALLOWED at runtime (regression). Source correctly BLOCKs src, `.claude`, `.ai/instructions`, `docs/architecture`, `.env` |
| 6 | Shell + GitHub tooling | PASS | git 2.52.0; gh 2.87.3; `gh auth status` → rwn34, scopes `repo, workflow, gist, read:org, write:packages`; `gh api repos/rwn34/rwn-multi-cli-skills` → `permissions:{admin:true,push:true,...}` |
| 6b | Working tree identity | PASS | primary checkout `C:/Users/rwn34/Code/rwn-multi-cli-skills`, branch `master` (NOT a worktree); `git rev-parse --show-toplevel` confirms |
| 7 | Commit identity = `opencode` | **FAIL (finding)** | `git config user.name` = `claude-code` (LOCAL scope, `.git/config`), overriding global `rwn34`. ADR-0005 pre-commit backstop keys on committer identity → any commit I make would be misattributed to claude-code |

## 6. Phase-3 (branch protection) — NOT done, by the owner's gate

- The gap is REAL and I have the access to close it:
  `gh api repos/rwn34/rwn-multi-cli-skills/branches/master/protection` →
  `{"message":"Branch not protected","status":"404"}`, and my token has `admin:true`.
- I deliberately did NOT execute it. The owner gated Phase 3 on "Phase 1 fully green"
  and said a guard regression is "more important than anything else in this prompt."
  Phase 1 item 2 and item 5 are FAIL. Making repo-settings changes while my own
  enforcement is provably dead would be exactly the premature, trust-eroding move the
  gate exists to catch.
- The task is SAFE and READY for whoever runs it next: it is `gh api`-only (repo
  settings), touches no source and none of my file lane, and does not depend on the
  file guard. It can proceed the moment the owner says "do it regardless of the guard,"
  or after the guard is fixed.

## 7. Fix (routed to Claude — `.opencode/` is outside my lane)

I must not edit `.opencode/plugin/framework-guard.js` (not in my writable lane; the dead
guard is not a license to expand my contract). Handoff written:
`.ai/handoffs/to-claude/open/202607121446-guard-plugin-fails-to-load.md`.

Recommended direction (Claude to confirm against the actual 1.17.15 loader and
`test-guard.mjs`, which does `import { decide, WRITABLE_LANE }`):
- Make the plugin entry unambiguously a function: add `export default FrameworkGuard`.
- If the loader iterates exports and throws on any non-function, ALSO stop exporting the
  bare `WRITABLE_LANE` array (expose it via `export function getWritableLane()` and update
  `test-guard.mjs` accordingly), so every top-level export is a function.
- Verify by restarting opencode and confirming (a) no `failed to load plugin` in the log,
  and (b) a real `write` to `src/x.js` is BLOCKED by the guard.

## 8. What I still CANNOT do (plainly)

1. I cannot enforce my own lane — the guard is dead; only my contract discipline stops me
   writing anywhere. Until the plugin loads, OpenCode's mechanical enforcement is absent.
2. I cannot fix the guard myself — `.opencode/` is Claude's custodian territory.
3. I cannot commit under the correct identity — repo-local `user.name` is `claude-code`,
   not `opencode`. (I left all my file changes uncommitted to avoid misattribution.)
4. I cannot (yet) prove a clean handoff round-trip — the guard must be fixed and a fresh
   process must load it before the `202607121900` retry is meaningful.
5. I cannot confirm any auto-invocation path exists for me — I only run when a human prompts.
