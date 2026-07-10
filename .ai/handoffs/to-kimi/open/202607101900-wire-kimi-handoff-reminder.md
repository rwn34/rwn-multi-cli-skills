# Wire Kimi's handoff-reminder hook so interactive Kimi notices handoffs (gap B1)
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 (UTC filename 202607101900)
Auto: yes
Risk: B

## Why
Root cause of "handoffs don't work when I open an existing project" for the Kimi
lane (see `.ai/reports/claude-2026-07-11-framework-panes-gap-analysis.md`, gaps
A2 + B1):
- Claude just fixed the installer to auto-wire `.ai/config-snippets/kimi-hooks.toml`
  into the CORRECT global config `~/.kimi-code/config.toml` (was wrongly documented
  as `~/.kimi/config.toml`).
- BUT that snippet only wires the 4 guards — it has **no SessionStart
  handoff-reminder hook at all**. `.kimi/hooks/handoffs-remind.sh` exists but is
  flagged NOT WIRED (`.kimi/hooks/README.md`). So even a fully-wired Kimi never
  lists `to-kimi/open/` and silently ignores every handoff addressed to it.

## Task
1. Add a **SessionStart** `[[hooks]]` entry that runs `.kimi/hooks/handoffs-remind.sh`
   to BOTH Kimi config sources, kept identical:
   - `.kimi/config.toml` (the documented paste block)
   - `.ai/config-snippets/kimi-hooks.toml` (the snippet the installer now appends to
     `~/.kimi-code/config.toml` via `wire_kimi_hooks`) — shared `.ai/`, but it is
     your Kimi content to own.
2. Verify `handoffs-remind.sh` lists this project's `.ai/handoffs/to-kimi/open/`
   qualifying items (Auto:yes, Status:OPEN, Risk A|B). If it only reminds, also add
   (or note for the B3 dispatch handoff) that it can run
   `bash .ai/tools/dispatch-handoffs.sh --exec` scoped to Kimi's own queue so
   Auto:yes Risk-A/B handoffs are actually processed, not just listed.
3. Add a Stop or SessionStart **queue-count reminder** for Kimi equivalent to
   Claude's `stop-reminder.sh` (gap B4) — currently only Claude gets one.
4. Mark `handoffs-remind.sh` **WIRED** in `.kimi/hooks/README.md`; extend
   `.kimi/hooks/test_hooks.sh` to cover the new wiring if testable.
5. Grep your steering/docs for `~/.kimi/config.toml` and correct any remaining
   references to `~/.kimi-code/config.toml`.

## Rules
- Your territory: `.kimi/**` + the shared `.ai/config-snippets/kimi-hooks.toml`.
  Do NOT edit `scripts/install-template.sh` (Claude owns the wiring side).
- Prepend an activity entry via `bash .ai/tools/activity-append.sh`. Self-retire
  (Status DONE + move to `.ai/handoffs/to-kimi/done/`) per protocol v3. Blocked →
  leave OPEN as BLOCKED with a verbatim `## Blocker`.

## Report
What you wired (both files), the before/after of a fresh Kimi startup (does it now
list open to-kimi handoffs?), and the test result.
