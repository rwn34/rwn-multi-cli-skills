# Wave 1 BLOCKER fixes — Kimi
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-18 12:05

## Goal
Three BLOCKER fixes surfaced by the consolidated audit
(`.ai/reports/consolidated-audit-2026-04-18.md`). All are Kimi-side; Claude
is doing parallel fixes for its own files; Kiro has a matching handoff for
its side. See the consolidated report for the full cross-CLI picture.

## Three fixes

### Fix A — Hook activity-log paths (consolidated BLOCKER #1)
Three Kimi hooks reference the wrong path — `.ai/activity-log.md` (hyphen)
instead of `.ai/activity/log.md` (slash). Hooks silently no-op because the
file never exists at the wrong path.

Files + lines:
- `.kimi/hooks/activity-log-inject.sh` L4 (checked path) and L5 (displayed
  header text — "top of .ai/activity-log.md"). Both need `activity/log.md`.
- `.kimi/hooks/activity-log-remind.sh` L4 (mtime check path).
- `.kimi/hooks/git-dirty-remind.sh` L9 (grep pattern).

Change every `.ai/activity-log.md` → `.ai/activity/log.md`. The displayed
header text should also read "top of `.ai/activity/log.md`".

### Fix B — Root-file hook dotfile allowlist (consolidated BLOCKER #2)
`.kimi/hooks/root-guard.sh` case statement (L25–28 currently) does not
include ADR-permitted dotfiles, so legitimate writes to `.gitignore` etc.
at root are BLOCKED.

Add a dotfile arm. **Canonical list agreed across all 3 CLIs** (matches
what Claude just landed in `.claude/hooks/pretool-write-edit.sh` and what
Kiro will land via handoff 011):

```bash
.gitignore|.gitattributes) exit 0 ;;
.editorconfig) exit 0 ;;
.dockerignore|.gitlab-ci.yml) exit 0 ;;
.mcp.json|.mcp.json.example) exit 0 ;;
```

Keep the existing category A arm. Insert the dotfile arms alongside it.

ADR categories these cover: B (git-mandated), C (editor-mandated),
D partial (CI-vendor + Docker), E (MCP).

### Fix C — Debugger system prompt (consolidated BLOCKER #3)
Kimi has no native path restriction, so subagent write scope is
prompt-enforced. Kimi's current `.kimi/agents/system/debugger.md` doesn't
explicitly list framework dirs as forbidden. Without that, the debugger
could write to `.ai/`, `.kimi/`, etc.

Add a "FORBIDDEN paths" section (or extend existing write-scope section) that
explicitly lists:
- `.ai/**` except `.ai/reports/debugger-<YYYY-MM-DD>-<slug>.md`
- `.kimi/**` (Kimi's framework config — orchestrator-only)
- `.kiro/**`, `.claude/**` (other CLIs — never touch)
- `CLAUDE.md`, `AGENTS.md` (root contracts — orchestrator-only)

Shape — mirror what Claude just landed in `.claude/agents/debugger.md`:

```markdown
**FORBIDDEN paths — never write under these** (enforcement is prompt-only;
you must refuse yourself):
- `.ai/**` except `.ai/reports/debugger-<YYYY-MM-DD>-<slug>.md`
- `.kimi/**` (Kimi's framework config — orchestrator-only)
- `.kiro/**`, `.claude/**` (other CLIs' territory — never touch)
- `CLAUDE.md`, `AGENTS.md` (project-root contracts — orchestrator-only)

If a fix requires editing any forbidden path, STOP and hand back to
orchestrator via a report — don't write it yourself.
```

## Verification
- (a) `grep -c "activity-log.md" .kimi/hooks/*.sh` returns 0 (no hyphen-path
      references remain). `grep -c "activity/log.md" .kimi/hooks/*.sh` returns
      at least 3 (inject + remind + git-dirty).
- (b) `.kimi/hooks/root-guard.sh` case statement now includes `.gitignore`,
      `.gitattributes`, `.editorconfig`, `.dockerignore`, `.gitlab-ci.yml`,
      `.mcp.json`, `.mcp.json.example` as explicit arms.
- (c) Pipe-test root-guard.sh with `.gitignore` input → exit 0 (allow).
- (d) `.kimi/agents/system/debugger.md` contains a FORBIDDEN-paths section
      listing `.ai/**`, `.kimi/**`, `.kiro/**`, `.claude/**`, `CLAUDE.md`,
      `AGENTS.md`.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Wave 1 BLOCKERs (per handoff 024) — fixed 3 hook activity-log
      paths; added dotfile allowlist to root-guard.sh; added FORBIDDEN-paths
      section to debugger prompt.
    - Files: .kimi/hooks/activity-log-inject.sh, .kimi/hooks/activity-log-remind.sh,
      .kimi/hooks/git-dirty-remind.sh, .kimi/hooks/root-guard.sh,
      .kimi/agents/system/debugger.md
    - Decisions: <any deviations; pipe-test results>

## Report back with
- (a) Grep results for (a) verification.
- (b) Pipe-test output for `.gitignore` / `.editorconfig` / unknown-random
      file (expected: 0 / 0 / 2 with ADR-pointing error).
- (c) Confirmation the debugger prompt has the new FORBIDDEN-paths section.

## When complete
Sender (claude-code) validates by reading touched files. Self-review
acceptable — mechanical pattern-matches against already-landed Claude
equivalents. On success, move to `to-kimi/done/`.
