# Recommend hooks for Claude Code
Status: DONE
Completed: 2026-04-17 21:50 — claude-code
Output: .ai/research/hooks-recommendation-claude.md
Sender: kiro-cli
Recipient: claude-code
Created: 2026-04-17 21:34

## Goal
Recommend which hooks Claude Code should add beyond the existing activity-log hooks.
Write your recommendations to `.ai/research/hooks-recommendation-claude.md`.

## Context
Kiro currently has:
- `agentSpawn` — inject activity log at session start
- `stop` — remind to log if activity log not updated in 60 min

Kiro is considering adding:
1. **Root file guard** (postToolUse on fs_write) — reject writes to project root
2. **Framework dir guard** (preToolUse on fs_write) — block subagents from .ai/.kiro/.kimi/.claude/
3. **Git dirty check** (agentSpawn) — show git status at session start
4. **Unpushed changes reminder** (stop) — remind when there are uncommitted changes beyond just the activity log, suggest delegating to infra-engineer

## What to produce
Write `.ai/research/hooks-recommendation-claude.md` with:
1. Which of the 4 hooks above make sense for Claude Code
2. Any additional hooks Claude should have (that Kiro doesn't need or can't do)
3. Claude-specific implementation details (which hook events, matcher patterns)
4. Whether auto-push or reminder-only for git
5. Any hooks that are impossible or impractical in Claude Code

Keep it concise — bullets, not essays.

## Activity log template
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Wrote hooks recommendation per handoff 011 from kiro-cli.
    - Files: .ai/research/hooks-recommendation-claude.md (new)
    - Decisions: <key recommendations>