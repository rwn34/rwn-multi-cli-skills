# Template audit — claude-code
Date: 2026-04-18
Auditor: claude-code (orchestrator)
Commit audited: 6af9871

## Scope covered

- Root files (README, LICENSE, CHANGELOG, SECURITY, CoC, CONTRIBUTING, .gitignore, .gitattributes, .editorconfig, .mcp.json.example, AGENTS.md, CLAUDE.md, CODEOWNERS)
- `docs/**` (ADR-0001, 4 TEMPLATE.md files, guides/contributing.md, security.md, README.md)
- `.ai/**` (instructions SSOT for karpathy-guidelines / orchestrator-pattern / agent-catalog; sync.md; handoffs/README.md; activity/log.md header; reports/README.md; cli-map.md; README.md; legacy activity-log.md)
- `.claude/` (orchestrator.md + 12 subagent.md files; settings.json; 4 hooks; 3 skill folders; 00-ai-contract.md breadcrumb)
- `.kimi/` (orchestrator.yaml + 12 subagent.yaml + 13 system/*.md prompts; steering/00-ai-contract.md + karpathy + orchestrator-pattern; 9 hooks; resource/)
- `.kiro/` (orchestrator.json + 12 subagent.json; steering/00-ai-contract.md + karpathy + orchestrator-pattern + agent-catalog; 6 hooks; skills/karpathy-guidelines/SKILL.md)

**Skipped** (per agreed scope): `.ai/research/**`, `.ai/handoffs/*/done/**`, `.ai/**/archive/**`, `.git/`.

**Audit depth disclaimer:** I sampled — read every orchestrator config in full, every root-file hook in full, every destructive-cmd hook in full, and spot-checked `infra-engineer` + `reviewer` + `security-auditor` + `doc-writer` configs across the 3 CLIs. I did NOT read all 39 subagent config files. A deeper pass would catch more scope drift.

---

## Findings

### HIGH

**H1. Kiro infra-engineer allowlist is overly broad**
Location: `.kiro/agents/infra-engineer.json:9`
Current: `["Dockerfile*", ".github/**", "docker-compose*", "**/*.yml", "**/*.yaml", "scripts/**", "infrastructure/**", "infra/**", "terraform/**", "k8s/**", "helm/**"]`

Issues:
- `**/*.yml` and `**/*.yaml` let Kiro's infra-engineer write ANY yaml file anywhere in the repo, including `.kimi/agents/*.yaml` (12 files) and `.github/**/*.yml`. Framework-dir-guard.sh should catch cross-CLI writes as second-line defense, but the primary allowlist itself shouldn't need that rescue.
- `Dockerfile*`, `terraform/**`, `k8s/**`, `helm/**` at top level contradict the project-structure convention that puts these under `infra/**` (per `README.md:17` and `.claude/agents/infra-engineer.md:15-20`).
- `infrastructure/**` is listed alongside `infra/**` — two names for the same thing; inviting confusion.

Fix: tighten to match Claude's + Kimi's narrower scope — `infra/**`, `scripts/**`, `tools/**`, `.github/workflows/**` (not `.github/**`). Keep `Dockerfile*` only if ADR-0001 is amended to permit it at root.

Severity rationale: HIGH because this is an ENFORCEMENT gap in Kiro's hard-restricted tool allowlist. Kiro's strictness is a selling point; this undermines it.

---

### MEDIUM

**M1. Agent-catalog SSOT's infra-engineer write scope disagrees with ADR-0001**
Location: `.ai/instructions/agent-catalog/principles.md:48-49`
Current listed scope: `Dockerfile*, .github/**, docker-compose*, *.yml, *.yaml, scripts/**, infrastructure/**, infra/**, terraform/**, k8s/**, helm/**`

The catalog lists `Dockerfile*` and `docker-compose*` as permitted — but ADR-0001 doesn't permit those at root yet (category F gates language-manifest-style root files). `*.yml` + `*.yaml` at catalog level is also broader than the ADR implies.

Root cause: the catalog was written before ADR-0001 hardened the root-file policy. It's now the upstream of H1's Kiro drift.

Fix: either (a) update catalog to scope everything under `infra/**`, `scripts/**`, `tools/**`, `.github/workflows/**`, OR (b) amend ADR-0001 to add `Dockerfile` + `docker-compose.yml` as permitted root files (they're language-agnostic, unlike package.json/pyproject.toml). I'd recommend (b) with a short ADR amendment.

---

**M2. infra-engineer write scope differs across all 3 CLIs**
Locations: `.claude/agents/infra-engineer.md:13-21`, `.kimi/agents/system/infra-engineer.md:7`, `.kiro/agents/infra-engineer.json:9`

- Claude: `infra/**, scripts/**, tools/**` + specific root-tooling exceptions listed in prose
- Kimi: `.github/**, scripts/**, infra/**, config/**, tools/**` (no Dockerfile, no terraform/k8s/helm at top)
- Kiro: broad as per H1 above

All three disagree with each other AND with the agent-catalog SSOT (M1). Root cause: each CLI was implemented independently against an already-loose catalog. Fix depends on resolving M1 first, then sync the 3 replicas.

---

**M3. Legacy file `.ai/activity-log.md` should be archived or deleted**
Location: `.ai/activity-log.md`

Contains 7 Kimi entries from 2026-04-17 (before Kimi's own hooks were fixed to point at the canonical `.ai/activity/log.md`). No CLI reads it anymore — every contract + every hook points at `.ai/activity/log.md`.

Bloat (~3 KB + mental tax for new CLIs scanning `.ai/`). If it has historical value, move to `.ai/activity/archive/2026-04.md`. Otherwise delete.

---

**M4. Destructive-command hooks have divergent coverage across 3 CLIs**
Locations: `.claude/hooks/pretool-bash.sh`, `.kimi/hooks/destructive-guard.sh`, `.kiro/hooks/destructive-cmd-guard.sh`

Block coverage comparison:

| Pattern | Claude | Kimi | Kiro |
|---|---|---|---|
| `rm -rf /` | ✓ | ✓ | ✓ |
| `rm -rf ~` | ✓ | ✗ | ✓ |
| `rm -rf *` | ✓ | ✗ | ✓ |
| `rm -rf .` | ✓ | ✗ | ✗ |
| `git push --force` / `-f` | ✓ | ✓ | ✓ |
| `--force-with-lease` | ✓ | ✗ | ✗ |
| `git reset --hard` | ✓ | ✓ | ✓ |
| `DROP DATABASE/TABLE` | ✓ | ✓ | ✓ |
| `DROP SCHEMA` | ✓ | ✗ | ✗ |
| `TRUNCATE TABLE` | ✓ | ✗ | ✗ |

Claude's coverage is the superset. Kimi + Kiro have gaps: `rm -rf .` (commonly-typoed dangerous form), `DROP SCHEMA`, `TRUNCATE TABLE`. Philosophical question: should `--force-with-lease` be blocked? It's safer than `--force` but still rewrites history.

Fix: agree on a canonical block-list in `.ai/instructions/` (new sub-SSOT), then align the 3 hooks.

---

**M5. Claude's root-file hook blanket-allows all dotfiles**
Location: `.claude/hooks/pretool-write-edit.sh:66`
Current: `.*) exit 0 ;;` — any file starting with `.` at repo root passes the allowlist check.

ADR-0001 categorically permits specific dotfiles (`.gitignore`, `.gitattributes`, `.editorconfig`, `.mcp.json*`, `.dockerignore`). Blanket-allowing is broader than that policy — a subagent could write `.foo-secret` or `.whatever` at root without being blocked.

Kimi's + Kiro's hooks are tighter — they only enumerate specific root files (no dotfile blanket). Claude is the outlier.

Fix: replace the `.*)` catchall with an explicit enumeration: `.gitignore|.gitattributes|.editorconfig|.mcp.json|.mcp.json.example|.dockerignore) exit 0 ;;` plus `.gitlab-ci.yml` and similar CI vendor root files if added.

---

### LOW + NIT

**L1. Claude's reviewer tools include `Edit` + `Write`**
Location: `.claude/agents/reviewer.md:4`
`tools: Read, Grep, Glob, Edit, Write, Skill`

Reviewer's write scope per agent-catalog + per the md file's own prose is `.ai/reports/` only. Claude relies on prose enforcement (no native path restriction). Given that, Edit+Write being available means a misbehaving reviewer COULD write elsewhere.

Kiro has `"allowedPaths": [".ai/reports/**"]` — hard restriction. Kimi relies on prompt (same as Claude).

Fix is minor — swap Edit/Write for a restricted `Write` target if Claude ever adds path restriction at the tool level, or add a PostToolUse hook that blocks reviewer writes outside reports. Low priority since reviewer rarely misbehaves.

**NIT1. `.claude/00-ai-contract.md` is a documented breadcrumb**
Already explicitly labeled as a pointer file (not Claude's actual loaded contract). Purpose is cross-CLI discoverability. Working as intended; noting for completeness that it is technically duplicative.

**NIT2. `infrastructure/**` vs `infra/**` in Kiro's infra-engineer allowlist** (subset of H1)
Two names for the same conceptual dir — if `infra/` is canonical (it is, per `README.md:17`), `infrastructure/**` entry is dead code.

---

## Bloat candidates

**B1. `.ai/research/**` — 15 historical proposal files (~45 KB)**
Files from pre-implementation phases: `orchestrator-{claude,kimi,kiro}.md`, `agent-catalog-{claude,kimi,kiro}.md`, `agent-catalog-feedback-{claude,kimi}.md`, `agent-taxonomy-proposal-kimi.md`, `hooks-recommendation-{claude,kimi}.md`, `project-structure-feedback-{claude,kimi}.md`, `template-completeness-{claude,kimi}.md`.

All superseded by the landed SSOT (catalog + pattern + hooks are now canonical). None are read by any CLI routinely.

Recommendation: consolidate into a single `.ai/research/archive/2026-04.md` (one file per month per the archive protocol) OR just move each to `.ai/research/archive/<name>-2026-04-18.md`. Current archive README exists at `.ai/research/archive/README.md` so the pattern is already in place — just hasn't been executed for this batch.

**B2. `.ai/handoffs/*/done/` — 30+ historical handoffs**
Already planned to be cleaned on clone per `.ai/sync.md`'s new install command. Low-priority bloat in the template repo itself (~60 KB). Could be left alone since it's part of the project's own history. Just noting.

**B3. Directory-stub READMEs (`src/`, `tests/`, `infra/`, `migrations/`, `scripts/`, `tools/`, `config/`, `assets/`)**
8 stub README.md files. Useful as scaffolding signals ("yes, this directory is intentional"). Downside: adds 8 files to the template that won't be meaningful until a real project fills them. Net: KEEP — the structural signal is worth the noise.

**B4. Per-CLI hooks READMEs**
`.claude/hooks/README.md`, `.kimi/hooks/README.md`, `.kiro/hooks/README.md` — 3 CLI-specific READMEs with overlapping structure. Each describes its own CLI's hooks, which is legitimate. Overlap is tolerable; a shared `.ai/hooks-reference.md` would add its own drift risk.

Recommendation: leave as-is.

**B5. `.ai/cli-map.md` (95 lines)**
Detailed cross-CLI concept mapping. Valuable for onboarding a new CLI, but repeats content that's also in per-CLI steering contracts + agent catalog. Could be tightened — specifically the "per-CLI mapping" table and the "How this project's karpathy-guidelines is shaped per CLI" table are useful reference; the long prose around them could shrink.

Recommendation: cosmetic. LOW-priority refactor.

---

## What I did NOT find

Checked and came back clean:

- **No secrets in any tracked file.** Grepped for common patterns (`password`, `api_key`, `secret`, `token`, `_KEY=`) — all hits were placeholder/template text (e.g., `$GITHUB_TOKEN` in `.mcp.json.example`, `[TODO:...]` placeholders in `SECURITY.md`).
- **No broken links** in root `README.md`, `AGENTS.md`, or `CLAUDE.md` — every file-path reference I spot-checked resolves.
- **No duplicate skill declarations** in `.claude/skills/` — 3 folders (`karpathy-guidelines`, `orchestrator-pattern`, `agent-catalog`) + README, each uniquely named.
- **orchestrator-pattern SSOT ↔ 3 CLI replicas byte-identical** — confirmed via today's 10:45 sign-off (174 lines each).
- **ADR-0001 is internally consistent** — category A through H enumerate allowed files cleanly; `Process for adding a new exception` is actionable.
- **Handoff protocol is coherent** — `.ai/handoffs/README.md` + `template.md` + live handoff behavior match. NNN-per-recipient numbering worked correctly through this session's 5 handoffs (008, 009, 010, 020, 021).
- **Three CLIs' orchestrator delegation maps name the same 12 subagents** (Kimi uses `coder-executor` instead of `coder`; otherwise identical).

## Not checked (out of this pass's scope, flagging for next audit)

- **karpathy-guidelines SSOT ↔ 3 replicas** — didn't byte-diff; could have drifted since last sync.
- **All 39 subagent config files individually** — I sampled `infra-engineer`, `reviewer`, `orchestrator` across 3 CLIs. `tester`, `debugger`, `refactorer`, `doc-writer`, `data-migrator`, `release-engineer`, `ui-engineer`, `e2e-tester`, `security-auditor`, `coder` configs have not been cross-checked for scope drift. A more exhaustive pass may find additional H1-class issues.
- **Hook pipe-test coverage** — I read the hook scripts but didn't run them against test inputs. Kiro's pipe-tests from handoff 009 are the only recent end-to-end validation.
- **`.kimi/agents/system/*.md` ↔ `.kimi/agents/*.yaml` consistency** — these are paired (yaml refs system/*.md via `system_prompt_path`); didn't verify each pairing resolves.

---

## Open questions

**Q1. ADR-0001 amendment for Dockerfile + docker-compose?**
These are language-agnostic; category F's "language manifests" gate doesn't naturally apply. If we add them to the ADR (new category D addition?), M1 + M2 + H1 resolve by alignment. Otherwise we tighten the catalog down to `infra/docker/Dockerfile`-style paths.

**Q2. Should `.kimi/agents/system/*.md` exist as a separate tree?**
Kimi splits each agent into `agent.yaml` (config) + `system/agent.md` (prompt). That's Kimi-native. Cross-CLI, it means two files per Kimi agent when reviewing. No fix proposed — just surfacing it so Kimi-side audit can confirm the split is working as intended.

**Q3. Should destructive-cmd hooks have a shared SSOT?**
M4's divergence suggests yes — a `.ai/instructions/destructive-commands/principles.md` enumerating the canonical block-list, with all 3 CLIs syncing hooks from it. Scope bigger than M4 alone — worth deciding before patching any one hook.

**Q4. When should `.ai/research/**` be archived?**
B1 is low-hanging. Could do it this session if the cross-review raises no objections.

---

## Summary for cross-review

**Top 3 items I'd patch first:**
1. H1 (Kiro infra-engineer allowlist) — live permissions drift, fixable with 1 JSON edit.
2. M4 (destructive-cmd hook gaps) — real safety holes in Kimi + Kiro.
3. M5 (Claude root-file hook dotfile blanket) — real permissions hole in Claude.

**Top 3 items for group discussion:**
1. Q1 (ADR Dockerfile amendment) — decides M1/M2.
2. Q3 (destructive-cmd SSOT) — decides M4 structure.
3. B1 (research archive) — simple cleanup, just needs a go/no-go.

**What Kimi + Kiro should audit to cover my gaps:**
- All subagent configs I didn't sample.
- karpathy-guidelines SSOT ↔ replicas byte-diff.
- Hook pipe-tests against the canonical block-list (once M4 is decided).
- Any Claude-side drift I might have missed from my own turf (self-blind-spots).
