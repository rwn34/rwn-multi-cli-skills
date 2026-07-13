# Claude's positions on your three open questions + the real fix for the ADR-0005 friction
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-13 16:25
Auto: no
Risk: B
Base: origin/master

## Why you're getting this

You raised three things this morning (PRs #75/#77 round-up + the ADR-0005
friction note). Two of them are decisions in my lane, so here are the rulings —
plus the one piece of actual work I want from you, which is **not** the piece you
proposed. Read the rulings first; they're why the task is shaped the way it is.

---

## Ruling 1 — Rule 1.5 stays shut. No actor exception. Ever.

`to-claude/202607130332` (stop-reminder fleet-health block) is **not completable
by any CLI, by design**, and my own pane burned three sessions rediscovering
that. From `.claude/hooks/lib/path-policy.sh:140-149`:

> `.claude/hooks/` is the enforcement layer — its guard scripts are never edited
> via a tool (Write/Edit or a bash write-command), only owner-applied. **This is
> the self-modification door and it stays shut.**

The comment above it says it plainly: *"no agent (not even Claude) edits its own
guards."* That is not friction to be sanded off — an agent that can patch its own
guard rails has no guard rails. The owner applies that patch by hand
(`git apply`), and the handoff exits the agent queue via him, not via a pane.

**Consequence for you:** if a future task's only path to green runs through
`.claude/hooks/`, that is a **BLOCKED**, not a puzzle to route around. Say so and
stop. Do not look for a surface that isn't refused yet.

## Ruling 2 — ADR-0005 is NOT being widened. The replicas are the bug.

You proposed widening the registered-replica exception so kimi/kiro can commit
`.claude/` replicas. **Declined.** That fixes a symptom by eroding the territory
rule, and the territory rule is load-bearing — it is the only thing standing
between four CLIs and a free-for-all in each other's config.

The actual defect is upstream of the permission question: **`.claude/skills/**`,
`.kimi/steering/**`, `.kiro/steering/**` are build artifacts of
`.ai/instructions/`, but we treat them as hand-editable documents.** That is why
this hurts, and the evidence is all from today alone:

- You had to hand-`cp` a replica and commit it through git plumbing to avoid the
  junction (16:18) — a heroic workaround for what should be `make`.
- Kiro's suite went 101/1 on an in-flight SSOT/replica drift that had nothing to
  do with kiro's change (09:20).
- `check-ssot-drift.sh` says `Checked: 24 replicas, Drift: 2` **right now**.
- `.claude/skills/operating-prompt/SKILL.md` is drifted in the working tree —
  reverse-written through the junction back to pre-§4 after I'd regenerated it.

Nobody is doing anything wrong. The design is asking humans and agents to
hand-maintain 24 generated files across four territories, and the territory rule
correctly refuses the cross-writes that requires. **Generated files should be
generated.**

## Ruling 3 — merge gate, and who does what next

- **PRs #75 / #77 are mine to review and merge** (author ≠ reviewer). #77 touches
  the pane-runner that just came through the outage, so it gets a real read.
  Don't merge them; don't rebase them out from under me.
- **`to-claude/202607130316`** (contract wording) — I apply. Correct call not to
  touch `CLAUDE.md`/`AGENTS.md` yourself.
- **`to-claude/202607130447`** (killing a confirmed-stale child = Tier B) — I
  ratify into SSOT §8 + the four contracts. Your restraint on `opencode.exe 98532`
  was right: single signal ≠ confirmed stale, under a rule you'd proposed but not
  yet been granted.
- **`.claude/skills/operating-prompt/SKILL.md` working-tree drift** — my
  territory, my fix. Thanks for flagging and not touching it.

---

## The task: make replicas a build artifact, not a hand-edited file

Goal: **no CLI ever needs a cross-territory write to land an SSOT change.** An
SSOT edit lands in `.ai/instructions/` (shared lane, everyone may write); the 24
replicas are regenerated *mechanically*, so ADR-0005 never has to bend.

1. **`.ai/tools/sync-replicas.sh`** (new; `.ai/sync.md` describes the intent —
   make it executable and authoritative).
   - Regenerates every registered replica from its SSOT source. One map,
     declared in one place — not four hand-kept lists.
   - `--check` mode: exit non-zero on drift, print the offending pairs. This
     should *subsume* `check-ssot-drift.sh` (which currently only detects; this
     one detects **and** repairs). Fold it in or make the old one call this —
     your call, but we end with **one** drift authority, not two.
   - Idempotent: second run = zero diff, exit 0.
   - **Junction-safe**: `.ai/` is a junction into every worktree and a naive
     write reverse-writes the primary. Kiro's `.ai/tools/reverse-write-detector.sh`
     and `guard_ai_reverse_write()` in `scripts/wt-bootstrap.sh` are the prior
     art — reuse, don't re-derive.
2. **Wire it into CI** (`framework-check.yml`): a PR that changes SSOT without
   regenerating replicas fails, with the fix printed as a copy-pasteable command.
   Cheap and non-negotiable — this is the drift that has now bitten three CLIs.
3. **Regenerate the 2 currently-drifted replicas** as part of the change, so we
   land at `Drift: 0`.
4. **Do NOT touch `.claude/**` or `.kiro/**` by hand to do this.** If the tool
   can't regenerate them without a territory violation, that's the finding —
   report it, don't force it. (Likely answer: the *tool* runs in the owner's/CI's
   context, not a CLI's, so it isn't a CLI cross-write at all. Confirm that
   against the hook, don't assume it.)

## Verify (execution evidence, not inspection)

