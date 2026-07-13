# Apply the Auto:-boundary rule to the operating-prompt SSOT + CLAUDE.md/AGENTS.md (verbatim text inside)
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 10:16
Auto: yes
Risk: B
Base: origin/master

## Why this is in your lane

Handoff `to-kimi/202607130250` (cockpit-vs-pane ownership; DONE on branch
`exec/kimi/202607130250-cockpit-pane-handoff-ownership`, PR open) shipped
`.ai/tools/claim-handoff.sh` + `release-handoff.sh` and the
`.ai/handoffs/README.md` rule. The remaining doc items are yours:

1. The operating-prompt SSOT one-liner. I drafted it and verified it locally
   (sync-replicas + `check-ssot-drift.sh` → Drift 0 with all 3 replicas), but
   **kimi cannot commit it**: the pre-commit hook's atomic SSOT-sync gate
   (ADR-0005 second amendment) requires SSOT source + ALL replicas in one
   commit, while its territory gate forbids kimi from staging the `.claude/`
   and `.kiro/` replicas — only `claude-code` has the registered-replica
   exception (`scripts/git-hooks/pre-commit:78-93` vs `:95-98`). History
   agrees: every commit touching `.claude/skills/operating-prompt/SKILL.md`
   is claude-code's (latest a64002f; the 8163372→f8def53 split predates the
   atomic gate). So the exact text is below for you to apply as one atomic
   commit (your hook auto-stages the replicas).
2. The CLAUDE.md / AGENTS.md contract line — the handoff named you custodian
   (ADR-0001) and forbade me to edit them.
3. The ratifying ADR — the handoff reserved ADR authorship to you; the
   implementation is green (counts below).

## Apply verbatim — operating-prompt SSOT

File: `.ai/instructions/operating-prompt/principles.md` §7, immediately after
the "**Handoff protocol v3:**" paragraph (the one ending "…leave it in `open/`
as `BLOCKED` with a verbatim `## Blocker` section."), insert this paragraph:

    **The `Auto:` tag is the ownership boundary.** `Auto: yes` + Risk A/B belongs
    to the auto pane — a cockpit must not hand-take it; `Auto: no` / Risk C is
    cockpit-owned. A cockpit taking an `Auto: yes` handoff (pane down,
    quarantined, owner waiting live) must FIRST run `bash .ai/tools/claim-handoff.sh
    <path>` (flips `Auto: no` + claim sidecar, atomically); `release-handoff.sh`
    reverts. Symmetric across all four CLIs.

Then run `bash .ai/tools/sync-replicas.sh` (your hook does this on commit) and
confirm `bash .ai/tools/check-ssot-drift.sh` → `Drift: 0`.

## Apply verbatim — CLAUDE.md + AGENTS.md line

Suggested placement: AGENTS.md in the "Cross-CLI handoffs" section (after the
Protocol v3 paragraph); CLAUDE.md wherever it restates the handoff protocol —
one line each, identical text:

    The `Auto:` tag is the ownership boundary: `Auto: yes` + Risk A/B belongs to the auto pane (a cockpit must not hand-take it), `Auto: no` / Risk C is cockpit-owned; a cockpit takes an `Auto: yes` handoff only by first running `bash .ai/tools/claim-handoff.sh <path>` (atomically flips `Auto: no` + claim sidecar; `release-handoff.sh` reverts).

## Evidence the implementation is green (executed, not inspected)

- `tools/4ai-panes/test-claim-handoff.ps1` (new sibling suite — drives the
  REAL `Get-QualifyingHandoff`, :594-596 gate): **23 passed, 0 failed**.
- `tools/4ai-panes/test-pane-runner.ps1` (existing): **132 passed, 0 failed**
  (baseline before the work was also 132/0 — no regression).
- claim-handoff.sh transcripts (refuse live-foreign-pid / reclaim dead-pid /
  idempotent) are in the retired handoff's Completion note:
  `.ai/handoffs/to-kimi/done/202607130250-cockpit-pane-handoff-ownership.md`.

## Two observations for the ADR (surfaced during implementation)

1. **Risk C + `Auto: yes` reads ambiguously.** The rule makes Risk C
   cockpit-owned regardless of `Auto:`, and the pane gate (:596) already
   enforces that — but a skimmer reading only the `Auto:` line can misjudge.
   Recommend the ADR state explicitly: `claim-handoff.sh` is needed ONLY for
   `Auto: yes` + Risk A/B; Risk C is cockpit-owned without any claim.
2. **Owner-string collision for 3 of 4 CLIs.** `pane-runner.ps1
   Get-DefaultOwner` maps kimi→kimi-cli, kiro→kiro-cli, opencode→opencode —
   the same strings a cockpit naturally uses, so a claim sidecar cannot
   distinguish pane-vs-cockpit for them (only claude splits
   claude-auto/claude-code). Both tools accept `--owner`; consider documenting
   a `<cli>-cockpit` convention. claim-handoff.sh's idempotent no-op is keyed
   on owner+host+Auto-already-`no` (a re-run is a fresh pid, so pid cannot be
   the identity) — safe today, but the ADR may want to pin this down.

## When complete (protocol v3)

Self-retire: set Status `DONE`, move to `.ai/handoffs/to-claude/done/`. Do NOT
merge kimi's PR — merging is OpenCode's Tier-B lane (or the owner's).
