# Cross-CLI consistency audit — Kiro review
Status: OPEN
Sender: user
Recipient: kiro-cli
Created: 2026-04-18 10:35

## Goal
Independent read-only audit of the entire multi-CLI framework from Kiro's
perspective. Check for: (1) **inconsistencies** — the same rule stated
differently in two places, (2) **flaws** — gaps, contradictions, or live bugs,
(3) **bloat** — duplication, over-verbosity, or dead weight that could be
consolidated or deleted.

## Scope

### Tier 1 — shared policy layer (highest priority)
Files Kiro can read:
- `README.md` — root policy pointer, project structure, AI framework map
- `AGENTS.md` — cross-CLI contract pointers
- `docs/architecture/0001-root-file-exceptions.md` — ADR, the authority
- `CLAUDE.md` — Claude's contract (read-only for Kiro)
- `.ai/README.md` — SSOT layout explanation
- `.ai/sync.md` — copy-command map, install instructions
- `.ai/instructions/orchestrator-pattern/principles.md` — SSOT pattern spec
- `.ai/instructions/agent-catalog/principles.md` — SSOT agent roster
- `.ai/instructions/karpathy-guidelines/principles.md` — SSOT coding guidelines
- `.ai/handoffs/README.md` — handoff protocol
- `.ai/handoffs/template.md` — handoff file shape
- `.ai/activity/log.md` — last ~20 entries (format consistency)

### Tier 2 — Kiro-native layer (own folder)
Files Kiro can read + edit:
- `.kiro/steering/00-ai-contract.md`
- `.kiro/steering/orchestrator-pattern.md`
- `.kiro/steering/agent-catalog.md`
- `.kiro/steering/karpathy-guidelines.md`
- `.kiro/agents/*.json` — all 13 agent configs
- `.kiro/hooks/*.sh` — hook scripts
- `.kiro/skills/*/*.md` — skills

### Tier 3 — cross-check against sibling CLIs (read-only)
Files Kiro can read but NOT edit:
- `.kimi/steering/00-ai-contract.md`
- `.kimi/steering/orchestrator-pattern.md`
- `.kimi/agents/system/orchestrator.md`
- `.kimi/hooks/*.sh`
- `.claude/agents/orchestrator.md`
- `.claude/hooks/pretool-write-edit.sh`

### Tier 4 — handoff queue hygiene
- `.ai/handoffs/to-kiro/open/` — any stale open handoffs?
- `.ai/handoffs/to-kiro/done/` — any that should have been moved by sender?

## Checklist — what to look for

### (A) Inconsistencies
- [ ] Root-file policy: does every file that mentions root files point at ADR-0001?
  Flag any file that still re-lists an allowlist inline.
- [ ] Agent roster: does every roster mention the same 13 agents by the same names?
  (Kimi uses `coder-executor`; Kiro uses `coder` — known delta.)
- [ ] Write-path restriction: does every orchestrator prompt agree on `.ai/**`,
  `.kiro/**`, `.kimi/**`, `.claude/**` as the framework set?
- [ ] Hook coverage: does `.kiro/hooks/root-file-guard.sh` allow the same
  ADR category A files as `.claude/hooks/pretool-write-edit.sh` and
  `.kimi/hooks/root-guard.sh`?
- [ ] Activity-log format: does `.kiro/steering/00-ai-contract.md` match the
  format rules in `AGENTS.md` / `.ai/activity/log.md`?
- [ ] Sync map: does `.ai/sync.md` list the correct source→destination pairs?
  Are there instructions in `.ai/instructions/` that are NOT mapped?
- [ ] Skill provenance: do all `.kiro/skills/*/SKILL.md` files contain provenance
  pointers back to `.ai/instructions/`?

### (B) Flaws
- [ ] Gaps: any rule stated in one place but missing in another?
- [ ] Contradictions: two files giving opposite advice.
- [ ] Live bugs: any hook that would block a legitimate write, or any prompt
  that would misdirect a subagent. Run pipe-tests if needed.
- [ ] Missing files: any referenced file that doesn't exist.
- [ ] Broken links: any markdown link pointing to a non-existent path.
- [ ] JSON validity: are all `.kiro/agents/*.json` files valid JSON?

### (C) Bloat
- [ ] Duplication: same paragraph in >2 files.
- [ ] Over-verbosity: sections that could be half as long.
- [ ] Dead weight: placeholder files, empty dirs, `[TODO:...]` scaffolds left
  unfilled across multiple sessions.
- [ ] Overlapping scopes: two agents with blurred responsibilities.
- [ ] Redundant handoffs: old `done/` noise.

## Output format

Write findings to `.ai/reports/kiro-audit-2026-04-18.md` with this structure:

```markdown
# Kiro CLI consistency audit — 2026-04-18

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
- **Read-only audit.** Do not edit any file. Report findings — don't patch silently.
- Report on ALL tiers, even clean ones.
- If a finding requires cross-CLI coordination, flag it and suggest owner.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Cross-CLI consistency audit (per handoff 010). Read ~30 files across
      shared policy + Kiro-native + sibling-CLI layers. Wrote findings report.
    - Files: .ai/reports/kiro-audit-2026-04-18.md
    - Decisions: <any deviations>

## When complete
Sender (user) reads the report. On validation, moves this handoff to
`.ai/handoffs/to-kiro/done/`. If BLOCKER-level findings exist, sender may
spawn follow-up handoffs to owning CLI(s).
