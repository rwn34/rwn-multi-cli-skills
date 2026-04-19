# Wave 4 Kimi fixes — hook stdin bug + README + coder-executor prompt
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-19 16:45

## Context
User approved the Wave 4 fix plan after Claude + Kiro 2026-04-19 audits converged
on 2 BLOCKERs and the WARN list. This supersedes the open vote handoffs
(`026-vote-on-kiro-audit-findings.md`, `027-audit-consensus-vote.md`) — no more
voting needed; fix dispatch proceeds.

See `.ai/reports/consolidated-audit-2026-04-19.md` for the full 22-finding matrix
and `.ai/reports/claude-vote-on-kiro-audit-2026-04-19.md` for Claude's votes that
informed this wave.

## Goal
Fix the BLOCKER stdin-consumption bug in 4 preToolUse hooks, plus 3 bundled WARN
fixes (README path, README allowlist description, coder-executor prompt reports-dir).

---

## Fix 1 (BLOCKER) — hook `read JSON` stdin consumption

**Root cause:** each of these 4 hooks starts with `read JSON` which consumes stdin,
then calls `python -c "... json.load(sys.stdin) ..."` — python sees EOF, fails, the
`|| echo ""` fallback fires, `FILE_PATH`/`COMMAND` ends up empty, and the hook
fail-opens on `[ -z "$FILE_PATH" ] && exit 0`. All 4 hooks are currently no-ops.

**Affected files:**
- `.kimi/hooks/root-guard.sh` (line 6)
- `.kimi/hooks/framework-guard.sh` (line 7)
- `.kimi/hooks/destructive-guard.sh` (line 5)
- `.kimi/hooks/sensitive-guard.sh` (line 6)

**Recommended fix pattern** — two options, pick whichever fits Kimi's house style:

**Option A: Kiro's pattern — direct stdin to python (simplest, fewest lines)**
```bash
#!/bin/bash
# Hook ... description ...

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0
# ... existing case statement ...
```

**Option B: Claude's pattern — capture, then pipe (safer if multiple reads needed)**
```bash
#!/bin/bash
input=$(cat)
FILE_PATH=$(echo "$input" | python -c "import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')" 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0
# ... existing case statement ...
```

Apply whichever to all 4 hooks — consistency across Kimi's hook dir matters more
than Claude-vs-Kiro stylistic parity.

**Verification (critical — must pass for each hook):**

```bash
# root-guard.sh must block non-allowlisted root writes
echo '{"tool_input":{"file_path":"badfile.txt"}}' | bash .kimi/hooks/root-guard.sh
echo "exit=$?"   # MUST be exit=2 with "BLOCKED..." on stderr

# root-guard.sh must allow src/ writes
echo '{"tool_input":{"file_path":"src/app.ts"}}' | bash .kimi/hooks/root-guard.sh
echo "exit=$?"   # MUST be exit=0, no stderr

# root-guard.sh must allow ADR-approved dotfiles
echo '{"tool_input":{"file_path":".gitignore"}}' | bash .kimi/hooks/root-guard.sh
echo "exit=$?"   # MUST be exit=0

# framework-guard.sh must block .claude/ writes
echo '{"tool_input":{"file_path":".claude/settings.json"}}' | bash .kimi/hooks/framework-guard.sh
echo "exit=$?"   # MUST be exit=2

# sensitive-guard.sh must block .env
echo '{"tool_input":{"file_path":".env"}}' | bash .kimi/hooks/sensitive-guard.sh
echo "exit=$?"   # MUST be exit=2

# destructive-guard.sh must block rm -rf /
echo '{"tool_input":{"command":"rm -rf /"}}' | bash .kimi/hooks/destructive-guard.sh
echo "exit=$?"   # MUST be exit=2

# destructive-guard.sh must block DROP TABLE
echo '{"tool_input":{"command":"DROP TABLE users"}}' | bash .kimi/hooks/destructive-guard.sh
echo "exit=$?"   # MUST be exit=2
```

All 7 pipe-tests must return the expected exit code with the expected stderr.
**If any test still returns unexpected exit 0, the fix is incomplete.** Prior Wave 1
wrote off these failures as "Windows bash unreliable" — that diagnosis was wrong;
F-4 is the actual cause.

