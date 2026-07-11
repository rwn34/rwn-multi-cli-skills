# Kimi: add an always-on auto-dispatcher for the to-kimi queue (e2e-test gap)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 (UTC filename 202607110218)
Auto: yes
Risk: B
Completed: 2026-07-11 10:13 (local) by kimi-cli

## Why
The auto-handoff end-to-end test (2026-07-11, `.ai/reports/claude-2026-07-11-auto-handoff-e2e-test.md`, PR #18) found ONE silent-non-delivery surface in the whole fleet: **Kimi's own queue**.
- **Claude:** `.claude/settings.json` SessionStart -> `.ai/tools/dispatch-own-queue.sh` -> `dispatch-handoffs.sh --exec --only claude`. Auto-dispatches. PASS.
- **Kiro:** `guards.json` SessionStart wires `.kiro/hooks/dispatch-own-queue.sh` -> `--exec --only kiro`. Auto-dispatches. PASS.
- **Kimi:** its SessionStart hook `.kimi/hooks/handoffs-remind.sh` only **lists** open `to-kimi` handoffs and prints the dispatch command **as text** — it never runs it. Tree grep confirms no Kimi hook executes `dispatch-handoffs.sh --exec`.

Net: `to-kimi` Auto:yes Risk-A/B handoffs are NOT auto-processed on session start — they wait for a live pane-runner pane, a human, or an interactive Kimi acting on the printed reminder. This is the last gap in the "handoffs get processed without a live pane" work (B1/B2/B3).

## Task
Give Kimi the same always-on auto-dispatch its siblings have:
1. Add `.kimi/hooks/dispatch-own-queue.sh` mirroring `.ai/tools/dispatch-own-queue.sh` but scoped to Kimi: recursion guard (`[ -n "${AI_HANDOFF_DISPATCH:-}" ] && exit 0`), fast-exit when no Auto:yes+OPEN+Risk-A/B `to-kimi` handoff exists, a debounce stamp, then `bash .ai/tools/dispatch-handoffs.sh --exec --only kimi`. Fail-open (exit 0 always). (Alternatively: make `handoffs-remind.sh` actually RUN the dispatch after listing — but a separate dispatch-own-queue.sh matching Claude/Kiro is cleaner + consistent.)
2. Wire it into Kimi's SessionStart in BOTH the live block source `.kimi/config.toml` AND the installer snippet `.ai/config-snippets/kimi-hooks.toml` (keep them identical; the snippet is inside the `# >>> rwn-framework:kimi-hooks >>>` fenced block now that D3 landed — add the new hook inside that block). Keep `handoffs-remind.sh` as the human-visible listing; ADD the auto-dispatch alongside it.
3. Mark it WIRED in `.kimi/hooks/README.md`; add `.kimi/hooks/test_hooks.sh` coverage (recursion-guard no-op; candidate -> would-dispatch).
4. Verify: with `kimi` masked off PATH, a throwaway Auto:yes Risk-B `to-kimi` handoff makes the hook select it + invoke `dispatch-handoffs.sh --exec --only kimi`; recursion guard no-ops; debounce on 2nd run. Clean up throwaways.

## Rules
- Your territory: `.kimi/**` + the shared `.ai/config-snippets/kimi-hooks.toml`. Do NOT edit `.ai/tools/dispatch-handoffs.sh` or `.claude/`/`.kiro/` (reference only).
- IMPORTANT (D1 gate is now live): `.kimi/**` + `.ai/config-snippets/**` are versioned framework content — your commit must BUMP `tools/multi-cli-install/package.json` version (currently 0.0.9 -> 0.0.10) or the `gates` CI check FAILS the PR. (Confirm current version first.)
- Prepend an activity entry via `bash .ai/tools/activity-append.sh`. Self-retire (Status DONE + move to `.ai/handoffs/to-kimi/done/`) per protocol v3. Blocked -> leave OPEN as BLOCKED with a verbatim `## Blocker`.

## Report (kimi-cli, 2026-07-11 10:13 local)

**Wired:**
- New `.kimi/hooks/dispatch-own-queue.sh` — kimi-scoped mirror of
  `.ai/tools/dispatch-own-queue.sh` (claude) / `.kiro/hooks/dispatch-own-queue.sh`
  (kiro): recursion guard, fast-exit on empty queue, 5-min debounce stamp, then
  `bash .ai/tools/dispatch-handoffs.sh --exec --only kimi`. Fail-open (exit 0).
  Overrides (`HANDOFFS_DIR`, `DISPATCH_STAMP`, `DISPATCH_ONLY`, `DRY_RUN`) make it
  testable offline.
- SessionStart auto-dispatch `[[hooks]]` entry added to BOTH `.kimi/config.toml`
  and `.ai/config-snippets/kimi-hooks.toml` (inside the D3
  `>>> rwn-framework:kimi-hooks >>>` fence; block byte-identical across files,
  diff-verified). `handoffs-remind.sh` kept as the human-visible listing; the
  dispatch hook acts alongside it.
- Marked WIRED in `.kimi/hooks/README.md` (table row + wiring-status note).

**Before/after (does a fresh Kimi session now auto-dispatch a queued to-kimi handoff?):**
- Before: `handoffs-remind.sh` only printed the dispatch command as text — tree
  grep confirmed no Kimi hook executed `dispatch-handoffs.sh --exec` (the e2e
  silent-non-delivery surface).
- After (verify with `kimi` masked via `PATH=/usr/bin:/bin`, throwaway Risk-B
  handoff named to sort first):
  ```
  [dispatch-own-queue/kimi] auto-dispatchable to-kimi handoff found: .ai/handoffs/to-kimi/open/202001010000-aathrowaway-autodispatch.md
  [dispatch-own-queue/kimi] running: dispatch-handoffs.sh --exec --only kimi
  SKIP  [kimi] ... — 'kimi' not on PATH
  ```
  → the hook SELECTED the throwaway and INVOKED the scoped dispatcher (which
  SKIPped only because kimi was masked — no real headless launch). Debounce fired
  on the 2nd run (`debounced ... skipping`, no re-dispatch); recursion guard
  (`AI_HANDOFF_DISPATCH=1`) was silent. Trap removed the throwaway/stamps; the
  real handoff was untouched and no claim sidecars were left. On a real fresh
  session with kimi on PATH, the same path runs `kimi -p` for the queued handoff.

**Test result:** `bash .kimi/hooks/test_hooks.sh` → `PASS: 55/55` (added t52
recursion no-op, t53 empty fast-exit, t54 candidate→would-dispatch, t55 debounce).

**Version bump:** `tools/multi-cli-install/package.json` `0.0.9` → `0.0.10` (D1
gate — `.kimi/**` + `.ai/config-snippets/**` are versioned framework content).

**Touched files:** `.kimi/hooks/dispatch-own-queue.sh` (new), `.kimi/config.toml`,
`.ai/config-snippets/kimi-hooks.toml`, `.kimi/hooks/README.md`,
`.kimi/hooks/test_hooks.sh`, `tools/multi-cli-install/package.json`,
`.ai/activity/log.md`.

**Notes for sender:** (1) dispatch hook uses `timeout = 600` (a real dispatch runs a
headless CLI; the 10s guard timeout would kill it) — tuneable. (2) Added a `DRY_RUN`
knob not present in the claude reference so `candidate→would-dispatch` is covered
offline. (3) Did NOT add the D3 fence to the legacy `.kimi/config.toml` doc block
(pre-existing; only the new hook entry is kept identical). (4) Not committed/pushed
— left to the human/orchestrator.
