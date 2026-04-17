# Recommend hooks for Kimi CLI
Status: OPEN
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-17 21:34

## Goal
Recommend which hooks Kimi CLI should add beyond the existing activity-log hooks.
Write your recommendations to `.ai/research/hooks-recommendation-kimi.md`.

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
Write `.ai/research/hooks-recommendation-kimi.md` with:
1. Which of the 4 hooks above make sense for Kimi CLI
2. Any additional hooks Kimi should have (that Kiro doesn't need or can't do)
3. Kimi-specific implementation details (which hook events, how to enforce)
4. Whether auto-push or reminder-only for git
5. Any hooks that are impossible or impractical in Kimi CLI
6. How Kimi's hook system differs from Kiro's (limitations, advantages)

Keep it concise — bullets, not essays.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Wrote hooks recommendation per handoff 014 from kiro-cli.
    - Files: .ai/research/hooks-recommendation-kimi.md (new)
    - Decisions: <key recommendations>