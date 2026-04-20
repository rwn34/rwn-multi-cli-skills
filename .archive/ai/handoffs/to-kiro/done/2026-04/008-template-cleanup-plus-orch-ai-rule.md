# Template cleanup (Phase 2) + surface the orchestrator `.ai/` write rule
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-04-18 00:35

## Goal
Close the minor gaps from Claude's template review so this repo can be cloned as
a fresh project starter without hand-editing, and make the "orchestrator reads +
writes `.ai/` directly — no delegation" rule unambiguous in the SSOT (already
stated, but buried). When Kiro finishes, a review flows through Kimi back to
Claude for final sign-off.

## Current state
Claude just reviewed the template and flagged these gaps (see activity log entry
at 00:30 `claude-code` once it lands, or the chat summary that preceded this
handoff):

1. Root `README.md` is stale — states only `AGENTS.md / README.md / CLAUDE.md`
   are allowed at root; `docs/architecture/0001-root-file-exceptions.md` now
   permits 8 more (LICENSE, CHANGELOG, SECURITY, CODE_OF_CONDUCT, CONTRIBUTING,
   and the dotfile quartet `.gitignore / .gitattributes / .editorconfig / .mcp.json*`).
2. Same file also says "No `package.json`, `tsconfig.json`, `Dockerfile`, `.env`,
   etc. at root" — ADR category F allows those by amendment once a language is
   chosen. The flat "no" is misleading.
3. Same file is hardcoded to `# rwn-multi-cli-skills`. As a project starter it
   should be a `[TODO:...]` placeholder.
4. `docs/api/TEMPLATE.md` missing — but `docs/README.md` lists `api/` as a
   subdir.
5. `docs/security.md` missing — but `SECURITY.md` forwards readers to it.
6. `.github/CODEOWNERS` absent (optional; GitHub expects it for auto-reviewers).
7. `.ai/sync.md` "project-agnostic install" command doesn't reset the handoff
   `done/` folders or re-stamp the `LICENSE` year — cloned projects inherit ~30
   historical handoffs + last year's copyright.
8. `.ai/instructions/orchestrator-pattern/principles.md` already states that the
   orchestrator can write `.ai/` (line 13–15 + the write-path table), but the
   user wants the rule surfaced to the top of the Orchestrator-role section so
   no orchestrator (any CLI) mistakenly delegates `.ai/` edits.

## Target state
After this pass:
- **Root `README.md`**: title/blurb → `[TODO:...]` placeholders; root-file policy
  section is a short pointer to ADR-0001 (not a re-listing); "no language
  manifests" line softened to reference category F.
- **`docs/api/TEMPLATE.md`**: short API-reference scaffold matching the style of
  the other `docs/*/TEMPLATE.md` files.
- **`docs/security.md`**: short threat-model / hardening scaffold.
- **`.github/CODEOWNERS`**: stub with a single commented example block.
- **`.ai/sync.md`**: install command extended with (a) wipe of
  `.ai/handoffs/to-*/{open,done}/*`, (b) LICENSE copyright re-stamp.
- **`.ai/instructions/orchestrator-pattern/principles.md`**: one-line lede at the
  top of the Orchestrator-role section stating `.ai/**` is a direct write path.
- **`.kiro/agents/orchestrator.json`**: confirm `.ai/**` is in
  `toolsSettings.fs_write.allowedPaths`; add if missing.
- **Review flow queued**: Kiro files handoff `019-review-template-cleanup.md` to
  Kimi; Kimi will file `014-final-review-template-cleanup.md` to Claude.

## Steps
Do them in this order. Root `README.md` first (most externally visible); SSOT
wording last among the edit steps so the review flow covers it.

### 1. Update root `README.md`
Replace the title + blurb with placeholders and replace the Root-file-policy
section with a pointer. Keep the "Project structure" and "AI framework" sections
as-is.

New title block (lines 1–3):
```markdown
# [TODO: project name]

[TODO: one-sentence project description]
```

New Root-file-policy section (replaces lines 5–14 of the current file):
```markdown
## Root file policy

Root is strict. The authoritative allowlist lives in
`docs/architecture/0001-root-file-exceptions.md` — new root files require an
ADR amendment before creation. The `.claude/hooks/pretool-write-edit.sh` hook
and the Kimi/Kiro equivalents enforce this at the tool layer.
```

