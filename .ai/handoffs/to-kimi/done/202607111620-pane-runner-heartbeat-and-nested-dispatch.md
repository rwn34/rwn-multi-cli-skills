# pane-runner: idle heartbeat (F1) + nested self-dispatch race (F3)
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 23:20
Auto: yes
Risk: B

## Goal
Two defects in `tools/4ai-panes/pane-runner.ps1`, found by a root-cause
investigation tonight. **Scope is `tools/4ai-panes/pane-runner.ps1` and its tests
ONLY.** Do NOT touch `.ai/tools/dispatch-handoffs.sh` — PR #42 is rewriting it
right now and you WILL conflict. A third defect (F2) that needs both files is
deliberately held back for a follow-up handoff.

## Background — the owner's actual complaint
The owner reported "the auto Claude pane doesn't work." It does work. A full
repro proved the headless Claude lane consumes a handoff end-to-end, commits, and
self-retires. **The real defect is that a healthy idle pane is indistinguishable
from a dead one** — it prints its banner once and then goes permanently silent.
Kimi and Kiro panes only *looked* alive because they happened to have work. This
affects all four panes.

---

## F1 — silent idle loop (the symptom the owner actually hit)
**Current state** — `tools/4ai-panes/pane-runner.ps1:632-635`:
```powershell
$handoff = Get-QualifyingHandoff -ProjectDir $ProjectDir -CliName $Cli
if ($null -eq $handoff) {
    Start-Sleep -Seconds $PollSeconds
    continue          # <- no output. Ever.
}
```
**Target state:** the pane emits a periodic idle heartbeat so an operator can see
at a glance that it is alive and polling, e.g.:
```
-- idle [claude] no qualifying handoff (23:14:02) --
```
Requirements:
- Throttle it. A line every poll would be noise — emit every Nth poll or at a
  time interval (your call; state the choice and why). It must be visible enough
  to prove liveness, quiet enough to not drown the pane.
- Low-contrast colour (`DarkGray`) so it reads as chrome, not signal.
- Include the CLI name and a timestamp.
- Applies to ALL four CLIs — this is generic runner code, not a Claude special case.
- Consider (and decide, with a stated reason) whether to also print a one-line
  "picked up <handoff>" on transition from idle to working. The idle→busy
  transition being invisible is part of the same problem.

## F3 — nested self-dispatch race (Claude lane only, but fix it generically)
**Current state:** `$script:InvokeCli` in `pane-runner.ps1` spawns the CLI child
process **without setting `AI_HANDOFF_DISPATCH`**. For the Claude lane, the
spawned `claude` runs its SessionStart hook → `.ai/tools/dispatch-own-queue.sh` →
`dispatch-handoffs.sh --exec --only claude`. That is **a second consumer of the
same queue, launched from inside the session that is already processing it.**

Today it is saved ONLY by the per-handoff claim sidecar, which goes stale after
15 minutes (`$script:HandoffClaimStaleMinutes = 15`) **with no heartbeat**. A
trivial repro handoff took ~7 minutes. A real handoff plus auto-continues will
exceed 15 minutes, the claim will go stale, and **the nested dispatcher will
re-dispatch the same handoff to a second Claude instance.** Two CLIs, same
handoff, same tree.

**Target state:** the pane-runner IS a dispatcher, so its children must know that.
Export `AI_HANDOFF_DISPATCH=1` in the child environment inside `$script:InvokeCli`
so the nested dispatch short-circuits. Set it for ALL CLIs (harmless for the ones
whose hooks don't read it, correct for the one that does) rather than special-
casing Claude — a per-CLI carve-out is how this bug got in.

Do NOT attempt the claim-heartbeat fix (renewing the claim while work is in
flight). That is a separate, larger change already logged as owed in the
2026-07-10 07:40 activity entry. Note it in your report; don't do it.

---

## Constraints
- PowerShell 5.1 compatible. A pre-commit hook parse-gates every staged `.ps1` —
  a non-parsing file cannot be committed. Parse-check before you commit.
- Branch off `origin/master` explicitly (NOT off ambient HEAD, NOT off another
  CLI's branch — that mistake caused a real incident today and ADR-0004's
  amendment now forbids it). Branch name: `exec/kimi/pane-runner-heartbeat`.
- Do NOT touch `.ai/tools/dispatch-handoffs.sh` (PR #42 owns it right now).
- Read `docs/architecture/0004-worktree-multi-project-topology.md` §Amendment
  (2026-07-11) and `.ai/instructions/delivery-integrity/principles.md` first.

## Tests (the delivery bar — real assertions, no stubs)
Extend `tools/4ai-panes/test-pane-runner.ps1` (currently 37 passing):
1. The idle path emits a heartbeat containing the CLI name, and does so on the
   throttle you chose (assert it does NOT emit every single poll).
2. The heartbeat does not fire when a qualifying handoff IS found (idle-only).
3. `$script:InvokeCli` sets `AI_HANDOFF_DISPATCH=1` in the child environment.
   Assert on the constructed environment/invocation, as the existing suite does —
   do not spawn a real CLI.
4. A guard test that fails loudly if `AI_HANDOFF_DISPATCH` is ever dropped from
   the child env again (this is a regression magnet; make the next removal noisy).

## Verification (execute — inspection is not evidence)
- (a) Paste the full `test-pane-runner.ps1` output (was 37 passed / 0 failed).
- (b) Paste the parse-check result for `pane-runner.ps1`.
- (c) Paste `grep -n "AI_HANDOFF_DISPATCH" tools/4ai-panes/pane-runner.ps1`.
- (d) Run the other two 4ai-panes suites (`test-selector-e2e.ps1`,
      `test-pane-supervisor.ps1`) to prove no collateral damage. NOTE:
      `test-pane-supervisor.ps1` has a KNOWN pre-existing timing flake on case C —
      if it trips, rerun once and SAY SO. Do not hide it, do not claim it as a
      regression.

## Next step / future note
After this lands, the panes become observably alive, which is the precondition for
the owner's real goal: proving all four auto lanes work by feeding each a live
handoff. What breaks first afterwards: the 15-minute claim staleness with no
heartbeat is still armed — F3's env fix closes the *nested* re-dispatch path, but
an EXTERNAL dispatcher run (cron, another operator) can still steal a claim from a
long-running handoff. That's the next thing to fix.

## Activity log template
    ## 2026-07-11 HH:MM — kimi-cli
    - Action: pane-runner idle heartbeat (F1) + AI_HANDOFF_DISPATCH in child env (F3) per handoff 202607111620-pane-runner-heartbeat-and-nested-dispatch
    - Files: tools/4ai-panes/pane-runner.ps1, tools/4ai-panes/test-pane-runner.ps1
    - Decisions: <heartbeat throttle choice + why>

## Report back with
- (a) files changed + PR URL (branch `exec/kimi/pane-runner-heartbeat` off origin/master)
- (b) the heartbeat throttle you chose and WHY
- (c) all pasted test output, verbatim (not summarized)
- (d) the grep evidence for AI_HANDOFF_DISPATCH
- (e) anything you could NOT verify, stated plainly

## When complete (protocol v3)
Self-retire: set Status `DONE`, move this file to `.ai/handoffs/to-kimi/done/`.
Do NOT merge (Tier C — Claude gates, owner approves). If blocked, leave it in
`open/` as `BLOCKED` with a verbatim `## Blocker` section.
