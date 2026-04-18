# Wave 1 BLOCKER fixes — Kiro
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-18 12:05

## Goal
Two BLOCKER fixes surfaced by the consolidated audit
(`.ai/reports/consolidated-audit-2026-04-18.md`). Both are Kiro-side. Matches
the Kiro BUG-1/F-1 and BUG-2/F-2 you already flagged in your own audit.
Claude has landed its parallel fixes; Kimi has a matching handoff (024).

## Handoff numbering note
Skipping number **010** because it already exists in two places:
- `.ai/handoffs/to-kiro/done/010-resync-orchestrator-pattern.md` (my handoff,
  completed earlier today)
- `.ai/handoffs/to-kiro/open/010-cross-cli-consistency-audit.md` (user's
  dispatch for your audit, still open awaiting user's sender-move)

Using 011 to avoid a third 010 collision.

## Two fixes

### Fix A — Root-file hook dotfile allowlist (consolidated BLOCKER #2 / your BUG-1/F-1)
`.kiro/hooks/root-file-guard.sh` case statement (L10–23 currently) does not
include ADR-permitted dotfiles. The comment on L18–20 says they "are caught
by the `DIR = .` branch above" — but as your own audit flagged, that's wrong.
`dirname "./.gitignore"` returns `.`, so dotfiles enter the case block and
hit the `*) BLOCKED` branch.

Add explicit dotfile arms. **Canonical list agreed across all 3 CLIs**
(matches what Claude landed in `.claude/hooks/pretool-write-edit.sh` and
what Kimi will land via handoff 024):

```bash
# Category B — git-mandated dotfiles
.gitignore|.gitattributes) exit 0 ;;
# Category C — editor-mandated
.editorconfig) exit 0 ;;
# Category D — platform / CI-vendor dotfiles at root
.dockerignore|.gitlab-ci.yml) exit 0 ;;
# Category E — MCP convention (already present — keep)
.mcp.json|.mcp.json.example) exit 0 ;;
```

Keep the existing category A arms + MCP arm. Remove the stale
"caught by the DIR=." comment and replace with a "see ADR-0001" reference.

### Fix B — Debugger framework-dir deniedPaths (consolidated BLOCKER #3 / your BUG-2/F-2)
`.kiro/agents/debugger.json` has `fs_write` in its tools but no
`toolsSettings.fs_write.allowedPaths` / `deniedPaths`. Architecturally this
lets the debugger write to any path, including all framework dirs.

Add to `toolsSettings.fs_write`:

```json
"fs_write": {
  "deniedPaths": [".kimi/**", ".kiro/**", ".claude/**"],
  "allowedPaths": [".ai/reports/**", "**/*"]
}
```

Or whatever combination Kiro's config schema supports for "allow everywhere
except framework dirs, but always allow `.ai/reports/`". If Kiro can't
combine `allowedPaths` + `deniedPaths`, structure as a strict allowlist of
reasonable writable zones: `src/**`, `tests/**`, `scripts/**`, `tools/**`,
`.ai/reports/**` — pick what matches the debugger's actual needs (scratch
repro scripts, failing test cases, small fixes).

**Note on `.ai/` scope:** The catalog says debugger should NOT write `.ai/**`
EXCEPT `.ai/reports/`. If your schema permits nested rules, carve out
`.ai/reports/` as an allowed exception. Otherwise, pick the least-restrictive
safe default — prose + hook backup will catch the remainder.

## Verification
- (a) Pipe-test `.kiro/hooks/root-file-guard.sh` with:
  - `echo '{"path":"./.gitignore"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./.gitattributes"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./.editorconfig"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./.dockerignore"}' | bash .kiro/hooks/root-file-guard.sh` → exit 0
  - `echo '{"path":"./randomfile.txt"}' | bash .kiro/hooks/root-file-guard.sh` → exit 2 with ADR-pointing error
- (b) `.kiro/agents/debugger.json` has `toolsSettings.fs_write` with
      either `deniedPaths` covering `.kimi/`, `.kiro/`, `.claude/` OR a
      restrictive `allowedPaths` that excludes framework dirs.
- (c) JSON still valid (`python -c "import json; json.load(open('.kiro/agents/debugger.json'))"`).

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Wave 1 BLOCKERs (per handoff 011) — added dotfile allowlist arms
      to root-file-guard.sh (category B/C/D); added framework-dir deniedPaths
      to debugger.json.
    - Files: .kiro/hooks/root-file-guard.sh, .kiro/agents/debugger.json
    - Decisions: <which deniedPaths schema variant chosen; pipe-test results>

## Report back with
- (a) Pipe-test results for all 5 cases above.
- (b) Diff of debugger.json showing the new deniedPaths/allowedPaths block.
- (c) JSON validity confirmation.

## When complete
Sender (claude-code) validates by reading touched files + pipe-test output.
Self-review acceptable — mechanical pattern-matches against already-landed
Claude/Kimi equivalents. On success, move to `to-kiro/done/`.
