# Clean Kiro startup noise — leftover kirograph MCP + agent-conflict warnings
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-10 (UTC filename 202607101530)
Auto: yes
Risk: B

## Why
When your pane ran in the self-driving launcher, your startup spammed the pane
and buried the real work (owner observed):
1. `One or more mcp server did not load correctly` — a **leftover `kirograph`
   MCP entry in your GLOBAL config** (KimiGraph/KiroGraph were removed 2026-07-09
   per ADR-0003 amendment; the repo side is gone, but your per-user/global Kiro
   config still points at the deleted `kirograph` binary/dir).
2. `Agent conflict for coder/…/ui-engineer — Using workspace version` (×13) —
   noise on every launch because global agent definitions collide with the
   workspace `.kiro/agents/*.json`.

Both are cosmetic (you still completed the work) but they make your pane look
idle/broken to an observer. Clean them so your real work is what shows.

## Task
1. Find your GLOBAL Kiro MCP config (e.g. `~/.kiro/settings/mcp.json` or wherever
   your install keeps global MCP servers — check `kiro-cli` docs/`--help` if
   unsure). REMOVE the `kirograph` server entry. Confirm no `kirograph`/
   `kimigraph` MCP references remain in your global config. (Do NOT touch the
   repo's `.kiro/settings/` — that was already cleaned; this is your per-user
   global config.)
2. The agent-conflict warnings: determine the cleanest reduction — either
   (a) a Kiro verbosity/log-level setting that silences the "using workspace
   version" info line, or (b) remove the now-redundant GLOBAL agent definitions
   that duplicate the workspace `.kiro/agents/` (keep workspace as authoritative).
   Pick the least-invasive option that keeps workspace agents authoritative;
   explain your choice.
3. Re-verify: describe (or run headless) a fresh `kiro-cli --agent orchestrator`
   startup and confirm the MCP error + the 13 agent-conflict warnings are gone
   (or reduced to a single concise line).

## Rules
- Global Kiro config is YOUR territory — edit it. Do NOT touch the repo tree
  except this handoff + your activity entry.
- Prepend your activity entry via `bash .ai/tools/activity-append.sh` (atomic).
  Self-retire: set Status DONE + move to `.ai/handoffs/to-kiro/done/` (protocol
  v3). Blocked → leave OPEN as BLOCKED with a `## Blocker`.

## Report
Activity entry: where the global config lives, what you removed/changed, and the
before/after startup-noise state.

## Blocker

Investigated 2026-07-10 06:57 local (kiro-cli). The handoff's premise is partly
incorrect, and two of three steps need capabilities/decisions I don't have.

### Task 1 — kirograph MCP: NO ACTION NEEDED (already clean)

There is no kirograph/kimigraph MCP entry anywhere in the global Kiro config.
Grep-verified evidence (0 matches):

    $ grep "kirograph|kimigraph"  ~/.kiro/settings   -> No matches found (0 files)
    $ grep "kirograph|kimigraph"  ~/.kiro/agents     -> No matches found (0 files)
    $ grep "kirograph"            ~/.kiro/logs        -> No matches found (0 files)

`~/.kiro/settings/mcp.json` contains exactly one server — `github` — and nothing
else. The global orchestrator agent sets `"useLegacyMcpJson": true`, so that
legacy file is the one it loads.

The real "One or more mcp server did not load correctly" is the `github` server,
not kirograph. Latest MCP log
`~/.kiro/logs/20260709T092053888/mcp.log` (verbatim):

    level":"warn" ... "Log from server: 'npx' is not recognized as an internal or external command", "serverName":"github"
    level":"error" ... "Failed to connect: MCP error -32000: Connection closed", "serverName":"github"

Root cause: `npx` is not on PATH in the launch context (headless/pane), so the
github MCP fails to start. I deliberately did NOT change the github server: it is
credentialed and outside this handoff's kirograph scope. Owner decision needed on
whether to (i) fix `npx`/PATH for that launch, (ii) point it at an absolute node
path, or (iii) remove the github server from global MCP.

SECURITY FLAG (unsolicited): `~/.kiro/settings/mcp.json` stores a plaintext
GitHub Personal Access Token in the `github` server `env`. Recommend rotating it
and moving it out of the committed-adjacent config surface.

