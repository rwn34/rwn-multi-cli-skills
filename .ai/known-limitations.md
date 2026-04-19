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

**Upstream bug filed:** <pending — user action> (link TBD)

**What NOT to do because of this:**
- Do not rely solely on Kiro's hook layer for subagent safety. Combine with
  prompt rules, tool-level `deniedPaths`, and explicit allowedPaths where
  applicable.
- Do not assume hook coverage from orchestrator session extends to subagents.

---

## Kimi CLI — bash guards not wired into global config

**Status:** Characterized 2026-04-19 22:30 by kimi-cli (handoff 031).
Different failure mode than Kiro — **easier to fix**.

**What:** Kimi's 4 bash guard scripts (`.kimi/hooks/root-guard.sh`,
`framework-guard.sh`, `sensitive-guard.sh`, `destructive-guard.sh`) exist and
pass pipe-tests, but they're NOT registered as active hooks in
`~/.kimi/config.toml` (Kimi's global user-scope config). When an agent runs
`fs_write` or `execute_bash`, NO guard fires because no guard is registered.

**Only hook currently active:** `safety-check.ps1` (PowerShell). Scope and
coverage of this hook is not fully audited — may overlap with
`destructive-guard.sh`.

**Good news — Kimi architecture is simpler than Kiro:**
Hooks in Kimi are *global* (`[[hooks]]` array in `~/.kimi/config.toml`), not
per-agent. One config edit wires them for root agent + subagents + every
session. No Wave 4c equivalent needed.

**Fix path:** user must paste a config.toml snippet to wire the 4 guards.
Kimi cannot self-modify the global config (security boundary). Snippet
available in `.ai/config-snippets/kimi-hooks.toml` (pending).

**Residual risk until fix:** Kimi agents (root + subagents) have ZERO hook
enforcement today. Rely on tool-level `allowedPaths` / `deniedPaths` and
prompt discipline only.

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
