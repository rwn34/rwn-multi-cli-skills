# Framework upgrade runbook

How to bring an **old framework install** in an adopter project up to the
current template state. "Old" means the project was set up from an earlier
version of this template and is missing newer pieces — Rule 2.5 delegation
enforcement, `CRUSH.md`, the operating-prompt and delivery-integrity SSOTs,
role lanes (ADR-0002), rationalized graph wiring (ADR-0003), or the
`.ai/.framework-version` marker itself.

This is the manual procedure. It was battle-tested on the 4AI-panes repo
upgrade (2026-07-07) and embeds three lessons learned there — they are called
out inline as **Lesson (a)**, **(b)**, **(c)**.

> **Or use the installer.** `tools/multi-cli-install/` (npm package
> `@rwn34/multi-cli-install`) is growing an `--upgrade` mode. Phase A — the
> `.ai/.framework-version` marker plus a file manifest written at install
> time — lands in the same change set as this runbook; Phases B–F (detector,
> planner, merger, executor) are planned in
> [`.ai/research/framework-upgrade-mode-plan.md`](../../.ai/research/framework-upgrade-mode-plan.md).
> Until the full mode ships, this runbook is the supported upgrade path.

Terminology: **template repo** = a current checkout of this repository.
**Target project** = the adopter project being upgraded. All commands run
from the target project root in bash (Git Bash on Windows) unless noted.

---

## Phase 1 — Preflight

1. **Clean tree.** `git status` in the target project must be clean. Commit
   or stash anything pending — the upgrade must be reviewable as a single
   diff and revertible with `git reset --hard`.
2. **Fresh refs.** `git fetch` in both the target project and the template
   repo. Upgrade from the template's current `master`, not a stale checkout.
