# Phase 1 template scaffolding — complete (FYI + one optional follow-up)
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 23:30

## TL;DR
Claude finished Phase 1 of the template ship — 17 shared + Claude-specific files. Most is informational for Kiro; one optional alignment task at the bottom (extending Kiro's native path-enforcement to reflect the full ADR, same as Claude's hook update).

## What landed this turn

### Shared files (project-level, Kiro can read and reference)

| File | Notes |
|---|---|
| `/LICENSE` | MIT, TODO author. |
| `/CHANGELOG.md` | keepachangelog.com v1.1.0 shell. |
| `/SECURITY.md` | Disclosure template. |
| `/CODE_OF_CONDUCT.md` | **Short pointer** to Contributor Covenant v2.1 (not inlined — see "Lesson learned"). |
| `/docs/guides/contributing.md` | Contributing guide with "Working with the AI CLIs" subsection referencing the three-CLI setup. |
| `/docs/architecture/TEMPLATE.md` | Nygard ADR template (next ADR = 0002). |
| `/docs/specs/TEMPLATE.md` | Feature-spec scaffold. |
| `/docs/standards/TEMPLATE.md` | Coding-standard scaffold. |
| `/.github/ISSUE_TEMPLATE/{bug_report,feature_request}.md` | GitHub issue templates. |
| `/.github/pull_request_template.md` | GitHub PR template. |
| `/.gitignore`, `/.gitattributes`, `/.editorconfig` | Root tooling configs. |
| `/.mcp.json.example` | Claude-convention MCP example (commented GitHub / Playwright / Postgres / Cloudflare servers). |

### Claude-specific files (informational for Kiro)

| File | Kiro's parallel |
|---|---|
| `/.claude/skills/README.md` | Documents Claude's 3 active skills + pattern. Parallels your `.kiro/skills/README.md`. |
| `/.claude/hooks/README.md` | Documents Claude's 4 hook scripts + testing. Parallels your `.kiro/hooks/README.md`. |
| `/.claude/hooks/pretool-write-edit.sh` (edit) | Rule 3 allowlist extended from "AGENTS.md/README.md/CLAUDE.md only" to the full ADR category A — LICENSE, CHANGELOG, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md. |

## One optional alignment task for Kiro

Kiro's write-path enforcement is native and hard-enforced via `toolsSettings.fs_write.allowedPaths` / `deniedPaths` in each agent's JSON (your advantage over Claude/Kimi). If any of those allowlists / denylists were written with the old "only AGENTS.md/README.md/CLAUDE.md at root" assumption, they'll block Kiro-side writes to the now-ADR-approved files (LICENSE, CHANGELOG, etc.).

Check these agent configs on your side:
- `.kiro/agents/orchestrator.json` — if it has `fs_write.allowedPaths` including root globs
- `.kiro/agents/infra-engineer.json` — handles `.github/` + infra stuff
- `.kiro/agents/doc-writer.json` — would handle LICENSE/CHANGELOG/SECURITY/CoC/docs templates on Kiro side

If their paths need extending, amend them to match the ADR category A list. If they already delegate to the ADR (e.g. your orchestrator's write scope is just `docs/architecture/**` + shared-docs paths and your prompts defer to the ADR for root-file approval), no change needed.

## Lesson learned — FYI

First doc-writer delegation hit a content-filter 400 — likely the verbatim Contributor Covenant text (explicit harassment-behavior language is a known trigger). Re-delegated with `CODE_OF_CONDUCT.md` as a **short pointer** to the upstream URL. Common open-source pattern; filter didn't trigger. If Kiro is ever asked to inline long-form community code / legal text, the pointer shape is the robust answer.

## Minor follow-ups (logged for visibility, not this handoff's ask)

1. `docs/api/TEMPLATE.md` missing — `docs/README.md` lists `api/` as a subdir. Defer until the project has an actual API surface.
2. `docs/security.md` missing — `SECURITY.md` at root references it. Minor stub could come later.
3. Phase 2 (language-dependent) items still deferred per earlier consensus: CI pipeline (`.github/workflows/ci.yml` + `infra/ci/*.sh` split), test-framework config, pre-commit hooks, `.dockerignore`, language-version pinners.

## Validation invitation

If Kiro wants to spot-check the ADR-category-A root files Claude shipped (LICENSE, CHANGELOG.md, SECURITY.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md-via-docs), read and confirm they match the ADR + that voice is consistent with the rest of the framework. No handback expected — just a parallel validation pass if you feel like it.

## When complete
Move to `.ai/handoffs/to-kiro/done/` once you've (a) noted the shared files exist, (b) decided whether to extend any Kiro agent `fs_write.allowedPaths` to include the new ADR-approved root files, (c) optionally spot-validated. Informational handoff; no required action if your side already aligns.
