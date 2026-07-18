# Cockpit/auto workflow docs: `Next:` field is documented but unimplemented
Status: DONE
Sender: kiro-auto
Recipient: kimai-cockpit
Owner: kimai-cockpit
Created: 2026-07-18 21:01 (UTC+7)
Completed: 2026-07-18 21:11 (UTC+7)
Auto: no
Risk: B
Observed-in: main@fd519aa
Evidence: VERIFIED (see grep evidence below)
Resolution: (a) implemented — `Next:` fan-out, six-actor identities, and `Owner:` lines are now emitted by `tools/4ai-panes/pane-runner.ps1`. Also fixed a Windows-path bug in `.ai/tools/sync-ai-state.sh` that was blocking the snapshot-copy test suite.
Touched: tools/4ai-panes/pane-runner.ps1, tools/4ai-panes/test-pane-runner.ps1, .ai/tools/sync-ai-state.sh

## Goal
Reviewed `docs/specs/saja-akun-cli-workflow.md`, `docs/guides/example-handoff-chain.md`,
`.ai/handoffs/README.md`, and `.ai/handoffs/template.md` per handoff
`202607181358-review-cockpit-auto-workflow-docs.md`. Verdict: **changes-requested**.
The docs are a good design reference but overstate what the pane-runner actually
does today. Filing this as a routed-back follow-up rather than editing the docs
directly, since fixing them requires either (a) implementing `Next:` in
`pane-runner.ps1` or (b) softening the docs' claims — a decision for a cockpit,
not something to silently pick in an auto pane.

## Findings

### 1. `Next:` is documented as implemented but is not (the main issue)

`docs/specs/saja-akun-cli-workflow.md` §3.5 states: *"The pane-runner's
`Emit-NextStageHandoff` reads `Next:` (in addition to the existing `ReviewBy:`,
`FinalReview:`, and `Deploy:` fields) and emits the follow-up handoff to the
correct queue."* §9 goes further: *"No change is required to
`dispatch-handoffs.sh`, `fleet-health.sh`, heartbeat sidecars, or the claim-lock
mechanics"* — implying the pattern is pure convention, no code changes needed.

I read the actual function:

```
$ grep -n "ReviewBy\|FinalReview\|Deploy\|Next" tools/4ai-panes/pane-runner.ps1 | grep -n "Read-HandoffField"
745:    $reviewBy = Read-HandoffField -HandoffPath $donePath -FieldName 'ReviewBy'
764:    $finalReview = Read-HandoffField -HandoffPath $donePath -FieldName 'FinalReview'
783:    $deploy = Read-HandoffField -HandoffPath $donePath -FieldName 'Deploy'
```

There is no `Read-HandoffField -FieldName 'Next'` anywhere in the file — I read
`Emit-NextStageHandoff` end-to-end (lines 699-802) and it only branches on
`ReviewBy`, `FinalReview`, and `Deploy`.

**Concrete impact:** `docs/guides/example-handoff-chain.md` Stage 1 depends on
this exact mechanism — `claude-auto` finishing a handoff with
`Next: kimai-auto,kiro-auto` is supposed to auto-fan-out two implementation
handoffs. As written today, that fan-out will NOT happen automatically; a human
or the cockpit has to do it by hand. The example reads as a working trace but
currently isn't one for that step.

### 2. Auto-emitted handoffs still use four-actor identities, not six-actor

The same function hardcodes the legacy scheme when it emits review/final-review/
deploy handoffs:

```
$ grep -n '"Sender: \$CliName-cli"\|"Recipient: \$Recipient-cli"' tools/4ai-panes/pane-runner.ps1
734:            "Sender: $CliName-cli",
735:            "Recipient: $Recipient-cli",
```

So a real `ReviewBy`/`FinalReview`/`Deploy`-triggered handoff emitted by the
pane-runner today writes `Sender: kiro-cli` / `Recipient: kimi-cli`, etc. — the
exact bare four-actor form that `saja-akun-cli-workflow.md` §3.4 says not to use
("Do not use bare `kimi-cli` or `claude-code`"). The new docs describe a target
identity scheme; the emitting code hasn't caught up yet.

### 3. Claim-owner identities are also four-actor, and asymmetric across CLIs

```
$ grep -n "function Get-DefaultOwner" -A 8 tools/4ai-panes/pane-runner.ps1
1148:function Get-DefaultOwner {
1149:    param([string]$CliName)
1150:    switch ($CliName) {
1151:        'claude'   { return 'claude-auto' }
1152:        'kimi'     { return 'kimi-cli' }
1153:        'kiro'     { return 'kiro-cli' }
1154:        'opencode' { return 'opencode' }
```

Only Claude has a `-auto` claim identity distinct from its cockpit form; Kimi,
Kiro, and OpenCode's claim sidecars still use the pre-six-actor names. This is
already flagged as a known limitation in ADR-0013 ("owner-string collision"),
but the new spec's §3.4/§10 read as though the six-actor scheme is closer to
live everywhere than it actually is. Worth a one-line caveat in the spec so a
reader doesn't assume `kiro-auto` shows up in a live claim sidecar today.

## Recommendation (pick one — cockpit's call)

- (a) Implement `Next:` support in `Emit-NextStageHandoff` (parse a
  comma-separated actor list, strip the `-auto`/`-cockpit` suffix to resolve the
  CLI name, emit one handoff per listed actor) and update the hardcoded
  `$CliName-cli` / `$Recipient-cli` lines to emit six-actor identities. This
  makes the docs true as written.
- (b) Add a short "current implementation status" callout to
  `saja-akun-cli-workflow.md` §3.5/§9 and `example-handoff-chain.md` Stage 1
  stating that `Next:`-based fan-out and six-actor emission are not yet wired
  into `pane-runner.ps1`, so a cockpit or human currently performs that step
  manually.

Either is fine; (a) is the more complete fix, (b) is the faster one. Not
picking either and shipping the docs as-is is the one option I'd flag against —
a reader following the docs today would expect automatic fan-out that doesn't
happen.

## Verification
- (a) `grep -n "Next" tools/4ai-panes/pane-runner.ps1` — confirm status.
- (b) If (a) is implemented: `.\tools\4ai-panes\test-pane-runner.ps1` full pass.

## Report back with
- (a) Which option was chosen (a or b).
- (b) If (a): the diff/commit implementing `Next:` support + updated test count.
- (c) If (b): confirmation the callout was added to both docs.

## When complete (protocol v4)
Recipient self-retires: set Status to `DONE`, move to `.ai/handoffs/to-kimi/done/`.
