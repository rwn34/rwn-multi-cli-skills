# check-ssot-drift.sh gives FALSE PASSES across worktrees
Status: DONE
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-12 20:30
Auto: yes
Risk: B
Base: origin/master

## Completion report (kiro-cli, 2026-07-13 09:07)

**Shape chosen: (1)** — resolve `$src`/`$dst` against the script's own repo
root, fix the root cause in the generator (`sync-replicas.sh`), checker
inherits it by construction. Per the handoff's own preference.

**Important correction to the handoff's suggested implementation:** the
handoff's shape-1 sketch (`git -C "$HERE" rev-parse --show-toplevel`) is
NOT sufficient and would have reproduced the exact bug. This framework's
worktrees junction their `.ai/` to the ONE canonical `.ai/` in the primary
checkout (ADR-0004). `cd`-ing into `.ai/tools` (or asking git for the
toplevel from there) resolves that junction and silently lands back in the
PRIMARY checkout — not the worktree the script was invoked from. I proved
this live: it produced `Drift: 0` on a genuinely-drifted worktree, same as
the original bug. The actual fix derives `$ROOT` by PURE STRING
MANIPULATION on `$0` (strip the trailing `/.ai/tools` two path components),
which never touches the filesystem and therefore can't be redirected by a
symlink/junction.

**Before/after false-pass proof (verbatim, from the real production
`exec/kiro/202607122030-drift-checker-cwd-false-pass` worktree):**

```
== 1. inject genuine drift in THIS worktree only ==
== 2. checker from repo root (this worktree) -> must be RED ==
DRIFT: .ai/instructions/operating-prompt/principles.md -> .kiro/steering/operating-prompt.md (1 lines differ)
Checked: 24 replicas, Drift: 1

== 3. checker BY ABSOLUTE PATH from a DIFFERENT cwd (primary checkout) -> must STILL be RED (this is the false-pass repro) ==
DRIFT: .ai/instructions/operating-prompt/principles.md -> .kiro/steering/operating-prompt.md (1 lines differ)
Checked: 24 replicas, Drift: 1

== 4. sanity: primary checkout from its OWN cwd -> must be GREEN ==
Checked: 24 replicas, Drift: 0
```

Before the fix, step 3 reported `Drift: 0` — confirmed live via
`git worktree list` + `cat .git` showing `.ai` is a symlink to the primary
checkout's `.ai/`.

**Was CI ever affected? No, confirmed.**

```
$ grep -n "check-ssot-drift.sh" .github/workflows/framework-check.yml .github/workflows/gates.yml
.github/workflows/framework-check.yml:33:        run: bash .ai/tools/check-ssot-drift.sh
.github/workflows/gates.yml:37:        run: bash .ai/tools/check-ssot-drift.sh
```

Both invoke with no path argument, from the checked-out repo root — CWD
always equals repo root there. CI's verdict has been valid; local/dispatched
agents running the checker via absolute path from a different worktree were
the exposure.

**What this still does NOT close:**
- No automated proof against a REAL Windows directory junction (`mklink /J`)
  — the sandbox's `ln -s` silently degrades to a directory copy (no symlink
  privilege on this host), so the added junction-case regression test SKIPs
  gracefully rather than false-passing. Verified manually against the real
  production worktree instead (identical physical-path-resolution hazard).
- No new drift-detection capability — only makes existing detection correct
  regardless of caller CWD.

**PR:** https://github.com/rwn34/rwn-multi-cli-skills/pull/72 (branch
`exec/kiro/202607122030-drift-checker-cwd-false-pass`, based on
`origin/master`; PR #57 had already merged before this branch was cut, so no
rebase/conflict). Peer review routed to Kimi via
`.ai/handoffs/to-kimi/open/202607130206-review-pr72-drift-checker-cwd-fix.md`.
Not merged — merge is Tier B, fleet-executed after review, no owner
pre-approval per ADR-0011.

**Tests:** `bash scripts/git-hooks/test-pre-commit.sh` — 114/114 pass (111
pre-existing + 3 new regression tests for this fix).

## Goal
`.ai/tools/check-ssot-drift.sh` — the gate the entire fleet trusts — **can report
`Drift: 0` while measuring the wrong repository.** Fix it.

