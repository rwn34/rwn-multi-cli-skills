# Add KiroGraph steering + hook tests

**From:** kimi-cli
**To:** kiro-cli
**Date:** 2026-04-26
**Priority:** medium

## Context

The framework is adopting three code graph tools — CodeGraph for Claude, KimiGraph for Kimi, KiroGraph for Kiro. Kimi has completed its parts (see `.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md` v2). This handoff covers Kiro's parts.

## Tasks

### 1. Add KiroGraph steering to Kiro's contract

Update `.kiro/steering/` with KiroGraph usage instructions, following the pattern in `.kimi/steering/kimigraph.md`.

Key points:
- If `.kirograph/` exists, use `kirograph_context` as PRIMARY exploration tool
- KiroGraph uses Kiro hooks for auto-sync (no background watcher needed)
- Main session may use lightweight tools: `kirograph_search`, `kirograph_callers`, `kirograph_callees`, `kirograph_impact`, `kirograph_node`, `kirograph_path`, `kirograph_type_hierarchy`
- If `.kirograph/` does NOT exist, ask user if they want to run `kirograph install`
- Include the tool quick-reference table
- Note limitations: Kiro subagent hook-inheritance bug means auto-sync may miss subagent writes; run `kirograph sync` manually if needed
- Architecture analysis is opt-in (`enableArchitecture: true`)
- Caveman mode is opt-in (`cavemanMode` in config)

### 2. Update `.kiro/hooks/` if needed

KiroGraph already installs its own hooks in `.kiro/hooks/`. Verify they coexist with existing safety hooks (they use different events: `fileEdited`/`fileCreated`/`fileDeleted`/`agentStop` vs our `preToolUse`). No changes needed unless you find a conflict.

### 3. Update `.kiro/hooks/test_hooks.sh`

Add 2 tests:
- Allow write to `.kirograph/config.json` (Kiro's own graph dir)
- Block write to `.codegraph/codegraph.db` (not Kiro's territory)
- Block write to `.kimigraph/kimigraph.db` (not Kiro's territory)

That's 3 tests for completeness.

### 4. Verify test suite passes

Run `.kiro/hooks/test_hooks.sh` and confirm PASS.

## Report back with

- Files touched
- Test results (PASS/FAIL count)
- Any deviations from spec
