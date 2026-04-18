# Kiro-side Audit — Rule Consistency, Flaws, and Bloat

Auditor: kiro-cli
Date: 2026-04-18
Scope: SSOT instructions, Kiro steering replicas, all 13 agent configs, all 6 hooks, docs cross-references, file-level bloat scan

---

## Summary

3 SSOT replicas are byte-identical (no drift). 13 agent configs have correct tool arrays. However, there are **3 bugs** (2 in hooks, 1 in agent config), **4 spec-drift issues** in agent path restrictions, and **2 bloat items**.

---

## Bugs (action required)

### BUG-1: root-file-guard.sh blocks ADR category B/C/D dotfiles (CRITICAL)

**File:** `.kiro/hooks/root-file-guard.sh`
**Lines:** 19–22 (comment block)

The case allowlist covers category A (docs entry points) and category E (MCP), but does NOT include:
- `.gitignore` (category B — git-mandated)
- `.gitattributes` (category B — git-mandated)
- `.editorconfig` (category C — editor-mandated)

The comment on lines 19–22 says these are "caught by the `DIR = .` branch above" — this is **wrong**. `dirname "./.gitignore"` returns `.`, so they enter the case block and hit the `*) BLOCKED` branch.

**Impact:** Any agent trying to write `.gitignore`, `.gitattributes`, or `.editorconfig` at root will be blocked. This will bite the first time a language/tool is chosen and these files need updating.

**Fix:** Add a case arm: `.gitignore|.gitattributes|.editorconfig) exit 0 ;;`

### BUG-2: debugger.json has no path restrictions (HIGH)

**File:** `.kiro/agents/debugger.json`

The debugger config has `fs_write` in its tools array but has **neither** `allowedPaths` nor `deniedPaths` in `toolsSettings`. The catalog says write scope is "Anywhere + `.ai/reports/`" — but the catalog also says "All subagents are denied write access to [framework dirs]."

**Impact:** The debugger can write to `.ai/`, `.kiro/`, `.kimi/`, `.claude/` — violating the framework-dir restriction. The `framework-dir-guard.sh` hook only blocks `.kimi/` and `.claude/` (see BUG-3 below), so `.ai/` and `.kiro/` are unprotected.

**Fix:** Add `deniedPaths: [".ai/**", ".kiro/**", ".kimi/**", ".claude/**"]` to debugger.json's `toolsSettings.fs_write`, then add `allowedPaths` exception for `.ai/reports/**` if Kiro supports both simultaneously, or restructure to use allowedPaths only.

### BUG-3: framework-dir-guard.sh doesn't block .ai/ or .kiro/ writes from subagents (MEDIUM)

**File:** `.kiro/hooks/framework-dir-guard.sh`

The hook only blocks `.kimi/*` and `.claude/*`. It does NOT block `.ai/*` or `.kiro/*` writes from subagents. The orchestrator is supposed to be the only writer to all four framework dirs.

**Impact:** Any subagent (especially debugger, which has no path restrictions at all) can write to `.ai/` and `.kiro/`. For agents with `deniedPaths` configured (coder, refactorer, ui-engineer), this is already handled at the config level. But for debugger, it's wide open.

**Mitigation note:** This hook runs for ALL agents including orchestrator. If it blocked `.ai/` and `.kiro/`, it would also block the orchestrator. The hook would need agent-awareness (check which agent is running) or the orchestrator would need to be excluded. Alternatively, rely on per-agent `deniedPaths` config (which means BUG-2 is the real fix).

---

## Spec Drift (config doesn't match catalog)

### DRIFT-1: doc-writer.json has extra root-file paths

**File:** `.kiro/agents/doc-writer.json`
**Catalog says:** `*.md`, `docs/**`, `CHANGELOG*`, `.ai/reports/`
**Config has:** Also `LICENSE`, `LICENSE.*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`

