# Wave 4 Kiro fixes — doc-writer glob + sensitive pattern + allowlists + destructive-guard
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-19 16:45

## Context
User approved the Wave 4 fix plan after Claude + Kiro 2026-04-19 audits converged
on 2 BLOCKERs and the WARN list. This supersedes the open vote handoff
(`013-audit-consensus-vote.md`) — no more voting needed; fix dispatch proceeds.

See `.ai/reports/consolidated-audit-2026-04-19.md` for the full 22-finding matrix
and `.ai/reports/claude-vote-on-kiro-audit-2026-04-19.md` for Claude's votes that
informed this wave.

Your audit surfaced both BLOCKERs (F-3 doc-writer, F-4 Kimi stdin) — strong work.
This wave fixes F-3 on Kiro's side + 4 bundled WARNs.

---

## Fix 1 (BLOCKER) — `.kiro/agents/doc-writer.json` `**/*.md` bypasses framework-dir restriction

**Current allowedPaths:**
```json
"allowedPaths": [
  "**/*.md",
  "docs/**",
  "CHANGELOG*",
  "LICENSE*",
  "README*",
  ".ai/reports/**"
]
```

**Problem:** `**/*.md` matches ANY `.md` file in the repo — including
`.kimi/steering/*.md`, `.claude/agents/*.md`, `.ai/instructions/**/*.md`. Combined
with the fact that `framework-dir-guard.sh` is only wired in `orchestrator.json`
(not subagent configs), a doc-writer subagent can silently bypass the edit-boundary rule.

**Fix:** narrow `allowedPaths` to root-level + docs-subtree only:

```json
"allowedPaths": [
  "*.md",
  "docs/**/*.md",
  "docs/**",
  "CHANGELOG*",
  "LICENSE*",
  "README*",
  "CONTRIBUTING.md",
  "SECURITY.md",
  "CODE_OF_CONDUCT.md",
  ".ai/reports/**"
]
```

Rationale:
- `*.md` (no `**`) only matches root-level `.md` — one level deep, no traversal
- `docs/**/*.md` and `docs/**` covers the docs subtree (need both — `docs/**/*.md` catches nested, `docs/**` catches non-md like images/templates)
- Named root files `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` are explicit (ADR category A)
- `.ai/reports/**` stays (doc-writer can write documentation-audit reports)

This matches catalog's stated scope: "`*.md`, `docs/**`, `CHANGELOG*`, `LICENSE*`,
`README*`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `.ai/reports/`"
— except spelled out as Kiro glob patterns.

**Verification:** after editing, pipe-test that doc-writer cannot write to framework dirs:

```bash
# Simulate a doc-writer write to .kimi/steering/ — should be blocked by allowedPaths
# (not hooks — Kiro's fs_write restriction is hard-config-level)
# Verification: cat .kiro/agents/doc-writer.json | grep -A 15 allowedPaths
# — confirm **/*.md is gone, replaced by narrower patterns
```

JSON must remain valid — run `python -m json.tool .kiro/agents/doc-writer.json` to
verify.

---

## Fix 2 (WARN) — `.kiro/hooks/sensitive-file-guard.sh` missing `id_ed25519*`

**Current (line 11):**
```bash
case "$BASE" in
  .env|.env.*|*.key|*.pem|id_rsa*|*.p12|*.pfx) echo "BLOCKED: ..." ; exit 2 ;;
esac
```

**Fix:** add `id_ed25519*` to the alternation list. Ed25519 is the modern SSH key
default; `id_rsa*`-only leaves a real gap.

```bash
case "$BASE" in
  .env|.env.*|*.key|*.pem|id_rsa*|id_ed25519*|*.p12|*.pfx) echo "BLOCKED: ..." ; exit 2 ;;
esac
```

**Verification:**
```bash
echo '{"tool_input":{"file_path":"id_ed25519"}}' | bash .kiro/hooks/sensitive-file-guard.sh
echo "exit=$?"  # MUST be 2
```

---

