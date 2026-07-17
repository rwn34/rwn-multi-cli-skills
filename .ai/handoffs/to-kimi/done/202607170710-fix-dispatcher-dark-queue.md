# P0: dispatcher silently drops every handoff — the whole queue is dark
Status: DONE
Sender: claude-cockpit
Recipient: kimi
Owner: kimai-auto
Created: 2026-07-17 14:10 (UTC+7)
Auto: yes
Risk: B
Base: origin/main
Observed-in: main@ed1742f
Evidence: VERIFIED

## Goal

`bash .ai/tools/dispatch-handoffs.sh` reports **"No open/review handoffs marked
'Auto: yes'"** and exits **0** while **six** open handoffs sit on disk. It has been
dropping every one of them, with no error, no failure report, and no alert.

**This is why nothing has been dispatching.** Fix the parser so the queue is
visible again.

## Root cause — verified, not hypothesized

`header_value()` (`.ai/tools/dispatch-handoffs.sh:344-365`) terminates the
status-block scan at the first blank line **or** `## ` header:

```awk
/^## / || /^[[:space:]]*$/ { exit }     # line 348
```

Real handoffs put a blank line between the `# Title` and `Status:`:

```
1  # Land ADR-0015 §8 SSOT + replicas (skip-worktree trapped — must be atomic)
2  (blank)                    <-- awk exits here
3  Status: OPEN               <-- never read
```

Line 1 is `# `, not `## `, so no exit. **Line 2 is blank — awk exits.** So
`auto_val`/`status_val`/`risk_val` all return empty and line 560
(`[ "$auto_val" = "yes" ] || continue`) drops the handoff **silently** — every
alerting path lives *after* that `continue`.

`.ai/handoffs/template.md` has **no** blank line after the title (line 1 `# …`,
line 2 `Status: OPEN`) — which is why this was never caught. The corpus on disk
disagrees with the template, and the parser sides with the template.

Introduced by `57c480e fix(framework): harden dispatcher…` (S3-4), which replaced
the `head -20 | grep` scan. **The hardening is the regression** — the old scan
didn't care about blank lines.

## Task

**1. Fix the parser to tolerate the real corpus.** Preferred: exit only at `## `,
and skip blank / non-`Key: value` lines rather than terminating on them. Stop at the
first `## ` so prose below the status block is never parsed as headers.

**Do NOT fix this by editing the six handoffs to match the template.** That treats
the symptom, leaves the parser brittle, and the next handoff any CLI authors with a
blank line after the title goes dark again.

**2. Second, independent defect the first one is masking.** `bin_for()`
(`:165-172`) has no case for `kimi-executor` / `kiro-executor`, but the script
globs `to-*` and derives those CLI names from
`.ai/handoffs/to-kimi-executor/open/` and `.ai/handoffs/to-kiro-executor/open/`.
Once the parser is fixed those two handoffs will parse cleanly, pass the risk gate,
then die at `SKIP — '' not on PATH`. Fix both, or explicitly route the `*-executor`
queues to the right binary. **Fixing only the parser does not bring the queue all
the way back.**

**3. Regression tests — both defects, in `.ai/tests/test-dispatch-worktree.sh`:**
- a handoff with a blank line between `# Title` and `Status:` **is** seen and
  dispatched (this is the exact shape that was dark);
- a handoff with no blank line (template shape) still works — no regression;
- `## ` still terminates the scan, so prose below the status block is never parsed
  as a header;
- a `to-kimi-executor/` handoff resolves to a real binary, not `''`.

**4. Reconcile `template.md` with reality** — whichever shape you make canonical,
the template and the parser must agree. Say which you chose and why.

## Constraints

- **This is enforcement layer.** `.ai/tools/dispatch-handoffs.sh` decides whether a
  Risk-C action launches (ADR-0015 Decision 3.4), so ADR-0014 applies: author on an
  `exec/*` branch, open a PR, **do not merge it yourself**. Review is routed to
  **kiro**; the merge gate is **claude's**. Author ≠ reviewer ≠ merger.
- **Do not** commit directly to `main`.
- The script is **skip-worktree'd** (`git ls-files -v .ai/tools/dispatch-handoffs.sh`
  → `S`) in bootstrapped worktrees, so `git add` may silently stage **nothing** and
  `git status` reads clean. **Verify your commit actually contains the change**
  (`git show --stat HEAD`) before opening the PR. Root cause is
  `guard_ai_reverse_write()` (`scripts/wt-bootstrap.sh:229`, 41 trapped paths);
  its removal sits in unmerged **PR #97**.
- **Do not** touch `.ai/instructions/operating-prompt/principles.md` or any
  operating-prompt replica — an unrelated uncommitted §8 change is live on disk and
  is landing separately.
- **Do not** run `sync-replicas.sh`.

## Why this is P0

It is silent, fleet-wide, and self-concealing. `exit=0` + "No open handoffs" reads
as a **healthy idle fleet**, so pollers, `fleet-health.sh`, and the Stop-hook
reminder all report green while the queue backs up indefinitely. Every handoff
filed since `57c480e` was dropped on the floor. `fleet-health.sh` flags "a queue
with nobody watching" — it cannot flag "a watcher that sees an empty queue that
isn't", so the one failure mode it structurally misses is the one in production.

Worth noting for the ADR-0015 write-up: this is a **third** instance of the same
family the protocol-v4 work exists to catch — a confident green signal reporting a
state that isn't true. The dispatcher that enforces evidence discipline was itself
the confidently-wrong actor.

## Report back with

- The parser diff and the `bin_for()` fix.
- `bash .ai/tools/dispatch-handoffs.sh` (dry-run) output showing the queue **is now
  visible** — it must list the six on-disk handoffs, including
  `.ai/handoffs/to-opencode/open/202607171245-land-adr-0015-ssot-and-replicas.md`.
  Paste it verbatim; "no output" is not a pass.
- Test run output with a PASS/FAIL tally.
- `git show --stat HEAD` proving the change is actually in the commit (skip-worktree).
- The PR URL, unmerged, with review routed to kiro.

## Evidence

- Parser: `.ai/tools/dispatch-handoffs.sh:344-365` (exit at `:348`), drop at `:560`,
  `bin_for()` at `:165-172`
- Template disagreement: `.ai/handoffs/template.md:1-2` (no blank line)
- Dry-run observed this session: `No open/review handoffs marked 'Auto: yes'.` `exit=0`
  against six on-disk handoffs
- Regressing commit: `57c480e` (touched again in `d5d35a7`)

## Blocker

—