These were likely added during Phase 1 template work. They're wider than the catalog spec. `*.md` already covers `SECURITY.md` and `CODE_OF_CONDUCT.md`, so those are redundant. `LICENSE` and `LICENSE.*` are genuinely outside the catalog's doc-writer scope.

**Severity:** Low — the extra paths are reasonable for a doc-writer but the catalog should be updated to match, or the config trimmed.

### DRIFT-2: infra-engineer.json has overly broad YAML glob

**File:** `.kiro/agents/infra-engineer.json`
**Catalog says:** IaC/CI dirs only (specific directory patterns)
**Config has:** `**/*.yml`, `**/*.yaml` — matches ANY YAML file anywhere in the project

**Severity:** Medium — this means infra-engineer could overwrite non-IaC YAML files (e.g., if the project had `config/app.yaml` or `docs/openapi.yaml`).

### DRIFT-3: e2e-tester.json has extra test dirs

**File:** `.kiro/agents/e2e-tester.json`
**Catalog says:** Test files (same list as tester)
**Config has:** Also `e2e/**`, `cypress/**`

**Severity:** Low — these are reasonable additions for an E2E tester. Catalog should be updated to include them.

### DRIFT-4: release-engineer.json allows full file writes to version manifests

**File:** `.kiro/agents/release-engineer.json`
**Catalog says:** `package.json` (version field only), `pyproject.toml` (version field only), `Cargo.toml` (version field only)
**Config has:** Full file write access to `package.json`, `pyproject.toml`, `Cargo.toml`

**Severity:** Low (known limitation) — Kiro's `allowedPaths` can't enforce field-level restrictions. Prompt says "version only" but the config can't enforce it.

---

## Bloat

### BLOAT-1: `.ai/activity-log.md` — stale duplicate

**File:** `.ai/activity-log.md` (4,698 bytes)

This is a stale copy of activity log entries sitting at `.ai/` root. The real log is `.ai/activity/log.md`. This file contains old entries from 2026-04-17 and is not referenced by any config, contract, or hook.

**Action:** Delete.

### BLOAT-2: Research files — candidates for archival

**Directory:** `.ai/research/` — 12 files, ~115KB total

All research files fed into decisions that have since landed (agent catalog, orchestrator pattern, hooks, template completeness). They're referenced in ADR-0001's References section. Not orphaned, but the decisions are finalized.

**Action:** Move to `.ai/research/archive/` per the archival protocol in `.ai/research/archive/README.md`. Not urgent.

---

## Clean (no issues found)

- **SSOT replicas:** All 3 byte-identical (orchestrator-pattern, karpathy-guidelines, agent-catalog)
- **Tool arrays:** All 13 agent configs match the catalog's tool lists exactly
- **Orchestrator prompt:** Updated to ADR pointer (handoff 009 confirmed)
- **Kiro AI contract:** Has ADR pointer, no stale root-file-policy text
- **CLAUDE.md:** Has ADR pointer, consistent
- **AGENTS.md:** Consistent with current state
- **docs/README.md:** `api/` subdir now exists (TEMPLATE.md created in handoff 008)
- **sensitive-file-guard.sh:** Correctly blocks `.env*`, `*.key`, `*.pem`, etc.
- **activity-log-inject.sh / activity-log-remind.sh:** Working correctly
- **destructive-cmd-guard.sh:** Covers major destructive patterns (note: `rm -rf *` uses literal asterisk match — could miss variants like `rm -rf ./` but covers the most common dangerous patterns)

---

## Recommended priority

1. **BUG-1** (root-file-guard dotfiles) — fix now, will block `.gitignore` writes
2. **BUG-2** (debugger deniedPaths) — fix now, framework-dir violation
3. **BLOAT-1** (stale activity-log.md) — delete now, zero risk
4. **DRIFT-2** (infra-engineer YAML glob) — tighten when convenient
5. **BUG-3** (framework-dir-guard scope) — addressed by fixing BUG-2; hook redesign is optional
6. **DRIFT-1/3/4** — catalog or config alignment, low priority
7. **BLOAT-2** (research archival) — when convenient