Leave "Project structure" (the tree) and "AI framework (dot-prefixed)" intact.

### 2. Create `docs/api/TEMPLATE.md`
Short scaffold, ~40 lines, `[TODO:...]` placeholders. Section outline:
- `# [TODO: Endpoint / operation name] — API`
- HTML comment: "Copy to `docs/api/<short-slug>.md`"
- `## Summary`
- `## Endpoint` (method + path + auth requirement)
- `## Request` (params / body / headers table)
- `## Response` (success shape)
- `## Errors` (status → meaning table)
- `## Examples` (curl + response snippet)
- `## Notes` (rate limits, idempotency, deprecation, etc.)

### 3. Create `docs/security.md`
Short scaffold, ~50 lines, `[TODO:...]` placeholders. Section outline:
- `# Security — threat model and hardening notes`
- Link at top back to root `SECURITY.md` (disclosure channel)
- `## Threat model` — brief
- `## Assets` — what we're protecting
- `## Trust boundaries` — where untrusted input crosses in
- `## Known risks & mitigations` — table: risk / mitigation / status
- `## Hardening notes` — TLS, secret management, dependency policy, auth
- `## Dependencies & CVE policy` — how updates are handled

### 4. Create `.github/CODEOWNERS`
```
# Ownership rules for auto-requesting reviewers on PRs.
# Format: <path pattern> <@user-or-team> [<@user-or-team2> ...]
# See https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
#
# Examples (uncomment + customize when contributors are assigned):
# *.md                    @docs-team
# /src/                   @engineering
# /infra/                 @platform
```

### 5. Extend `.ai/sync.md` project-agnostic install
After the existing `cp -R .ai CLAUDE.md .claude .kimi .kiro <target>/` block,
append post-copy cleanup for both Bash and PowerShell sections:

Bash:
```bash
# Reset cross-CLI handoff history — cloned project starts with empty queues
rm -rf <target>/.ai/handoffs/to-claude/{open,done}/*
rm -rf <target>/.ai/handoffs/to-kimi/{open,done}/*
rm -rf <target>/.ai/handoffs/to-kiro/{open,done}/*

# Reset activity log to an empty header (existing step — keep as-is)
printf '# Activity Log\n\nNewest entries at the top. Each CLI prepends before finishing substantive work.\n\n---\n\n' > <target>/.ai/activity/log.md

# Reset LICENSE placeholders — year + author are template TODOs
sed -i.bak 's/Copyright (c) 2026 \[TODO: project author \/ organization\]/Copyright (c) [TODO: YEAR] [TODO: project author]/' <target>/LICENSE && rm -f <target>/LICENSE.bak
```

PowerShell:
```powershell
Remove-Item -Recurse -Force <target>/.ai/handoffs/to-claude/open/*, <target>/.ai/handoffs/to-claude/done/*
Remove-Item -Recurse -Force <target>/.ai/handoffs/to-kimi/open/*, <target>/.ai/handoffs/to-kimi/done/*
Remove-Item -Recurse -Force <target>/.ai/handoffs/to-kiro/open/*, <target>/.ai/handoffs/to-kiro/done/*

(Get-Content <target>/LICENSE) -replace 'Copyright \(c\) 2026 \[TODO: project author / organization\]', 'Copyright (c) [TODO: YEAR] [TODO: project author]' | Set-Content <target>/LICENSE
```

### 6. Update `.kiro/agents/orchestrator.json`
Read the file. If `.ai/**` (or equivalent pattern) is already in
`toolsSettings.fs_write.allowedPaths`, no change — just note that in the
handback. If absent, add it alongside `.kiro/**`.

