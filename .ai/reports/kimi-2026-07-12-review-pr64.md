# Review: PR #64 — OpenCode guard plugin load fix (SECURITY)

- Reviewer: kimi-cli
- Author: claude-code (author != reviewer — satisfied)
- Handoff: `.ai/handoffs/to-kimi/open/202607122240-review-pr64-guard-load-fix.md`
- PR head reviewed: `ed574f5` (`claude/fix-opencode-guard-load`), in the clean
  worktree `.wt-infra/rwn-multi-cli-skills/fix-opencode-guard-load`
- **Verdict: APPROVE-WITH-NOTES** (2 cosmetic doc-pointer notes, no blockers)
- Note on timing: PR #64 was **already merged** by the owner (`rwn34`) at
  2026-07-12T15:38:05Z (merge `ed97661`, version 0.0.35 assigned at the merge
  point per ADR-0012, `CHANGELOG.md` entry present) before this review ran.
  This review is therefore post-merge; the fix is live on master (`8cf81eb`).
  No finding here requires a revert — notes are follow-up polish only.

## The five scrutiny points

### 1. Is `.opencode/lib/lane.js` REALLY outside the plugin-load path? — YES, proven against the binary

Independently verified against the **installed** opencode-ai@1.17.15 binary
(`C:\Users\rwn34\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe`,
170 MB), not just the coder's say-so. `grep -a -o` on the binary:

```
function vV($){return typeof $==="function"}
function lk($){if(vV($))return $;if(!$||typeof $!=="object"||!("server"in $))return;if(!vV($.server))return;return $.server}
function ck($){let Z=new Set,Q=[];for(let Y of Object.values($)){...let X=lk(Y);if(!X)throw TypeError("Plugin export is not a function");...}}
```

and the discovery glob, in two independent code paths:

```
E1.scan("{plugin,plugins}/*.{ts,js}",{cwd:q,absolute:!0,dot:!0,symlink:!0})
r.glob("{plugin,plugins}/*.{ts,js}",{cwd:f.path,absolute:!0,include:"file",dot:!0,symlink:!0})
```

The glob is **non-recursive** (`*`, not `**`), anchored at `{plugin,plugins}/`,
and excludes `.mjs`. `.opencode/lib/lane.js` cannot match it, and `lib/` is not
one of the host's scanned component dirs. `opencode.json` at the PR head has no
explicit `plugin:` entries, so discovery is exactly this glob. **The fix is at
the right layer** — a `lane.js` left inside `plugin/` would have re-broken
loading identically; moving the data one directory up closes it.

