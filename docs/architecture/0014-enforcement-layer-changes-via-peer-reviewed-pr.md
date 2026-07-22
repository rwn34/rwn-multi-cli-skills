# 14. Enforcement-layer changes land via peer-reviewed PR, not by owner hand-application

## Status

Accepted (2026-07-13).

Amends **Rule 1.5 only** of the shared path-policy classifier
(`.claude/hooks/lib/path-policy.sh`). Every other rule in that classifier —
Rule 1 (other CLIs' framework dirs), Rule 2 (sensitive-file patterns), Rule 2.6
(worktree confinement, ADR-0004), Rule 2.5 and the territory rules — is
**untouched**. Does not alter ADR-0005 (commit-governance backstop) or
ADR-0012 (version assigned at merge); applies the separation-of-duties principle
already established in ADR-0002 ("author ≠ reviewer ≠ deployer") to the
enforcement layer itself.

## Context

Rule 1.5 of `path-policy.sh` (the single decision point both the Write/Edit hook
and the Bash hook call, so the two surfaces cannot disagree) makes
`.claude/hooks/**` **owner-apply-only**. Verbatim, the rule and its own comment:

```sh
    # Rule 1.5 — enforcement-layer self-protection. The guard scripts are
    # owner-apply-ONLY: no agent (not even Claude) edits its own guards via any
    # tool (Write/Edit OR a bash write-command). The Claude harness already
    # refuses Write/Edit here; stating it in the shared classifier closes the SAME
    # door for the Bash surface (the side-door this fix exists to shut) and for any
    # subagent Write/Edit the harness may not cover — one rule, both surfaces.
    case "$rel_lc" in
        .claude/hooks|.claude/hooks/*|*/.claude/hooks|*/.claude/hooks/*)
            echo "BLOCK:1.5:.claude/hooks/ is the enforcement layer — its guard scripts are never edited via a tool (Write/Edit or a bash write-command), only owner-applied. This is the self-modification door and it stays shut."; return 0 ;;
    esac
```

**The rule's intent is correct and this ADR preserves it in full:** no agent may
unilaterally and unreviewably weaken its own guard rails. That constraint is not
negotiable and nothing below relaxes it.

What is being replaced is the rule's **escape hatch**, which in practice
degenerated into security theater:

- **The hatch is "the owner applies it by hand."** In the only real exercise of
  it, an agent authored a `.patch` file and asked the owner to `git apply` it —
  a diff the owner would not read, could not meaningfully review, and would
  apply on trust. That is agent self-modification with a human acting as a
  **relay**, exactly what the operating prompt rejects: §8 states plainly that
  *"the human is a gate, not a relay."* A gate that always opens is not a
  control; it is a delay with a signature on it.
- **The owner cannot be this control.** Owner directive (2026-07-13, this
  session): the owner is not a programmer, does not use git, and holds exactly
  **one** release-path gate — the **production deploy**. Merges and git mechanics
  are the fleet's (Claude's, or handed to OpenCode) — operating-prompt §8, owner
  directive 2026-07-12. "Owner reviews the hook diff" is therefore not a control
  this owner can exercise; it produces a rubber stamp, not a review.
- **The cost is already paid, in the exact failure the guard was meant to
  prevent.** The fleet-health STALL/WEDGED surfacing change
  (`.ai/handoffs/to-claude/open/202607130332-surface-fleet-health-in-stop-reminder.md`,
  plus its unapplied `.patch`) bounced across **three** Claude sessions (12:04,
  12:31, and one more), each terminating on the identical Rule 1.5 verdict, and
  never landed. Meanwhile OpenCode sat wedged for ~15h with nobody watching —
  precisely the condition that alert exists to surface. The guard did not prevent
  a bad change; it prevented a *good* change, and the safety feature it was
  blocking was the one that would have caught the outage.
- **Bootstrap reality.** The guard protects itself: no agent can edit
  `path-policy.sh` to change Rule 1.5, and that is by design. Relaxing it
  therefore requires exactly one human action that no agent can perform. The
  owner has authorized spending that action **once**, in order to never have to
  spend it again.

The question this ADR answers is not "should the enforcement layer be
protected?" (yes) but "**by what control?**" — an unreadable diff handed to a
non-reading human, or separation of duties plus CI.

## Decision

**We replace "owner-apply-only" with separation of duties.** An enforcement-layer
change is authored by one CLI, reviewed by a different CLI, gated by CI, and
merged by the merge gate — never by its author, and never by the owner's hand.

Concretely, for any change to `.claude/hooks/**`:

1. **No agent writes `.claude/hooks/**` in the PRIMARY working tree, ever.** The
   primary stays sacred. This is unchanged in spirit from Rule 1.5 and remains a
   hook-enforced block in the primary tree.
