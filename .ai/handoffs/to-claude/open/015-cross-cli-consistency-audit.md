# Cross-CLI consistency audit — Claude review
Status: OPEN
Sender: user
Recipient: claude-code
Created: 2026-04-18 10:35

## Goal
Independent read-only audit of the entire multi-CLI framework from Claude's
perspective. Check for: (1) **inconsistencies** — the same rule stated
differently in two places, (2) **flaws** — gaps, contradictions, or live bugs,
(3) **bloat** — duplication, over-verbosity, or dead weight that could be
consolidated or deleted.

## Scope

### Tier 1 — shared policy layer (highest priority)
Files Claude can read:
- `README.md` — root policy pointer, project structure, AI framework map
- `AGENTS.md` — cross-CLI contract pointers
- `docs/architecture/0001-root-file-exceptions.md` — ADR, the authority
- `CLAUDE.md` — Claude's always-loaded contract
- `.ai/README.md` — SSOT layout explanation
- `.ai/sync.md` — copy-command map, install instructions
- `.ai/instructions/orchestrator-pattern/principles.md` — SSOT pattern spec
- `.ai/instructions/agent-catalog/principles.md` — SSOT agent roster
- `.ai/instructions/karpathy-guidelines/principles.md` — SSOT coding guidelines
- `.ai/handoffs/README.md` — handoff protocol
- `.ai/handoffs/template.md` — handoff file shape
- `.ai/activity/log.md` — last ~20 entries (format consistency)

### Tier 2 — Claude-native layer (own folder)
Files Claude can read + edit:
- `.claude/agents/*.md` — all 13 agent configs
- `.claude/skills/*/*.md` — all skills
- `.claude/hooks/*.sh` — hook scripts
- `.claude/settings.json`
- `.claude/00-ai-contract.md`

### Tier 3 — cross-check against sibling CLIs (read-only)
Files Claude can read but NOT edit:
- `.kimi/steering/00-ai-contract.md`
- `.kimi/steering/orchestrator-pattern.md`
- `.kimi/agents/system/orchestrator.md`
- `.kimi/hooks/*.sh`
- `.kiro/steering/00-ai-contract.md`
- `.kiro/steering/orchestrator-pattern.md`
- `.kiro/agents/orchestrator.json`
- `.kiro/hooks/root-file-guard.sh`

### Tier 4 — handoff queue hygiene
- `.ai/handoffs/to-claude/open/` — any stale open handoffs?
- `.ai/handoffs/to-claude/done/` — any that should have been moved by sender?
- `.ai/handoffs/to-kimi/open/014-final-review-template-cleanup.md` — Kimi's handoff to Claude; still open. Is this Claude's to move or Kimi's?

## Checklist — what to look for

### (A) Inconsistencies
- [ ] Root-file policy: does every file that mentions root files point at ADR-0001?
  Flag any file that still re-lists an allowlist inline.
- [ ] Agent roster: does every roster mention the same 13 agents by the same names?
  (Kimi uses `coder-executor`; others use `coder` — that's a known naming delta.)
- [ ] Write-path restriction: does every orchestrator prompt agree on `.ai/**`,
  `.kiro/**`, `.kimi/**`, `.claude/**` as the framework set?
- [ ] Hook coverage: does `.claude/hooks/pretool-write-edit.sh` allow the same
  ADR category A files as `.kimi/hooks/root-guard.sh` and
  `.kiro/hooks/root-file-guard.sh`?
- [ ] Activity-log format: does `CLAUDE.md` / `.claude/00-ai-contract.md` match
  the format rules in `AGENTS.md` / `.ai/activity/log.md`?
- [ ] Sync map: does `.ai/sync.md` list the correct source→destination pairs?
  Are there instructions in `.ai/instructions/` that are NOT mapped?
- [ ] Skill provenance: do all `.claude/skills/*/SKILL.md` files contain the
  required provenance pointer back to `.ai/instructions/`?

### (B) Flaws
- [ ] Gaps: any rule stated in one place but missing in another where it should
  also appear?
- [ ] Contradictions: two files giving opposite advice.
- [ ] Live bugs: any hook that would block a legitimate write, or any prompt
  that would misdirect a subagent.
- [ ] Missing files: any referenced file that doesn't exist.
- [ ] Broken links: any markdown link pointing to a non-existent path.
- [ ] Settings drift: does `.claude/settings.json` reference agents/hooks that
  no longer exist, or miss ones that were recently added?

### (C) Bloat
- [ ] Duplication: same paragraph in >2 files.
- [ ] Over-verbosity: sections that could be half as long.
- [ ] Dead weight: placeholder files, empty dirs, `[TODO:...]` scaffolds left
  unfilled across multiple sessions.
- [ ] Overlapping scopes: two agents with blurred responsibilities.
- [ ] Redundant handoffs: old `done/` noise.

## Output format

Write findings to `.ai/reports/claude-audit-2026-04-18.md` with this structure:

```markdown
# Claude Code consistency audit — 2026-04-18

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
    ## YYYY-MM-DD HH:MM — claude-code
    - Action: Cross-CLI consistency audit (per handoff 015). Read ~30 files across
      shared policy + Claude-native + sibling-CLI layers. Wrote findings report.
    - Files: .ai/reports/claude-audit-2026-04-18.md
    - Decisions: <any deviations>

## When complete
Sender (user) reads the report. On validation, moves this handoff to
`.ai/handoffs/to-claude/done/`. If BLOCKER-level findings exist, sender may
spawn follow-up handoffs to owning CLI(s).
