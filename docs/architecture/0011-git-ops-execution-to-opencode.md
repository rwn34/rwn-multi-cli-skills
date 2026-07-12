# 11. Git-Ops Execution Moves to OpenCode; Claude Keeps the Gate

## Status

Accepted (owner-directed 2026-07-11). **Amended 2026-07-12** (see "Amendment
(2026-07-12)" below): merge-to-main reclassified Tier C (owner-gated) → Tier B
(fleet act-then-notify); deploy remains the owner's Tier-C gate.
**Amended 2026-07-12b** (see "Amendment (2026-07-12b)" below): full git/GitHub
authority to the fleet; deploy splits into STAGING (Tier B, fleet) and
PRODUCTION (Tier C, owner-gated); ADR authorship/amendment moves Tier C → Tier B.

**Conditionally effective — see "Sequencing precondition" in the Decision.** This
ADR is accepted as policy but does NOT take effect until OpenCode has completed
one live handoff round-trip end to end. Until then, the pre-existing rules
(ADR-0002 pipeline, operating-prompt §4/§13) remain in force verbatim.

This ADR **narrows the execution half of Claude's lane** in
`docs/architecture/0002-cli-role-topology.md` (§ "Per-CLI roles" and
§ "GitHub/release pipeline"). It does not alter ADR-0002's separation-of-duties
principle — it strengthens it. It also **amends the handoff protocol v3 rule**
that Risk-C handoffs are never auto-dispatched (`.ai/handoffs/README.md` step 2b).

## Amendment (2026-07-12b) — full git/GitHub authority + staging/production deploy split + ADR authorship to Tier B

Owner directive, 2026-07-12 (verbatim):

> "merge doesn't have to be my gate — this is yours and it has to be in the
> steering. Committing tree, merge, cleanup, push, or any activity related to
> GitHub is yours to make. Deploy to prod would be mine to decide. Deploy to
> staging is still your call, not me."

The 2026-07-12 amendment (below) moved *merge* to Tier B. It stopped there. The
owner's intent is broader than the one action that was encoded, and three gaps
remained. This amendment closes all three.

### 1. All git/GitHub mechanics are fleet-executed

Operating-prompt §8 named "commits, pushes to feature/exec branches" and (after
the first amendment) merge. It never said that the *whole class* of git/GitHub
work belongs to the fleet, so every action not on the list — deleting a merged
branch, pruning a worktree, cleaning stale refs, closing or re-titling a PR —
fell into an unclassified grey zone and, under the "when in doubt take the more
restrictive tier" rule, drifted toward asking the owner. The directive resolves
it: **committing, branching, pushing, opening PRs, merging, branch deletion,
worktree/tree cleanup and every other repo-housekeeping action are the fleet's
to execute.** They are Tier A (commit, push, branch creation) or Tier B (PR,
merge, cleanup) — never an owner ask.

### 2. Deploy splits: STAGING is Tier B, PRODUCTION is Tier C

This distinction did not exist anywhere in the framework before this amendment.
§8 listed a bare, undifferentiated "deploy" under Tier C; `.opencode/contract.md`
and ADR-0002's Stage-2 conditions likewise treated every deploy identically —
"Deploys are Tier-C hard-gated no matter who executes them." The owner has now
drawn the line where irreversibility actually is:

- **Deploy to STAGING → Tier B (the fleet's call, act-then-notify).** Staging is
  a disposable environment; a bad staging deploy is fixed by another staging
  deploy. **The operational guardrails are retained in full: dry-run first and
  paste the output, refuse on a dirty working tree, refuse on failing tests, and
  execute only commands enumerated in the brief.** What is removed is the
  *per-deploy human confirmation*, and nothing else.
- **Deploy to PRODUCTION → Tier C (the owner's gate, per deploy).** Unchanged in
  every respect.

**This amendment weakens NO production guardrail.** Production deploys keep all
four Stage-2 conditions verbatim: (1) mandatory dry-run first with pasted
output, (2) per-deploy human confirmation of every mutating command, (3) only
commands enumerated in an approved deploy brief, (4) refuse on a dirty tree or
failing tests. A production deploy brief remains `Risk: C` and remains
subject to the `Approved-by:` rules in §3 of this ADR.

**New prohibited coupling: a staging deploy must never auto-promote to
production.** Staging deploy is Tier B *because* it stops at staging. If a
staging deploy can cascade into production — a promotion pipeline, an
auto-promote-on-green stage, a shared deploy target — then the staging deploy is
in substance a production deploy and it re-tightens to Tier C. This is the exact
sibling of the merge/deploy decoupling rule the first amendment introduced, and
it is what keeps the Tier-B classification honest.

### 3. ADR authorship and amendment move to Tier B

Operating-prompt §8 listed "ADR creation or amendment" as Tier C — ask the owner
*before* writing. §4 simultaneously states that Claude Code **owns** ADRs as its
architect lane. Those two rules contradict each other: the CLI whose designated
job is authoring ADRs had to obtain permission before doing its job, while Kimi
and Kiro were barred from ADR authorship outright by lane. The Tier-C entry was
therefore either a no-op or an obstacle, never a safeguard.

**ADR authorship and amendment are now Tier B: author it, then notify
prominently.** The surfacing requirement is *not* removed — an ADR lands in a PR
the owner sees, is called out in the summary and in the activity log, and is
revertible like any other file. What is removed is the *pre-approval gate* on
writing it down. The owner remains free to reject any ADR at the PR; an
unwritten ADR is simply an undocumented decision, which is worse.

### What this supersedes

- **Operating-prompt §8** — the Tier-A/B/C lists, replaced by the tables above.
  Superseded specifically: the bare "deploy" entry in Tier C (now "deploy to
  PRODUCTION"), and "ADR creation or amendment" in Tier C (now Tier B).
- **`.opencode/contract.md`** — Stage-2 condition 2 ("Per-deploy human
  confirmation ... Deploys are Tier-C hard-gated no matter who executes them")
  now applies to **production** deploys only. Staging deploys are Tier B and
  fleet-authorized; conditions 1, 3 and 4 (dry-run, brief-only, refuse on
  dirty/failing) apply to **both** environments, unchanged.
- **ADR-0002 § "Per-CLI roles" → OpenCode → Deploy execution (Stage 2), and
  § "GitHub/release pipeline" step 6** — same split: read "deploy" there as
  "production deploy" wherever a per-deploy human gate is asserted; staging
  deploy is Tier B under this amendment. ADR-0002's separation-of-duties
  principle (author ≠ reviewer ≠ deployer) is untouched.
- **This ADR's own § "Decision → 3 → What OpenCode must verify", item 4**
  ("Deploys keep their own per-deploy guardrails ... a per-deploy human
  confirmation, every time") — now scoped to **production** deploys. A staging
  deploy brief needs no `Approved-by:` line and no per-deploy confirmation; it
  still needs the dry-run, the clean tree, the green tests, and the brief.
- **This ADR's own § "Consequences → Neutral"** first bullet ("Merge, deploy,
  publish, tag, destructive ops: the owner still approves each one") — merge was
  already removed by the first amendment; staging deploy is removed by this one.
  Read it as: production deploy, publish, tag and destructive ops.

Everything else in Tier C is unchanged and unweakened: publish to a public
registry, tag/release cuts, force-push and destructive operations on shared
history, `git reset --hard` on shared state, data deletion, `DROP`/`TRUNCATE`,
secrets and credentials, spending money, production data of any kind, and writes
into another CLI's territory outside the handoff protocol. The
"when in doubt, take the more restrictive tier and say so" rule survives intact.

## Amendment (2026-07-12) — merge-to-main is Tier B (fleet-executed), not owner-gated

Owner directive, 2026-07-12:

> "merge doesn't have to be my part, it can be the fleet — the one thing I
> should decide is deploy."

This reclassifies merge-to-main from Tier C (owner-gated, ask-before-acting) to
Tier B (fleet act-then-notify) in operating-prompt §8. The owner's single
irreversibility gate on the release path is now **deploy**, not merge. Merge into
`main` is revertible; a bad merge is undone with a revert commit and another
peer-reviewed PR. Deploy pushes code onto running infrastructure and is the point
where the owner wants to be the one who says go.

Under the amended policy the pipeline reads: an author opens a PR → a peer reviews
it (author ≠ reviewer, unchanged) → the required CI checks go green → **the fleet
merges (Tier B) and notifies the owner after the fact** → **deploy is a separate,
explicitly Tier-C owner-gated step.** Merge and deploy are two distinct actions
with two distinct gates; collapsing them is prohibited. A merge must **never**
auto-trigger a deploy — no merge-to-`main` webhook, pipeline stage, or automation
may push to a live environment as a side effect of landing a PR. If that coupling
is ever introduced, merge is no longer independently revertible and it
re-tightens to Tier C; the Tier-B classification is valid **only** while merge and
deploy remain decoupled.

This supersedes the original text of this ADR in two specific places: the §3
decision-table row that lists merge under "owner approves (Tier C)," and the first
bullet of the "What does NOT change" list that names merge as an owner gate. Where
those passages say the owner approves the merge, read instead: the fleet merges
under Tier B after peer review and green CI, and notifies the owner. The
`Approved-by:` trailer machinery this ADR introduces for gated operations now
applies **only** to the operations that remain Tier C — deploy, tag/release, and
publish — and no longer to merge.

The safeguards retained on merge are peer review (author ≠ reviewer), the required
status checks, and the revertibility of `main` — not an owner sign-off. **Deploy
stays owner-gated Tier C**, with the Stage-2 deploy guardrails described elsewhere
in this ADR intact and unchanged.

Finally, the tier change and the executor change are decoupled. This amendment
moves *who gates* the merge (owner → fleet); it does not by itself move *who runs*
the merge. Merge **execution** still transfers to OpenCode only after OpenCode has
proven one live handoff round-trip end to end, exactly as the "Sequencing
precondition" in the Decision requires. Until that proof lands, the fleet's merge
is executed by `release-engineer`/`infra-engineer` as today — now under Tier B
rather than as an owner-relayed Tier-C step.

## Context

Owner directive, 2026-07-11:

> "Claude orchestrator shouldn't spend its tokens just to push, PR, merge,
> deploy. Leave it to OpenCode, so Claude does something more valuable."

The forces behind it:

- **Claude is the fleet's scarcest budget.** Claude Code runs on the $100/5x
  plan; Kimi and Kiro are both $200 plans; OpenCode owns the ops lane.
  Operating-prompt §14 (delegation economics, added 2026-07-11) already
  established routing-by-capacity as policy: *"If it can be handed off, hand it
  off. Claude performing work another CLI could have done is a budget leak, not
  helpfulness."* §14 named GitHub operations explicitly as OpenCode's.

- **§14 was written but not obeyed.** Within a day of §14 landing, the activity
  log for 2026-07-11 records the Claude orchestrator opening and gating PRs
  #29–#42 and merging #31, #39 and #40 itself — routing the git mechanics
  through its own `infra-engineer` subagent, in the CLI with the smallest
  budget, while the ops CLI sat idle. §14 rule 3 says "do not do them yourself
  if OpenCode can." The reflex beat the rule.

- **OpenCode has never performed a single git or GitHub operation in this
  repo.** It is not an unused CLI — the activity log shows four OpenCode entries
  on 2026-07-09 (two reports, one round-trip reply handoff, one correctly-refused
  misrouted handoff), and `.ai/handoffs/to-opencode/done/` holds five retired
  handoffs. But every one of those was a *report* or a *handoff file*. No branch,
  no commit, no push, no PR, no merge, no tag, no deploy has ever been executed
  by OpenCode here. Its designated lane — the ops lane — has never once been
  exercised.

- **The lane was not broken; it was starved.** OpenCode is fully wired in: it is
  pane #4 of the 4ai-panes launcher (`opencode run --auto --agent opencode`), it
  is a registered handoff recipient with a live inbox, and its guardrails are
  mechanical (harness-level `allow`/`ask`/`deny` permissions plus
  `.opencode/plugin/` framework-guard hooks, per the ADR-0002 amendment of
  2026-07-09). Nothing prevented it from working. The orchestrator simply never
  fed it, because doing the `gh pr merge` itself was always the path of least
  resistance in the moment.

- **The relay rule makes the correct behavior more expensive than the wrong
  one.** Under handoff protocol v3, Risk-C handoffs (merge, deploy, publish,
  destructive) are "NEVER auto-dispatched, regardless of `Auto:` — a human
  relays them." So routing a merge to OpenCode costs the owner *two*
  interactions: approve the merge to Claude, then relay the handoff to OpenCode.
  Doing it in Claude costs one. The protocol was actively taxing the delegation
  it was supposed to enable — and the tax was paid in the owner's time, which is
  the exact resource §14 exists to protect.

## Decision

**Execution of git/GitHub mechanics moves to OpenCode. Claude keeps only the
judgment.**

### 1. The split is decide-vs-execute, not which-repo-actions

The boundary is not a list of git commands divided between two CLIs. It is a cut
between *deciding* and *doing*, applied to the same action:

| Action | Who decides | Who executes |
|---|---|---|
| Open a PR | Claude (what ships, what the PR says) | **OpenCode** |
| Merge to main | Claude recommends; **the owner approves (Tier C)** | **OpenCode** |
| Tag / release | Claude + owner | **OpenCode** |
| Deploy | Owner (Tier C, per-deploy) | **OpenCode** |
| Branch / commit / push for non-executor work | Claude | **OpenCode** |
| CI config + workflow fixes, repo housekeeping | Claude briefs | **OpenCode** |
| Review the diff, gate the merge | **Claude** | **Claude** |

Claude reads the diff, checks the gate conditions (branch up to date, required
checks green, peer review passed, linked issue addressed), and recommends. The
*decision* to merge stays with Claude and the owner — author ≠ reviewer is
preserved exactly as ADR-0002 and operating-prompt §4 define it. Only the *act*
of merging moves. OpenCode is a hand, not a judge: it never decides that
something should merge, and it is never the reviewer of the change it lands.

**Scope clarification — whose git ops move.** This ADR narrows the *orchestrator's*
git lane. It does **not** revoke ADR-0002 pipeline step 1: Kimi and Kiro continue
to branch, commit and push **their own delegated work** via their own
`infra-engineer` subagents (Tier A, on feature branches, in their own worktrees
per ADR-0004). Forcing an executor to file a handoff to OpenCode just to commit
the code it is holding in its own tree would add a round-trip to the most common
operation in the fleet, for no gain. What moves to OpenCode is the git/GitHub
work that today lands on *Claude*: PRs, merges, tags, releases, CI chores, repo
housekeeping, and branch/commit/push for changes that Claude itself originated.

### 2. `infra-engineer` (Claude's subagent) is demoted to FALLBACK — not deleted

Claude's `infra-engineer` **remains in the roster, keeps its git tooling, and
stays usable.** It is demoted from *default git executor* to *documented
fallback*.

**Why it is not deleted:** routing 100% of git operations through a single CLI
creates a single point of failure. If OpenCode is down, misconfigured, or its
queue is blocked, then with no fallback *nothing merges or deploys for any CLI in
the fleet* — Kimi's and Kiro's finished work strands on feature branches behind a
dead ops lane. A documented, deliberately-narrow fallback is the mitigation, and
it is cheaper than the outage it prevents.

Legitimate uses of the `infra-engineer` fallback:

- OpenCode is unavailable, erroring, or its inbox is demonstrably blocked.
- The owner is waiting live on something trivial where a handoff round-trip costs
  more than it saves (§14 rule 2's existing "owner is waiting live" carve-out).
- Claude-only tooling is genuinely required for the operation.

**Every fallback use must be logged.** The activity-log entry must name
`infra-engineer` and state *why* the fallback was taken (e.g. "OpenCode inbox
blocked — fell back to infra-engineer"). An unexplained `infra-engineer` git
operation in the log is a protocol violation, not a convenience. This makes the
starvation failure mode visible: if the log fills with unexplained fallbacks, the
reflex has returned and the ADR is being routed around.

The fallback for *deploys* specifically is unchanged from ADR-0002: Claude's
`release-engineer`, under the same four Stage-2 conditions.

### 3. Protocol change — the owner's approval is the gate; the relay stops being human

Handoff protocol v3 currently says Risk-C handoffs are never auto-dispatched and
a human relays them. Under this ADR that rule would force the owner to approve a
merge to Claude and then *hand-carry the same decision* to OpenCode: two
approvals for one decision, spending the owner's time to save Claude's tokens.
That is backwards.

**New rule: the owner's in-session approval IS the gate. A Risk-C handoff that
carries a recorded owner approval for the specific action it describes may be
auto-dispatched to OpenCode.**

- Claude records the approval **verbatim** in the handoff's status block, in a
  new field:

      Approved-by: owner — 2026-07-12 00:31 — "merge #42 approved"

- The `Approved-by:` field is only valid when written by Claude (or another CLI)
  transcribing an approval the owner actually gave **in-session, for that
  action**. Fabricating, inferring, or generalizing an approval into this field
  is a delivery-integrity violation of the first order — it forges the human
  gate. A Risk-C handoff with no `Approved-by:` line is still never
  auto-dispatched.

- **The gate stays human. The relay stops being human.** The owner still decides
  every merge, tag, publish and deploy. They just no longer have to carry the
  message.

**What OpenCode must verify before acting on a recorded approval:**

1. **The approval names THIS action.** The `Approved-by:` quote must
   unambiguously identify the specific operation in the handoff — this PR number,
   this tag, this environment. A general approval ("go ahead", "ship it", "yes")
   attached to a multi-action brief does not license all of it.
2. **Refuse on ambiguity.** If the approval is vague, stale, or could plausibly
   refer to a different action, OpenCode does NOT act: it leaves the handoff
   `OPEN`, sets `BLOCKED`, and reports. "When in doubt, don't" is not optional
   here — an over-broad reading of an approval is an ungated Tier-C action.
3. **The pre-existing refusal conditions all still apply, unweakened.** Refuse on
   a dirty working tree. Refuse on failing tests. Refuse on red required checks.
   Refuse to run any command not enumerated in the brief. Never improvise beyond
   the brief. Never touch source code. (`.opencode/contract.md` "Enforcement" +
   ADR-0002 Stage-2 conditions.)
4. **Deploys keep their own per-deploy guardrails on top of all of the above.**
   `Approved-by:` does **not** replace the Stage-2 deploy conditions: dry-run
   first and paste the output, then a per-deploy human confirmation, every time.
   A deploy brief with a recorded approval may be *dispatched* without a human
   relay; the mutating deploy command itself still gets its own confirmation.
   This ADR weakens no deploy guardrail.

### 4. Sequencing precondition — this ADR is inert until OpenCode proves the loop

**This decision does NOT take effect until OpenCode has demonstrably completed one
full handoff round-trip:** a handoff lands in its inbox → the auto pane consumes
it unattended → real work is committed → OpenCode self-retires the handoff to
`done/` per protocol v3 step 4.

Handing the most irreversible operations in the system — merge, tag, deploy — to
the least-exercised CLI in the fleet, on the strength of a config file and a
role table, would be precisely the "verify by inspection, not by execution"
failure that `.ai/instructions/delivery-integrity/principles.md` forbids.
OpenCode's ops lane is, as of this writing, entirely unexercised (see Context).
A green config is not a green pipeline.

The proving handoff is in flight:
`.ai/handoffs/to-opencode/open/202607120021-gates-required-check-and-step-order.md`
(CI-config work — no source code, no merge, Risk B). When it round-trips
successfully, this ADR becomes effective and the implementation changes in
Consequences may be rolled out. If it fails, the failure is diagnosed and fixed
*before* any Tier-C authority moves — a failed round-trip is information, not a
reason to skip the precondition.

## Consequences

### Implementation — every file that must change

This decision is only real once the operating rules say so. A CLI reads its own
contract, not this ADR; a missed file means that CLI keeps operating under the
old rule. The complete set:

**SSOT + replicas (via `.ai/sync.md`; drift-gated by `check-ssot-drift.sh`):**

- `.ai/instructions/operating-prompt/principles.md` — §4 (Claude's lane loses git
  execution; OpenCode's lane gains it; the pipeline line), §13 (git workflow
  summary), §14 (rules 2–4: `infra-engineer` demotion, the `Approved-by:` gate).
- `.claude/skills/operating-prompt/SKILL.md` — Claude replica (body only).
- `.kimi/steering/operating-prompt.md` — **via handoff to Kimi** (Claude may not
  write `.kimi/`).
- `.kiro/steering/operating-prompt.md` — **via handoff to Kiro** (Claude may not
  write `.kiro/`).
- `.ai/instructions/agent-catalog/principles.md` — `infra-engineer` row + the
  role-lane section: git lane demoted to fallback, logging requirement stated.
- `.claude/skills/agent-catalog/SKILL.md` — Claude replica (body only).
- `.kimi/steering/agent-catalog.md` — **via handoff to Kimi.**
- `.kiro/steering/agent-catalog.md` — **via handoff to Kiro.**

**Claude-local:**

- `.claude/agents/orchestrator.md` — route git ops to OpenCode, not to
  `infra-engineer`.
- `.claude/agents/infra-engineer.md` — FALLBACK status, the three legitimate-use
  conditions, the logging requirement.
- `CLAUDE.md` — the orchestrator's own contract must state the new reflex.

**Contracts:**

- `AGENTS.md` — OpenCode's shipped contract. **Note: it is already stale** — the
  "GitHub / repo-ops lane" paragraph added to `.opencode/contract.md` on
  2026-07-11 was never mirrored here (`AGENTS.md` mentions only "ADR-0002 Stage
  2"). Fix both in the same change.
- `.opencode/contract.md` — the `Approved-by:` verification rules (what to check,
  when to refuse), and the explicit statement that deploy guardrails are
  unchanged.

**Handoff protocol:**

- `.ai/handoffs/README.md` — protocol v3 step 2b: Risk-C handoffs carrying a
  valid `Approved-by:` line ARE auto-dispatchable; those without one are not.
- `.ai/handoffs/template.md` — add the `Approved-by:` field to the status block
  and document its meaning in the protocol comment.
- `.ai/tools/dispatch-handoffs.sh` — the dispatcher currently filters Risk-C out
  unconditionally; it must instead dispatch Risk-C **only** when a well-formed
  `Approved-by:` line is present. **This is the one code change in the set** and
  it is security-relevant: it is the mechanical half of the human gate. It needs
  its own tests in `.ai/tests/`.

**Installer asset tree** (onboarded projects read these, not the repo copies — a
miss here ships the old rule to every new project):

- `tools/multi-cli-install/assets/.ai/instructions/{operating-prompt,agent-catalog}/principles.md`
- `tools/multi-cli-install/assets/.claude/skills/{operating-prompt,agent-catalog}/SKILL.md`
- `tools/multi-cli-install/assets/.claude/agents/{orchestrator,infra-engineer}.md`
- `tools/multi-cli-install/assets/.ai/handoffs/{README.md,template.md}`
- `tools/multi-cli-install/assets/{CLAUDE.md,AGENTS.md}`
- `tools/multi-cli-install/package.json` — version bump (framework content
  changed; `check-version-bump.sh` gates this) + `CHANGELOG.md`.
- **Gap flagged, not fixed here:** there is no
  `tools/multi-cli-install/assets/.opencode/` in the asset tree at all. Onboarded
  projects receive `AGENTS.md` but never `.opencode/contract.md` or its plugin
  guards — so in those projects OpenCode runs on the `AGENTS.md` contract alone,
  with no mechanical guard layer. That predates this ADR and deserves its own
  follow-up.

### Positive

- **The scarcest budget stops being spent on mechanics.** Claude's tokens go to
  triage, specs, ADRs, briefs, and the final review — the work only Claude does.
- **The ops lane finally exists in practice, not just on paper.** A lane that has
  never executed its designated work is not a lane; it is a diagram.
- **One approval per decision, not two.** The owner's time — the resource §14 was
  written to protect — stops being spent on relaying.
- **Separation of duties gets sharper, not looser.** Today the CLI that gates the
  merge is also the CLI that performs it. After this, the reviewer and the
  merger are different processes. That is a strictly better posture than the one
  ADR-0002 originally described.

### Negative

- **Single point of failure in the ops lane.** All git/GitHub execution
  concentrates in one CLI. *Mitigation:* the `infra-engineer` fallback (§2),
  deliberately kept alive and loggable. The risk is real and the mitigation is
  partial — a fallback that is rarely exercised will itself rot. Expect to test
  it deliberately.
- **The least-proven CLI receives the most irreversible operations.** OpenCode
  has never executed a git operation here, and it is being handed merge, tag and
  deploy. *Mitigation:* the round-trip precondition (§4), plus its unchanged
  dry-run / per-deploy-confirm / refuse-on-dirty-tree guardrails, plus the
  Claude-authored brief that bounds every command it may run. This is the single
  largest risk in this ADR and the precondition exists solely because of it.
- **Latency.** A handoff round-trip is slower than Claude running `git push`
  inline — minutes instead of seconds, and it can fail in ways an inline command
  cannot (queue not polled, pane paused, dispatch error). **This cost is real and
  we are choosing to pay it.** The reason: the alternative spends the two
  scarcest resources in the system (Claude's budget and the owner's attention) on
  the least valuable work in the system (typing git commands), and it produces a
  fleet where the ops CLI never runs. A slower merge is an acceptable price for a
  fleet that actually uses all four of its CLIs. Where the latency genuinely does
  not pay — the owner waiting live on a one-line fix — the §2 fallback exists.
- **A new forgeable field.** `Approved-by:` is a text line; nothing cryptographic
  prevents a CLI from writing one. The framework's existing accepted-risk stance
  applies (single trust domain: this repo is written only by the owner and their
  own CLIs — see the 2026-07-11 audit disposition). It should be revisited the
  moment that assumption stops holding.

### Neutral — what this does NOT change

- **Tier-C actions remain human-gated.** Merge, deploy, publish, tag, destructive
  ops: the owner still approves each one. Only the *relay* is automated, never
  the *gate*.
- **Kimi and Kiro are untouched.** They still may not merge to main, author ADRs,
  or deploy — no matter how much budget they have. Their `infra-engineer`
  subagents keep branching, committing and pushing their own delegated work.
- **Author ≠ reviewer ≠ deployer** (ADR-0002) is preserved, and by §1 it is
  tightened.
- **Deploy guardrails are unchanged.** Stage-2 conditions apply in full.
- **Claude remains custodian of OpenCode's files** (ADR-0001, amended
  2026-07-09). OpenCode does not edit its own contract.

## Alternatives considered

- **(A) Status quo — Claude keeps doing git ops.** Rejected. This is exactly what
  starved the OpenCode lane into never having run, and it spends the fleet's
  smallest budget on its least-skilled work. §14 already rejected this in
  principle on 2026-07-11; within a day it was being violated in practice, which
  is evidence that a cost *rule* is not enough — the lane boundary itself has to
  move.
- **(B) Delete `infra-engineer` entirely and route 100% of git through
  OpenCode.** Rejected. Cleaner on paper, but it makes an OpenCode outage a
  fleet-wide stop-the-world: nothing merges or deploys for anyone, and finished
  work from Kimi and Kiro strands on branches. A single point of failure with no
  documented fallback is not a simplification, it is an unowned risk.
- **(C) Keep the human relay for Tier C.** Rejected. It forces two approvals for
  one decision — approve to Claude, relay to OpenCode — which burns the owner's
  time to save Claude's tokens. That inverts the priority §14 exists to enforce,
  and it would make the correct routing feel more expensive than the wrong one,
  guaranteeing the reflex returns. The gate is what protects the owner; the relay
  never did.
- **(D) Move git ops to Kimi or Kiro (the highest-budget CLIs) instead.**
  Rejected. Budget is not the only axis: ADR-0002's author ≠ deployer rule exists
  precisely to keep the CLI that wrote the code from being the one that ships it.
  OpenCode's whole value here is that it writes no source.

## References

- `docs/architecture/0002-cli-role-topology.md` — the role-lane and
  GitHub/release-pipeline ADR this one narrows (Claude's execution half) and
  whose separation-of-duties principle it preserves.
- `docs/architecture/0001-root-file-exceptions.md` — Claude's custodianship of
  OpenCode's config files.
- `docs/architecture/0004-worktree-multi-project-topology.md` — worktree-per-CLI
  dispatch; the reason executors keep committing in their own trees.
- `.ai/instructions/operating-prompt/principles.md` — §4 (role lanes), §8
  (autonomy tiers), §13 (git workflow), §14 (delegation economics — the direct
  parent of this decision).
- `.ai/instructions/agent-catalog/principles.md` — `infra-engineer` and
  `release-engineer` entries.
- `.ai/instructions/delivery-integrity/principles.md` — "verify by execution, not
  by inspection"; the basis for the §4 sequencing precondition.
- `.opencode/contract.md` — OpenCode's contract: the GitHub/repo-ops lane and the
  Stage-2 deploy guardrails this ADR leaves intact.
- `.ai/handoffs/README.md` + `template.md` — handoff protocol v3; the `Auto:` /
  `Risk:` fields and the Risk-C relay rule this ADR amends.
- `.ai/handoffs/to-opencode/open/202607120021-gates-required-check-and-step-order.md`
  — the in-flight round-trip proof this ADR's effectiveness is gated on.
