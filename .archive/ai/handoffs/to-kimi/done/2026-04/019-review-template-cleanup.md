# Review: Template cleanup Phase 2
Status: DONE
Completed: 2026-04-18 08:01
Sender: kiro-cli
Recipient: kimi-cli
Created: 2026-04-18 07:43

## Goal
Read-only review of the 7 files Kiro touched in handoff 008. Verify each
target-state bullet is satisfied. Do NOT edit any files — just read and report.
On completion, file handoff 014 to Claude with the verdict.

## Backlink
This review was requested by handoff `008-template-cleanup-plus-orch-ai-rule.md`
(sender: claude-code, executor: kiro-cli). See that file for full context on
what was changed and why.

## Files to review

1. `README.md` — placeholder title + pointer-only root-file-policy
2. `docs/api/TEMPLATE.md` — API endpoint scaffold
3. `docs/security.md` — threat model scaffold
4. `.github/CODEOWNERS` — stub, all comments
5. `.ai/sync.md` — install section with handoff wipe + LICENSE re-stamp
6. `.ai/instructions/orchestrator-pattern/principles.md` — .ai/ lede in Orchestrator section
7. `.kiro/agents/orchestrator.json` — confirm `.ai/**` in allowedPaths (no change was needed)

## Target state (from handoff 008)

- **Root `README.md`**: title/blurb → `[TODO:...]` placeholders; root-file policy
  section is a short pointer to ADR-0001 (not a re-listing); no blanket "no
  language manifests" line.
- **`docs/api/TEMPLATE.md`**: short API-reference scaffold with `[TODO:...]`
  placeholders in every section.
- **`docs/security.md`**: short threat-model / hardening scaffold with `[TODO:...]`
  placeholders + top-of-file link back to `SECURITY.md`.
- **`.github/CODEOWNERS`**: stub with commented example blocks, no active rules.
- **`.ai/sync.md`**: Bash and PowerShell install sections both include handoff-folder
  wipe (all 3 CLI queues, open + done) and LICENSE copyright re-stamp.
- **`.ai/instructions/orchestrator-pattern/principles.md`**: one-line lede at the
  top of the Orchestrator-role section stating `.ai/**` is a direct write path.
- **`.kiro/agents/orchestrator.json`**: `.ai/**` in `toolsSettings.fs_write.allowedPaths`
  (was already present — confirmed, not changed).

## Verification checklist

Walk each item. For each, state PASS or FAIL with file + line references.

- (a) Root `README.md` has placeholder title + pointer-only root-file-policy
      section; no language-manifest blanket "no".
- (b) `docs/api/TEMPLATE.md` exists with `[TODO:...]` placeholders in every section.
- (c) `docs/security.md` exists with `[TODO:...]` placeholders + top-of-file link
      back to `SECURITY.md`.
- (d) `.github/CODEOWNERS` exists, file is all comments, no active rules.
- (e) `.ai/sync.md` Bash and PowerShell sections both include the handoff-folder
      wipe + LICENSE re-stamp.
- (f) `.ai/instructions/orchestrator-pattern/principles.md` has the `.ai/` lede
      at the top of the Orchestrator-role section.
- (g) `.kiro/agents/orchestrator.json` allows `.ai/**` writes (confirmed
      pre-existing by Kiro).
- (h) This handoff (019) exists and addresses Kimi with the review scope.

## Steps

1. Read each of the 7 files listed above.
2. Walk the verification checklist (a)–(h).
3. Write your verdict and findings into handoff 014 to Claude (see below).

## Handoff 014 to Claude

After completing the review, file `.ai/handoffs/to-claude/open/014-final-review-template-cleanup.md`.
Include in that handoff:

- Verdict: `clean — merge` or `issues — back to Kiro`
- Verification checklist results (a)–(h) with PASS/FAIL and file+line references
- Backlinks to handoff 008 (original) and 019 (this review)
- Any issues found with specific file + line references

## Activity log template

    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Read-only review of template cleanup Phase 2 (per handoff 019,
      originating from 008). Filed handoff 014 to Claude with verdict.
    - Files: —
    - Decisions: <any observations or flags>

## Report back with
- (a) Verdict: clean or issues
- (b) Checklist results (a)–(h)
- (c) Handoff 014 filed to Claude (confirm path)

## When complete
Sender (kiro-cli) validates by reading handoff 014. On success, moves this file
to `.ai/handoffs/to-kimi/done/`. On failure, leaves it in `open/` with
`Status: BLOCKED` and a `## Blocker` section.
