# 1. Root File Policy and Its Ecosystem Exceptions

## Status

Accepted (2026-04-17)

## Context

- The project wants a minimal, clean repo root for discoverability and visual clarity.
- Many ecosystem tools hard-code root paths (git, editors, GitHub, package managers, Claude Code, etc.).
- A purely-strict policy would break tooling; a free-for-all loses clarity.
- Prior inline policy in `CLAUDE.md`, `AGENTS.md`, and each CLI's steering contract listed only `AGENTS.md`, `README.md`, and `CLAUDE.md` as root-permitted. In practice, exceptions kept piling up.
- This ADR is the single authority going forward. CLI contracts should reference it, not duplicate the list.

## Decision

Root-file policy is strict: any file not explicitly listed below requires orchestrator approval **and** an amendment to this ADR before creation. The permitted root files, by category:

### A. Docs entry points (convention-discoverable by external readers)

- `AGENTS.md` — multi-CLI project pointer
- `README.md` — project README
- `CLAUDE.md` — Claude Code's always-loaded memory
- `LICENSE` (or `LICENSE.*`) — GitHub / npm / PyPI / crates.io auto-detection
- `CHANGELOG.md` (or `CHANGELOG`) — release-tooling convention (keepachangelog, release-please, semantic-release)
- `CONTRIBUTING.md` — optional; canonical version lives at `docs/guides/contributing.md`. Root file allowed for GitHub auto-link UX.
- `SECURITY.md` — optional; canonical at `docs/security.md`. Root or `.github/SECURITY.md` also recognized.
- `CODE_OF_CONDUCT.md` — optional; root or `.github/CODE_OF_CONDUCT.md`.

### B. Git-mandated

- `.gitignore` — git hard-codes repo root
- `.gitattributes` — git hard-codes repo root

### C. Editor-mandated

- `.editorconfig` — editors walk up from file location; root file required for root-level files

### D. Platform-mandated

- `.github/` — GitHub Actions workflows, issue templates, CODEOWNERS, SECURITY.md, pull_request_template.md
- `.gitlab-ci.yml`, `.circleci/`, `.buildkite/` — respective CI platforms
- `.dockerignore` — Docker build-context expectation (pairs with Dockerfile wherever it lives)

### E. AI framework

- `.ai/` — shared multi-CLI framework state and SSOT
- `.archive/` — framework cold storage (old reports, resolved handoffs, activity rollups; see `.archive/README.md`)
- `.claude/` — Claude Code config
- `.kimi/` — Kimi CLI config
- `.kiro/` — Kiro CLI config
- `.mcp.json` or `.mcp.json.example` — Claude Code MCP convention

### F. Language manifests (allowlist extended only when a language is chosen — amend this ADR at that time)

- Not yet allowed. When a language is chosen: `package.json` (npm/bun), `pyproject.toml` (Python), `Cargo.toml` (Rust), `go.mod` (Go), `Gemfile` (Ruby), etc.
- The manifest's lockfile (`package-lock.json`, `uv.lock`, `Cargo.lock`, `go.sum`, `Gemfile.lock`) is implicitly permitted once the manifest is.

### G. Language-version pinners (same policy as F)

- Not yet allowed. When applicable: `.nvmrc`, `.python-version`, `.tool-versions`, `rust-toolchain.toml`, `.ruby-version`.

### H. Dev tooling (add by amendment when tool is chosen)

- `.pre-commit-config.yaml` — only when pre-commit is in use.
- Other linter/formatter configs (`.prettierrc`, `.eslintrc.*`, `.ruff.toml`, etc.) — amend this ADR when introduced. Prefer configs that read from `package.json` / `pyproject.toml` to avoid extra root files when possible.

Framework dirs (`.`-prefixed directories under E) are exempt from the "loose file at root" question by nature — they are directories that hold their own contents, not single root files.

### Process for adding a new exception

1. A subagent hits a tooling constraint requiring a root file.
2. Surface to orchestrator; orchestrator surfaces to user.
3. User approves → orchestrator amends this ADR (new subsection under the appropriate category, or new category).
4. Once amended, the file is approved for creation.

## Consequences

- **Positive:** every root-level file has a documented reason; template stays scannable; new contributors and new CLIs can tell at a glance what's there and why.
- **Positive:** enforcement via `.claude/hooks/pretool-write-edit.sh` (and equivalents in Kimi/Kiro) rejects unapproved root writes automatically.
- **Negative:** ongoing maintenance — adding a new tool to the project often means amending this ADR. That is the intended friction (visibility + approval).
- **Negative:** out-of-band discoveries (tools we did not know about) still cause orchestrator-level blocks before approval.

## References

- `CLAUDE.md` § "Root file policy" (live reference — should be updated to point here rather than re-list exceptions)
- `.claude/agents/orchestrator.md` § "Root file policy" (same — update to reference-only)
- `.kimi/steering/00-ai-contract.md` (update to reference-only)
- `.kiro/steering/00-ai-contract.md` (update to reference-only)
- Research docs that led to this decision: `.ai/research/template-completeness-claude.md`, `.ai/research/template-completeness-kimi.md`, `.ai/research/project-structure-feedback-claude.md`, `.ai/research/project-structure-feedback-kimi.md`
- `.archive/README.md` — archive protocol doc (layout, triggers, move commands)