---

## Fix 2 (WARN) — `.kimi/hooks/README.md:16` stale activity-log path

**Current:** `| Activity log inject | UserPromptSubmit | — | activity-log-inject.sh | Inject top 40 lines of .ai/activity-log.md into context |`

**Fix:** change `.ai/activity-log.md` → `.ai/activity/log.md` (the actual path).
The hook script itself already uses the correct path; just the table description is stale.

---

## Fix 3 (WARN) — `.kimi/hooks/README.md:10` incomplete root allowlist description

**Current description:** `Block writes to project root except ADR Category A allowlist (AGENTS.md, README.md, CLAUDE.md, LICENSE, CHANGELOG, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, .mcp.json)`

**Fix:** extend to cover all ADR categories the actual hook allows:

    Block writes to project root except the ADR-0001 allowlist. Category A (AGENTS.md,
    README.md, CLAUDE.md, LICENSE*, CHANGELOG*, CONTRIBUTING.md, SECURITY.md,
    CODE_OF_CONDUCT.md) + Category B (.gitignore, .gitattributes) + Category C
    (.editorconfig) + Category D (.dockerignore, .gitlab-ci.yml) + Category E
    (.mcp.json, .mcp.json.example). See docs/architecture/0001-root-file-exceptions.md
    for the authoritative allowlist.

Keep the table-cell prose compact; full list can go below the table if preferred.

---

## Fix 4 (WARN) — `.kimi/agents/system/coder-executor.md` missing reports-dir note

**Context:** catalog says coder writes "Anywhere except framework dirs" but the
agent-catalog also says "Diagnosers never modify code under review. Reports go to
`.ai/reports/`." — coder is an executor, not a diagnoser, but the catalog's general
guidance (reports are diagnoser-only, `.ai/reports/` is the diagnoser output path)
should still be mentioned so coder doesn't accidentally write reports.

**Fix:** after the existing "write anywhere EXCEPT framework directories" paragraph,
add a note:

    Reports go to `.ai/reports/` via diagnoser agents (reviewer, security-auditor,
    e2e-tester) — not you. If your work surfaces something that deserves a report,
    hand back to the orchestrator for diagnoser routing instead of writing a report
    yourself.

Keep it brief; the rule is already in the SSOT agent-catalog.

---

## Steps
1. Apply Fix 1 to all 4 preToolUse hooks.
2. Run all 7 pipe-tests listed above. Record exit codes.
3. Apply Fixes 2–4 to the respective files.
4. Prepend activity-log entry.
5. Report back in chat with pipe-test results + file paths touched.

## Verification
- (a) All 4 hooks no longer contain `read JSON` before python parse
- (b) All 7 pipe-tests return expected exit codes
- (c) `.kimi/hooks/README.md:16` shows correct path `.ai/activity/log.md`
- (d) `.kimi/hooks/README.md:10` root allowlist description expanded
- (e) `.kimi/agents/system/coder-executor.md` has reports-dir note

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Wave 4 Kimi fixes (per handoff 028). Fixed F-4 read-JSON stdin bug in 4 preToolUse hooks (pattern: <A or B>). Pipe-tests pass. Fixed README path + allowlist description + coder-executor reports-dir note.
    - Files: .kimi/hooks/root-guard.sh, .kimi/hooks/framework-guard.sh, .kimi/hooks/destructive-guard.sh, .kimi/hooks/sensitive-guard.sh, .kimi/hooks/README.md, .kimi/agents/system/coder-executor.md
    - Decisions: <pattern choice + any deviations>

## Report back with
- (a) Pipe-test results (7 tests, exit code + stderr for each)
- (b) Hook-pattern choice (Option A Kiro-style vs Option B Claude-style)
- (c) Files touched (paths)
- (d) Any unexpected behavior surfaced by the pipe-tests

## When complete
Claude validates by reading the touched files + spot-checking a pipe-test. On
validation, Claude moves 028 to `done/` and coordinates with the Kiro Wave 4
handoff (014) to land a combined Wave 4 commit.
