# Phase 1 template scaffolding — complete (FYI + one optional follow-up)
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-17 23:30

## TL;DR
Claude finished Phase 1 of the template ship — 17 shared + Claude-specific files. Nothing here requires Kimi to do anything urgent. One optional alignment task at the bottom: extend Kimi's write-guard hook allowlist to mirror the full ADR, same as Claude's `.claude/hooks/pretool-write-edit.sh` update.

## What landed this turn

### Shared files (project-level, not Claude-specific — Kimi can read and reference)

| File | Notes |
|---|---|
| `/LICENSE` | MIT text with TODO author placeholder. Category A of the ADR. |
| `/CHANGELOG.md` | keepachangelog.com v1.1.0 shell; empty `## [Unreleased]`. |
| `/SECURITY.md` | Disclosure template with TODO contact + supported-versions table. |
| `/CODE_OF_CONDUCT.md` | **Short pointer** to Contributor Covenant v2.1 upstream (not inlined). This is intentional — see "Lesson learned" below. |
| `/docs/guides/contributing.md` | Contributing guide with a "Working with the AI CLIs" subsection referencing the three-CLI setup + `.ai/` layout. |
| `/docs/architecture/TEMPLATE.md` | Nygard-style ADR template. Next ADR is 0002. |
| `/docs/specs/TEMPLATE.md` | Feature-spec scaffold. |
| `/docs/standards/TEMPLATE.md` | Coding-standard scaffold. |
| `/.github/ISSUE_TEMPLATE/{bug_report,feature_request}.md` | GitHub issue templates. |
| `/.github/pull_request_template.md` | GitHub PR template. |
| `/.gitignore`, `/.gitattributes`, `/.editorconfig` | Root tooling configs (ADR categories B + C). |
| `/.mcp.json.example` | Claude-convention MCP config with commented-out GitHub / Playwright / Postgres / Cloudflare server examples. |

### Claude-specific files (informational for Kimi — analogs in Kimi's folder may or may not exist)

| File | Notes |
|---|---|
| `/.claude/skills/README.md` | Documents the three active Claude skills (karpathy-guidelines, orchestrator-pattern, agent-catalog) + pattern for adding new ones. Parallels what your `.kimi/agents/README.md` does on the Kimi side. |
| `/.claude/hooks/README.md` | Documents the 4 Claude hook scripts + testing pattern + relationship to `.claude/settings.json`. Parallels your `.kimi/hooks/README.md`. |
| `/.claude/hooks/pretool-write-edit.sh` (edit) | Rule 3 allowlist extended from "AGENTS.md/README.md/CLAUDE.md only" to the full ADR category A — LICENSE, CHANGELOG, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md. |

## One optional alignment task for Kimi

**If** Kimi's setup has a write-guard equivalent to Claude's `.claude/hooks/pretool-write-edit.sh` (your system-prompt path-scoping or a PostToolUse hook), consider extending its allowlist to match the full ADR categories too. Otherwise Kimi-side writes to root files like `LICENSE`, `CHANGELOG.md`, etc. may trip the guard.

Since Kimi's path enforcement is prompt-based (per your earlier research doc), this might already be a non-issue — your orchestrator prompt that references the ADR will handle it. Check your own setup; no required action if your current enforcement already defers to the ADR.

## Lesson learned — FYI for any future Covenant / long-form legal text

The first doc-writer delegation hit `API Error 400: Output blocked by content filtering policy` partway through. Likely trigger: the Contributor Covenant's enumerated harassment-behavior list (long-form explicit-behavior text). Re-delegated with `CODE_OF_CONDUCT.md` as a **short pointer** to the upstream URL — filter no longer triggered, and this is a common open-source pattern.

If Kimi is ever asked to inline Covenant v2.1 text, Code of Conduct v1.x, or similar long-form community-code documents, expect the same filter behavior. The pointer shape is the cleaner answer anyway.

## Minor follow-ups (NOT this handoff's ask — just logging for visibility)

1. `docs/api/TEMPLATE.md` is missing — `docs/README.md` lists `api/` as a subdir but no template shipped this phase. Defer until the project has an actual API surface.
2. `docs/security.md` is missing — `SECURITY.md` at root references it. Minor stub could be added later.
3. Deferred to Phase 2 (when language chosen): CI pipeline, test-framework config, pre-commit hooks, `.dockerignore`, language-version pinners. All three CLIs agreed on deferral.

## When complete
Move to `.ai/handoffs/to-kimi/done/` once you've (a) noted the shared files exist, (b) decided whether to update your own hook/prompt allowlist, (c) confirmed no conflicts with Kimi's side. If your current setup needs no changes, this handoff is purely informational — just move it.
