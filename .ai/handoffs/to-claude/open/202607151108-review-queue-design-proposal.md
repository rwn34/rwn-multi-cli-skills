# RFC: Add `.ai/handoffs/to-claude/review/` for post-execution verification
Status: OPEN
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-15 11:08
Auto: yes
Risk: B
Base: origin/master

## Context

The current topology has:
- 2 cockpits: Kimi and Claude (owner uses at will)
- 1 auto-claude: handoff receiver / distributor
- 2 executors + reviewers: Kiro and Kimi
- 1 DevOps/release: OpenCode

When OpenCode executes a Tier B operation (e.g., `git push origin master`), it retires its own handoff to `to-opencode/done/`. There is no automatic follow-up verification handoff, so nobody checks OpenCode's work unless a human notices.

## Proposal

Add dedicated review queues:

```
.ai/handoffs/
  to-claude/
    open/     <- work for claude-auto to execute
    review/   <- work done by other CLIs that needs claude-auto verification
    done/
  to-kiro/
    open/
    review/   <- peer-review tasks routed to kiro-auto
    done/
  to-kimi/
    open/
    review/   <- peer-review tasks routed to kimi-auto
    done/
```

### Lifecycle

1. Executor CLI (e.g., OpenCode) completes a handoff from `to-opencode/open/`.
2. It moves the original handoff to `to-opencode/done/`.
3. For operations that should be verified, it also creates a review handoff in `to-claude/review/` (or `to-kiro/review/` / `to-kimi/review/` if peer-review is wanted).
4. The designated reviewer auto-pane polls its `review/` directory alongside `open/`.
5. Reviewer verifies, then moves the review handoff to its own `done/`.

### Review handoff contents

- Reference to the original handoff
- What operation was performed
- Evidence (commit SHAs, PR URLs, deploy output, etc.)
- Suggested reviewer (optional)
- Risk tier

### Why this is better than scanning `done/`

- Explicit signal instead of scraping every completed handoff
- Lower noise
- Clear separation of concerns: `open` = do work, `review` = verify work, `done` = finished

## Question for Claude

Please review this design and give your opinion:

1. Is `to-claude/review/` the right shape, or do you prefer a different structure?
2. Should review handoffs be emitted by the executor automatically (e.g., OpenCode's pane-runner), or should claude-auto scan `done/` queues and decide what to review?
3. Should we add `review/` for Kiro and Kimi too, or start with only `to-claude/review/`?
4. What criteria should trigger a review handoff? (e.g., every push, only merges, only releases, only Tier B+ ops)
5. Any concerns about pane-runner changes needed to poll `review/`?

Please respond by editing this handoff with your conclusions and either:
- Returning it as `DONE` if you approve as-is, or
- Creating follow-up handoffs to Kimi/Kiro for implementation if changes are needed.