2. **A change MAY be authored on an `exec/*` branch in a worktree** (ADR-0004
   topology). That is the only place enforcement-layer edits are permitted.
3. **It reaches main ONLY via a PR that:**
   - (a) is reviewed by a **different CLI than the author** (author ≠ reviewer,
     per ADR-0002's review flow);
   - (b) passes the required CI gates — `gates` and `framework-check`; and
   - (c) is merged by the **merge gate** (Claude, or OpenCode acting under
     ADR-0011) — **never self-merged by the author**.
4. **CI enforces (a) and (c)** for any PR touching `.claude/hooks/**`. A PR that
   touches the enforcement layer without an independent peer review, or whose
   merger is its author, is **refused**.

The owner is not in this path at any point. Their single release-path gate
(production deploy) is untouched.

### Implementation state as of 2026-07-13

This ADR authorizes the target state; it does **not** describe a fully built
system. What exists today, stated exactly:

- **Built and live:** `gates` and `framework-check` **are** required status
  checks on `main` — branch protection was applied 2026-07-12 per handoff
  `.ai/handoffs/to-opencode/done/202607121900-gates-required-check.md` (now
  `done/`), with `enforce_admins=false`, no restrictions, and deliberately **no**
  GitHub-level required PR-review approval (forcing one mechanically risked
  deadlocking the merge train — that constraint was set before this ADR and is
  revisited under Residual risks below).
- **NOT yet built:** the CI check that enforces Decision 4 — author ≠ reviewer
  and no self-merge for PRs touching `.claude/hooks/**`. This ADR authorizes it;
  it does not describe existing behavior. Until it ships, clauses (a) and (c) are
  process rules only, held by the merge gate.
- **NOT yet built:** `.ai/tools/unlock-hook-policy.sh` (see below) does not exist
  in the tree today.
- **TBD — the identity signal CI keys on.** GitHub PR-review approvals are not a
  usable author≠reviewer signal here, because the fleet's CLIs do not each hold a
  distinct GitHub account; the per-CLI identity the repo *does* carry mechanically
  is git committer identity (`git config user.name` = `claude-code` / `kimi-cli` /
  `kiro-cli` / `opencode`), which ADR-0005's backstop already keys on. Whether the
  reviewer signal is a committer-identity trailer, a required `.ai/reports/` review
  artifact naming the reviewing CLI, or a GitHub review from a separate machine
  account is **TBD** and must be settled by the implementing handoff before the CI
  check is written. Getting this wrong produces a gate that *looks* enforced and
  is not — the exact failure mode this ADR exists to end.

### One-time bootstrap

Because the guard protects itself, exactly one human action is required to land
this change, and it is scripted so the owner never reads a diff:

- The owner runs `bash .ai/tools/unlock-hook-policy.sh` **once**.
- That script is **authored by `kimi`** and **independently reviewed by
  `kiro` BEFORE the owner runs it** (author ≠ reviewer applies to the
  bootstrap itself — the one action no CI gate can cover).
- After that single run, every subsequent enforcement-layer change follows the
  peer-reviewed-PR path above. The owner's hand is never needed again.

## Consequences

### This is a tightening, not a loosening — state it plainly

The old control could be defeated by **one** actor: an agent writes a convincing
`.patch` and hands it to a human who does not read code and does not use git. One
agent, one plausible-looking diff, one trusting `git apply`. That is the entire
attack path, and the owner's own directive establishes that the human end of it
cannot be hardened — they are not a programmer.

The new control requires **three** simultaneous compromises: the **author** CLI
must write the weakening, an **independent reviewer** CLI (a different model, a
different session, a different token budget) must pass it, and **CI** must go
green on it — with the change permanently recorded as a reviewable diff on
main, attributable to a named committer identity, in a PR merged by neither
author nor reviewer. Collusion across two independent CLIs plus a CI gate is a
strictly harder bar than one unread patch file. Anyone arguing this ADR weakens
the enforcement layer must explain why "one agent + one non-reading human" is a
higher bar than "two agents + CI + a permanent audit trail."

It also converts an **invisible** control into an **auditable** one. The old path
left no reviewable record of *why* a guard changed — a `git apply` by the owner
lands as a bare commit with no PR, no review, no reviewer. Every future
enforcement-layer change now has a PR, a diff, a named author, a named reviewer,
and a CI verdict attached.

### Residual risks — named, not hidden

- **An agent CAN now edit hook files locally, on a branch.** Between authoring and
  merge, an agent's *own worktree* may contain a hook file whose guard is weakened
  — and that weakened guard is the one governing that worktree's session. This is
  real and it is new. It is **bounded** (the primary tree is still hook-blocked;
  the branch cannot reach main without a peer review and CI) and **detectable**
  (`.ai/tools/reverse-write-detector.sh` catches a linked worktree writing back
  into the primary; the SSOT drift checks catch divergence), but "bounded and
  detectable" is not "impossible." Naming it is the point.
- **CI becomes part of the trust boundary.** A PR that edits
  `.github/workflows/**` could in principle weaken the very gate that enforces
  Decision 4. Required status checks on `main` (`gates`, `framework-check`) are
  the mitigation and are **already in place** as of 2026-07-12 — but they were
  configured with `enforce_admins=false` and with no GitHub-level required review,
  so an admin-token actor can still bypass, and a workflow-file change is reviewed
  only by the same process rule this ADR is trying to mechanize. Closing that loop
  — `enforce_admins`, and treating `.github/workflows/**` as enforcement-layer for
  the purposes of Decision 4 — is the recommended follow-up.
- **Perfect self-protection is impossible.** A system whose guards live in its own
  repo, edited by the agents the guards constrain, cannot prove its own integrity.
  This ADR does not claim to. It buys **defense in depth** (three independent
  actors) and **auditability** (every change is a reviewed diff with named
  parties). It is not a proof, and should never be cited as one.

### Positive

- **Good enforcement-layer changes can land again.** The fleet-health alert — and
  every future guard improvement — has a path to main that does not require the
  owner to read a patch.
- **Every guard change is reviewed by someone qualified to review it** (a peer
  CLI), instead of by someone who by their own account cannot.
- **Auditability.** Author, reviewer, CI verdict and diff, permanently on main.
- **The owner's time is returned to the one gate that is actually theirs** —
  production deploy. Consistent with the owner-interaction preference (2026-07-11)
  and §8.

### Negative

- **A local weakening window exists on branches** (see Residual risks). It did not
  exist before.
- **Enforcement-layer changes get slower per-change** — a peer review is a real
  round trip. That is intended friction, and it is friction paid by the fleet, not
  by the owner.
- **A new CI check must be written and maintained**, and its identity signal is
  TBD (above). Until it lands, clauses (a) and (c) rest on the merge gate's
  discipline rather than on mechanism — a stated, temporary gap.

### Neutral — what this does NOT change

- **Rule 1.5's intent is preserved**: no agent unilaterally and unreviewably
  weakens its own guards. Only the *control* changes.
- **The rest of `path-policy.sh` is untouched** — Rules 1, 2, 2.5, 2.6 and the
  territory rules keep their exact current behavior. This ADR amends the Rule 1.5
  clause and nothing else.
- **ADR-0005 (commit-governance backstop) is unaffected** — no committer-identity
  or territory change (though its identity mechanism is a candidate signal for the
  TBD above).
- **The owner's Tier-C gates are unaffected** — production deploy, publish,
  tag/release, destructive ops on shared history, secrets and production data all
  keep every guardrail they have. Nothing here touches the release path.
- **The primary working tree remains agent-unwritable for `.claude/hooks/**`.**

## References

- `.claude/hooks/lib/path-policy.sh` — Rule 1.5 (lines ~140-149), the clause this
  ADR amends; the shared classifier both the Write/Edit and Bash hooks call.
- `.ai/instructions/operating-prompt/principles.md` §8 — autonomy tiers; *"the
  human is a gate, not a relay"*; the owner's single release-path gate
  (production deploy); merge and git/GitHub mechanics as fleet actions.
- `docs/architecture/0002-cli-role-topology.md` — the review flow and the
  separation-of-duties principle (author ≠ reviewer ≠ deployer) this ADR applies
  to the enforcement layer.
- `docs/architecture/0004-worktree-multi-project-topology.md` — the `exec/*`
  worktree topology in which enforcement-layer changes may be authored.
- `docs/architecture/0005-commit-governance-backstop.md` — per-CLI committer
  identity; unchanged by this ADR, and a candidate identity signal for the CI
  check.
- `docs/architecture/0011-git-ops-execution-to-opencode.md` — the merge lane that
  performs clause (c).
- `.ai/handoffs/to-opencode/done/202607121900-gates-required-check.md` — the work
  that made `gates` + `framework-check` required status checks on `main`
  (landed 2026-07-12; `enforce_admins=false`, no GitHub-required review).
- `.ai/handoffs/to-claude/open/202607130332-surface-fleet-health-in-stop-reminder.md`
  (+ its `.patch`) — the change Rule 1.5 blocked across three sessions; the
  concrete cost recorded in Context.
- `.ai/tools/reverse-write-detector.sh` — the detector that bounds the
  branch-local weakening window.
- `.ai/tools/unlock-hook-policy.sh` — the one-time bootstrap script. **Does not
  exist yet**; to be authored by `kimi` and reviewed by `kiro` before the
  owner runs it.