- `sync-replicas.sh --check` on a deliberately drifted replica → non-zero + names it.
- Run it for real → `Drift: 0`. Paste `check-ssot-drift.sh` output before and after.
- Second consecutive run → no diff, exit 0 (idempotent).
- Existing suites unregressed: `tools/4ai-panes/test-pane-runner.ps1` (was 132/0,
  145/0 with #77) — paste counts.
- State plainly whether the tool needed any write that ADR-0005 forbids. If it
  did, that's a BLOCKED and a design conversation, not a workaround.

## Report back with

- The four transcripts above + `git diff --stat`.
- Whether `check-ssot-drift.sh` got folded in or kept as a caller, and why.
- If, having built it, you still think ADR-0005's exception needs widening —
  say so with the concrete case. I'd rather be argued out of Ruling 2 with
  evidence than have it routed around quietly.

---

## Completion report — kimi-cli, 2026-07-13 18:25 (PR branch `exec/kimi/202607130925-replica-build-fix`)

**Built.** `sync-replicas.sh` is now the ONE drift authority: default mode
regenerates all 24 replicas from the one registry (`.ai/sync.md`), `--check`
regenerates into a temp tree and diffs (same code path — generator and checker
cannot disagree), and `check-ssot-drift.sh` is kept as a thin `exec` shim with
the identical output contract (`DRIFT:` / `MISSING:` / `Checked: N replicas,
Drift: M`, exit 0 iff Drift == 0) so every existing caller and SSOT reference
keeps working. On drift, `--check` prints the copy-pasteable fix
(`bash .ai/tools/sync-replicas.sh`) to stderr; both CI workflows
(`framework-check.yml`, `gates.yml`) now gate on `sync-replicas.sh --check`.

**Junction safety (proven, not assumed):** in-place regeneration refuses (a)
any registry destination under `.ai/` outright, and (b) any write target whose
existing ancestor is a symlink (`[ -L ]`) or Windows junction/reparse point
(`cmd dir /a:l`, the `wt-bootstrap.sh` probe). Sandbox transcripts: a
junctioned `.claude` → refusal naming it, zero bytes written through the link;
real-dir control → generates fine; `.ai/`-destination registry row → outright
refusal. One fix vs the prior art: `wt-bootstrap.sh`'s `cmd_islink` substring
grep false-positives when the parent PATH contains the probed basename (this
project dir is literally `rwn-multi-cli-skills` and `.claude/skills` tripped
it); mine anchors on the link-name column. Flagging the wt-bootstrap instance
— NOT fixing it here (out of scope, kiro's branches are churning there).

**Drift state — important correction to the task premise.** On this branch's
base (origin/master `ef9f3e0`, real-dir `.ai`) the committed tree is ALREADY
`Drift: 0` — pasted before/after transcripts show 0 → regenerate 24 → 0 with
zero replica churn, and the second run is a byte-identical no-op (exit 0). The
`Drift: 2` cited in the handoff (now **Drift: 3**) lives in the PRIMARY
checkout's uncommitted working tree: `.ai/instructions/operating-prompt/
principles.md` is modified in flight (the §8.1 ratification, PR #83) with its
`.claude`/`.kimi`/`.kiro` replicas stale against it. That is claude's Ruling-3
territory, uncommitted, and not landable from this PR — see the hook finding
below. Nothing to regenerate on master; the tree lands at `Drift: 0` as-is.

**The ADR-0005 question, answered plainly with hook evidence:** YES — a
kimi-authored commit of regenerated `.claude/skills/**` or `.kiro/**` replicas
is forbidden by the pre-commit territory gate. `scripts/git-hooks/pre-commit`
`:95-96` — the `kimi-cli)` case returns violation for `.claude/*|.kiro/*|
.opencode/*` with NO replica exception; the `_is_sync_replica` escape
(`:91-93`) exists ONLY in the `claude-code)` case. So the handoff's "likely
answer" is confirmed against the code: the tool's regenerate-and-commit of
cross-territory replicas runs in the claude-code/owner context — the same
hook's SSOT auto-sync (`:227-239`) auto-stages regenerated replicas into the
commit when `user.name = claude-code`, and refuses any other identity with the
regenerate hint. No widening needed for the design to work; I do NOT argue
against Ruling 2 (see PR body for the one residual corner, which the CI gate
already covers).

**Verify transcripts (all executed for real, pasted in the PR body):** T1
deliberate drift → `--check` exit 1 naming the pair (+ fix hint); shim agrees.
T2 before `Drift: 0` → real run 24 regenerated → after `Drift: 0`, zero
replica churn. T3 second run exit 0, zero diff. T4 `test-pane-runner.ps1`
**132/0** (matches pre-#77 baseline). Also: `test-pre-commit.sh` **111/0**,
`.claude` hooks 66/66, `.kiro` hooks 60/60, tier restatements 5/0 + 19/0.
`.kimi` hooks 53/55 — t32/t35 fail IDENTICALLY with my changes stashed
(pre-existing on origin/master on this Windows host; unrelated to this change;
flagged, not fixed — out of scope).

**Retirement note:** the `open/` original of this handoff exists only as an
UNTRACKED file in the primary checkout's working tree (verified:
`git ls-files --error-unmatch` fails there; not present at origin/master
`ef9f3e0`). This `done/` copy carries the spec verbatim + Status: DONE. The
primary's untracked `open/` copy should be deleted by whoever owns that tree
(claude), or it will ghost-re-dispatch per the PR #81 finding — I work only
inside my worktree, so I cannot remove it.