## Fix 3 (WARN) — `.kiro/agents/tester.json` missing `*_test.*` and `*_spec.*` patterns

Catalog's "Test files (tester)" scope lists:
> `tests/**`, `test/**`, `**/__tests__/**`, `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `conftest.py`, `jest.config.*`, `pytest.ini`, `.coveragerc`

**Fix:** add the missing patterns to `tester.json` `allowedPaths`. Don't replace —
add alongside existing patterns. Keep JSON valid.

Final `allowedPaths` should include at minimum:
- `tests/**`, `test/**`
- `**/__tests__/**`
- `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`  ← add `*_test.*` + `*_spec.*`
- `conftest.py`, `jest.config.*`, `pytest.ini`, `.coveragerc`, `vitest.config.*`
- `.ai/reports/**`

---

## Fix 4 (WARN) — `.kiro/agents/e2e-tester.json` missing E2E-specific patterns

Catalog's "E2E test files" scope is superset of tester + E2E dirs:
> Plus E2E-framework dirs: `e2e/**`, `tests/e2e/**`, `**/*.e2e.*`, `playwright/**`, `cypress/**`. Plus E2E config files: `playwright.config.*`, `cypress.config.*`.

**Fix:** ensure `e2e-tester.json` `allowedPaths` includes at minimum:
- All the tester patterns (or a reference / rely on subagent-composition)
- `e2e/**`, `tests/e2e/**`
- `**/*.e2e.*`
- `playwright/**`, `cypress/**`
- `playwright.config.*`, `cypress.config.*`
- `.ai/reports/**`

Audit flagged missing: `playwright/**`, `**/*.e2e.*`, `playwright.config.*`, `cypress.config.*`.

---

## Fix 5 (WARN — my AMEND of your INFO-severity I-4) — destructive-cmd-guard lowercase normalize

**Current pattern (lines 13–15):**
```bash
case "$CMD" in
  ...
  *"DROP DATABASE"*|*"DROP TABLE"*|*"DROP SCHEMA"*|*"drop database"*|*"drop table"*|*"drop schema"*) ... ;;
  *"TRUNCATE TABLE"*|*"truncate table"*) ... ;;
esac
```

**Problem:** literal case match misses mixed-case like `Drop Database`, `Truncate Table`.
Kiro's guard has both uppercase and lowercase variants, but middle-cap variants bypass.

**Fix:** normalize once at the top, then match lowercase only. Mirrors Kimi's pattern.

```bash
CMD_LOWER=$(echo "$CMD" | tr '[:upper:]' '[:lower:]')
case "$CMD_LOWER" in
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf *"*|*"rm -rf ."*) echo "BLOCKED: Destructive command — rm -rf with dangerous target." >&2; exit 2 ;;
  *"git push --force"*|*"git push -f "*|*"git push --force-with-lease"*) echo "BLOCKED: Force-push not allowed. Use release-engineer for controlled pushes." >&2; exit 2 ;;
  *"git reset --hard"*) echo "BLOCKED: Hard reset not allowed without explicit user approval." >&2; exit 2 ;;
  *"drop database"*|*"drop table"*|*"drop schema"*) echo "BLOCKED: Destructive SQL — DROP not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
  *"truncate table"*) echo "BLOCKED: Destructive SQL — TRUNCATE not allowed via hook. Use data-migrator with reversible migrations." >&2; exit 2 ;;
esac
```

**Verification:**
```bash
echo '{"tool_input":{"command":"Drop Database production"}}' | bash .kiro/hooks/destructive-cmd-guard.sh
echo "exit=$?"  # MUST be 2 (was 0 before fix)

echo '{"tool_input":{"command":"TrUnCaTe TaBlE users"}}' | bash .kiro/hooks/destructive-cmd-guard.sh
echo "exit=$?"  # MUST be 2