While there, flag in the handback (don't edit) whether Claude's
`.claude/agents/orchestrator.md` and Kimi's `.kimi/agents/orchestrator.yaml`
appear to have the same allowance. You can read them to check — you just can't
edit them. Claude's already does (confirmed before this handoff was written).

### 7. Update `.ai/instructions/orchestrator-pattern/principles.md`
At the top of the `### Orchestrator (default agent)` section (currently line
19), immediately under the `**Purpose:** Consult, plan, analyze, delegate.`
line, insert this lede:

```markdown
> **`.ai/` is a direct write path for orchestrators — no delegation.** Handoffs,
> activity-log entries, research docs, reports, and SSOT instruction edits are
> all the orchestrator's direct responsibility. This rule is the same across
> all three CLIs: Claude Code, Kimi CLI, Kiro CLI.
```

Leave the rest of the principles file intact (the same rule is elaborated in the
write-path restriction table below; this one-liner is the lede so it can't be
missed).

### 8. Prepend activity log entry
Use your `kiro-cli` identity. One entry for the whole Phase 2 pass:

    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Template cleanup Phase 2 (per handoff 008) — README pointer-ification,
      docs/api + docs/security stubs, CODEOWNERS, sync.md install hardening,
      orchestrator-pattern .ai/ lede, Kiro orchestrator allowlist check
    - Files: README.md, docs/api/TEMPLATE.md, docs/security.md, .github/CODEOWNERS,
      .ai/sync.md, .ai/instructions/orchestrator-pattern/principles.md,
      .kiro/agents/orchestrator.json (if changed)
    - Decisions: <any scope deviations; note whether Claude's/Kimi's orch configs
      need matching fs_write updates — Kiro can't edit those>

### 9. File the review handoff to Kimi
Write `.ai/handoffs/to-kimi/open/019-review-template-cleanup.md`. Scope:
read-only review of the 7 files Kiro touched + confirmation that each
verification bullet (a)–(g) below is satisfied. Kimi should NOT edit anything
during this review — just read + report. Kimi's report goes to Claude via
`.ai/handoffs/to-claude/open/014-final-review-template-cleanup.md`.

Include in handoff 019: a backlink to this handoff (008), the full target-state
list, and the verification checklist. Kimi's report to Claude (014) should
include: verdict (clean / issues), any issues found with file+line references,
a pointer to 008 and 019.

## Verification
- (a) Root `README.md` has placeholder title + pointer-only root-file-policy
      section; no language-manifest blanket "no".
- (b) `docs/api/TEMPLATE.md` exists with `[TODO:...]` placeholders in every
      section.
- (c) `docs/security.md` exists with `[TODO:...]` placeholders + top-of-file
      link back to `SECURITY.md`.
- (d) `.github/CODEOWNERS` exists, file is all comments, no active rules.
- (e) `.ai/sync.md` Bash and PowerShell sections both include the handoff-folder
      wipe + LICENSE re-stamp.
- (f) `.ai/instructions/orchestrator-pattern/principles.md` has the `.ai/` lede
      at the top of the Orchestrator-role section.
- (g) `.kiro/agents/orchestrator.json` allows `.ai/**` writes (either confirmed
      pre-existing or newly added). Handback explicitly states which.
- (h) Handoff 019 created and addresses Kimi with the review scope.

## Report back with
- (a) List of files touched with line counts (or "no change" for the Kiro orch
      config if it was already correct).
- (b) Whether `.kiro/agents/orchestrator.json` needed a change, or was already
      correct. If changed, show the added allowlist pattern.
- (c) Whether Claude's `.claude/agents/orchestrator.md` and Kimi's
      `.kimi/agents/orchestrator.yaml` appear to already allow `.ai/**` writes.
      Flag only — don't edit. Claude's is confirmed OK (lines 13–16 of that
      file); Kiro just needs to spot-check Kimi's.
- (d) Handoff number Kiro filed with Kimi (expected: 019).
- (e) Any scope deviations from this handoff — what was kept, dropped, or
      reshaped, with one-line rationale.

## Flow after Kiro
1. **Kimi review** (via handoff 019): Kimi reads the touched files, walks the
   verification checklist (a)–(h), and either signs off or flags specific
   issues. Kimi does not edit any files during review.
2. **Kimi → Claude** (via handoff 014): Kimi reports "clean — merge" or
   "issues — back to Kiro". Both outcomes include verification-checklist
   results and file/line references for any issues.
3. **Claude final review**: Claude reads the touched files, cross-checks Kimi's
   review, and either (a) moves handoff 008 to `done/` (clean path) or (b)
   sends a follow-up handoff to Kiro with the specific fixes needed
   (issues path). If issues are minor, Claude may also handle them directly
   within framework-dir write scope.

## When complete
Sender (claude-code) validates by reading the files Kiro touched AND reading
Kimi's review in handoff 014. On success, moves THIS file (handoff 008) to
`.ai/handoffs/to-kiro/done/` — leave 019 and 014 for their respective senders
to move per normal protocol. On failure, this file stays in `open/` with
`Status: BLOCKED` and a `## Blocker` section describing what's missing.
