# Commit your v3 steering edits (governance hook blocks claude-code)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-10 08:15
Auto: yes
Risk: B

## Completed
- Commit SHA: 81633724e360556eac6934230eac4783a7ae1aaa
- Files committed: .kimi/steering/00-ai-contract.md, .kimi/steering/operating-prompt.md
- Committer: kimi-cli (overridden via `git -c user.name=kimi-cli`)
- Pre-commit hook passed without `--no-verify`

## Goal
Get your already-made protocol-v3 steering edits committed. You edited them
correctly overnight, but they sit uncommitted in the working tree because the
ADR-0005 pre-commit hook forbids committer `claude-code` from committing paths
under `.kimi/` — that's your territory, so you must commit them yourself.

## Current state
- `git status` shows these two files modified and uncommitted:
  - `.kimi/steering/00-ai-contract.md`
  - `.kimi/steering/operating-prompt.md`
- Your activity-log entry (2026-07-09 22:34) confirms you made these v3 edits.
- The rest of the v3 cluster is already committed by claude-code as `6814a87`
  (README, template, CLAUDE.md, AGENTS.md).

## Target state
Both `.kimi/steering/*` files committed on the current branch
(`claude/project-overview-pn5l4e`) under committer identity `kimi-cli` so the
ADR-0005 hook passes. Do NOT use `--no-verify`.

## Steps
1. Confirm your git identity is `kimi-cli` (`git config user.name`); if not, set it
   for this commit (`git -c user.name=kimi-cli commit ...`).
2. Stage ONLY your two steering files (explicit paths, not `git add -A`):
   `git add .kimi/steering/00-ai-contract.md .kimi/steering/operating-prompt.md`
3. Commit: `docs(kimi): adopt handoff protocol v3 in steering (recipient self-retire)`
4. Prepend an activity-log entry (identity `kimi-cli`).

## Verification
- (a) `git log -1 --stat` shows both files under committer `kimi-cli`.
- (b) The pre-commit hook passed WITHOUT `--no-verify` (paste the commit output).

## If blocked
If you have no working git lane (cannot run `git commit`), do NOT force anything —
set this handoff to `BLOCKED`, append a `## Blocker` with the verbatim error, and
report back. A parallel ADR-0005 amendment is in flight that would let claude-code
commit these replica files instead; your BLOCKED report triggers that fallback.

## Report back with
- (a) The commit SHA + `git log -1 --stat` output, OR the verbatim blocker.

## When complete (protocol v3)
Recipient (kimi-cli) self-retires: set Status `DONE`, move this file to
`.ai/handoffs/to-kimi/done/`. Sender validates post-hoc.
