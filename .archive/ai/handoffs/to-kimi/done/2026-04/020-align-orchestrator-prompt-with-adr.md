# Align Kimi orchestrator prompt with ADR-0001
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-18 09:25

## Goal
Kimi's orchestrator prompt still re-lists the old "only AGENTS.md / README.md /
CLAUDE.md at root" policy + a blanket "no package.json / tsconfig.json /
Dockerfile / .env" line. Both contradict `docs/architecture/0001-root-file-exceptions.md`
(ADR category A allows 8 root files, category F allows language manifests once
a language is chosen). Replace with a pointer.

This is prompt-only — Kimi's hook (`.kimi/hooks/root-guard.sh`) was already
aligned in the previous session via handoff 018, and `.kimi/steering/00-ai-contract.md`
already points to the ADR. Just the per-agent prompt is stale.

## Current state
`.kimi/agents/system/orchestrator.md` lines 7–14:

```markdown
## Root file policy

Only these files are permitted at project root:
- `AGENTS.md`
- `README.md`
- `CLAUDE.md`

No `package.json`, `tsconfig.json`, `Dockerfile`, `.env`, or similar at root. Those belong in `config/`, `infra/docker/`, `tools/`, etc. When delegating, ensure subagents respect this policy.
```

## Target state
Replace the whole section (lines 7–14) with a short ADR pointer:

```markdown
## Root file policy

The project root allowlist lives in
`docs/architecture/0001-root-file-exceptions.md`. Any root file not listed
there requires an ADR amendment before creation. When delegating, tell
subagents which directory the file belongs in (`src/`, `tests/`, `docs/`,
`infra/`, `config/`, etc.); `.kimi/hooks/root-guard.sh` will block unapproved
root writes at the tool layer.
```

Leave the rest of the file untouched (role intro, subagent list, rules,
docs-resource section).

## Verification
- (a) `.kimi/agents/system/orchestrator.md` line 7 section heading still reads
      `## Root file policy`.
- (b) The section body is the new ADR-pointer paragraph, not the old 3-file list.
- (c) The old phrase `ONLY` + the three-file enumeration no longer appears in
      the file.
- (d) The old "No `package.json`, `tsconfig.json`, `Dockerfile`, `.env`..."
      sentence is gone.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Aligned orchestrator prompt root-file policy with ADR-0001 (per
      handoff 020) — replaced re-listed allowlist with a pointer.
    - Files: .kimi/agents/system/orchestrator.md
    - Decisions: <any deviations>

## Report back with
- (a) Before/after of the replaced section.
- (b) Confirmation the rest of the file is untouched.

## When complete
Sender (claude-code) validates by reading the file. Self-review acceptable —
narrow mechanical change matching the pattern already in
`.kimi/steering/00-ai-contract.md`. On success Claude moves this file to
`.ai/handoffs/to-kimi/done/`.