echo '{"tool_input":{"command":"echo hello"}}' | bash .kiro/hooks/destructive-cmd-guard.sh
echo "exit=$?"  # MUST be 0
```

---

## NOT in this handoff (deferred to Wave 4c)

- **Finding #8 (F-5) hook inheritance verification** — empirically test whether
  Kiro runtime inherits orchestrator-registered hooks to spawned subagents.
  Test approach: dispatch trivial coder task that tries to write `evil.txt` at
  root; observe whether `root-file-guard.sh` fires. If not, all 12 subagent
  configs need their own `hooks` section wired. Please do this test and report
  back; don't modify anything yet — the fix is a big batch change only warranted
  if inheritance is broken.

- **Finding I-2 (infra-engineer.json prompt-text drift)** — cosmetic; prompt
  mentions stale paths while `allowedPaths` is correctly tightened. Downgraded
  to INFO per Claude's vote. Fix if you're in the file anyway; otherwise skip.

- **Finding B-2 (`docs/*/TEMPLATE.md` move to `docs/_templates/`)** — Wave 5,
  dispatched via doc-writer after this wave lands.

---

## Steps
1. Apply Fix 1 to `.kiro/agents/doc-writer.json`. Verify JSON valid.
2. Apply Fix 2 to `.kiro/hooks/sensitive-file-guard.sh`. Pipe-test `id_ed25519`.
3. Apply Fix 3 to `.kiro/agents/tester.json`. Verify JSON valid.
4. Apply Fix 4 to `.kiro/agents/e2e-tester.json`. Verify JSON valid.
5. Apply Fix 5 to `.kiro/hooks/destructive-cmd-guard.sh`. Pipe-test mixed-case inputs.
6. Run `python -m json.tool` on all 3 edited JSONs to confirm validity.
7. Perform the hook-inheritance test (Wave 4c item above) — **test only, don't fix if broken**.
8. Prepend activity-log entry.
9. Report back with pipe-test results + JSON validity + hook-inheritance verdict.

## Verification
- (a) `doc-writer.json` no longer has `**/*.md`; has narrower patterns
- (b) `sensitive-file-guard.sh` blocks `id_ed25519` (pipe-test passes)
- (c) `tester.json` includes `*_test.*`, `*_spec.*`
- (d) `e2e-tester.json` includes `playwright/**`, `**/*.e2e.*`, `playwright.config.*`, `cypress.config.*`
- (e) `destructive-cmd-guard.sh` blocks `Drop Database` (mixed case) — pipe-test passes
- (f) All edited JSONs parse as valid JSON
- (g) Hook-inheritance test result reported (doesn't need fix this wave; informs Wave 4c)

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Wave 4 Kiro fixes (per handoff 014). Tightened doc-writer.json (BLOCKER F-3). Added id_ed25519* to sensitive-guard. Added missing test patterns to tester.json + e2e-tester.json. Lowercase-normalized destructive-cmd-guard. Verified hook-inheritance empirically (<result>).
    - Files: .kiro/agents/doc-writer.json, .kiro/hooks/sensitive-file-guard.sh, .kiro/agents/tester.json, .kiro/agents/e2e-tester.json, .kiro/hooks/destructive-cmd-guard.sh
    - Decisions: <inheritance verdict, any deviations from proposed patterns>

## Report back with
- (a) Files touched (paths)
- (b) Pipe-test results for sensitive-file-guard (id_ed25519) + destructive-cmd-guard (Drop Database + TrUnCaTe TaBlE + echo hello)
- (c) JSON validity for the 3 edited agent configs
- (d) **Hook-inheritance test verdict** — does subagent spawn inherit orchestrator's `root-file-guard.sh`, or does it bypass? Answer decides whether Wave 4c needs to wire hooks on all 12 subagent configs.

## When complete
Claude validates by reading the touched files. On validation, Claude moves 014 to
`done/` and coordinates with the Kimi Wave 4 handoff (028) to land a combined
Wave 4 commit via infra-engineer.

## Note on handoff numbering
This is 014 because 010 (user's audit dispatch) is still open, 011 and 012 landed
Waves 1 and 2+3 respectively, 013 is the now-superseded vote handoff. 014 is next
unused per-recipient across open+done.
