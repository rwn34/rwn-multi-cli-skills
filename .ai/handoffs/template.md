# <Task title — one short clear line>
Status: OPEN
Sender: <claude-code | kimi-cli | kiro-cli | opencode>
Recipient: <claude-code | kimi-cli | kiro-cli | opencode>
Created: YYYY-MM-DD HH:MM
Auto: yes
Risk: <A | B | C>

<!-- Protocol v2 (2026-07-08):
     Auto: yes  = eligible for headless dispatch via .ai/tools/dispatch-handoffs.sh.
                  DEFAULT is yes — the human is a gate, not a relay.
     Risk:      = autonomy tier per operating-prompt §8.
                  A = reversible routine (edits on a branch, tests, reports, replicas)
                  B = act-then-notify class (refactors, deps, config, PRs)
                  C = irreversible/gated (deploy, publish, merge to main, destructive,
                      ADR changes, secrets) — NEVER auto-dispatched, human relays.
     The dispatcher only launches Auto: yes + Risk A/B. Missing Risk = treated as C.
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
    ## YYYY-MM-DD HH:MM — <recipient-cli>
    - Action: <summary — include the handoff filename, e.g. "per handoff 202607081200-slug">
    - Files: <paths touched, or "—">
    - Decisions: <non-obvious choices, or "—">

## Report back with
- (a) <concrete item the sender will use to validate, e.g. "config file path(s) touched">
- (b) <e.g. "exact event names / values used">
- (c) <e.g. "pipe-test / validation results — pasted output, not a summary">
- (d) <e.g. "fresh-session verification results">

## When complete
Sender validates by reading the touched files AND checking the pasted execution
evidence. On success, move this file to `.ai/handoffs/to-<recipient>/done/`. On
failure, leave it in `open/`, change Status to `BLOCKED`, and append a `## Blocker`
section explaining what's missing — verbatim error messages, not paraphrase.
