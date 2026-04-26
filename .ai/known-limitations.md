# Known framework limitations

Living document. Records runtime/platform quirks that config cannot fix.
Any AI CLI hitting behavior that seems wrong should check here first.

---

## Kiro CLI — subagent hook inheritance broken

**Status:** Open. Confirmed empirically 2026-04-19 21:22 by kiro-cli.

**What:** `.kiro/agents/*.json` subagent configs correctly declare a `hooks`
section (wired Wave 4c per handoff 015), but Kiro CLI runtime does NOT fire
those hooks when a subagent performs `fs_write` or `execute_bash`. Hooks only
execute for the main agent (orchestrator) session.

**Repro:**
1. Orchestrator spawns `coder` subagent via the `subagent` tool.
2. Coder runs `fs_write` on `evil.txt` at repo root.
3. Expected: `root-file-guard.sh` fires, blocks the write with exit 2.
4. Observed: file is written, no hook execution.

**Impact on safety layers:**

| Protection | Orchestrator session | Subagent session |
|---|---|---|
| Framework-dir write (`.ai/`, `.kiro/`, `.kimi/`, `.claude/`) | ✓ tool-level `deniedPaths` (enforced by Kiro regardless of hooks) | ✓ tool-level `deniedPaths` |
| Sensitive-file write (`.env*`, `*.key`, `id_rsa*`, `secrets.*`) | ✓ `sensitive-file-guard.sh` | ✗ **not enforced** |
| Root-file policy (ADR-0001 allowlist) | ✓ `root-file-guard.sh` | ✗ **not enforced** |
| Destructive bash (`rm -rf /`, `DROP DATABASE`, `git push --force`) | ✓ `destructive-cmd-guard.sh` | ✗ **not enforced** (for subagents with `execute_bash`) |

**Mitigations applied (Wave 4d, handoff to-kiro/017):**

1. **Prompt hardening** — every Kiro subagent prompt carries explicit
   SAFETY RULES that replicate the guard-script logic. LLM self-enforces.
2. **Pattern gap fix** — `sensitive-file-guard.sh` expanded to block
   `secrets.*` + `credentials.*` patterns.
3. **Tool-list review** — confirmed all 10 execute_bash-holding subagents
   genuinely need shell (no removals viable this wave).

**Residual risk:** prompt-level self-enforcement is SOFT. An adversarial or
confused context could still push a subagent into unsafe behavior. A Kiro
runtime fix is the only hard guarantee.

**Project tracking issue:** https://github.com/rwn34/rwn-multi-cli-skills/issues/1 (filed 2026-04-21). Close when Kiro upstream fix is released AND empirical re-verification per handoff 017 passes.

**Upstream bug filed:** https://github.com/kirodotdev/Kiro/issues/7671 (filed 2026-04-21)

**What NOT to do because of this:**
- Do not rely solely on Kiro's hook layer for subagent safety. Combine with
  prompt rules, tool-level `deniedPaths`, and explicit allowedPaths where
  applicable.
- Do not assume hook coverage from orchestrator session extends to subagents.

---

## Code graph index staleness (all three CLIs)

**Status:** Characterized 2026-04-26 by kimi-cli.

**What:** CodeGraph, KimiGraph, and KiroGraph all maintain a local SQLite index of
code symbols. When source files change, the index must be re-synced. Each tool has
auto-sync, but with different reliability:

| Tool | Sync mechanism | Subagent writes synced? |
|---|---|---|
| CodeGraph | OS file watcher (FSEvents/inotify/ReadDirectoryChangesW) | Yes (OS-level, agent-agnostic) |
| KimiGraph | OS file watcher (`fs.watch`) | Yes (OS-level, agent-agnostic) |
| KiroGraph | Kiro hooks (`fileEdited`/`fileCreated`/`fileDeleted`/`agentStop`) | **No** — blocked by Kiro subagent hook-inheritance bug |

**Impact:** If a Kiro subagent edits files, KiroGraph's index goes stale silently.
The next `kirograph_context` or `kirograph_search` may return outdated symbol
locations or miss new symbols entirely.