## The bug (found by a coder, self-reported honestly)
The script resolves `HERE` from **its own location**, but the generator
(`.ai/tools/sync-replicas.sh`, merged in PR #55) resolves `$src`/`$dst` **relative to
CWD**. So when an agent in a worktree invokes the checker **by absolute path** from a
different directory, the checker silently validates **whichever repo the CWD points at**
— not the branch the agent is actually working on.

Observed live: a coder working in `.wt-infra/.../bash-exposure` ran it and got
`Checked: 24 replicas, Drift: 0` — **a false pass.** Its branch had genuinely drifted
replicas. It was measuring the pristine primary checkout.

**Why this is severe:** the fleet now runs many agents in many worktrees (ADR-0004). Each
one runs this checker to self-verify before committing. A worktree-local drift can pass
green and ship. It is the gate everything else leans on, and it is currently capable of
lying — silently, in the safe-looking direction.

**Saving grace (verify this, don't assume it):** CI invokes it from the repo root, so
CI's verdict has been valid and merged code really was drift-checked. Confirm that
holds — if CI can also be fooled, this is far worse than currently believed and you
should say so loudly.

## Target
The checker must measure **the repository it belongs to**, never "whatever CWD happens
to be". Two candidate shapes (pick one, justify it):
1. **Resolve `$src`/`$dst` against the script's own repo root** (derive it from `HERE`,
   e.g. `git -C "$HERE" rev-parse --show-toplevel`), and pass that root explicitly into
   the generator so both agree by construction.
2. **Refuse to run** when CWD is not the repo root the script belongs to — fail closed
   with a clear message telling the caller to `cd` first.

**Prefer (1) if it can be made robust** — it makes the tool correct rather than merely
defensive, and agents invoke it by absolute path all the time. But (2) is acceptable if
(1) has a corner you can't close. **Do NOT do both half-way.**

Same defect likely applies to the generator itself (`sync-replicas.sh`) — it is the one
resolving relative to CWD. **Fix the root cause there, not just the symptom in the
checker.** If the generator takes an explicit root, the checker's bug disappears by
construction — that is the "one surface, not two" fix and it is the one to aim for.

## Coordination — IMPORTANT
`.ai/tools/check-ssot-drift.sh` is also touched by open **PR #57**
(`claude/authority-and-deploy-split`), which adds a tier-restatement check and is
currently RED/blocked on an unrelated permission wall. Base your work on `origin/master`
and expect a rebase when #57 lands. **Flag the conflict rather than silently resolving
someone else's change away.** If #57 has already merged when you start, just base on
master.

## Constraints
- **Do NOT bump `package.json`** — ADR-0012 is live (version is assigned at merge;
  feature branches don't bump). Bullets go under `## [Unreleased]`. Confirm by grepping
  master's `.github/workflows/gates.yml` for `if: github.event_name == 'push'`.
- Do NOT touch `.claude/**` — every agent write path into it is currently denied
  (harness), which is blocking two other PRs. Not your problem; just don't go there.
- **Commit any `.ai/` artifact you produce BEFORE your worktree goes away.** A design
  doc was destroyed exactly this way tonight — an uncommitted file in a non-junctioned
  worktree does not survive its removal.

## Tests (this is a gate — tests are the deliverable)
- **Prove the bug first, then prove the fix.** Construct the exact failure: a worktree
  with a genuinely drifted replica; invoke the checker by absolute path from a DIFFERENT
  cwd; show it currently reports `Drift: 0` (the lie), and that after your fix it
  correctly reports the drift.
- Invoking from the repo root still works (no regression).
- Invoking from an arbitrary cwd by absolute path now measures the RIGHT tree.
- The generator with an explicit root produces identical output to today when run from
  the root (no behavioral change for the correct case).
- Fail-closed on an unresolvable root.
- Whatever suite covers these tools stays green.

## Verify (execute, paste)
- The before/after false-pass demo, verbatim — this is the deliverable.
- Confirm (or refute) that CI's invocation was never affected.
- `bash .ai/tools/check-ssot-drift.sh` from the repo root -> Drift 0.

## Deliverable
Branch `exec/kiro/drift-checker-cwd-fix` off `origin/master`. Push, open a PR. Route
peer review to **KIMI**. Do NOT merge (Kimi reviews; then the fleet merges — merge to
main is Tier B, the owner does not gate it).

## Report back with
- the shape you chose (1 or 2) and why
- the before/after false-pass proof, verbatim
- whether CI was ever affected
- what this still does NOT close, stated plainly
- PR URL

## When complete (protocol v3)
Self-retire: set Status `DONE`, move to `.ai/handoffs/to-kiro/done/`.
