# Kimi: add an always-on auto-dispatcher for the to-kimi queue (e2e-test gap)
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 (UTC filename 202607110218)
Auto: yes
Risk: B

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

## Report
What you wired, the before/after (does a fresh Kimi session now auto-dispatch a queued to-kimi handoff?), the test result, and the version bump.