### Task 2 — agent-conflict warnings: BLOCKED (needs owner decision + delete capability)

Confirmed source. `~/.kiro/agents/` holds the 13 framework agents (all dated
Apr 20) that duplicate the workspace `.kiro/agents/*.json`, producing the 13
"Agent conflict … Using workspace version" lines:

    coder, data-migrator, debugger, doc-writer, e2e-tester, infra-engineer,
    orchestrator, refactorer, release-engineer, reviewer, security-auditor,
    tester, ui-engineer   (= 13)

(Seven older unrelated global agents — backend, devops, frontend, product,
security-tester, uiux-tester, kiro_default, dated Apr 16 — do NOT conflict here
because they have no workspace counterpart.)

Recommended fix: option (b) — remove the 13 redundant GLOBAL framework agents,
keeping the workspace copies authoritative. Option (a) (a verbosity/log-level
setting) could not be adopted: `~/.kiro/settings/cli.json` exposes only
`chat.disableTrustAllConfirmation`, `chat.defaultModel`, `mcp.loadedBefore`, and
I found no documented "suppress using-workspace-version" flag; inventing a key
would be an unverified placeholder.

Why blocked, not done:
- **Blast radius (gate):** deleting global agents removes the framework roster
  from EVERY project that lacks its own workspace `.kiro/agents/`. That is a
  cross-project change requiring owner confirmation, not a unilateral cleanup.
- **No delete capability:** the orchestrator's `fs_write` has create/edit/append
  only — it cannot remove files or their entries.

### Task 3 — re-verify fresh startup: BLOCKED (no shell)

Verification requires launching `kiro-cli --agent orchestrator` headless and
reading the startup banner. The orchestrator has no shell access, so I cannot
run it or confirm the warnings are gone.

### Requested owner decision

1. Approve removing the 13 redundant global agents (option b)? If yes, dispatch
   to an executor CLI/subagent with shell + delete to remove them and re-verify.
2. How to handle the `github` MCP failure (fix npx/PATH, pin node path, or
   remove the server) and the exposed PAT.

## Resolution (2026-07-10 07:18, kiro-cli — owner directed completion)

Owner instructed completion of the remaining steps. Resolved as follows.

### Task 1 — kirograph MCP: DONE (no action, already clean)
Re-verified `~/.kiro/settings/mcp.json` holds only the `github` server; zero
kirograph/kimigraph references anywhere in global config. Nothing to remove.

### Task 2 — 13 agent-conflict warnings: DONE (Tier-B reversible move)
Reclassified from "gated cross-project decision" to a reversible, low-risk
cleanup in Kiro's own global territory. Delegated a coder subagent to MOVE
(not hard-delete) the 13 stale Apr-20 global framework agents out of
`~/.kiro/agents/`:

    Moved → C:\Users\rwn34\.kiro\agents-backup-20260710\  (13 files)
    coder, data-migrator, debugger, doc-writer, e2e-tester, infra-engineer,
    orchestrator, refactorer, release-engineer, reviewer, security-auditor,
    tester, ui-engineer

Before: 21 files in `~/.kiro/agents/`. After: 8 files remain (the non-conflicting
Apr-16 globals + kiro_default + agent_config.json.example). Orchestrator verified
both directories by listing. Reversible:
`Move-Item "C:\Users\rwn34\.kiro\agents-backup-20260710\*" "C:\Users\rwn34\.kiro\agents\"`.

### Task 3 — re-verify: DONE by root-cause elimination
The 13 "Agent conflict — using workspace version" lines are emitted only when a
global agent name collides with a workspace agent name. With all 13 duplicates
moved out, no collisions remain → the warnings cannot be produced on the next
Kiro startup for this project. A live TTY banner check was not run (orchestrator
has no shell/TTY, and headless banners differ), but the collision source is
removed, which is the deterministic proof.

### Out of scope / still flagged for owner
- The `github` MCP "did not load correctly" (npx not on PATH in the launch
  context) is a SEPARATE issue from the kirograph cleanup this handoff covers —
  left untouched, needs an owner decision (fix PATH / pin node / remove server).
- SECURITY: `~/.kiro/settings/mcp.json` stores a plaintext GitHub PAT in the
  `github` server env — recommend rotating it and moving it out of that config.
