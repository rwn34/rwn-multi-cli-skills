# Add ADR-0004 worktree-confinement + fleet-whitelist guards to Kiro's hooks
Status: OPEN
Sender: claude-code
Recipient: kiro-cli
Created: 2026-07-09 00:11
Auto: yes
Risk: B

## Goal
Guard parity for ADR-0004 (worktree + multi-project topology): Kiro's hook
layer gains the same two rules Claude's `pretool-write-edit.sh` now has, so an
executor Kiro session inside a `.wt/<project>/kiro/` worktree cannot escape
it, and fleet handoff writes respect the registry whitelist.

## Current state
- Kiro guards: `.kiro/hooks/*.sh` wired via `.kiro/agents/*.json` hooks
  sections; `toolsSettings.fs_write.deniedPaths` provides tool-level denial.
- No worktree or fleet awareness anywhere.
- KNOWN GAP: subagents don't inherit hooks (upstream #7671, see
  `.ai/known-limitations.md`) — these guards protect the MAIN session only;
  restate the residual risk in your report.

## Target state
1. **Worktree confinement:** session cwd matches `*/.wt/*/*` ⇒ block writes
   to absolute-outside-worktree paths or `../` escapes. Junctioned `.ai/`
   (relative) stays writable.
2. **Fleet whitelist:** writes matching `*/.fleet/handoffs/to-<X>/*` allowed
   only when `<fleetroot>/registry.json` lists `<X>` in THIS project's
   `talks_to`. Missing registry ⇒ block (fail-closed). Other `.fleet/` paths
   ⇒ allow.
3. Consider ALSO adding `../` patterns to `fs_write.deniedPaths` if Kiro's
   matcher supports it — tool-level denial is your only subagent-proof layer.

## Context (reference only, not binding)
Claude's implementation: `.claude/hooks/pretool-write-edit.sh` Rules 2.6/2.7;
tests `.claude/hooks/test_hooks.sh` t32-t38 (temp fixtures + run-from-worktree
helper). ADR: `docs/architecture/0004-worktree-multi-project-topology.md`.

## Steps
1. Implement both rules in your guard scripts; wire into agent config hooks.
2. Extend your hook test suite with the 7 equivalent cases.
3. Evaluate the deniedPaths hardening (step 3 above) and report feasibility.

## Verification
- (a) Full Kiro hook suite run — paste the PASS line.
- (b) Pipe-test one whitelisted and one blocked fleet write — paste both.

## Next step / future note
Kimi has the same parity handoff (202607090010). Breaks first: the `*/.wt/*/*`
cwd assumption if the worktree container location changes; and the subagent
gap means worktree confinement for Kiro SUBAGENTS rests on deniedPaths until
upstream #7671 is fixed.

## Activity log template
    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: ADR-0004 guard parity per handoff 202607090011
    - Files: <paths>
    - Decisions: <choices>

## Report back with
- (a) guard/config paths + diffs, (b) suite PASS line, (c) pipe-test outputs, (d) deniedPaths verdict

## When complete
Move to `.ai/handoffs/to-kiro/done/`.