**Mitigation:**
1. Run `kirograph sync` manually after subagent-heavy sessions.
2. All three tools run a pre-query freshness check; if they detect a mismatch,
   some will warn. Do not ignore warnings — run `sync`.
3. For critical refactors, run a full `kirograph index --force` before starting.

**Acceptance:** Stale index is an advisory failure mode, not a safety issue. The
worst case is wrong code locations in exploration results (LLM can verify by
reading the file). No data loss risk.

---

## Kimi CLI — bash guards wired into global config

**Status:** Characterized 2026-04-19 22:30 by kimi-cli (handoff 031). Snippet created 2026-04-19 23:30 (handoff 032). **Pasted and wired 2026-04-20.**

**What:** Kimi's 4 bash guard scripts (`.kimi/hooks/root-guard.sh`,
`framework-guard.sh`, `sensitive-guard.sh`, `destructive-guard.sh`) exist,
pass pipe-tests, and are **now registered as active hooks** in
`~/.kimi/config.toml`. They fire alongside the existing `safety-check.ps1`
hook (PowerShell) in parallel — if either exits 2, the operation is blocked.

**Also active:** `safety-check.ps1` (PowerShell). Scope and coverage of this
hook is not fully audited — may overlap with `destructive-guard.sh`.

**Good news — Kimi architecture is simpler than Kiro:**
Hooks in Kimi are *global* (`[[hooks]]` array in `~/.kimi/config.toml`), not
per-agent. One config edit wires them for root agent + subagents + every
session. No Wave 4c equivalent needed.

**Activation step:** restart Kimi Code CLI (or start a fresh session) to pick
up the newly appended `[[hooks]]` blocks.

**Residual unwired hooks:** five convenience hooks exist on disk but are **not**
registered in `~/.kimi/config.toml`:
- `git-status.sh` (SessionStart)
- `handoffs-remind.sh` (SessionStart)
- `activity-log-inject.sh` (UserPromptSubmit)
- `activity-log-remind.sh` (Stop)
- `git-dirty-remind.sh` (Stop)

These are optional — wire them manually if desired.

**Cross-CLI insight:** Kimi exposes `SubagentStart`/`SubagentStop` hook
events that Claude/Kiro may not have. Could inject safety rules at subagent
session start as defense-in-depth. Future consideration.

---

## Claude Code — none known at framework level

Hooks fire correctly for Write/Edit and Bash tools in orchestrator sessions.
Subagent hook behavior not yet empirically verified against evil-file-write
test — pending if Kimi or Kiro test pattern gets extended to Claude.

---

## Handoff numbering race condition

**Status:** Observed 2026-04-19 15:38/16:30. Low-severity INFO.

**What:** When two CLIs independently create a handoff to the same recipient
at nearly the same time, they can pick the same `NNN` number (each computes
`max(existing) + 1` against a stale filesystem snapshot). Observed: Kiro's 026
to Kimi collided with Claude's 026 to Kimi.

**Mitigation in place:** shim-rename (renumber loser + add SUPERSEDED pointer).

**Full fix deferred:** switch to timestamp-based numbering or introduce a
`.ai/handoffs/.claim-lock` file. Not yet implemented.

---

## Concurrent activity-log writes

**Status:** Untested (see `.ai/tests/concurrency-test-protocol.md`).

**Risk:** three CLIs prepending to `.ai/activity/log.md` simultaneously could
clobber entries. No atomic-append guarantee.

**Mitigation:** none yet. Run concurrency protocol to characterize actual
behavior before deciding on file-lock vs. lease-based coordination.

---

## How to add an entry

When you discover a new platform quirk:
1. Give it a clear H2 heading (CLI name or cross-CLI scope).
2. Status, date-confirmed, repro, impact table, mitigations, residual risk.
3. Update this file directly (framework-dir, orchestrator scope).
4. Log to `.ai/activity/log.md` noting the limitation was documented.
5. If it's a BLOCKER for real work, also dispatch a mitigation handoff.
