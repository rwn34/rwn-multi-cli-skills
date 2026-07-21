// OpenCode's writable lane — data module, deliberately OUTSIDE .opencode/plugin/.
//
// WHY THIS FILE EXISTS (do not move it back into plugin/): OpenCode's plugin host
// discovers plugins by globbing `{plugin,plugins}/*.{ts,js}` (verified against the
// opencode 1.17.15 binary) and requires EVERY top-level export of each matched
// module to be a plugin function — its validator throws
// `TypeError("Plugin export is not a function")` on the first non-function export,
// which kills the ENTIRE module. PR #45 added `export const WRITABLE_LANE = [...]`
// (an array) as a top-level export of framework-guard.js; that non-function export
// made the whole guard unloadable, so at runtime NOTHING was lane-restricted
// (root cause: .ai/reports/opencode-2026-07-12-guard-dead-plugin-load-failure.md).
//
// The array lives here, one directory up from plugin/, so the plugin glob never
// matches it (`.opencode/lib/*.js` is not `{plugin,plugins}/*.{ts,js}`). Both the
// guard (framework-guard.js) and the test harness (test-guard.mjs) import it from
// here. framework-guard.js's own top-level exports are therefore ONLY functions
// (`decide`, `FrameworkGuard`), restoring the pre-#45 loadable shape.

/**
 * THE enforced writable lane. `<prefix>/**` = subtree, bare path = exact file.
 * Matching is case-SENSITIVE (a case variant fails closed, i.e. blocked).
 *
 * This constant is machine-checked against the LANE:BEGIN/LANE:END block in
 * .opencode/contract.md and AGENTS.md by test-guard.mjs. A doc that misdescribes
 * this list is the exact bug that blocked handoff 202607120021 (docs said
 * "CI workflow fixes are yours", the guard said "no .github/") — so drift is a
 * test failure, not a comment.
 *
 * .github/** was added 2026-07-12: the GitHub / repo-ops lane (operating-prompt
 * §14, ADR-0011) assigns CI config + workflow fixes to OpenCode. Deliberately NOT
 * added: infra/, scripts/, Dockerfile, docker-compose* — see the contract.
 *
 * ADR-0010 Wave-3 (2026-07-21): the activity log is now an entry-per-file spool
 * under `.ai/activity/entries/**`. The generated `.ai/activity/log.md` view is
 * NOT writable directly; it is produced by `.ai/tools/render-activity-log.sh`.
 * OpenCode writes individual entries and (when needed) runs the renderer.
 */
export const WRITABLE_LANE = [
  ".ai/activity/entries/**",
  ".ai/reports/**",
  ".ai/handoffs/**",
  ".github/**",
];
