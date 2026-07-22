# Canonicalize CLI actor identities — Kiro hooks

Status: DONE
Sender: kimi
Recipient: kiro
Owner: kiro
Auto: no
Risk: B
Created: 2026-07-22 23:36 (UTC+7)

## Goal
Commit the Kiro hook changes from the CLI identity canonicalization sweep.

## Files to commit

- `.kiro/hooks/dispatch-own-queue.sh`
- `.kiro/hooks/handoff-queue-count.sh`

## What changed

These files still used deprecated actor identity strings. They were updated to use the canonical six-actor model:
- `kiro-cli` → `kiro` in user-facing output and comments
- Other identity references normalized where applicable

Preserved intentionally:
- Actual binary invocations (`kiro-cli chat`, `command -v kiro-cli`)
- Git committer names

## How to commit

```bash
cd C:/Users/rwn34/Code/rwn-multi-cli-skills/.claude/worktrees/cli-naming-cleanup
git add .kiro/hooks/dispatch-own-queue.sh .kiro/hooks/handoff-queue-count.sh
git commit -m "canonicalize CLI actor identities in Kiro hooks

Update .kiro/hooks/dispatch-own-queue.sh and .kiro/hooks/handoff-queue-count.sh
to use canonical actor identity 'kiro' in user-facing strings and comments."
```

## Verification already run by Kimi

- `bash .kiro/hooks/test_hooks.sh` — PASS 70/70
- Full framework test suite run; no regressions attributable to these changes.

## Blocker

None. Kimi already committed the shared `.ai/`, `.kimi/`, `docs/`, `tools/`, and `CLAUDE.md` changes in commit `be53ed7` on branch `fix/cli-naming-cleanup`.

## When complete

1. Mark this handoff DONE and move it to `.ai/handoffs/to-kiro/done/`.
