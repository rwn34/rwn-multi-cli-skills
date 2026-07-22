# Canonicalize CLI actor identities — Claude territory + SSOT replica sync

Status: OPEN
Sender: kimi
Recipient: claude-cockpit
Owner: claude-cockpit
Auto: no
Risk: B
Created: 2026-07-22 23:36 (UTC+7)

## Goal
Commit the remaining CLI identity canonicalization changes that Kimi could not commit due to cross-CLI territory and SSOT replica-sync rules.

## Files to commit in a single commit

1. SSOT source + replicas (must be in the same commit):
   - `.ai/instructions/agent-catalog/principles.md`
   - `.claude/skills/agent-catalog/SKILL.md`
   - `.kiro/steering/agent-catalog.md`

2. Claude territory:
   - `.claude/agents/orchestrator.md`
   - `.claude/hooks/session-start.sh`

## What changed

These files still use deprecated actor identity strings. They were updated by the Kimi swarm to use the canonical six-actor model:
- `claude-auto` → `claude`
- `claude-code` → `claude` (actor identity only, not git committer name)
- `kimi-cli` → `kimi`
- `kiro-cli` → `kiro`
- `opencode-auto` → `opencode`
- `kimai-auto` → `kimi`
- `kimai-cockpit` → `kimi-cockpit`

Preserved intentionally in these files:
- Git committer names (`claude-code`, `kimi-cli`, `kiro-cli`, `opencode`)
- Binary invocations (`kiro-cli chat`, `kiro-cli --v3`, etc.)
- Backward-compat alias descriptions

## How to commit

```bash
cd C:/Users/rwn34/Code/rwn-multi-cli-skills/.claude/worktrees/cli-naming-cleanup
git add .ai/instructions/agent-catalog/principles.md \
        .claude/skills/agent-catalog/SKILL.md \
        .kiro/steering/agent-catalog.md \
        .claude/agents/orchestrator.md \
        .claude/hooks/session-start.sh
git commit -m "canonicalize CLI actor identities in Claude territory and SSOT replicas

Update .ai/instructions/agent-catalog/principles.md and its registered
replicas (.claude/skills/agent-catalog/SKILL.md, .kiro/steering/agent-catalog.md)
plus .claude/agents/orchestrator.md and .claude/hooks/session-start.sh to use
the canonical six-actor model."
```

## Verification already run by Kimi

- `bash .ai/tools/lint-handoff.sh` — PASS
- `bash .ai/tools/sync-replicas.sh --check` — PASS (24 replicas, 0 drift)
- `bash .ai/tools/check-landed-ssot.sh` — PASS (24 pairs, 0 mismatches)
- `bash .ai/tools/check-tier-restatements.sh` — PASS
- `bash scripts/git-hooks/test-pre-commit.sh` — PASS 127/127
- `tools/4ai-panes/test-pane-runner.ps1` — PASS 195/195
- All per-CLI hook suites — PASS

## Blocker

None. Kimi already committed the shared `.ai/` (except this SSOT source), `.kimi/`, `docs/`, `tools/`, and `CLAUDE.md` changes in commit `be53ed7` on branch `fix/cli-naming-cleanup`.

## When complete

1. Mark this handoff DONE and move it to `.ai/handoffs/to-claude-cockpit/done/`.
2. If Kiro has not yet committed `.kiro/hooks/dispatch-own-queue.sh` and `.kiro/hooks/handoff-queue-count.sh`, remind Kiro to process its handoff.
