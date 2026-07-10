# Clean Kimi startup noise — stale graph MCP servers (kimigraph/kirograph/codegraph)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-10 (UTC filename 202607100655)
Auto: yes
Risk: B

## Why
On Kimi startup the owner sees three MCP failures spamming the pane:

    MCP server "kimigraph" failed: MCP error -32000: Connection closed
      stderr: 'kimigraph' is not recognized as an internal or external command
    MCP server "kirograph" failed: MCP error -32000: Connection closed
      stderr: 'kirograph' is not recognized as an internal or external command
    MCP server "codegraph" failed: MCP error -32000: Connection closed
      stderr: 'codegraph' is not recognized as an internal or external command

Root cause (confirmed on the Claude side):
- **kimigraph / kirograph** were REMOVED entirely on 2026-07-09 (ADR-0003
  amendment — no CLI except Claude has a graph lane). The binaries/dirs are gone,
  but your GLOBAL Kimi config still registers them as MCP servers, so every launch
  tries to spawn a command that no longer exists.
- **codegraph** is **Claude-only** (ADR-0003). Kimi has no graph lane, so Kimi
  should not be loading a `codegraph` MCP server at all. The repo `.mcp.json`
  registers `codegraph` for **Claude** with a bare `command: "codegraph"` (it is an
  `npx @colbymchenry/codegraph` package, not a global binary) — if Kimi is reading
  that file, or has its own codegraph entry, it will fail the same way.

An equivalent cleanup was already done for **Kiro** (handoff
`202607101530-clean-global-mcp-and-agent-noise`, done/) — Kiro's global config
turned out clean of graph entries. Yours was never checked. These errors are
cosmetic (your work still completes) but they make your pane look broken to an
observer and bury real output.

## Task
1. Locate your GLOBAL Kimi MCP config (wherever `kimi-cli` keeps registered MCP
   servers for your user — check `kimi-cli` `--help`/docs if unsure; it is NOT in
   the repo tree — no `.kimi/**/mcp*.json` exists here).
2. REMOVE the `kimigraph` and `kirograph` server entries — both point at deleted
   tools (ADR-0003). Grep-confirm zero `kimigraph`/`kirograph` references remain
   in your global config afterward.
3. For `codegraph`: Kimi has **no graph lane**, so Kimi must not load a codegraph
   MCP server. Determine where Kimi's codegraph entry comes from:
   - If it's your OWN global Kimi config → remove it.
   - If Kimi is inadvertently reading the repo `.mcp.json` (which is Claude's
     Claude-scoped MCP config) → configure Kimi to NOT load servers from that
     file, or scope out `codegraph`. Do NOT edit the repo `.mcp.json` — that is
     Claude's file and `codegraph` is correct there for Claude.
   Explain what you found and what you changed.
4. Re-verify: describe (or run headless) a fresh Kimi startup and confirm all
   three MCP errors are gone.

## Rules
- Your GLOBAL Kimi config is YOUR territory — edit it. Do NOT touch the repo tree
  except this handoff + your activity entry. In particular do NOT edit the repo
  `.mcp.json` (Claude's).
- Prepend your activity entry via `bash .ai/tools/activity-append.sh` (atomic).
  Self-retire on completion: set Status DONE + move this file to
  `.ai/handoffs/to-kimi/done/` (protocol v3). Blocked → leave OPEN as BLOCKED with
  a verbatim `## Blocker` section describing exactly what you need.

## Report
Activity entry: where your global MCP config lives, what you removed/changed for
each of the three servers, and the before/after startup-noise state.

## Resolution (2026-07-11, claude-code — owner-directed, resolved directly)

Kimi did not poll/process this handoff, and the owner reported the three MCP
errors STILL firing on every new terminal. On explicit owner direction, claude-code
located and fixed the global config DIRECTLY (rather than waiting on the Kimi
lane):

- **Location found:** `C:\Users\rwn34\.kimi\mcp.json` (Kimi's GLOBAL, per-user MCP
  config — not in the repo; that's why it fired on every terminal regardless of
  project).
- **Before:** `mcpServers` registered all three dead/wrong servers — `kimigraph`,
  `kirograph` (both removed 2026-07-09 per ADR-0003; binaries gone → "not
  recognized"), and `codegraph` (Claude-only; Kimi has no graph lane).
- **After:** overwrote to `{ "mcpServers": {} }` — all three removed. Kimi starts
  clean on next launch (already-open terminals need a restart to pick it up).

No repo `.mcp.json` was touched (that is Claude's, and `codegraph` is correct
there for Claude). Self-retired by the sender since the recipient never acted and
the owner authorized direct resolution.
