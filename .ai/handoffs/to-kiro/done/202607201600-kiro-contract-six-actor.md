---
Status: DONE
Sender: claude
Recipient: kiro
Created: 2026-07-20 16:00 (UTC+7)
Auto: yes
Risk: A
Base: origin/main
Observed-in: main@eabba85
---

# Update Kiro contract for six-actor model

## Goal

The framework just reverted from the eight-actor model to the six-actor model.
Only these actors remain:
- claude-cockpit
- kimi-cockpit
- claude
- kimi
- kiro
- opencode

Your own contract file `.kiro/steering/00-ai-contract.md` still references `kiro-cockpit`.
Update it and commit the change as kiro.

## Required change

In `.kiro/steering/00-ai-contract.md`:

1. Change the activity-log identity heading from:
   `## Your identity for the activity log: kiro-cockpit`
   to:
   `## Your identity for the activity log: kiro`

2. Update the explanatory paragraph from:
   ```
   You are the interactive Kiro cockpit session. The bare name `kiro` is the
   headless auto-pane identity; use `kiro-cockpit` for activity-log entries you
   prepend here.
   ```
   to:
   ```
   You are the interactive Kiro CLI session. The bare name `kiro` is also the
   headless auto-pane identity; there is no `kiro-cockpit`. Use `kiro` for
   activity-log entries you prepend here.
   ```

3. Update the activity-log template body heading from:
   `## YYYY-MM-DD HH:MM — kiro-cockpit`
   to:
   `## YYYY-MM-DD HH:MM — kiro`

The working tree already contains these exact edits; they were unstaged from
Claude's commit because the pre-commit hook blocks cross-CLI territory commits.
Your job is to stage, commit, and push `.kiro/steering/00-ai-contract.md` as kiro.

## Verification

- `bash .ai/tools/lint-handoff.sh` should pass.
- `git diff .kiro/steering/00-ai-contract.md` should show only the three identity changes above.
- Commit and push to main.

## On completion

Move this handoff to `.ai/handoffs/to-kiro/done/` and prepend a brief activity-log entry.

## Report

Status: DONE.

The three contract edits were **already present** in this worktree's
`.kiro/steering/00-ai-contract.md` at review time — the handoff's premise that
"they were unstaged from Claude's commit" did not hold for this snapshot (the
file matched the target text verbatim, confirmed via grep for the three
target strings). My job reduced to verification + commit/push, which I did:

1. `git diff .kiro/steering/00-ai-contract.md` showed exactly the 3 target
   changes (5 insertions / 5 deletions, single file) — no drift, no extra edits.
2. `bash .ai/tools/lint-handoff.sh` on this handoff → `OK: handoff lint passed`.
3. Committer identity was already `kiro-cli` (`git config user.name`).
4. Committed: `5f830d4 chore(kiro): update contract for six-actor model (drop kiro-cockpit)`.
5. Pushed to `origin/exec/kiro/202607201600-kiro-contract-six-actor` (not
   directly to `main` — per ADR-0004/ADR-0011 this fleet lands via
   peer-reviewed PR + CI, then a fleet merge; pushing straight to `main` would
   bypass that). A PR can be opened from this branch.

Verification evidence:

    $ git diff origin/main..HEAD --stat
     .kiro/steering/00-ai-contract.md | 10 +++++-----
     1 file changed, 5 insertions(+), 5 deletions(-)

Unrelated pre-existing worktree state (`.ai/.framework-version` modified,
`.ai/.snapshot-manifest` untracked) was left untouched — out of scope for this
handoff.
