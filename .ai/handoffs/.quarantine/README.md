# Per-handoff quarantine sidecars (poison-pill guard)

Durable markers that stop the self-driving runner from re-processing a handoff
that keeps failing. Everything here except this README is runtime state and is
gitignored (see repo `.gitignore`) - never commit a `.quarantine.json`.

A handoff is quarantined after it fails to reach `done/` on
`$script:MaxHandoffAttempts` consecutive supervisor attempts (default 3) -
whether it MAXED (still OPEN after the continue cap) or threw an error each time.
Once quarantined, `Get-QualifyingHandoff` skips it, so the pane keeps polling
OTHER handoffs instead of burning cycles (and tokens) on the poison pill.

- **File name:** `<recipient>__<handoff-basename>.quarantine.json` where
  `recipient` is `claude|kimi|kiro|opencode` and `handoff-basename` is the
  handoff filename without its `.md` extension.
- **Content:** `{ "handoff": "<basename>", "recipient": "<recipient>",
  "attempts": <int>, "quarantined": <bool>, "first_attempt": "<UTC ISO-8601>",
  "last_attempt": "<UTC ISO-8601>", "last_error": "<message>" }`.
- **Increment:** after a supervisor attempt leaves the handoff in `open/` (it
  MAXED past the continue cap, or the iteration threw), `attempts` is bumped; at
  the threshold `quarantined` flips to true and the runner logs one loud
  QUARANTINE alert (not repeated - the handoff is simply skipped thereafter).
- **Cleared automatically** when the handoff finally reaches `done/`.
- **Clear manually** (un-quarantine) by DELETING this sidecar after you have
  fixed or unblocked the handoff - the runner re-attempts it on the next poll.

Honored by `tools/4ai-panes/pane-runner.ps1`. Any future consumer that
auto-processes handoffs should follow the same contract.
