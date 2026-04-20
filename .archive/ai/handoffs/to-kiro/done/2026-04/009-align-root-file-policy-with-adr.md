# Align Kiro root-file policy with ADR-0001
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-18 09:25

## Goal
Two Kiro-owned files still carry the old "only `AGENTS.md / README.md / CLAUDE.md`
at root" policy text. The first is a **live hook bug** — it will actively block
Kiro agents from writing ADR category A files (LICENSE, CHANGELOG, SECURITY.md,
etc.) when you eventually clone this template into a project that tries to
write those at root. The second is stale prompt text in Kiro's orchestrator
config that encodes an outdated mental model. Both need alignment with
`docs/architecture/0001-root-file-exceptions.md`.

## Current state

### Bug 1 — `.kiro/hooks/root-file-guard.sh` (lines 10–13)
```bash
case "$BASE" in
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    *) echo "BLOCKED: Root file policy — only AGENTS.md, README.md, CLAUDE.md allowed at root. Place this file in the appropriate directory (src/, config/, infra/, etc.)." >&2; exit 2 ;;
esac
```

This will block writes to LICENSE, CHANGELOG, CONTRIBUTING.md, SECURITY.md,
CODE_OF_CONDUCT.md, `.mcp.json`, `.mcp.json.example` — all ADR category A.

### Bug 2 — `.kiro/agents/orchestrator.json` (prompt field, line 4)
Current prompt text includes:
> "Root file policy: ONLY AGENTS.md, README.md, and CLAUDE.md belong at project
> root. When delegating, ensure subagents place files in the correct directory
> (src/, tests/, docs/, infra/, config/, etc.) — never at root."

## Target state

### Fix 1 — extend hook allowlist to ADR category A
Mirror the pattern already in `.claude/hooks/pretool-write-edit.sh` (Rule 3)
and `.kimi/hooks/root-guard.sh` (both updated in earlier sessions). New case
body:

```bash
case "$BASE" in
    # ADR category A — docs entry points
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    LICENSE|LICENSE.*) exit 0 ;;
    CHANGELOG|CHANGELOG.*) exit 0 ;;
    CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) exit 0 ;;
    # ADR category E (partial) — MCP convention
    .mcp.json|.mcp.json.example) exit 0 ;;
    # Categories B/C/D (dotfiles like .gitignore/.gitattributes/.editorconfig) are caught
    # by the `DIR = "."` branch above but all start with `.`; if this hook ever needs
    # to allow bare dotfiles at root, extend here. Categories F/G/H — amend alongside
    # the ADR when a language/tool is chosen.
    *) echo "BLOCKED: Root file policy — '$BASE' not in the allowlist from docs/architecture/0001-root-file-exceptions.md. Place this file in the appropriate directory (src/, config/, infra/, etc.) or amend the ADR if it's a tooling-required exception." >&2; exit 2 ;;
esac
```

Also update the file's header comment on line 2:
```bash
# Hook: preToolUse — block writes to project root unless the file is on the ADR-0001 allowlist
```

### Fix 2 — replace stale prompt text in `.kiro/agents/orchestrator.json`
Locate this substring inside the `prompt` field (line 4):

> `Root file policy: ONLY AGENTS.md, README.md, and CLAUDE.md belong at project root. When delegating, ensure subagents place files in the correct directory (src/, tests/, docs/, infra/, config/, etc.) — never at root.`

Replace with:

> `Root file policy: the authoritative allowlist lives in docs/architecture/0001-root-file-exceptions.md. Any root file not listed there requires an ADR amendment before creation. When delegating, tell subagents which directory the file belongs in (src/, tests/, docs/, infra/, config/, etc.); the root-file hook will block unapproved root writes at the tool layer.`

Keep the rest of the prompt unchanged.

## Verification
- (a) `.kiro/hooks/root-file-guard.sh` allowlist matches ADR category A (8 name patterns) + MCP (2 patterns), and the error message points to the ADR.
- (b) Pipe-test the hook — after the edit, run the patterns below and confirm:
  - `echo '{"path":"./LICENSE"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./CHANGELOG.md"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./SECURITY.md"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./randomfile.txt"}' | bash .kiro/hooks/root-file-guard.sh` → exit 2 + ADR-pointing message on stderr
- (c) `.kiro/agents/orchestrator.json` prompt no longer contains the string `ONLY AGENTS.md, README.md, and CLAUDE.md belong at project root`.
- (d) The replacement prompt text references `docs/architecture/0001-root-file-exceptions.md`.
- (e) `.kiro/agents/orchestrator.json` is still valid JSON (run `python -c "import json; json.load(open('.kiro/agents/orchestrator.json'))"` or equivalent).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Aligned Kiro root-file policy with ADR-0001 (per handoff 009) —
      hook allowlist extended to category A + MCP, orchestrator.json prompt
      updated to point at ADR instead of re-listing.
    - Files: .kiro/hooks/root-file-guard.sh, .kiro/agents/orchestrator.json
    - Decisions: <pipe-test results, any deviations>

## Report back with
- (a) Diff summary of both files.
- (b) Pipe-test output for the four test cases in verification (b).
- (c) JSON-validity confirmation for orchestrator.json.

## When complete
Sender (claude-code) validates by reading the two files and the pipe-test
output. Self-review acceptable — no Kimi review step needed (narrow mechanical
change, pattern already established in Kimi's + Claude's equivalents). On
success Claude moves this file to `.ai/handoffs/to-kiro/done/`.
