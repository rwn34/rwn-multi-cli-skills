# Decision: Option A strict root-file policy with full exception ADR
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-17 22:50

## Goal
Inform Kimi that the user picked **Option A** (strict root-file policy), and align
Kimi's side with the full exception ADR Claude is about to produce.

## Decision summary
User accepted Option A (keep strict) + full exception ADR. Claude is delegating
authoring of `docs/architecture/0001-root-file-exceptions.md` to its `doc-writer`
subagent on this turn. The ADR will be the single authority; CLI contracts should
reference it, not re-state the policy.

## Why Claude pushed back on your 2-item amendment

Your proposed amendment added LICENSE + CHANGELOG only. The honest exception list
is ~12 categories because many ecosystem tools hard-code repo root:

- `.gitignore`, `.gitattributes` — git hard-codes root
- `.editorconfig` — editors walk up from file location
- `.github/` — GitHub Actions / issue templates / CODEOWNERS fixed-path
- `.mcp.json`, `.dockerignore`, `.pre-commit-config.yaml` — convention-fixed
- Language manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`) — once language chosen
- Language version pinners (`.nvmrc`, `.python-version`, `.tool-versions`) — once applicable
- LICENSE, CHANGELOG, SECURITY.md — convention-discoverable (your amendment covers the first two)
- AGENTS.md, README.md, CLAUDE.md — already in policy

A 2-item amendment would have shipped broken (`.gitignore` wouldn't match, editors
wouldn't load `.editorconfig`, GitHub Actions would never find workflows, etc.).

Full argument + ADR draft outline in `.ai/research/template-completeness-claude.md`
§ "What I'd do".

## What Kimi should do in parallel

1. **Wait for the ADR to land** at `docs/architecture/0001-root-file-exceptions.md`
   (Claude's doc-writer delegate is producing it this turn; Kiro can also validate).
2. **Update `.kimi/steering/00-ai-contract.md`** to *reference* the ADR rather than
   re-state the policy. Swap the existing "Archive folders" or "Cross-CLI handoffs"
   sections' peer with a short "Root file policy" paragraph that points at the ADR
   and says "exceptions are listed there; any new root file requires ADR
   amendment." No re-duplication.
3. **Write `.kimi/hooks/README.md`** — documenting the 2 Kimi hook scripts (what each
   guards against, how to test with piped JSON). Claude is doing the Claude-side
   equivalent; Kiro will do theirs. Cross-CLI parallel.
4. **Write `.kimi/agents/README.md`** — Kimi-specific agent-setup guide (the
   `extend:` inheritance mechanism, the `--agent-file` launch pattern, how to add a
   new agent by extending `default`). Users copying the template get a Kimi quick-start.
5. **Consider if `.ai/instructions/orchestrator-pattern/principles.md` needs the
   ADR pointer added.** It mentions "root file policy" informally; pointing at the
   ADR closes the loop. If you touch this file, remember it's SSOT and should
   re-sync to Kimi/Kiro steering per `.ai/sync.md`.

## Items Kimi should NOT do
- **Don't edit `.kiro/` or `.claude/`** — edit-boundary rule. Handoffs for others'
  folders go through `.ai/handoffs/to-<cli>/`.
- **Don't ship CI / test-framework config / pre-commit** — both Claude and Kimi
  agreed in feedback docs to defer until language is chosen.

## When complete
Move this handoff to `.ai/handoffs/to-kimi/done/` once your 2–3 items above land.
Post an activity-log entry per the usual format with what you touched.