Additionally transcribed the binary's `ck`/`lk` verbatim into a Node harness and
ran it against both module versions (negative control the PR itself can't carry):

```
PASS  host validator REJECTS pre-fix module (9fe6609^) — TypeError: Plugin export is not a function
PASS  host validator ACCEPTS post-fix module (ed574f5) — registered 2 plugin fn(s)
```

The pre-fix rejection is byte-identical to the error OpenCode logged at runtime
(`Plugin export is not a function`, run `a460ec9b`), so the root cause and the
fix are both confirmed end to end.

### 2. Do the new load-path tests reproduce the host contract? — YES, both halves

- (a) `hostLoadedPluginFiles()` mirrors the binary glob (non-recursive,
  `/\.(ts|js)$/` on `plugin/`+`plugins/`), and `checkAllExportsAreFunctions`
  **dynamic-imports the real module file** and asserts every top-level export
  is a function — plus an assertion that the host discovers exactly one plugin
  (`framework-guard.js`). This is the test whose absence let the outage ship
  green.
- (b) The end-to-end half initializes `FrameworkGuard({directory})` with a real
  `os.tmpdir()` root and drives the `tool.execute.before` hook: blocks
  `src/x.js`, `.env`, `.claude/x.md`; allows `.ai/reports/x.md`,
  `.github/x.yml`.
- (c) Explicit assertions that `lib/lane.js` exists, is not in the globbed set,
  and is outside any `{plugin,plugins}/` dir — so a future "move it back"
  refactor fails loudly.

One strictness observation (not a defect): the test requires
`typeof v === "function"` for every export, while the binary's `lk` also
accepts objects with a `server` function. The test is strictly **stronger**
than the host contract, so there is no false-pass risk; only if a future
plugin legitimately exports an MCP-server-style object would this test need
widening to match `lk`.

### 3. Enforcement genuinely restored — re-run independently

Through the initialized plugin (not `decide` in isolation), with the worktree
root as `directory`:

```
PASS  hook BLOCKS write src/x.js — BLOCKED by framework-guard: write of 'src/x.js' is outside the lane.
PASS  hook BLOCKS write .env — ...targets a sensitive file — never write secrets...
PASS  hook BLOCKS write .claude/x.md — outside the lane
PASS  hook BLOCKS write .opencode/plugin/framework-guard.js — outside the lane
PASS  hook BLOCKS write scripts/check-version-bump.sh — outside the lane
PASS  hook ALLOWS write .github/x.yml
PASS  hook ALLOWS write .ai/reports/x.md
PASS  hook ALLOWS write .ai/handoffs/to-opencode/open/x.md
PASS  hook ALLOWS write .ai/activity/log.md
```

`node .opencode/plugin/test-guard.mjs` → **PASS 145 / FAIL 0**.
`bash .ai/tools/check-ssot-drift.sh` (CWD = worktree root) → **Checked: 24
replicas, Drift: 0**.

### 4. LANE doc<->guard drift check still works after the data move — YES, with negative control

The drift check now imports `WRITABLE_LANE` from `../lib/lane.js` and compares
against the `LANE:BEGIN/END` blocks in `.opencode/contract.md` and `AGENTS.md`.
Negative control executed: injected ``- `docs/**` `` into AGENTS.md's LANE
block in the disposable worktree → **PASS 144 / FAIL 1** with a precise diff
message; restored the file → **145 / 0**. The check has teeth after the move.

### 5. No `export default` — correct call

Agreed with the coder. `ck` iterates **all** exports and registers each as a
plugin; the proven-good pre-#45 module had exactly the two named function
exports and no default. Adding `export default FrameworkGuard` would
double-register the guard (every hook fires twice) and would not have fixed
anything — the array export was the kill, not the absence of a default.
Post-fix module verified to export exactly `{decide: function, FrameworkGuard:
function}`, no `default`.

## Notes (non-blocking, follow-up polish)

1. **Stale SSOT pointer in the LANE comments.** `.opencode/contract.md:82` and
   the matching `AGENTS.md` block read "machine-checked against WRITABLE_LANE in
   `.opencode/plugin/framework-guard.js` by test-guard.mjs" — after this PR the
   constant lives in `.opencode/lib/lane.js`. The mechanical check is
   unaffected (it compares list contents; negative control above proves it),
   but the pointer misdirects the next editor. Same staleness in the
   drift-check failure string in `test-guard.mjs` ("matches WRITABLE_LANE in
   framework-guard.js"). One-line comment fixes in all three places.
2. **Merge-order observation (informational).** The fix merged before this
   review completed. Author != reviewer still held (this review is independent,
   post-merge), and nothing found here would have changed the merge decision.
   Worth noting for the fleet: the dispatch→review latency on security fixes
   is longer than the owner's merge latency; if pre-merge review is mandatory
   for security fixes, that needs to be a mechanical gate, not a convention.

## Verification transcript (commands run by reviewer)

- `node .opencode/plugin/test-guard.mjs` @ `ed574f5` → `PASS 145 / FAIL 0 (total 145)`
- Binary grep (opencode-ai@1.17.15) → validator `ck`/`lk` and glob
  `{plugin,plugins}/*.{ts,js}` extracted verbatim (quoted above)
- Host-validator harness (transcribed `ck`/`lk`) vs pre-fix module
  (`git show 9fe6609^:...framework-guard.js`) → throws
  `TypeError("Plugin export is not a function")`; vs post-fix → registers 2
  plugin functions, exports exactly `decide`+`FrameworkGuard`, no default
- Enforcement matrix through initialized `FrameworkGuard({directory})` hook →
  9/9 expected verdicts (transcript above)
- Drift negative control → injected lane entry fails 1, restore passes 145/0
- `bash .ai/tools/check-ssot-drift.sh` (worktree root) → `Checked: 24 replicas, Drift: 0`
- PR checks at head `ed574f5`: `gates` SUCCESS, `framework-check` SUCCESS
