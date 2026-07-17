# Review: activity-log superset gate + pre-commit wiring

Status: OPEN
Sender: kimi-cli
Recipient: kiro-cli
Created: 2026-07-17 21:06 (UTC+7)
Auto: yes
Risk: B
ReviewOf: .ai/handoffs/to-kimi/open/202607171655-fix-log-recovery-gate-and-s-bit-deadlock.md
Branch: exec/kimi/202607171655-fix-log-recovery-gate-and-s-bit-deadlock
Commit: 79e5cc3

## What to review

Defect 1 of the source handoff: add `.ai/tools/check-log-superset.sh <candidate>`
and wire it into `scripts/git-hooks/pre-commit` for any commit staging
`.ai/activity/log.md`.

## Scope

- `.ai/tools/check-log-superset.sh`
- `.ai/tools/test-check-log-superset.sh`
- `scripts/git-hooks/pre-commit` (activity-log superset gate block only)
- `scripts/git-hooks/test-pre-commit.sh` (activity-log gate integration tests)

## Required checks

1. The checker compares **entry headers as a set** (`^## ` lines) across:
   - the `origin/main` blob of `.ai/activity/log.md`,
   - the current working-tree `.ai/activity/log.md`,
   - any `.ai/activity/log.md.bak` / `.ai/activity/log.md.KEEP*` files.
2. It FAILS a candidate that drops any header from any source.
3. It PASSES additions (candidate is a strict superset).
4. It deduplicates headers with `sort -u` so the known duplicate
   `## 2026-07-15 07:07 (UTC+7) — kimi-cli` does not read as loss.
5. The PR #107 repro (candidate superset of `main`, subset of working tree)
   fails the gate.
6. The pre-commit hook block reads the **staged** `.ai/activity/log.md` as the
   candidate and invokes the checker; on failure it rejects the commit with a
   clear ADR-0010 message.

## Verification to paste

```bash
bash .ai/tools/test-check-log-superset.sh
bash scripts/git-hooks/test-pre-commit.sh
```

Expected: 9/0 and 115/0 respectively.

## Outcome

- If approved, emit a final-review handoff to `to-claude/review/`.
- If rejected, move this handoff back to `to-kimi/open/` as `BLOCKED` with a
  verbatim `## Blocker`.

## Blocker

—
