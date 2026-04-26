# Add CodeGraph steering + hook tests

**From:** kimi-cli
**To:** claude-code
**Date:** 2026-04-26
**Priority:** medium
**Status:** DONE — 2026-04-26 12:45 by claude-code

## Resolution

- **Steering:** Added "CodeGraph" section to `CLAUDE.md` (full pattern from `.kimi/steering/kimigraph.md`: when-active rules, when-not-active prompt, quick-reference table, limitations, cross-CLI parity note). Added shorter reference in `.claude/agents/orchestrator.md` pointing back to CLAUDE.md to avoid duplication.
- **Hook denies:** `.claude/hooks/pretool-write-edit.sh` Rule 1 case statement gained two new arms — `.kimigraph|.kimigraph/*` → block, `.kirograph|.kirograph/*` → block. Claude's own `.codegraph/**` is allowed by default (no entry needed; Rule 3 only restricts root files).
- **Tests:** `.claude/hooks/test_hooks.sh` gained 3 tests (t22 .codegraph allowed, t23 .kimigraph blocked, t24 .kirograph blocked). 21/21 → 24/24 PASS verified by infra-engineer.
- **Embeddings policy:** Resolved with user as "structural-only at adoption, opt-in later per tool" — matches Kimi's v2 plan + all 3 reviewer report recommendations. No wording change needed in Kimi's already-shipped steering.

This handoff can be moved to `.ai/handoffs/to-claude/done/`.

---

(Original handoff content below.)

## Context

The framework is adopting three code graph tools — CodeGraph for Claude, KimiGraph for Kimi, KiroGraph for Kiro. Kimi has completed its parts (see `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` v2). This handoff covers Claude's parts.

## Tasks

### 1. Add CodeGraph steering to Claude's contract

Update `CLAUDE.md` and `.claude/agents/orchestrator.md` with CodeGraph usage instructions, following the pattern in `.kimi/steering/kimigraph.md`.

Key points:
- If `.codegraph/` exists, use `codegraph_explore` as PRIMARY exploration tool
- Spawn Explore agents for broad questions with CodeGraph instruction
- Main session may use lightweight tools: `codegraph_search`, `codegraph_callers`, `codegraph_callees`, `codegraph_impact`, `codegraph_node`
- If `.codegraph/` does NOT exist, ask user if they want to run `codegraph init`
- Include the tool quick-reference table
- Note limitations (dynamic imports invisible, structural-only start, etc.)

### 2. Update `.claude/hooks/pretool-write-edit.sh`

Add `.kirograph/**` and `.kimigraph/**` to the blocked paths (same pattern as `.kiro/**`). Claude should not write to other CLIs' graph dirs.

### 3. Update `.claude/hooks/test_hooks.sh`

Add 2 tests:
- Allow write to `.codegraph/config.json` (Claude's own graph dir)
- Block write to `.kirograph/kirograph.db` (not Claude's territory)
- Block write to `.kimigraph/kimigraph.db` (not Claude's territory)

Actually that's 3 tests — add all 3 for completeness.

### 4. Verify test suite passes

Run `.claude/hooks/test_hooks.sh` and confirm PASS.

## Report back with

- Files touched
- Test results (PASS/FAIL count)
- Any deviations from spec
