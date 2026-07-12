# Fix framework-guard: plugin fails to load ("Plugin export is not a function")
Status: OPEN
Sender: opencode
Recipient: claude-code
Created: 2026-07-12 21:46
Auto: yes
Risk: B
Base: origin/master

<!-- Protocol v3. Root-caused by opencode's capability self-test 2026-07-12 (session
     run a460ec9b). Full evidence: .ai/reports/opencode-2026-07-12-guard-dead-plugin-load-failure.md.
     This blocks OpenCode's entire lane: with the guard dead, nothing is mechanically
     lane-restricted, and the pending handoff to-opencode/202607121900-gates-required-check
     is held BLOCKED until a fresh process can load the guard. -->

## Goal
Make `.opencode/plugin/framework-guard.js` loadable by opencode 1.17.15 again. It
currently fails to import with `error="Plugin export is not a function"`, so the
`tool.execute.before` hook never registers and OpenCode's writable-lane enforcement is
completely absent at runtime.

## Current state
- `.opencode/plugin/framework-guard.js` exports, in order:
  `export const WRITABLE_LANE = [ ... ]` (an **array**, leading), then
  `export function decide(...)`, then `export const FrameworkGuard = async (...) => {...}`.
  There is NO `export default` (never has been).
- The original (commit `406f2a9`) exported ONLY `decide` and `FrameworkGuard` (both
  functions) and loaded/enforced fine — it produced the BLOCK messages in OpenCode's
  attempts 1 and 2 on 2026-07-12.
- PR #45 (`6acadaa`) extracted `WRITABLE_LANE` into a top-level exported array const so
  `test-guard.mjs` could import it. That non-function leading export is what the loader
  now rejects.
- Verbatim boot error (opencode log, run a460ec9b = a fresh 2026-07-12 process):
  `message="failed to load plugin" path=.../.opencode/plugin/framework-guard.js error="Plugin export is not a function"`
- Source logic is otherwise CORRECT — running `decide()` directly via node yields the
  right lane (`.github/**`, `.ai/**` ALLOW; `src/`, `.claude/`, `.ai/instructions/`,
  `docs/architecture/`, `.env` BLOCK). Only the module's import-ability is broken.

## Target state
A plugin module whose every top-level export resolves to the plugin function (or that the
loader accepts), such that a FRESH opencode process loads it and `tool.execute.before`
fires. `test-guard.mjs` (which does `import { decide, WRITABLE_LANE } from "./framework-guard.js"`)
must keep working — coordinate any change to how `WRITABLE_LANE` is exposed.

## Steps
1. Confirm the loader behavior for opencode 1.17.15 (the exact reason a non-function
   export is rejected — likely it iterates exports and throws on a non-function, or it
   resolves the entry and finds the array). Pick the fix to match:
   - **Minimum:** add `export default FrameworkGuard;`.
   - **If the loader throws on ANY non-function export:** also stop exporting the bare
     array — e.g. `const WRITABLE_LANE = [...]` (unexported) +
     `export function getWritableLane() { return WRITABLE_LANE.slice(); }`, and change
     `test-guard.mjs:3` to `import { decide, getWritableLane }` + use `getWritableLane()`.
2. Keep `WRITABLE_LANE`'s CONTENT and the LANE:BEGIN/LANE:END doc block in
   `.opencode/contract.md` and `AGENTS.md` in sync (the doc<->guard drift test
   `test-guard.mjs` machine-checks these — do not regress it).
3. Re-run the guard suite: `node .opencode/plugin/test-guard.mjs` (must pass).

## Verification (EXECUTE)
- (a) Start a FRESH opencode process in this repo; check
  `C:\Users\rwn34\.local\share\opencode\log\opencode.log` for the new run — there must be
  NO `failed to load plugin` for `framework-guard.js`.
- (b) In that fresh process, attempt a real write to `src/x.js` — it must be BLOCKED by
  `framework-guard` (paste the block message). Attempt a write to `.github/.probe` — it
  must be ALLOWED (then delete it). This proves source==runtime end to end.
- (c) `node .opencode/plugin/test-guard.mjs` → all pass.

## Next step / future note
Once the guard loads in a fresh process, re-dispatch `to-opencode/202607121900-gates-required-check`
(branch protection on master) — OpenCode held it BLOCKED solely because the guard is dead.
If the opencode plugin-loader API changes again, this exact class of bug recurs: the
defense is a CI check that imports the plugin the way the loader does, not just unit-tests
`decide()`.

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Fixed framework-guard plugin load failure ("Plugin export is not a function") per handoff 202607121446-guard-plugin-fails-to-load
    - Files: .opencode/plugin/framework-guard.js, .opencode/plugin/test-guard.mjs
    - Decisions: <export-shape fix chosen + how WRITABLE_LANE is now exposed to the test>

## Report back with
- (a) the loader behavior you confirmed and the exact export change made
- (b) pasted fresh-process log excerpt showing NO load failure + the BLOCK(src)/ALLOW(.github) results
- (c) `test-guard.mjs` result

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-claude/done/`. If blocked, leave
in `open/` as `BLOCKED` with verbatim errors.
