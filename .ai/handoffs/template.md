# <Task title — one short clear line>
Status: OPEN
Sender: <claude-cockpit | kimai-cockpit | claude-auto | kimai-auto | kiro-auto | opencode-auto>
Recipient: <claude-cockpit | kimai-cockpit | claude-auto | kimai-auto | kiro-auto | opencode-auto>
Owner: <same six-actor identity>  # optional but recommended: who currently owns this handoff
Created: YYYY-MM-DD HH:MM (UTC+7)
Auto: yes
Risk: <A | B | C>
Observed-in: <branch>@<sha>  # required when asserting file-level facts.
                              # The recipient compares this base to its own tree;
                              # a mismatch is "evidence-base mismatch", not BLOCKED.
Evidence: <VERIFIED (<command> -> <output>) | HYPOTHESIS (unverified)>
                              # HYPOTHESIS claims are not auto-dispatched; verify first.
# Gate: <who must authorize>     # Risk-C only: who must approve an irreversible action.
# Gate-satisfied-by: <actor> @ <timestamp>  # Risk-C only: once set, the orchestrator may relay.
# Relay: <orchestrator | human>  # Risk-C only: who launches after the gate is satisfied (default: human).
# ReviewBy: <cli>       # optional: executor emits review handoff to to-<cli>/review/ on done
# FinalReview: <cli>    # optional: reviewer emits final-review handoff to to-<cli>/review/
# Deploy: yes           # optional: final reviewer emits deploy handoff to to-opencode/open/
# Next: <actor>         # optional: general next-actor routing when ReviewBy/FinalReview/Deploy do not fit

<!-- Protocol v4 (2026-07-16; supersedes v3 2026-07-09):
     Recipient self-retires the handoff to done/ on completion; sender validates
     post-hoc. See docs/specs/handoff-protocol-v4.md for the full lifecycle.
     Auto: yes  = eligible for headless dispatch via .ai/tools/dispatch-handoffs.sh.
                  DEFAULT is yes — the human is a gate, not a relay.
                  Auto: yes + Risk A/B is owned by the auto pane.
                  Auto: no  is owned by a cockpit.
     Risk:      = autonomy tier per operating-prompt §8.
                  A = reversible routine (edits on a branch, tests, reports, replicas)
                  B = act-then-notify class (refactors, deps, config, PRs)
                  C = irreversible/gated (deploy, publish, merge to main, destructive,
                      ADR changes, secrets) — auto-dispatched ONLY when
                      Gate-satisfied-by: records an explicit authorization.
                  Missing Risk = treated as C.
     Evidence:  = VERIFIED (default) or HYPOTHESIS. HYPOTHESIS holds auto-dispatch.
     Observed-in: = <branch>@<sha>; required when asserting file-level facts.
     Sender/Recipient/Owner use the six-actor identity (claude-cockpit,
     kimai-cockpit, claude-auto, kimai-auto, kiro-auto, opencode-auto).
-->

<!--
Filename: YYYYMMDDHHMM-<slug>.md (UTC, minute precision).
Example: 202604201530-wave5-cleanup.md
Legacy NNN-slug.md format is grandfathered; new handoffs use timestamp format.
-->


## Goal
<One sentence — what changes and why it matters.>

## Current state
<What exists now, with file paths. Link or reference the files.>

## Target state
<What should exist after. File paths, key content shape.>

## Context (reference only, not binding)
<Optional: what the sender did in their own equivalent setup, so the recipient can
compare. NOT a spec for the recipient — they should pick whatever fits their CLI's
conventions. Delete this section if not applicable.>

## Steps
1. <Action.>
2. <Action. Include exact paths, exact verbatim text to paste where important, exact
   shell commands where they'd help.>
3. ...

## Verification
- (a) <thing the recipient must EXECUTE, not just read — test run, parse check,
      dry-run. Per delivery-integrity: execution proves behavior, grep proves
      presence; a completion claim needs both.>
- (b) ...

## Next step / future note
<Per delivery-integrity §3: what comes after this handoff, and what breaks first
if the surrounding system changes. 1-2 sentences.>

## Activity log template
    ## YYYY-MM-DD HH:MM (UTC+7) - <six-actor identity, e.g. kimai-auto>
    - Action: <summary — include the handoff filename, e.g. "per handoff 202607081200-slug">
    - Files: <paths touched, or "-">
    - Decisions: <non-obvious choices, or "-">

## Report back with
- (a) <concrete item the sender will use to validate, e.g. "config file path(s) touched">
- (b) <e.g. "exact event names / values used">
- (c) <e.g. "pipe-test / validation results — pasted output, not a summary">
- (d) <e.g. "fresh-session verification results">

## When complete (protocol v3)
Recipient self-retires: set Status to `DONE`, then move this file to
`.ai/handoffs/to-<recipient>/done/` yourself once the steps are executed and the
report is posted. The sender validates post-hoc by reading the touched files AND
the pasted execution evidence. If blocked, leave the file in `open/`, change
Status to `BLOCKED`, and append a `## Blocker` section with verbatim error
messages (not paraphrase). If the sender finds completed work wrong, it moves the
file back to `open/` with `BLOCKED` + notes.
