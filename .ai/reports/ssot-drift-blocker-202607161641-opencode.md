# SSOT drift blocker — master→main migration

**Status:** BLOCKED

**Reported by:** opencode-auto

**Created:** 2026-07-16 20:41 (UTC+7)

**Root cause:** CI on PR #101 failing due to SSOT drift between replicas and SSOT.

## The problem

PR #101 (`migrate-master-to-main`) fails `framework-check` because the SSOT drift checker reports:
- DRIFT: `.ai/instructions/operating-prompt/principles.md` → `.kimi/steering/operating-prompt.md`
- DRIFT: `.ai/instructions/operating-prompt/principles.md` → `.kiro/steering/operating-prompt.md`
- DRIFT: `.ai/instructions/operating-prompt/principles.md` → `.claude/skills/operating-prompt/SKILL.md`

## What happened

1. Commit 8150c90 in the migration branch updated the replicas (`.kimi/steering/operating-prompt.md`, `.kiro/steering/operating-prompt.md`, `.claude/skills/operating-prompt/SKILL.md`) with a new §1.1 bullet point about "Claude cockpit execution boundary".
2. The SSOT (`.ai/instructions/operating-prompt/principles.md`) was updated separately to use the new wording ("Claude lane defaults" → "cockpit defaults" and the revised bullet point).
3. The replicas in the branch are from the state before the SSOT was updated on `origin/master`, causing the drift.

## Why OpenCode cannot fix this

Per the operating-prompt and framework-guard rules:

- **Replicas in `.kimi/steering/` and `.kiro/steering/` are Kiro's territory** — the guard explicitly blocks OpenCode from writing to Kiro's steering files.
- **SSOT in `.ai/instructions/` is not in OpenCode's writable lane** — the guard blocks `.ai/instructions/` even though it's under `.ai/`.
- **The handoff excludes replicas from execution** (plan §1D marks them as "Claude's lane", excluded from the execution handoff).

Thus, OpenCode cannot update either file to resolve the drift.

## Required fix

**Option 1 (preferred):** Claude/Kiro to regenerate replicas from the SSOT using `bash .ai/tools/sync-replicas.sh` and commit the replicas along with the SSOT change in the migration branch.

**Option 2:** Revert replicas in the migration branch to match `origin/master` (i.e., before 8150c90's steering update), then run `sync-replicas.sh` on the branch to ensure consistency.

**Option 3:** Skip the replica changes entirely — if they are not functionally required for the migration, they can be removed from the branch history. This requires a more invasive revert of commit 8150c90 or an interactive rebase.

## Blocking files

- `.kimi/steering/operating-prompt.md` (Kiro's territory)
- `.kiro/steering/operating-prompt.md` (Kiro's territory)
- `.claude/skills/operating-prompt/SKILL.md` (Claude's territory)
- `.ai/instructions/operating-prompt/principles.md` (not in OpenCode's lane)

## Next steps

1. Decide which fix option to apply (pref: Option 1 or 2).
2. Apply the fix to the migration branch.
3. Push to trigger CI again.
4. Once CI passes, proceed with step 4 (awaiting Claude's merge gate).
