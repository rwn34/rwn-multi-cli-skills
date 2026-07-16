# Migrate default branch from `master` to `main`

Status: DONE
Sender: kimi-cockpit
Recipient: claude-auto
Owner: claude-auto
Created: 2026-07-16 19:31 (UTC+7)
Auto: yes
Risk: B
Next: opencode-auto, then kimi-cockpit

## Goal

Migrate the rwn-multi-cli-skills repository so that `main` becomes the sole
default branch, retiring `master`. This is a framework-wide change because many
tools, tests, and docs currently assume `master`.

## Deliverables

1. **Audit** every hardcoded reference to `master` / `origin/master` in the
   framework. Search at least:
   - `.ai/tools/dispatch-handoffs.sh` and `base_for()` default resolution
   - `.ai/tests/test-dispatch-worktree.sh`
   - `scripts/wt-bootstrap.sh`
   - `tools/4ai-panes/*.ps1`
   - `.github/workflows/*.yml`
   - `docs/architecture/*.md` and `docs/specs/*.md`
   - `AGENTS.md`, `.ai/handoffs/README.md`, and any install/sync scripts
   - Any `Base: origin/master` lines in open handoffs (skip `.archive/`)

2. **Write a migration plan** at `.ai/reports/migrate-master-to-main-plan.md`
   containing:
   - Exact list of files that must change and the replacement in each.
   - Git/GitHub steps: rename local branch, push `main`, update default branch
     on GitHub, retarget branch protection, delete `master`.
   - Worktree reconciliation plan: how existing `.wt/` worktrees (which may have
     been cut from `origin/master`) are refreshed or recreated safely.
   - Rollback steps if something breaks.

3. **Create an execution handoff** for `opencode-auto` at
   `.ai/handoffs/to-opencode/open/YYYYMMDDHHMM-execute-master-to-main-migration.md`
   that:
   - References the plan file above.
   - Instructs opencode-auto to apply every file change, run the Git/GitHub
     operations it is authorized for (Tier B per OpenCode contract), and push
     the result.
   - Explicitly requires opencode-auto to emit a final verification handoff to
     `kimi-cockpit` at
     `.ai/handoffs/to-kimi/open/YYYYMMDDHHMM-verify-master-to-main-migration.md`
     when done.

4. **Self-retire** this handoff (Status: DONE, move to `to-claude/done/`) once
   the plan and the opencode handoff are written.

## Constraints

- Do **not** perform the migration yourself — this is planning + handoff routing
  only.
- Do not modify `.archive/` or already-closed `done/` handoffs.
- The plan must keep the framework runnable on Windows PowerShell / Git Bash.
- Any change to `.github/` is OpenCode's lane; route it through the opencode
  handoff, not a direct edit.

## Verification

- The plan file exists and is internally consistent.
- Every hardcoded `master` reference found by the audit is mapped to a concrete
  change.
- The opencode execution handoff exists in `to-opencode/open/` and explicitly
  routes the final verification back to `kimi-cockpit`.

## Activity log

Prepend an entry with identity `claude-auto` when this handoff is retired.