3. **Identify the install vintage.** Check for the version marker:

   ```bash
   cat .ai/.framework-version 2>/dev/null || echo "no marker — pre-marker (old) install"
   ```

   Absence of the marker means an old install — proceed with the full
   runbook. If the marker exists, compare its `framework_version` to the
   template's current version and skip phases that are already covered
   (the file's `upgrade_history` tells you what was applied when).
4. **Work on a branch.** `git checkout -b framework-upgrade` (the 4AI-panes
   upgrade used `framework-upgrade-adr0002`; any descriptive name works).

## Phase 2 — Preserve adopter runtime state

These paths are **adopter data, never template content**. The upgrade must
not touch them — not overwrite, not reset, not "helpfully" clean:

| Path | What it is |
|---|---|
| `.ai/activity/` | cross-CLI activity log + archive |
| `.ai/handoffs/to-*/open/`, `.ai/handoffs/to-*/done/` | live and completed handoff queues |
| `.ai/reports/` | audit/review outputs |
| `.ai/research/` | long-form research docs |

The activity-log/handoff **reset** commands in
[`.ai/sync.md`](../../.ai/sync.md) are for *first installs only*. Running
them during an upgrade destroys the project's history. If you script the
copy phase below, exclude these four paths explicitly.

(`.ai/handoffs/README.md` and `.ai/handoffs/template.md` are framework
files, not runtime state — they *do* get refreshed in Phase 3.)

## Phase 3 — Copy from the template

Copy the framework-owned files from the template repo over the target's
copies. The authoritative source→replica map is the table in
[`.ai/sync.md`](../../.ai/sync.md); the inventory below enumerates it plus
the surrounding framework files, all verified against the current template
tree.

**SSOT sources** — `.ai/instructions/<name>/principles.md` for all seven
SSOTs (plus `examples.md` where present):

- `agent-catalog`, `code-graphs`, `delivery-integrity`,
  `karpathy-guidelines` (+ `examples.md`), `operating-prompt`,
  `orchestrator-pattern`, `self-grep-verify`

**Shared `.ai/` framework files:**

- `.ai/sync.md`, `.ai/cli-map.md`, `.ai/README.md`
- `.ai/known-limitations.md` — **Lesson (b):** this file was missing from
  the original 4AI-panes copy list and had to be patched in afterward. It
  carries the Crush known-issue entries among others. It is on this list on
  purpose; do not drop it.
- `.ai/tools/check-ssot-drift.sh`
- `.ai/handoffs/README.md`, `.ai/handoffs/template.md` (protocol v2 adds
  the `Risk:` field)

**Per-CLI replicas** (generated from the SSOTs — see the sync.md map for
which files are byte-identical copies vs body-only replacements under a
frontmatter header):

- Claude: `.claude/skills/<name>/SKILL.md` for all seven SSOTs (body-only —
  keep each file's frontmatter and `<!-- SSOT: ... -->` line), plus
  `.claude/skills/karpathy-guidelines/EXAMPLES.md`
- Kimi: `.kimi/steering/<name>.md` for all seven, plus
  `.kimi/resource/karpathy-guidelines-examples.md`
- Kiro: `.kiro/steering/<name>.md` for all seven, plus
  `.kiro/skills/karpathy-guidelines/SKILL.md` (body-only — keep Kiro
  frontmatter)

**Hooks** (the enforcement layer — includes Rule 2.5):

- `.claude/hooks/*.sh` — `pretool-write-edit.sh`, `pretool-bash.sh`,
  `session-start.sh`, `stop-reminder.sh`, `test_hooks.sh`
- `.kimi/hooks/*.sh` — the four guards (`root-guard.sh`,
  `framework-guard.sh`, `sensitive-guard.sh`, `destructive-guard.sh`),
  the reminder/inject scripts, `test_hooks.sh`
- `.kiro/hooks/*.sh` — the four guards (`root-file-guard.sh`,
  `framework-dir-guard.sh`, `sensitive-file-guard.sh`,
  `destructive-cmd-guard.sh`), the activity-log scripts, `test_hooks.sh`

**Agent definitions:**

- `.claude/agents/*.md` (13 files: orchestrator + 12 subagents)
- `.kimi/agents/*.yaml` (13 files)
- `.kiro/agents/*.json`

**Root contracts and Crush files:**

- `CLAUDE.md`, `AGENTS.md`, `.kimi/AGENTS.md`
- `CRUSH.md` and `.crush.json` — Crush's entire contract lives in these two
  files (no skill/steering channel; Claude is custodian per ADR-0001/0002).
  An old install predating Crush onboarding has *neither*, which is the
  worst stale-fleet failure mode: a Crush pane running `--yolo` with no
  contract at all.

**CI:**

- `.github/workflows/framework-check.yml`

Copy-direction warning: hooks and agent files are overwritten wholesale by
this phase. If the target project locally amended any of them (most
commonly the ADR Category F root-file allowlist inside the guard hooks),
note those local diffs *before* copying — you re-apply them in Phase 4.

## Phase 4 — Adapt per-CLI wiring

Copying files is not enough; each CLI needs its hooks actually wired.

**Claude.** Hooks are wired in `.claude/settings.json` under `"hooks"`:
`PreToolUse` matcher `Write|Edit` → `bash .claude/hooks/pretool-write-edit.sh`,
matcher `Bash` → `bash .claude/hooks/pretool-bash.sh`, plus
`UserPromptSubmit`, `SessionStart`, and `Stop` entries. If the target
project already has a customized `settings.json`, merge the hooks block
rather than overwriting the file.

**Kimi.** Kimi's hooks are wired in the **user-global** `~/.kimi/config.toml`,
not in the project. The project ships a paste-ready block at
`.kimi/config.toml` — append its four `[[hooks]]` entries (root, framework,
sensitive, destructive guards) to `~/.kimi/config.toml` and restart Kimi.
The commands use project-relative paths, so they work in any project whose
session starts at its root. This is per-machine, one-time — skip if already
done for a previous project.

**Kiro.** Kiro's enforcement lives *inside each agent config*:
`.kiro/agents/*.json` carry both the `hooks.preToolUse` guard entries and
`toolsSettings.fs_write.deniedPaths` (e.g. coder denies
`.ai/**`, `.kiro/**`, `.kimi/**`, `.claude/**`). Verify both survived the
Phase 3 copy in every agent file — a partial copy here silently drops
enforcement.

**Re-apply local policy amendments.** If the target project had amended the
ADR Category F allowlist (language/tooling root files such as
`package.json`, `pyproject.toml`, `Cargo.toml`), re-apply those entries to
the freshly copied guard hooks in all three CLIs and confirm they match the
target's own `docs/architecture/0001-root-file-exceptions.md`.

## Phase 5 — Verify

All three gates must pass before the final step.

1. **Drift checker — zero drift:**

   ```bash
   bash .ai/tools/check-ssot-drift.sh
   # expect: "Checked: <n> replicas, Drift: 0" and exit 0
   ```

2. **Hook regression suites — all pass:**

   ```bash
   bash .claude/hooks/test_hooks.sh
   bash .kimi/hooks/test_hooks.sh
   bash .kiro/hooks/test_hooks.sh
   ```

3. **Rule 2.5 live probe.** Confirm main-thread delegation enforcement
   actually blocks. **Lesson (a):** the probe must target a
   **project-source path** such as `docs/hook-probe.tmp`. Probing anything
   under `.ai/` proves nothing — `.ai/` is writable by every agent
   including the orchestrator, so an `.ai/` probe "passes" even when
   Rule 2.5 is completely unwired.

   Mechanical probe (simulates a main-thread Write — no `agent_type` in
   the payload):

   ```bash
   printf '{"tool_input":{"file_path":"docs/hook-probe.tmp"}}' \
     | bash .claude/hooks/pretool-write-edit.sh; echo "exit=$?"
   # expect: exit=2 and a "Main-thread (orchestrator) write..." block message
   ```

   Live probe: in a fresh Claude session, ask the orchestrator to write
   `docs/hook-probe.tmp` directly — the PreToolUse hook must block it.
   (When blocked, no probe file is created; nothing to clean up.)

## Final step — write the version marker

**Lesson (c): this is deliberately the LAST step.** The marker is the
upgrade receipt — writing it early would stamp a project that might still
fail verification (the original 4AI-panes upgrade skipped it entirely and
needed a fixup). It is also what the 4AI-panes Selector badge reads:
`Get-ProjectBadges` in `tools/4ai-panes/Selector.ps1` shows `[v OK]` when
`.ai/.framework-version` exists, `[! OLD]` when `.ai/` exists without it,
`[- none]` when the framework is absent.

```bash
cat > .ai/.framework-version <<'EOF'
{
  "framework_version": "<template version, e.g. 0.0.4>",
  "installer_name": "manual-runbook",
  "installed_at": "<ISO 8601 UTC timestamp>",
  "upgrade_history": [
    { "from": "unknown", "to": "<template version>", "at": "<same timestamp>" }
  ]
}
EOF
```

Use the current `@rwn34/multi-cli-install` package version
(`tools/multi-cli-install/package.json`) as the framework version. Schema
details: [`.ai/research/framework-upgrade-mode-plan.md`](../../.ai/research/framework-upgrade-mode-plan.md) §3.

Then commit the branch, review the diff as a whole, and merge. Prepend an
activity-log entry in the target project noting the upgrade and the version.

## Related documents

- [`.ai/sync.md`](../../.ai/sync.md) — authoritative source→replica map
- [`docs/architecture/0001-root-file-exceptions.md`](../architecture/0001-root-file-exceptions.md) — root allowlist the guard hooks enforce
- [`docs/architecture/0002-cli-role-topology.md`](../architecture/0002-cli-role-topology.md) — role lanes behind Rule 2.5
- [`docs/architecture/0003-code-graph-rationalization.md`](../architecture/0003-code-graph-rationalization.md) — graph wiring old installs violate
- [`.ai/research/framework-upgrade-mode-plan.md`](../../.ai/research/framework-upgrade-mode-plan.md) — installer `--upgrade` plan (Phases A–F)
- `tools/multi-cli-install/README.md` — installer usage
