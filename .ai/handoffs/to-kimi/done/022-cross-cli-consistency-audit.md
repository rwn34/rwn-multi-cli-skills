# Cross-CLI consistency audit — Kimi review
Status: OPEN
Sender: user
Recipient: kimi-cli
Created: 2026-04-18 10:35

## Goal
Independent read-only audit of the entire multi-CLI framework from Kimi's
perspective. Check for: (1) **inconsistencies** — the same rule stated
differently in two places, (2) **flaws** — gaps, contradictions, or live bugs,
(3) **bloat** — duplication, over-verbosity, or dead weight that could be
consolidated or deleted.

## Scope

### Tier 1 — shared policy layer (highest priority)
Files Kimi can read:
- `README.md` — root policy pointer, project structure, AI framework map
- `AGENTS.md` — cross-CLI contract pointers
- `docs/architecture/0001-root-file-exceptions.md` — ADR, the authority
- `CLAUDE.md` — Claude's always-loaded contract (read-only for Kimi)
- `.ai/README.md` — SSOT layout explanation
- `.ai/sync.md` — copy-command map, install instructions
- `.ai/instructions/orchestrator-pattern/principles.md` — SSOT pattern spec
- `.ai/instructions/agent-catalog/principles.md` — SSOT agent roster
- `.ai/instructions/karpathy-guidelines/principles.md` — SSOT coding guidelines
- `.ai/handoffs/README.md` — handoff protocol
- `.ai/handoffs/template.md` — handoff file shape
- `.ai/activity/log.md` — last ~20 entries (format consistency)

### Tier 2 — Kimi-native layer (own folder)
Files Kimi can read + edit:
- `.kimi/steering/00-ai-contract.md`
- `.kimi/steering/orchestrator-pattern.md`
- `.kimi/steering/agent-catalog.md`
- `.kimi/steering/karpathy-guidelines.md`
- `.kimi/agents/system/orchestrator.md`
- `.kimi/agents/system/*.md` — all 13 agent prompts
- `.kimi/agents/*.yaml` — all 13 agent configs
- `.kimi/hooks/*.sh` — hook scripts
- `.kimi/steering/*.md` — any other steering

### Tier 3 — cross-check against sibling CLIs (read-only)
Files Kimi can read but NOT edit:
- `.kiro/steering/00-ai-contract.md`
- `.kiro/steering/orchestrator-pattern.md`
- `.kiro/agents/orchestrator.json`
- `.kiro/hooks/root-file-guard.sh`
- `.claude/agents/orchestrator.md`
- `.claude/hooks/pretool-write-edit.sh`

### Tier 4 — handoff queue hygiene
- `.ai/handoffs/to-kimi/open/` — any stale open handoffs?
- `.ai/handoffs/to-kimi/done/` — any that should have been moved by sender?
- `.ai/handoffs/to-claude/open/014-final-review-template-cleanup.md` — still open; is Kimi the sender who should move it?

## Checklist — what to look for

### (A) Inconsistencies
- [ ] Root-file policy: does every file that mentions root files point at ADR-0001?
  Flag any file that still re-lists an allowlist inline.
- [ ] Agent roster: does every roster mention the same 13 agents by the same names?
  (Kimi uses `coder-executor`; others use `coder` — that's a known naming delta,
  not an inconsistency unless it causes confusion.)
- [ ] Write-path restriction: does every orchestrator prompt agree on `.ai/**`,
  `.kiro/**`, `.kimi/**`, `.claude/**` as the framework set?
- [ ] Hook coverage: does Kimi's `.kimi/hooks/root-guard.sh` allow the same
  ADR category A files as `.claude/hooks/pretool-write-edit.sh` and
  `.kiro/hooks/root-file-guard.sh`?
- [ ] Activity-log format: does `.kimi/steering/00-ai-contract.md` match the
  format rules in `AGENTS.md` / `.ai/activity/log.md`?
- [ ] Sync map: does `.ai/sync.md` list the correct source→destination pairs?
  Are there instructions in `.ai/instructions/` that are NOT mapped?

### (B) Flaws
- [ ] Gaps: any rule stated in one place but missing in another where it should
  also appear? (e.g., archive-skip rule is in contracts — is it in all agent
  prompts that read files?)
- [ ] Contradictions: two files giving opposite advice for the same situation.
- [ ] Live bugs: any hook that would block a legitimate write, or any prompt
  that would misdirect a subagent.
- [ ] Missing files: any referenced file that doesn't exist.
- [ ] Broken links: any markdown link pointing to a non-existent path.

### (C) Bloat
- [ ] Duplication: same paragraph appearing in >2 files. Could one be a pointer?
- [ ] Over-verbosity: sections that could be half as long without losing meaning.
- [ ] Dead weight: placeholder files, empty directories, or scaffold sections
  that have been `[TODO:...]` for multiple sessions with no plan to fill them.
- [ ] Overlapping scopes: two agents whose responsibilities blur together;
  could they merge?
- [ ] Redundant handoffs: old `done/` files that are just noise now.

## Output format

Write findings to `.ai/reports/kimi-audit-2026-04-18.md` with this structure:

```markdown
# Kimi CLI consistency audit — 2026-04-18

## Inconsistencies
| # | Rule | File A (says X) | File B (says Y) | Severity |

## Flaws
| # | Category | File + line | Description | Severity |

## Bloat
| # | Type | Location | Rationale for removal/consolidation | Savings |

## Clean — no findings
<List any tier that returned zero issues, for confidence.>
```

Severity: `BLOCKER` (fix before next feature), `WARN` (fix this session),
`INFO` (nice-to-have cleanup).

## Constraints
- **Read-only audit.** Do not edit any file. If you find a flaw that needs
  fixing, report it — don't patch it silently.
- Report on ALL tiers, even if some come back clean. "Zero findings in Tier 3"
  is useful signal.
- If a finding requires cross-CLI coordination, flag it as such and suggest
  which CLI should own the fix.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Cross-CLI consistency audit (per handoff 022). Read ~30 files across
      shared policy + Kimi-native + sibling-CLI layers. Wrote findings report.
    - Files: .ai/reports/kimi-audit-2026-04-18.md
    - Decisions: <any deviations from scope; any findings flagged for immediate fix>

## When complete
Sender (user) reads the report. On validation, moves this handoff to
`.ai/handoffs/to-kimi/done/`. If findings include BLOCKER-level items, sender
may spawn follow-up handoffs to the owning CLI(s).
