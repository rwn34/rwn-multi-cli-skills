# Review PR #64 — OpenCode guard plugin load fix (SECURITY, author != reviewer)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-12 22:40
Auto: yes
Risk: A
Base: origin/master

## Goal
Peer-review **PR #64** (`claude/fix-opencode-guard-load`). It restores OpenCode's
enforcement guard, which was **completely dead** — `framework-guard.js` failed to
load, so OpenCode ran with ZERO mechanical enforcement (it could write project
source, secrets, any CLI's territory). This is a SECURITY fix; author != reviewer
is mandatory. You can READ `.opencode/**` even though you cannot write it — a
read-only review is exactly right.

## The bug it fixes (proven, not inferred)
OpenCode's plugin host globs `{plugin,plugins}/*.{ts,js}` and requires **every
top-level export of each matched module to be a function** — the first non-function
export throws `"Plugin export is not a function"` and kills the whole plugin. PR #45
(mine, earlier tonight) added `export const WRITABLE_LANE = [...]` (an array) to
`framework-guard.js`, which tripped exactly this. OpenCode proved the consequence at
runtime: a write to `src/anything.js` (must-block) SUCCEEDED.

The coder extracted the loader logic from the **opencode 1.17.15 binary** (the
validator `ck`/`lk`, the glob) rather than guessing — verify that claim is sound.

## The fix
- New data module `.opencode/lib/lane.js` holds `WRITABLE_LANE`. `lib/` is OUTSIDE
  the `{plugin,plugins}/` glob, so the host never loads it as a plugin.
- `framework-guard.js` imports the array from `../lib/lane.js` and now exports ONLY
  functions (`decide`, `FrameworkGuard`) — the pre-#45 loadable shape.
- `test-guard.mjs` updated: import moved, +12 load-path tests. 145 total.

## Scrutinize hardest
1. **Is `.opencode/lib/lane.js` REALLY outside the plugin-load path?** This is the
   crux — if the host globs it, the fix moves the break instead of fixing it. The
   coder says the host only scans `plugin/plugins`, `tool/tools`, `command`, `agent`,
   `skill`. Sanity-check that claim however you can (the PR should cite the binary
   evidence). If `lib/` could ever be scanned, REQUEST CHANGES.
2. **Do the new load-path tests actually reproduce the host contract**, or do they
   just re-test `decide()` in a new costume? The whole outage happened because 133
   tests never loaded the plugin the host's way. Confirm the new tests: (a) assert
   every export of the globbed module is a function, (b) actually initialize
   `FrameworkGuard({directory})` and exercise its `tool.execute.before` hook end to
   end. If they don't do BOTH, they haven't closed the gap.
3. **Enforcement is genuinely restored** — through the initialized plugin (not just
   `decide` in isolation): `src/` BLOCKED, `.env` BLOCKED, `.claude/` BLOCKED,
   `.github/`+`.ai/reports/` ALLOWED. Re-run it yourself.
4. **The LANE doc<->guard drift check still works** after the data move (the
   `LANE:BEGIN/END` comparison now reads from `lib/lane.js`).
5. **No `export default` was added** — the coder argues the iterate-all host doesn't
   need one and the proven-good original had none. Assess whether that's right or
   whether a default would be safer/worse.

## Verify (execute, paste)
- `node .opencode/plugin/test-guard.mjs` -> expect 145/0.
- The prove-it-loads snippet (import the plugin, init FrameworkGuard, no throw).
- The enforcement matrix through the hook.
- `bash .ai/tools/check-ssot-drift.sh` (CWD = repo root) -> Drift 0.

## Deliverable
Review report `.ai/reports/kimi-2026-07-12-review-pr64.md` + a PR comment with an
explicit verdict: **APPROVE / APPROVE-WITH-NOTES / REQUEST-CHANGES**, evidence-backed.
A way the fix still leaves the guard un-loadable, or the data module still in the glob,
is the highest-value find. On APPROVE, the fleet merges (Tier B) WITH a version
assignment at the merge point (`.opencode/**` is versioned content, so the merger must
assign the next version or master's push-gate goes red).

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kimi/done/`. Do NOT merge.

## Completion (kimi-cli, 2026-07-12 23:00)
- Verdict: **APPROVE-WITH-NOTES** (2 cosmetic doc-pointer notes, no blockers).
  Review ran post-merge — the owner merged #64 at 15:38Z before the review
  completed; nothing found would have changed the merge decision.
- Touched: `.ai/reports/kimi-2026-07-12-review-pr64.md` (new), PR #64 comment
  (issuecomment-4951822749), `.ai/activity/log.md` (23:00 entry), this handoff
  (Status DONE, moved to `done/`). No code files touched — read-only review in
  the clean worktree `.wt-infra/rwn-multi-cli-skills/fix-opencode-guard-load`
  at head `ed574f5` (left clean).
- Evidence: binary-verified validator + glob (opencode 1.17.15), host-validator
  negative control (pre-fix module rejected with the exact runtime TypeError),
  test-guard 145/0, enforcement matrix 9/9 through the initialized hook, drift
  negative control (injected drift → FAIL 1), check-ssot-drift Drift 0. Full
  transcript in the report.
