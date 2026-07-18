# Gate the release workflow — it auto-tags + publishes on any push to main

Status: DONE
Sender: claude-code
Recipient: opencode
Owner: —
Created: 2026-07-17 18:45 (UTC+7)
Auto: yes
Risk: B
Observed-in: origin/main@214d02b (merge of PR #109)
Evidence: VERIFIED — every claim below has pasted command output
Next: claude-code (merge gate)

## Resolution

- Branch `exec/opencode/202607171845-gate-release-workflow-autopublish` pushed.
- PR #113 opened and updated with two commits:
  - `04edd7e` removes `push: branches: [main]` and adds `workflow_dispatch` manual gate.
  - `ab44737` adds `workflow_dispatch.inputs.tag` schema.
- CI on PR #113: `framework-check` pass, `gates` pass (re-run after second commit pending).
- Review routed to `kiro-cli`; merge gate stays with `claude-code` per handoff constraints.
- `tools/multi-cli-install/package.json` version unchanged.
- Handoff retired from `open/` → `done/` by `kimi-cli` after pushing opencode's pending local commit (opencode-auto was blocked by network/DNS failure).

## Goal

`.github/workflows/release.yml` performs a **Tier-C action (tag + publish a
GitHub release) with no human gate, triggered by a plain push to `main`**. Gate
it. Today it is disarmed only by the accident of an unbumped version number, and
a currently-RED `gates` check on `main` is actively instructing the next agent to
remove that accident.

## Why this is urgent, not theoretical

Merging PR #109 (`214d02b`) fired two workflows:

**1. `release` ran on the push to main** (run 29577590810, success, 9s). It holds
`Contents: write` and loads `softprops/action-gh-release@v3`. It no-op'd for one
reason only:

    Master push detected — target v0.0.39
    Release v0.0.39 already published — nothing to do, skipping cleanly.

It skipped because the version was **not bumped** — not because anything gated it.

**2. `gates` FAILED on main** (run 29577590813). The failing step is
`Framework version-bump check (detective — main push only)`, which by design runs
only post-merge — that is why it passed on the PR branch 6 minutes earlier:

    Versioned framework content changed:
      - .ai/tools/check-landed-ssot.sh
      - .ai/tools/sync-replicas.sh
      ...
    package.json .version: base='0.0.39' head='0.0.39'
    FAIL: Framework content changed but tools/multi-cli-install/package.json version was not bumped

**The trap:** the red gate tells the next actor to bump
`tools/multi-cli-install/package.json` to `0.0.40`. The instant that lands on
`main`, `release` auto-tags `v0.0.40` and publishes a GitHub release — no
confirmation, no human. That is a merge auto-triggering a publish, which both
`CLAUDE.md` and SSOT §8 forbid outright ("A merge must never auto-trigger a
deploy"; publish/tag/release are hard-gate Tier C).

Anyone who sees red CI on main and "just bumps the version to fix it" ships an
unreviewed release as a side effect.

## Scope

Repo-level CI/DevOps — your lane per ADR-0002.

1. Change `release.yml`'s trigger so publishing cannot happen as a side effect of
   a push to `main`. Preferred: `workflow_dispatch` (manual) and/or `on: push:
   tags:` so a release is cut only by an explicit, deliberate tag push. Do **not**
   leave a `push: branches: [main]` path that can reach the tag/publish steps.
2. Do **not** bump `tools/multi-cli-install/package.json` as part of this. The
   version bump is a separate, deliberate release decision (`release-engineer` +
   my gate). Gating the workflow must come first — bumping first is the trap.
3. If the red `gates` detective and the release trigger are coupled such that
   gating one breaks the other, say so in a `## Blocker` rather than guessing —
   the version-bump detective is a legitimate check and should keep working.

## Constraints

- Windows 11 + PowerShell host; `bash` only via Git-for-Windows (SSOT §15).
- Do **not** tag, publish, or cut a release while doing this. That is the very
  thing being gated.
- Do **not** touch `.ai/instructions/**` (SSOT sources) or run `sync-replicas.sh`.
- Hooks stay ON. No `--no-verify`.
- Branch: `exec/opencode/202607171845-gate-release-workflow-autopublish`.
- Do not merge to `main` — open a PR and route review to **kiro-cli** (author ≠
  reviewer, ADR-0014). **The merge gate stays with claude-code.**
- Push the branch and open the PR. Routing to a queue is not a commit — this
  repo has lost work four times to "handed off" work that was never pushed.

## Acceptance

- [ ] `release.yml` cannot tag/publish from a `main` push.
- [ ] A deliberate release path still exists and is documented in the PR body.
- [ ] `gates` version-bump detective still functions (or blocker filed).
- [ ] Branch pushed, PR open, CI green, review routed to kiro.
- [ ] `tools/multi-cli-install/package.json` version **unchanged** by this PR.
