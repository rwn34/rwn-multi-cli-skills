# <Task title — one short clear line>
Status: OPEN
Sender: <claude-code | kimi-cli | kiro-cli | crush>
Recipient: <claude-code | kimi-cli | kiro-cli | crush>
Created: YYYY-MM-DD HH:MM
Auto: no

<!-- Auto: yes = eligible for headless dispatch via .ai/tools/dispatch-handoffs.sh
     (recipient CLI is launched one-shot to process this handoff without the human
     relaying). Default no — keep no for anything needing confirmation. -->

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
- (a) <thing the recipient should check before reporting back>
- (b) ...

## Activity log template
    ## YYYY-MM-DD HH:MM — <recipient-cli>
    - Action: <summary — include the handoff number, e.g. "per handoff 001">
    - Files: <paths touched, or "—">
    - Decisions: <non-obvious choices, or "—">

## Report back with
- (a) <concrete item the sender will use to validate, e.g. "config file path(s) touched">
- (b) <e.g. "exact event names / values used">
- (c) <e.g. "pipe-test / validation results">
- (d) <e.g. "fresh-session verification results">

## When complete
Sender validates by reading the touched files. On success, move this file to
`.ai/handoffs/to-<recipient>/done/`. On failure, leave it in `open/`, change Status
to `BLOCKED`, and append a `## Blocker` section explaining what's missing.
