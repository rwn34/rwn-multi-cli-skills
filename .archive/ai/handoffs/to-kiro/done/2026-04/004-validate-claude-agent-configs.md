# Validate Claude Code agent-config implementation
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 17:50

## Goal
Validate Claude Code's implementation of the 13-agent catalog, requested via
`.ai/handoffs/to-claude/open/006-implement-agent-configs.md`. All 13 `.claude/agents/*.md`
files are in place, main-thread agent wired to `orchestrator`, behavior rules encoded
in each system prompt. This handoff hands Kiro everything it needs to validate and
cross-check.

## Files created

### `.claude/agents/` (13 new files)

    orchestrator.md         Default main-thread agent; read + delegate + framework-only writes
    coder.md                Tier 2 — general implementation
    reviewer.md             Tier 0 — code review, reports to .ai/reports/
    tester.md               Tier 1 — test files + test configs
    debugger.md             Tier 2 — repro-first, may apply small fixes, larger fixes → report + handoff
    refactorer.md           Tier 2 — behavior-preserving, test-invariant-strict, test runners only
    doc-writer.md           Tier 1 — *.md, docs/**, CHANGELOG, in-code comments (comments only)
    security-auditor.md     Tier 0 — read-only scanners (semgrep/bandit/trufflehog/audit), reports only
    ui-engineer.md          Tier 2 — frontend + browser tools, dev server for visual verification
    e2e-tester.md           Tier 1 — E2E test dirs + playwright/cypress only
    infra-engineer.md       Tier 1 — IaC + CI dirs, plan/validate/build only (no apply)
    release-engineer.md     Tier 1 — version files + CHANGELOG; dry-run + confirm + precondition checks
    data-migrator.md        Tier 1 — migrations/seeds/schema, reversible up+down, read-only raw SQL

### `.claude/settings.json` (edit)
Added `"agent": "orchestrator"` at the top level (merged with existing `hooks` block).
This makes orchestrator the main-thread persona on next session start.

## Tool-name mapping (abstract SSOT → Claude-native)

| SSOT token | Claude tool(s) used |
|---|---|
| `fs_read` | `Read` |
| `fs_write` | `Edit`, `Write`, `NotebookEdit` (where applicable) |
| `grep` | `Grep` |
| `glob` | `Glob` |
| `code` | (no direct tool — relies on `Read`+model reasoning; Claude has no separate "code" tool) |
| `introspect` | (no direct tool — relies on `Read`/`Grep`/`Bash`) |
| `knowledge` | `Skill` (invokes the installed skills: karpathy-guidelines, orchestrator-pattern, agent-catalog) |
| `web_search` | `WebSearch` |
| `web_fetch` | `WebFetch` |
| `todo_list` | `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet` |
| `subagent` | `Agent` |
| `execute_bash` | `Bash` |

Claude also has `AskUserQuestion` (for explicit confirmation flows — used by
orchestrator and release-engineer). No SSOT equivalent, but matches the intent of
"prompt before mutating things a user should see."

## Enforcement mechanism choices

Per the SSOT's "Enforcement per CLI" row for Claude, path/shell restrictions are
**soft-enforced via system prompts**, not hard-enforced via settings. Reasoning:

1. Claude Code's `tools:` frontmatter whitelists tool *names*, not tool-argument
   patterns. So `tools: Read, Grep, Glob` is a hard restriction on WHICH tools an
   agent has; it cannot express "Edit only files under `tests/**`".
2. `permissions.deny` rules in `.claude/settings.json` apply session-wide, not
   per-subagent. Setting `deny: [Edit(.ai/**)]` would block the orchestrator (which
   needs framework writes) along with subagents. Inverse scoping isn't available.
3. System-prompt discipline is the practical mechanism. Every agent's prompt
   explicitly enumerates allowed/denied paths. Claude follows the prompt.

This matches what the SSOT already flags for Claude in its enforcement table
(`permissions.deny` or prompt (soft)) — no deviation from the spec, just a note
that we landed on prompt over permissions.

## Claude-specific limitations discovered

1. **No inverse path scoping.** You cannot say "orchestrator CAN write to `.ai/**`
   while coder CANNOT" via a single settings block — both agents run in the same
   session with shared permissions. The separation is prompt-level only. If this
   becomes a problem, the fallback is a `PreToolUse` hook that inspects
   `tool_name == "Edit"` + the `file_path` argument + the active subagent_type,
   and blocks based on per-agent path rules. Heavier, works if needed.
2. **`NotebookEdit` is Claude-native only.** Included in `coder`'s tool list.
   Kimi/Kiro have no direct equivalent; they'd use their generic file-write tool.
3. **Built-in subagents (`Explore`, `Plan`, `general-purpose`, `claude-code-guide`,
   `statusline-setup`) remain available** alongside the custom 13. Orchestrator
   system prompt routes project-specific work to the custom agents; the built-ins
   stay as escape hatches for generic exploration/planning. Not an SSOT deviation;
   just worth noting that Claude sessions see 13 custom + 5 built-in subagents.
4. **Main-thread agent is session-scoped.** `"agent": "orchestrator"` in
   `.claude/settings.json` takes effect on next session start. No hot-swap during
   the active session (current session still runs with the pre-agent-setting
   persona). Kiro's `--agent <name>` flag is similar.
5. **Hooks fire regardless of which agent is active.** The existing
   `UserPromptSubmit` / `Stop` hooks (activity-log auto-injection + reminder) will
   run for every subagent invocation. That's the right behavior — keeps the
   activity log visible — but worth flagging if Kimi/Kiro are surprised that
   subagents also see the injected log.

## No deviations from the SSOT spec

Each agent's `tools:` frontmatter is the Claude translation of the SSOT's abstract
tool list. Each agent's write/shell scope matches the SSOT verbatim (expressed in
the system prompt rather than a settings block, per the limitations above).

The only liberties taken:
- Added `AskUserQuestion` to `orchestrator` and `release-engineer` — Claude-native
  UX primitive for explicit confirmations. Matches the SSOT intent ("Release-
  engineer must dry-run before any publish/tag").
- Added `TaskCreate`/`TaskUpdate`/`TaskList` to most Executor agents for progress
  tracking. Claude-native, not required by SSOT, but it's how Claude keeps
  multi-step work organized.
- Skill tool included in every agent that needs to reference the karpathy-guidelines
  / orchestrator-pattern / agent-catalog skills. SSOT's `knowledge` maps here.

## Verification steps for you (kiro-cli)

1. Check all 13 files exist: `ls .claude/agents/*.md | wc -l` → should be 13.
2. Spot-check any agent's frontmatter against the SSOT row for that agent. Tool
   list should be the Claude translation (see mapping table above).
3. Check `.claude/settings.json` contains `"agent": "orchestrator"`.
4. Read any system prompt (e.g. `.claude/agents/coder.md`) — confirm the
   write/shell scope matches the SSOT's row for that agent.
5. Confirm no edits leaked to `.kiro/` or `.kimi/` (edit-boundary rule).

## When complete
Move this file to `.ai/handoffs/to-kiro/done/` after validation. If anything's
off, move to `BLOCKED` with a note, or reopen a correction handoff.
