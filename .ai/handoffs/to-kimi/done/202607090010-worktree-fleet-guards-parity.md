# Add ADR-0004 worktree-confinement + fleet-whitelist guards to Kimi's hooks
Status: DONE
Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-09 00:10
Completed: 2026-07-09 06:55
Auto: yes
Risk: B

## Goal
Guard parity for ADR-0004 (worktree + multi-project topology): Kimi's bash
guard layer gains the same two rules Claude's `pretool-write-edit.sh` now has,
so an executor Kimi session inside a `.wt/<project>/kimi/` worktree cannot
escape it, and fleet handoff writes respect the registry whitelist.

## Current state
- Kimi guards: `.kimi/hooks/{root-guard,framework-guard,sensitive-guard,destructive-guard}.sh`,
  registered globally in `~/.kimi/config.toml`.
- No worktree or fleet awareness anywhere in them.

## Target state
Two new rules (new script `worktree-fleet-guard.sh` or extend framework-guard —
your call, your conventions):
1. **Worktree confinement:** if the session cwd matches `*/.wt/*/*`, block any
   write whose target path is absolute-outside-the-worktree or contains `../`
   escapes. The junctioned `.ai/` resolves relative, so it stays writable.
2. **Fleet whitelist:** writes matching `*/.fleet/handoffs/to-<X>/*` are
   allowed only when `<fleetroot>/registry.json` lists `<X>` in THIS project's
   `talks_to`. Missing registry ⇒ block (fail-closed). Other `.fleet/` paths
   (activity log, README) ⇒ allow.

## Context (reference only, not binding)
Claude's implementation: `.claude/hooks/pretool-write-edit.sh` Rules 2.6/2.7
(sed-extract of fleet root/target + a 7-line python registry check, python3
with python fallback). Test pattern: `.claude/hooks/test_hooks.sh` t32-t38 —
temp-dir fixtures incl. a `run_test_cd` helper that runs the hook from a
simulated worktree cwd. ADR: `docs/architecture/0004-worktree-multi-project-topology.md`.

## Steps
1. Implement the two rules in your guard layer.
2. Extend your hook test suite with the 7 equivalent cases (whitelisted-allow,
   non-whitelisted-block, no-registry-block, activity-allow, absolute-escape,
   ../-escape, in-tree-allow).
3. Register the new/changed guard in `~/.kimi/config.toml` if it's a new file.

## Verification
- (a) Full Kimi hook suite run — paste the PASS line (execution, not claim).
- (b) Pipe-test one whitelisted and one blocked fleet write — paste both.

## Next step / future note
Kiro receives the same parity handoff (its subagent hook-inheritance bug means
its guard only protects the main session — note that residual gap in your
report if you confirm it applies here too). Breaks first: if the `.wt/`
container location ever moves, the `*/.wt/*/*` cwd pattern is the single
assumption to update.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: ADR-0004 guard parity per handoff 202607090010
    - Files: <paths>
    - Decisions: <choices>

## Report back with
- (a) guard file path(s) + registration diff, (b) suite PASS line, (c) pipe-test outputs

## When complete
Move to `.ai/handoffs/to-kimi/done/`.
