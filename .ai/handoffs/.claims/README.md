# Per-handoff claim sidecars (ADR-0009 section 3)

Ephemeral claim markers so two consumers never process the same
`to-<recipient>/open/` handoff. Everything here except this README is runtime
state and is gitignored (see repo `.gitignore`) - never commit a `.claim.json`.

- **File name:** `<recipient>__<handoff-basename>.claim.json` where `recipient`
  is `claude|kimi|kiro|opencode` and `handoff-basename` is the handoff filename
  without its `.md` extension.
- **Content:** `{ "handoff": "<basename>", "recipient": "<recipient>",
  "owner": "<claude-cockpit|claude|kimi-cockpit|kimi|kiro|opencode>", "pid": <int>,
  "host": "<hostname>", "claimed_at": "<UTC ISO-8601>" }`. `owner` distinguishes
  the cockpit and auto-pane instances of the recipient CLI (e.g. `claude-cockpit` = interactive cockpit, `claude` = headless auto pane).
- **Acquire (atomic):** create the sidecar with an exclusive-create open
  (fails if it already exists). Win = you may run the handoff; lose = skip it.
- **Check:** a claim is LIVE only if its `pid` is alive on the same `host` AND
  `claimed_at` is within the staleness window (default 15 min).
- **Stale reclaim:** a claim whose pid is dead (same host) or whose `claimed_at`
  is older than the window counts as unclaimed and may be overwritten.
- **Release:** delete the sidecar when the handoff moves to `done/`, or on a
  graceful pause/stop for claims you hold.

Honored by `tools/4ai-panes/pane-runner.ps1` today; app-Claude (reads files) and
any future bash consumer must follow the same contract.
