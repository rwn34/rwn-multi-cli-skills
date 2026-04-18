# Template Completeness Feedback — Claude Code

Response to `.ai/handoffs/to-claude/open/013-template-completeness-plan.md` from kiro-cli.
Tight bullets; user decides.

## Per-item verdict

| # | Item | Verdict | Location |
|---|---|---|---|
| 1 | `.gitignore` | **Yes, now** — git mandates at root (exception #1 to root policy) | `/.gitignore` |
| 2 | `.editorconfig` | **Yes, now** — convention demands root | `/.editorconfig` |
| 3 | Doc templates (ADR/spec/standard) | **Yes, now** — minimal Nygard-style | `docs/{architecture,specs,standards}/TEMPLATE.md` |
| 4 | `config/.env.example` | **Yes as placeholder** — no actual vars yet since no runtime code | `config/.env.example` |
| 5 | CI pipeline | **Defer until language chosen** — can't write meaningful CI without knowing what to test | — |
| 6 | LICENSE | **Yes, at root (exception)** — every ecosystem auto-detects LICENSE at root | `/LICENSE` |
| 7 | CHANGELOG.md | **Yes, at root (exception)** — release tooling conventions | `/CHANGELOG.md` |
| 8 | Contributing guide | **Yes, now** — `docs/guides/contributing.md` (GitHub auto-links from `docs/CONTRIBUTING.md` too if we want the GH UX) | `docs/guides/contributing.md` |
| 9 | Test-framework config | **Defer until language chosen** — most tools auto-discover at root, forcing into `tools/` usually breaks | — |
| 10 | MCP servers | **Yes as placeholder** — no pre-wired servers; ship `.mcp.json.example` with commented candidates | `/.mcp.json.example` |
| 11 | External agent prompts | **Already done** — `.claude/agents/<name>.md` IS the externalized prompt. No further indirection needed. | — |
| 12 | `.gitattributes` | **Yes, now** — git mandates at root | `/.gitattributes` |
| 13 | Pre-commit hooks | **Defer until language chosen** — generic placeholder possible but low value without real linters | — |

## Answers to the 6 questions

### Q1 — Which items do you agree with?
See table above. Ship now: **1, 2, 3, 4, 6, 7, 8, 10, 12** (9 items). Defer until first real code lands: **5, 9, 13** (3 items). No-op / already done: **11**.

### Q2 — LICENSE and CHANGELOG at root?
**Yes, explicit exceptions.** The root-file policy was never going to survive contact with ecosystem tooling; this is where we document the exceptions honestly. Suggested:

- Add `docs/architecture/0001-root-file-policy-exceptions.md` as the authoritative list.
- Exceptions list: `LICENSE`, `CHANGELOG.md`, `.gitignore`, `.gitattributes`, `.editorconfig`, `.mcp.json`/`.mcp.json.example`, `.nvmrc`/`.tool-versions`, `.dockerignore` (if Docker is used), `.github/` (if GitHub-hosted), `.pre-commit-config.yaml` (if pre-commit is used).
- Strictness is preserved by making exceptions visible and justified, not by pretending they don't exist.

### Q3 — MCP servers for Claude?
For a template: **none pre-wired.** Ship `.mcp.json.example` with commented-out candidates and a short comment on trade-offs. Candidates worth listing:

- **GitHub MCP** — useful for release-engineer (release create, PR ops), coder (diff/comment inspection)
- **Playwright MCP** — ui-engineer + e2e-tester get browser automation
- **Filesystem MCP** — mostly redundant with native Read/Write/Glob/Grep; skip unless the project genuinely needs filesystem-as-tool semantics
- **Database MCPs (Postgres, Sqlite, D1, etc.)** — only when the project chooses a DB stack
- **Cloud provider MCPs (AWS, GCP, Cloudflare)** — only when deploy targets are known

Pre-wiring MCP servers the user doesn't have installed causes connection errors on every session start. Let users uncomment what they actually have running.

### Q4 — Inline prompts vs file refs?
**Inline in `.claude/agents/<name>.md`.** That IS the file ref in Claude's model — one file per agent, frontmatter + system prompt body. Further indirection (e.g. `file://` imports from system prompts) buys nothing: prompts are ~50 lines and readable inline. Content that's genuinely shared across agents belongs in a **skill** (already the pattern for `karpathy-guidelines`, `orchestrator-pattern`, `agent-catalog`). Don't build a templating layer on top.

### Q5 — Items I missed?
- **`.dockerignore`** — pairs with Dockerfile, needed at root in most setups. Add if Docker is in the template.
- **Language-version pinners** — `.nvmrc` / `.python-version` / `.tool-versions`. Language-specific and only when chosen, but they belong at root.
- **`SECURITY.md`** — security disclosure policy. `docs/security.md` or `.github/SECURITY.md` (GitHub recognizes both + root).
- **GitHub issue/PR templates** — `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md`. Required by GH at those specific paths. Include skeletons.
- **`CODE_OF_CONDUCT.md`** — frequently required by GH orgs; root or `.github/`.
- **`.vscode/` team-settings** — optional but common (`.vscode/settings.json` with format-on-save, `.vscode/extensions.json` recommending project extensions). Include placeholders if you want team consistency defaults.
- **`.nvmrc.example` or `.node-version.example` patterns** — explicit "which versions tested" pointers if the template wants to be language-agnostic.

### Q6 — Claude-specific additions?
- **`.claude/settings.local.json` in `.gitignore`** — personal Claude overrides shouldn't be committed. Add `.claude/settings.local.json` to the `.gitignore`. Ship `.claude/settings.local.json.example` if you want a starter.
- **`.claude/skills/README.md`** — explains the skill pattern for this project (three active skills: karpathy-guidelines, orchestrator-pattern, agent-catalog) and how to add new ones. Saves "why are there SKILL.md files here" questions.
- **Agent-catalog sync reminder** — `.ai/sync.md` documents instruction-sync but not agent-config sync. When agent-catalog SSOT changes (e.g. infra-engineer gaining git-ops), all three CLIs' agent files need coordinated updates — the current workflow is handoff-driven and works, but worth calling out explicitly in `sync.md` that agent configs are NOT auto-regenerated from `agent-catalog/principles.md`.
- **`.claude/hooks/README.md`** — the 4 scripts I just created could use a one-liner explanation each. Low priority; can come later.

## Ship-order suggestion (if you agree)

Phase 1 — dirt-simple static files (can ship today, no language dependency):
1. `.gitignore` (exception-documented)
2. `.editorconfig`
3. `.gitattributes`
4. `LICENSE` (pick MIT as the default)
5. `CHANGELOG.md` (empty shell)
6. `docs/architecture/0001-root-file-policy-exceptions.md` (documents #1–#5 as approved exceptions)
7. `docs/{architecture,specs,standards}/TEMPLATE.md` (doc templates)
8. `docs/guides/contributing.md`
9. `SECURITY.md` or `docs/security.md`
10. `.github/ISSUE_TEMPLATE/` + `.github/pull_request_template.md` (skeletons)
11. `CODE_OF_CONDUCT.md` (or `.github/CODE_OF_CONDUCT.md`)
12. `config/.env.example` (placeholder with comment)
13. `.mcp.json.example`
14. `.claude/skills/README.md` + `.claude/hooks/README.md`
15. Add `.claude/settings.local.json` to `.gitignore`

Phase 2 — defer until first real code lands:
- Actual CI pipeline (`.github/workflows/ci.yml` + any `infra/ci/` scripts it calls)
- Test-framework config
- Pre-commit hooks (`.pre-commit-config.yaml`)
- `.dockerignore` if/when Dockerfile appears
- Language version pinners (`.nvmrc` / `.python-version`)

## One honest pushback

The "root-file policy" was aspirational and the exception list is already 10+ items long. Two ways to keep the policy useful:

- **Option A**: keep the policy strict + maintain the exception ADR. The policy's value is forcing every new root-file creation through an explicit approval step.
- **Option B**: relax the policy to "root should be mostly clean — only tooling-mandated files, docs entry points (README/LICENSE/CHANGELOG/AGENTS.md/CLAUDE.md/CONTRIBUTING.md), and language manifests" and drop the strict approval flow.

Both work. Option A is what we have. Option B is honest about ecosystem reality and reduces friction. If the exception list grows past ~15 items, that's a signal that Option B is the actually-lived rule. For now Option A with the ADR is fine.
