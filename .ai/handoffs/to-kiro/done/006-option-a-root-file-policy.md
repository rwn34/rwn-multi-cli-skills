# Decision: Option A strict root-file policy with full exception ADR
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-17 22:50

## Goal
Inform Kiro that the user picked **Option A** (strict root-file policy), and align
Kiro's side with the full exception ADR Claude is about to produce.

## Decision summary
User accepted Option A + full exception ADR. Claude is delegating authoring of
`docs/architecture/0001-root-file-exceptions.md` to its `doc-writer` subagent on
this turn. The ADR is the single authority; all CLI contracts (including the
orchestrator system prompts across all three CLIs) should reference it, not
re-state the policy.

## Why the 2-item amendment wasn't enough

Kimi's proposal added LICENSE + CHANGELOG only. The real exception list is ~12
categories (git-mandated, editor-mandated, platform-mandated, ecosystem-convention,
AI-framework dirs, language manifests when language is chosen). Full reasoning in
`.ai/research/template-completeness-claude.md` § "What I'd do".

Specifically, two concrete files you proposed ship locations for wouldn't work:

- **`infra/ci/github-actions.yml`** — GitHub Actions reads only from `.github/workflows/`.
  The filename + path you suggested results in zero CI runs. If CI logic lives in
  `infra/`, the shape is a thin `.github/workflows/ci.yml` calling
  `bash infra/ci/test.sh` + `bash infra/ci/lint.sh`.
- **`tools/jest.config.js`** (and similar test-framework configs) — most test
  runners auto-discover at root or in the package manifest. Putting it under
  `tools/` without an explicit `--config` flag in every invocation breaks
  discovery. Defer test-framework config until language is chosen (Kimi and
  Claude both agreed on this).

## What Kiro should do in parallel

1. **Wait for the ADR to land** at `docs/architecture/0001-root-file-exceptions.md`
   (Claude is delegating this turn). Validate that it matches the categories laid
   out in `.ai/research/template-completeness-claude.md`.
2. **Update `.kiro/steering/00-ai-contract.md`** to *reference* the ADR rather than
   re-state. Swap to a short "Root file policy" pointer paragraph.
3. **Update `.kiro/agents/orchestrator.json`** (and its system-prompt reference) so
   the orchestrator persona delegates to the ADR as authority instead of carrying
   the exception list inline. Claude will do the same for
   `.claude/agents/orchestrator.md`; Kimi will do the same for their agent config.
4. **Write `.kiro/hooks/README.md`** and **`.kiro/agents/README.md`** — Kiro-side
   parallels to what Claude and Kimi are producing.
5. **Consider whether `.ai/instructions/orchestrator-pattern/principles.md`** needs
   an ADR pointer added (it's the shared SSOT; small update + sync would propagate
   to all three CLIs' steering). Your call as framework owner.

## Phase 1 ship list (shared plan)

The ADR approves Phase 1 all at once. Each CLI does its own parallel work:

**Shared files** (orchestrator-authored, approved by ADR):
- `.gitignore` — must be at root, exception category B (git-mandated)
- `.gitattributes` — same
- `.editorconfig` — must be at root, category C (editor-mandated)
- `LICENSE` — root, category A
- `CHANGELOG.md` — root, category A (empty-shell)
- `config/.env.example` — placeholder, no actual vars yet
- `.mcp.json.example` — root, category E (AI-framework)
- `SECURITY.md` or `docs/security.md`
- `CODE_OF_CONDUCT.md` (or `.github/CODE_OF_CONDUCT.md`)
- `.github/ISSUE_TEMPLATE/*.md` + `.github/pull_request_template.md`
- `docs/guides/contributing.md`
- `docs/{architecture,specs,standards}/TEMPLATE.md` — doc templates

**Deferred until language chosen**: CI workflow (with the `.github/workflows/ci.yml` + `infra/ci/*.sh` split above), test-framework config, pre-commit hooks, `.dockerignore` when Docker appears.

Claude will orchestrate its Phase 1 on a follow-up turn once the ADR has landed.
Kiro and Kimi can run parallel Phase 1 for their own folder items.

## Items Kiro should NOT do
- **Don't edit `.claude/` or `.kimi/`** — edit-boundary rule. Handoffs only.
- **Don't ship CI / test-framework config / pre-commit** — deferred.

## When complete
Move this handoff to `.ai/handoffs/to-kiro/done/` once your parallel work lands
(contract update + agent-config update + Kiro hooks/agents READMEs).
