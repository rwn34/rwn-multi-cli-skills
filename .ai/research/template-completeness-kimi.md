# Template Completeness Feedback — Kimi CLI

**Scope:** Kimi's input on the 13-item scaffolding plan for the multi-CLI project template.

---

## 1. Item-by-item verdict

| # | Item | Verdict | Kimi-specific note |
|---|------|---------|-------------------|
| 1 | `.gitignore` | ✅ Yes | Include `.kimi/`, `*.kimi-soul`, `.env*`, `node_modules/`, `__pycache__/`, `dist/`, `build/`, `.DS_Store`, `Thumbs.db` |
| 2 | `.editorconfig` | ✅ Yes | Critical for multi-CLI — different agents on different OSs write with different defaults. Specify `charset = utf-8`, `end_of_line = lf`, `insert_final_newline = true` |
| 3 | Doc templates | ✅ Yes | ADR in `docs/architecture/adr-template.md`, spec in `docs/specs/spec-template.md`, standard in `docs/standards/standard-template.md` |
| 4 | `config/.env.example` | ✅ Yes | Complements the sensitive-guard hook (which blocks `.env*` writes). `.env.example` is the sanctioned template |
| 5 | CI pipeline | ✅ Yes | `infra/ci/github-actions.yml` — lint + test on push/PR. Keep it minimal |
| 6 | License | ✅ **Exception to root policy** | MIT/LICENSE at root is universal convention. GitHub, npm, PyPI, lawyers all look there. **Add LICENSE to the root allowlist** alongside AGENTS.md/README.md/CLAUDE.md |
| 7 | Changelog | ✅ **Exception to root policy** | CHANGELOG.md at root is standard convention (keepachangelog.com, semantic-release, etc.). Moving it breaks tooling. **Add CHANGELOG.md to root allowlist** |
| 8 | Contributing guide | ✅ Yes | `docs/guides/contributing.md` fits the directory structure |
| 9 | Testing framework config | ✅ Yes | `tools/jest.config.js` or `tools/pytest.ini` — *not* at root per policy |
| 10 | MCP servers | See §2 below |
| 11 | System prompts inline vs file refs | See §3 below |
| 12 | `.gitattributes` | ✅ Yes | `* text=auto eol=lf` — critical for Windows devs. Prevents LF/CRLF wars between CLIs on different OSs |
| 13 | Pre-commit hooks | ✅ Yes | Separate from CLI lifecycle hooks. `.git/hooks/pre-commit` or `config/pre-commit-config.yaml` for linting/formatting |

---

## 2. MCP servers for Kimi CLI

Kimi already has strong native tools; most MCP servers are redundant. Recommendations:

| MCP Server | Value | Why |
|------------|-------|-----|
| **git** | Medium | Safety layer for complex git ops (merge, rebase, bisect). Infra-engineer can use it instead of raw `Shell`. Redundant for simple add/commit. |
| **github** | Medium | PR review, issue creation, comment threads. Useful for release-engineer and reviewer workflows. |
| **playwright** | Low | Kimi has `FetchURL` and `SearchWeb`. Browser MCP only adds value for JS-heavy SPAs that need interaction. |
| **filesystem** | Low | Kimi's `ReadFile`/`WriteFile`/`Glob`/`Grep` are more powerful and don't require MCP setup. |
| **sqlite** | Low | Only if project uses SQLite; otherwise data-migrator handles DBs via migration tools. |

**Verdict:** Enable `git` and `github` MCPs as optional. Skip filesystem/playwright — native tools are sufficient and faster (no extra process overhead).

---

## 3. Inline prompts vs file refs

**File refs (`system_prompt_path`) — strongly preferred.**

Reasons:
- Kimi's `agent.yaml` supports `system_prompt_path: ./system/orchestrator.md` natively.
- `extend:` inheritance works cleanly with external prompt files.
- Inline prompts bloat YAML, lose syntax highlighting, and create unreadable diffs.
- External files allow editing in any editor with markdown support.
- The `system/` subdirectory pattern (`.kimi/agents/system/*.md`) is already working well in this project.

**Template should include:** `.kimi/agents/system/` directory with a `README.md` explaining the naming convention and how to add new agent prompts.

---

## 4. Missing items

| Item | Where | Why |
|------|-------|-----|
| **`.kimi/agents/README.md`** | `.kimi/agents/` | Explains how to add agents, launch with `--agent-file`, the `extend:` mechanism |
| **`hooks/README.md`** | `.kimi/hooks/` | Documents each hook, what it guards against, how to test |
| **`config/.kimi-config-template.toml`** | `config/` | Template showing the hooks array pattern for new projects |
| **Root file policy amendment** | `.kimi/steering/00-ai-contract.md` | Add LICENSE and CHANGELOG.md as exceptions |
| **`docs/README.md`** | `docs/` | Index of all docs subdirectories, how to add new docs |

---

## 5. Kimi-specific template additions

1. **Agent config template** — A starter `orchestrator.yaml` + one subagent (`coder-executor.yaml`) that new projects can copy and extend.
2. **Hook script template** — A `template-hook.sh` showing stdin JSON parsing, exit codes, and fail-open pattern.
3. **`max_steps_per_turn` guidance** — Document why 200 is the recommended default (prevents runaway loops while allowing complex tasks).
4. **Cross-CLI handoff protocol** — Document `.ai/handoffs/to-<cli>/open/` format in `docs/guides/cross-cli-handoffs.md`.

---

## 6. Root file policy amendment

Proposed updated root file policy:

> Only these files are permitted at project root:
> - `AGENTS.md`
> - `README.md`
> - `CLAUDE.md`
> - `LICENSE` (or `LICENSE.*`)
> - `CHANGELOG.md` (or `CHANGELOG`)
>
> No `package.json`, `tsconfig.json`, `Dockerfile`, `.env`, `.gitignore`, `.editorconfig`, etc. at root.

Rationale: LICENSE and CHANGELOG are external-facing conventions, not project config. They need to be discoverable by automated tools and humans browsing the repo. The other items in the plan (`.gitignore`, `.editorconfig`, testing configs) belong in `config/` or `tools/` as originally specified.
