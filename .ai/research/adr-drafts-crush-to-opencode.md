# ADR amendment drafts — Crush → OpenCode swap

> **STATUS: LANDED 2026-07-09 into both ADRs (owner-approved).** This file
> remains as the migration checklist (§3) until tasks 8-10 complete.
> Prepared 2026-07-09 by claude-code (doc-writer). Nothing under
> `docs/architecture/` has been modified. Both amendment texts below are
> paste-ready for insertion into the real ADRs once the owner approves.
> Owner decision reference: `.ai/activity/log.md` entry 2026-07-09 07:40
> ("OWNER DECISION (Tier C): replace Crush with OpenCode as 4th CLI ...
> Swap workstream queued (smoke test → ADR-0002/0001 amendments →
> contract+guard plugin → integrations → kimi/kiro parity → e2e).")
>
> All quotes of current ADR text below were verified by reading
> `docs/architecture/0001-root-file-exceptions.md` and
> `docs/architecture/0002-cli-role-topology.md` in full on 2026-07-09.
> The migration checklist in §3 is grep-derived (evidence in Appendix A).

---

## 1. DRAFT 1 — Amendment to ADR-0002 (`docs/architecture/0002-cli-role-topology.md`)

Style note: this mirrors how the 2026-07-08 Stage-2 amendment was applied —
a dated line appended to **Status**, inline `*[Amended YYYY-MM-DD: ...]*`
annotations at the points of change, and a replacement role block. It is not
a rewrite.

### 1.1 Paste into `## Status` (append as a new line after the existing "Amended 2026-07-08 ..." line)

```markdown
Amended 2026-07-09 (owner directive): OpenCode replaces Crush as the fourth
CLI — same role lane (general helper + Stage-2 deployment operator), same
Stage-2 conditions carried over verbatim. The TUI contingency raised by the
smoke test was RESOLVED same day via option (a): owner confirmed the TUI
renders correctly in the daily-driver Windows Terminal (the smoke test's DLL
error 126 occurred only under headless/redirected launches). Crush's history
remains in this ADR as record; Crush-specific text below is superseded where
marked.
```

### 1.2 Paste into `## Context` (append as a new bullet)

```markdown
- *[Amendment 2026-07-09]* Crush exhibited identity drift in daily use.
  Root cause: its contract (`CRUSH.md`) is loaded once per session with no
  per-turn reinforcement, it has no hook layer, and the daily `--yolo`
  launch removed the last interactive friction — so nothing mechanical ever
  re-asserted the SAFETY RULES after context grew. This confirmed the
  original Context observation ("weakest guardrail surface") as a practical
  failure, not just a theoretical one. OpenCode was selected as replacement
  because its guardrails are mechanical, not prompt-level: its permission
  system (`allow`/`ask`/`deny`) removes denied tools from the model's tool
  list at the harness level (smoke-test proven 2026-07-09), it supports JS
  plugin hooks (worktree-confinement / fleet-whitelist parity with the
  other CLIs' hook layers), and it has an agents system for role scoping.
```

### 1.3 Replace the `- **Crush** — ...` role block under `### Per-CLI roles` (the block currently spanning the "general helper + DevOps deployment operator (onboarded 2026-07-07)" bullet and its three sub-bullets) with:

```markdown
- **OpenCode** — general helper + DevOps deployment operator. *[Amended
  2026-07-09: OpenCode replaces Crush in this lane by owner directive. The
  role definition is unchanged from the 2026-07-08 amendment; only the CLI
  filling it changes.]*
  - **Deploy execution (Stage 2, carried over):** OpenCode may execute
    deploys under the same four conditions Crush held, carried verbatim
    from the Crush contract:
    1. **Dry-run first, always** (`--dry-run`, `terraform plan`, staging
       target) and paste the dry-run output before proposing the real run.
    2. **Per-deploy human confirmation** — every mutating deploy command is
       individually confirmed by the human in-session. Deploys are Tier-C
       hard-gated (operating-prompt §8) no matter who executes them.
    3. **Only commands enumerated in an approved deploy brief** (a handoff
       in the deploy inbox). Never improvise a command that is not in the
       brief — if the brief is wrong, STOP and report.
    4. **Refuse on dirty working tree or failing tests.** No exceptions.
  - **General helper:** small cross-cutting ops chores (env checks,
    housekeeping scripts, release checklists) within the OpenCode contract
    write scope (successor to the `CRUSH.md` SAFETY RULES scope).
  - **Guardrail surface (improvement over Crush):** unlike Crush, OpenCode's
    boundaries are enforced mechanically: `deny` rules strip tools at the
    harness level (the model cannot call what it cannot see), and JS plugin
    hooks provide worktree-confinement and fleet-whitelist parity with the
    Claude/Kimi/Kiro hook layers. Stage 2 nonetheless remains human-gated
    per deploy — the gate is policy, not a workaround for missing tooling.
  - **Identity / inbox:** activity-log identity changes `crush` →
    `opencode`; handoff inbox changes `.ai/handoffs/to-crush/` →
    `.ai/handoffs/to-opencode/`. The `to-crush/done/` history is preserved
    read-only (never rewritten, per handoff protocol).
  - **Key handling (owner directive 2026-07-09: "use the key as is"):**
    provider API keys remain user-scope local literals, migrated
    programmatically (value never displayed) from Crush's
    `%LOCALAPPDATA%\crush\crush.json` into OpenCode's user-scope global
    config (`~/.config/opencode/opencode.json`) — same security posture as
    today, zero owner action. The REPO-level `opencode.json` carries NO key
    material of any kind; OpenCode merges global + project config at
    runtime. (The repo-level `.crush.json` was verified key-free —
    `{ "mcp": {} }` — the inline-literal storage exists in the user-scope
    config only, and stays user-scope.)
  - **Smoke-test record (2026-07-09, opencode-ai 1.17.15, native
    Windows):** headless run PASS; permission `deny` PASS (harness-level
    tool removal); JS plugin hooks PASS; `{env:}` substitution PASS;
    TUI failed under headless/redirected launch (OpenTUI DLL error 126)
    but was confirmed working same day in the owner's real Windows
    Terminal session — contingency (a) RESOLVED; swap unconditional.
```

### 1.4 Paste into the sentence following the role list (the paragraph beginning "Rationale for Crush's originally narrow scope ...") — append this annotation at its end

```markdown
*[Amendment 2026-07-09: the "no hooks layer" gap this paragraph describes
is closed by the OpenCode swap (harness-level permissions + plugin hooks).
The per-deploy human gate is retained as policy regardless.]*
```

### 1.5 Amend pipeline step 6 under `### GitHub/release pipeline` — replace the leading clause "Crush executes (dry-run first + per-deploy human confirmation; refuses on dirty tree or failing tests). Claude's `release-engineer` is the FALLBACK deploy lane when Crush is unavailable, under the same conditions." with:

```markdown
*[Amended 2026-07-09]* OpenCode executes (dry-run first + per-deploy human
confirmation; refuses on dirty tree or failing tests). Claude's
`release-engineer` is the FALLBACK deploy lane when OpenCode is
unavailable, under the same conditions.
```

(The remainder of step 6 — "Kimi and Kiro have NO deploy lane ..." — is
unchanged.)

### 1.6 Paste into `## Consequences` (append)

```markdown
- *[Amendment 2026-07-09]* The Crush→OpenCode swap touches every file that
  names Crush in an operative (non-historical) way — root contracts, SSOT
  principles + their three replica channels, hooks/tests, the 4AI-panes
  launcher, the installer and its asset tree, dispatch tooling, and the
  fleet scripts. The grep-derived migration checklist lives in
  `.ai/research/adr-drafts-crush-to-opencode.md` §3 until executed.
  Historical records (activity log, done/ handoffs, dated research notes,
  prior ADR text) are NOT rewritten.
- *[Amendment 2026-07-09]* `CRUSH.md` and `.crush.json` are deprecated on
  landing of this amendment and physically deleted only after the swap's
  end-to-end verification gate (swap workstream task 10); ADR-0001's root
  exceptions for them are removed in the same commit as the deletion (see
  ADR-0001 amendment of the same date).
```

---

## 2. DRAFT 2 — Amendment to ADR-0001 (`docs/architecture/0001-root-file-exceptions.md`)

Style note: ADR-0001 changes land as edits to the category lists plus dated
NOTE lines (precedent: the `.crush.json` entry's own "NOTE: file predates
this amendment ... this entry cures the violation" line, and the dated
custodianship note). Paste-ready pieces follow.

### 2.1 Category A — no new entry needed for `AGENTS.md` (verified)

`AGENTS.md` is ALREADY a permitted Category-A root file in the current ADR
text (verified 2026-07-09: Category A lists "`AGENTS.md` — multi-CLI
project pointer"). OpenCode reads `AGENTS.md` natively as its always-loaded
contract, so no new exception entry is required — only this annotation.
Paste onto the existing `AGENTS.md` line in Category A (append to the line):

```markdown
 Also OpenCode's always-loaded contract file (OpenCode reads `AGENTS.md`
natively; per ADR-0002 amendment 2026-07-09, OpenCode replaces Crush as
fourth CLI). Claude Code is custodian of the OpenCode-facing content.
```

### 2.2 Category A — mark the `CRUSH.md` line deprecated (edit in place)

Replace the current line

> `- CRUSH.md — Crush CLI's always-loaded context/contract file (Crush reads root context files natively; added per ADR-0002 Crush onboarding)`

with:

```markdown
- `CRUSH.md` — DEPRECATED (2026-07-09, ADR-0002 amendment: OpenCode
  replaces Crush). Retained on disk until the swap's e2e verification gate
  (swap workstream task 10) passes; this entry is deleted in the same
  commit that deletes the file.
```

### 2.3 Category E — new entry: `opencode.json` (THIS IS the required new exception)

Paste into Category E (suggested position: where the `.crush.json` entry
currently sits):

```markdown
- `opencode.json` — OpenCode CLI project config (permissions allow/ask/deny,
  provider wiring; NO key material of any kind — keys live in OpenCode's
  user-scope global config outside the repo, per owner directive
  2026-07-09). OpenCode resolves this file at project root. Added per
  ADR-0002 amendment 2026-07-09 (OpenCode replaces Crush as fourth CLI).
- `.opencode/` — OpenCode project directory (JS guard plugins, agents,
  local data). As a dotfolder it is exempt from the loose-file-at-root
  question by nature (see note below Category H); listed here for
  discoverability, same as `.crush/` was.
```

### 2.4 Category E — mark the Crush entries deprecated (edit in place)

Replace the current lines

> `- .crush.json — Crush CLI config (MCP wiring). NOTE: file predates this amendment (created by the code-graph wiring change without ADR amendment); this entry cures the violation.`
> `- .crush/ — Crush CLI local data directory (sessions, logs; gitignored)`

with:

```markdown
- `.crush.json` — DEPRECATED (2026-07-09, see `CRUSH.md` note in
  Category A). Deleted, with this entry, after the swap's e2e gate.
- `.crush/` — DEPRECATED (2026-07-09). Local data dir; removed with the
  Crush uninstall.
```

### 2.5 Replace the custodianship note (the paragraph after Category E beginning "Custodianship note: Crush cannot self-manage framework files ...") with:

```markdown
Custodianship note *[amended 2026-07-09]*: Claude Code is custodian of
OpenCode's framework files — `AGENTS.md` (the OpenCode-facing contract
content), `opencode.json`, and `.opencode/` (guard plugins, agents).
OpenCode requests changes to its own files via
`.ai/handoffs/to-claude/open/` — the same change-request path Crush used.
During the deprecation window, the same custodianship still covers
`CRUSH.md` and `.crush.json` until their deletion.
```

---

## 3. Migration checklist — every file the full swap touches (grep-derived)

Method: `grep -ril crush` (case-insensitive) across `.ai/`, `.claude/`,
`tools/`, `scripts/`, plus root files and `CRUSH.md`'s own cross-references
(`docs/architecture/000{1,2}-*.md`, `.ai/instructions/*`,
`.ai/handoffs/README.md` + `template.md`, `.ai/cli-map.md`,
`.ai/known-limitations.md`, operating-prompt §8). Evidence lines per file in
Appendix A. Counts: **44 files require edits**, **2 ADRs amended by this
draft**, **2 ADRs flagged for small follow-up annotations**, **1 directory
rename**, plus regenerated asset mirrors and out-of-scope hits listed
separately.

### 3.1 Root files (5)

| # | File | Change |
|---|---|---|
| 1 | `CRUSH.md` | deprecate on ADR landing; delete after e2e gate (task 10) |
| 2 | `.crush.json` | same as above (verified content is `{ "mcp": {} }` — no secrets in-repo) |
| 3 | `AGENTS.md` | becomes OpenCode's contract carrier; update the CLI table row (`/CRUSH.md` → OpenCode/`AGENTS.md`) and the 4th-CLI description |
| 4 | `CLAUDE.md` | AI-contract header (Crush → OpenCode), custodianship line (`CRUSH.md`/`.crush.json` → `AGENTS.md`/`opencode.json`/`.opencode/`), protocol-v2 dispatch note |
| 5 | `README.md` | 4th-CLI description (L13), write-boundary table row (L442), hook-layer caveat (L444) |

Note: root `.gitignore` verified — contains no `crush` entry, so no
`.gitignore` edit is strictly required; add `.opencode/` local-data ignores
only if OpenCode writes session data there.

### 3.2 `.ai/` (11 files + 1 directory rename)

| # | File | Change |
|---|---|---|
| 6 | `.ai/cli-map.md` | §Crush → §OpenCode (config `opencode.json`, steering `AGENTS.md`, lifecycle = plugin hooks, identity `opencode`, inbox `to-opencode/`, headless `opencode run`) |
| 7 | `.ai/sync.md` | "Crush (no replicas)" section → OpenCode equivalent (AGENTS.md-carried contract) |
| 8 | `.ai/known-limitations.md` | rewrite "Crush — no hook layer" entry: closed by swap (TUI contingency resolved 2026-07-09; note OpenTUI DLL error 126 under headless/redirected launch as a minor known quirk) |
| 9 | `.ai/tools/dispatch-handoffs.sh` | dispatch case `crush) "crush run ..."` → `opencode) "opencode run ..."`; queue-name mapping |
| 10 | `.ai/handoffs/README.md` | custodian file list; Crush write-scope line; inbox tree diagram (`to-crush/` → `to-opencode/`) |
| 11 | `.ai/handoffs/template.md` | sender/recipient enum `crush` → `opencode` |
| 12 | `.ai/instructions/operating-prompt/principles.md` | identity list, §4 role lane, §8/§enforcement Crush caveats |
| 13 | `.ai/instructions/orchestrator-pattern/principles.md` | deploy-lane line (L119) |
| 14 | `.ai/instructions/agent-catalog/principles.md` | CLI role-lane block (L98–104) |
| 15 | `.ai/instructions/code-graphs/principles.md` | per-CLI graph tables + "Crush — no graph wiring" section (policy unchanged: OpenCode gets no graph lane) |
| 16 | dir rename: `.ai/handoffs/to-crush/` → `.ai/handoffs/to-opencode/` | `git mv`; `done/` history preserved read-only (currently only `.gitkeep`s: `to-crush/open/`, `to-crush/done/`) |

NOT edited (historical, never rewritten): `.ai/activity/log.md`,
`.ai/handoffs/to-*/done/*.md`, `.ai/research/4ai-panes-integration-notes.md`
(dated notes; add a dated UPDATE header only),
`.ai/research/worktree-multi-project-topology.md` (research input to
ADR-0004; add UPDATE header only if ADR-0004 is annotated).

### 3.3 `.claude/` (7)

| # | File | Change |
|---|---|---|
| 17 | `.claude/hooks/pretool-write-edit.sh` | custodianship allowlist: `CRUSH.md\|.crush.json` → add `AGENTS.md` already covered; add `opencode.json` (+ `.opencode/` prefix) to allowed writes; drop crush entries at deletion time (L128, L143, L154) |
| 18 | `.claude/hooks/test_hooks.sh` | t25/t26 crush-file tests → opencode.json/AGENTS.md custodianship tests |
| 19 | `.claude/agents/release-engineer.md` | fallback-lane wording: "Crush is the primary DevOps deployment operator" → OpenCode |
| 20 | `.claude/skills/operating-prompt/SKILL.md` | replica — regenerate from SSOT (#12) per `.ai/sync.md` |
| 21 | `.claude/skills/orchestrator-pattern/SKILL.md` | replica — regenerate (#13) |
| 22 | `.claude/skills/agent-catalog/SKILL.md` | replica — regenerate (#14) |
| 23 | `.claude/skills/code-graphs/SKILL.md` | replica — regenerate (#15) |

### 3.4 `.kimi/` (4) and `.kiro/` (5) — via parity handoffs (their territory)

| # | File | Change |
|---|---|---|
| 24–27 | `.kimi/steering/{operating-prompt,orchestrator-pattern,agent-catalog,code-graphs}.md` | replicas — regenerate from SSOTs via to-kimi handoff |
| 28–31 | `.kiro/steering/{operating-prompt,orchestrator-pattern,agent-catalog,code-graphs}.md` | replicas — regenerate via to-kiro handoff |
| 32 | `.kiro/agents/release-engineer.json` | fallback/deploy-lane wording parity with #19 |

### 3.5 `tools/` (9, excluding mirrors/build outputs/false positives)

| # | File | Change |
|---|---|---|
| 33 | `tools/4ai-panes/Selector.ps1` | `$cliDefs["Crush"]` detect/cmd → OpenCode (`opencode` on PATH, native launch — TUI contingency resolved (a) 2026-07-09); default pane order; framework-check file list (`CRUSH.md`, `.crush.json` → `AGENTS.md`, `opencode.json`) |
| 34 | `tools/4ai-panes/Launch4Panes.ps1` | header comment pane list |
| 35 | `tools/4ai-panes/README.md` | pane tables, prerequisites, layout examples |
| 36 | `tools/multi-cli-install/src/upgrade/manifest.ts` | framework-owned file list: `CRUSH.md`/`.crush.json` → `AGENTS.md` (already listed? verify) + `opencode.json` |
| 37 | `tools/multi-cli-install/src/installer/copy-framework.ts` | same list change |
| 38 | `tools/multi-cli-install/src/installer/wire-mcp.ts` | comment "Crush: no graph wiring, ever" → OpenCode equivalent |
| 39 | `tools/multi-cli-install/scripts/sync-assets.ts` | synced-file list: swap `CRUSH.md`, `.crush.json` for `opencode.json` (AGENTS.md already listed) |
| 40 | `tools/multi-cli-install/test/installer.test.ts` | existence/wire-mcp/template tests for crush files → opencode equivalents |
| 41 | `tools/multi-cli-install/test/upgrade-phase-a.test.ts` | manifest-key expectations |

Regenerated, not hand-edited: `tools/multi-cli-install/assets/**` (mirror of
the live tree — rerun `sync-assets.ts` after the source edits; the grep hits
there are copies of files already listed above) and
`tools/multi-cli-install/dist/**`, `tools/kirograph/dist/**` (build outputs).

FALSE POSITIVES — no change required: `tools/kirograph/src/**`,
`tools/kirograph/docs/**`, `tools/kirograph/CHANGELOG.md`. KiroGraph is a
standalone installer supporting 30+ third-party CLIs; `'crush'` there is one
generic install target among many (and `'opencode'` is ALREADY a supported
target in its `InstallTarget` union). Unrelated to this framework's role
topology.

### 3.6 `scripts/` (2)

| # | File | Change |
|---|---|---|
| 42 | `scripts/wt-bootstrap.sh` | `DEFAULT_EXECUTORS="kiro kimi crush"` → `kiro kimi opencode` (+ usage text L12/L41) |
| 43 | `scripts/fleet-init.sh` | executor list in handoff-topology table (L291) |

### 3.7 `docs/` (1 direct + 2 ADRs amended by this draft + 2 ADR follow-ups)

| # | File | Change |
|---|---|---|
| 44 | `docs/guides/framework-upgrade-runbook.md` | "Root contracts and Crush files" section (L124–130) and header list (L6) → OpenCode file set; the stale-fleet worst-case ("Crush pane running --yolo with no CRUSH.md") becomes historical context |
| — | `docs/architecture/0002-cli-role-topology.md` | DRAFT 1 above (Tier C) |
| — | `docs/architecture/0001-root-file-exceptions.md` | DRAFT 2 above (Tier C) |
| — | `docs/architecture/0003-code-graph-rationalization.md` | follow-up: one-line dated annotation on decision 4 ("Crush gets no graph wiring" → applies to OpenCode as lane successor). Tier C, owner-gated |
| — | `docs/architecture/0004-worktree-multi-project-topology.md` | follow-up: executor-name annotation (`crush` worktree/branch names → `opencode`). Tier C, owner-gated |

---

## 4. Proposed activity-log entry stub (prepend to `.ai/activity/log.md` when the ADR amendments LAND — not now)

```markdown
## 2026-07-XX HH:MM — claude-code
- Action: Landed ADR-0002 + ADR-0001 amendments (owner-approved, Tier C):
  OpenCode replaces Crush as 4th CLI — same lane (general helper + Stage-2
  deploy operator, four conditions verbatim), identity `crush`→`opencode`,
  inbox `to-crush/`→`to-opencode/` (done/ preserved), `opencode.json` root
  exception added, CRUSH.md/.crush.json marked deprecated (deletion gated
  on task-10 e2e). TUI contingency status: <(a) WT check | (b) version pin
  | (c) WSL pane — record which resolved, or "still open">.
- Files: docs/architecture/0002-cli-role-topology.md,
  docs/architecture/0001-root-file-exceptions.md
- Decisions: TUI contingency resolved via (a) owner WT check 2026-07-09 —
  swap unconditional; provider keys stay user-scope local (owner directive
  "use as is"; repo config key-free); migration checklist (44 files) in
  .ai/research/adr-drafts-crush-to-opencode.md §3 governs the follow-up
  commits.
- Grep-verified evidence: <paste post-edit grep lines for "OpenCode
  replaces Crush" in both ADRs>
```

---

## Appendix A — grep evidence for the migration checklist

One or two matching lines per file (`grep -in crush`, 2026-07-09 tree).
Historical/no-change files included where useful for the NOT-edited calls.

**Root**
- `CRUSH.md:3` — `You are **Crush**, one of four AI CLIs working in this project`
- `.crush.json` — full content: `{ "mcp": {} }` (no `crush` literal, no keys; listed via CRUSH.md cross-reference + ADR-0001 entry)
- `AGENTS.md:27` — `| Crush | /CRUSH.md (project root — Crush's native context file; Claude-maintained per ADR-0001) |`
- `CLAUDE.md` (AI Contract header) — `Crush: general helper + DevOps deployment operator — see CRUSH.md + ADR-0002, amended 2026-07-08` / `You are custodian of Crush's files (CRUSH.md, .crush.json) per ADR-0001.`
- `README.md:442` — `| Crush | .ai/** (activity log, reports, handoffs) | Everything else`

**.ai/**
- `.ai/cli-map.md:101` — `| **Session-root config** | .crush.json (project root — MCP wiring) |`
- `.ai/cli-map.md:107` — `| **Handoff inbox** | .ai/handoffs/to-crush/open/ |`
- `.ai/sync.md:37` — `## Crush (no replicas)`
- `.ai/known-limitations.md:8` — `## Crush — no hook layer at all; runs permission-bypassed in daily use`
- `.ai/tools/dispatch-handoffs.sh:41` — `crush)  printf '%s' "crush run \"$prompt\"" ;;`
- `.ai/handoffs/README.md:17` — `Also custodian of Crush's files (CRUSH.md, .crush.json) per ADR-0001.`
- `.ai/handoffs/README.md:41` — `└── to-crush/`
- `.ai/handoffs/template.md:3` — `Sender: <claude-code | kimi-cli | kiro-cli | crush>`
- `.ai/instructions/operating-prompt/principles.md:62` — `- **Crush — general helper + DevOps deployment operator (Stage 2).**`
- `.ai/instructions/orchestrator-pattern/principles.md:119` — `- **Deploy (amended 2026-07-08):** Kimi/Kiro have no deploy lane. Crush is`
- `.ai/instructions/agent-catalog/principles.md:98` — `- **Crush** — general helper + DevOps deployment operator (Stage 2 granted`
- `.ai/instructions/code-graphs/principles.md:124` — `### Crush — no graph wiring (ADR-0003)`
- `.ai/handoffs/to-crush/` — exists with `open/.gitkeep`, `done/.gitkeep` (glob-verified; rename target)
- Historical (NOT edited): `.ai/activity/log.md:104` — `- Files: ... CRUSH.md, .mcp.json, .crush.json, ...`; `.ai/research/4ai-panes-integration-notes.md:40` — `| 4 | Crush | crush --yolo |`; `.ai/research/worktree-multi-project-topology.md:48` — `crush/  .ai -> junction   git worktree, branch exec/crush/<task>`; `.ai/handoffs/to-{kimi,kiro,claude}/done/*` (5 files, e.g. `202607071330-fleet-upgrade-continuation.md:60` — `| Crush | **Worst**: crush --yolo with NO CRUSH.md`)

**.claude/**
- `.claude/hooks/pretool-write-edit.sh:128` — `CRUSH.md|.crush.json) : ;;                       # Crush custodianship (ADR-0001)`
- `.claude/hooks/pretool-write-edit.sh:154` — `.mcp.json|.mcp.json.example|.crush.json) exit 0 ;;`
- `.claude/hooks/test_hooks.sh:77` — `run_test "t25 CRUSH.md allowed"          "$WE" '{"tool_input":{"file_path":"CRUSH.md"}}'                 0`
- `.claude/agents/release-engineer.md:13` — `You are the **FALLBACK deploy lane**. Crush is the primary DevOps deployment`
- `.claude/skills/operating-prompt/SKILL.md:69` — `- **Crush — general helper + DevOps deployment operator (Stage 2).**`
- `.claude/skills/orchestrator-pattern/SKILL.md:126` — `- **Deploy (amended 2026-07-08):** Kimi/Kiro have no deploy lane. Crush is`
- `.claude/skills/agent-catalog/SKILL.md:105` — `- **Crush** — general helper + DevOps deployment operator (Stage 2 granted`
- `.claude/skills/code-graphs/SKILL.md:131` — `### Crush — no graph wiring (ADR-0003)`

**.kimi/ and .kiro/**
- `.kimi/steering/operating-prompt.md:62` — `- **Crush — general helper + DevOps deployment operator (Stage 2).**`
- `.kimi/steering/orchestrator-pattern.md:119` — `Kimi/Kiro have no deploy lane. Crush is`
- `.kimi/steering/agent-catalog.md` — (in files-with-matches set; same role-lane block as SSOT #14)
- `.kimi/steering/code-graphs.md:124` — `### Crush — no graph wiring (ADR-0003)`
- `.kiro/steering/operating-prompt.md:4` — `**Kiro CLI**, or **Crush** — working inside a shared project workspace.`
- `.kiro/steering/orchestrator-pattern.md:119` — `Kimi/Kiro have no deploy lane. Crush is`
- `.kiro/steering/agent-catalog.md:98` — `- **Crush** — general helper + DevOps deployment operator (Stage 2 granted`
- `.kiro/steering/code-graphs.md:124` — `### Crush — no graph wiring (ADR-0003)`
- `.kiro/agents/release-engineer.json` — (in files-with-matches set; deploy-lane wording parity with `.claude/agents/release-engineer.md:13`)

**tools/**
- `tools/4ai-panes/Selector.ps1:30` — `$cliDefs["Crush"]  = @{ detect = "crush"; cmd = "crush --yolo" }`
- `tools/4ai-panes/Selector.ps1:282-283` — `'CRUSH.md',` / `'.crush.json',`
- `tools/4ai-panes/Launch4Panes.ps1:2` — `# Opens Windows Terminal with Selector (full width), which splits into Claude|Kiro|Kimi|Crush`
- `tools/4ai-panes/README.md:37` — `- Crush (crush --yolo)`
- `tools/multi-cli-install/src/upgrade/manifest.ts:10-11` — `'CRUSH.md',` / `'.crush.json',`
- `tools/multi-cli-install/src/installer/copy-framework.ts:9-10` — `'CRUSH.md',` / `'.crush.json',`
- `tools/multi-cli-install/src/installer/wire-mcp.ts:8` — `// - Crush: no graph wiring, ever (.crush.json is never touched here).`
- `tools/multi-cli-install/scripts/sync-assets.ts:26` — `for (const f of ['CLAUDE.md', 'AGENTS.md', 'CRUSH.md', '.crush.json', ...])`
- `tools/multi-cli-install/test/installer.test.ts:288` — `it('wireMcp never touches an existing .crush.json (Crush gets no graph, ever)', () => {`
- `tools/multi-cli-install/test/upgrade-phase-a.test.ts:312-313` — `expect(keys).toContain('CRUSH.md');` / `expect(keys).toContain('.crush.json');`
- False positive: `tools/kirograph/src/bin/installer/common.ts:7` — `export type InstallTarget = 'kiro' | ... | 'opencode' | ... | 'crush' | ...` (generic third-party target list; opencode already present)

**scripts/**
- `scripts/wt-bootstrap.sh:23` — `DEFAULT_EXECUTORS="kiro kimi crush"`
- `scripts/fleet-init.sh:291` — `| **Intra-project** | project-x/.ai/handoffs/ | a project's Claude ↔ its executors (Kiro/Kimi/Crush) |`

**docs/**
- `docs/guides/framework-upgrade-runbook.md:127` — `- CRUSH.md and .crush.json — Crush's entire contract lives in these two`
- `docs/architecture/0001-root-file-exceptions.md:24` — `- CRUSH.md — Crush CLI's always-loaded context/contract file (Crush reads root context files natively; added per ADR-0002 Crush onboarding)`
- `docs/architecture/0001-root-file-exceptions.md:57` — `- .crush.json — Crush CLI config (MCP wiring). NOTE: file predates this amendment ...`
- `docs/architecture/0002-cli-role-topology.md:22` — `- **Crush** — general helper + DevOps deployment operator (onboarded 2026-07-07).`
- `docs/architecture/0003-code-graph-rationalization.md:18` — `4. **Crush gets no graph wiring.** Its ADR-0002 ops/release lane doesn't need structural code queries; .crush.json MCP entries are removed.`
- `docs/architecture/0004-worktree-multi-project-topology.md:38` — `crush/  .ai -> junction   git worktree, branch exec/crush/<task>`
- `.gitignore` — grep for `crush|opencode`: no matches (verified; no edit required)
