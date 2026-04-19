# Audit consensus vote — Kimi input (supplement to Kiro's 026)  [SUPERSEDED]
Status: SUPERSEDED — fix dispatch replaces vote
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-19 16:20
Superseded: 2026-04-19 16:45 by handoff `028-wave4-stdin-bug-readme-coder-executor.md`

## Why superseded
User approved the Wave 4 fix plan at 16:40 without waiting for full 3-CLI vote
convergence. Kimi no longer needs to vote — execute fix handoff 028 instead.
The consolidated matrix at `.ai/reports/consolidated-audit-2026-04-19.md` remains
as the audit-cycle reference; the fix handoff 028 is derived from it.

---

Original content below for reference only (no longer requires action):

## Collision note
This was originally numbered 026. Kiro-cli filed `to-kimi/open/026-vote-on-kiro-audit-findings.md`
at 15:38 — before I checked the inbox — so this file is renumbered to 027 to resolve
the per-recipient numbering collision. Kiro's 026 is **complementary**, not redundant:

- **Kiro's 026** asks you to vote AGREE/DISAGREE/AMEND on Kiro's 16 audit findings only.
- **This 027** asks you to vote on the **consolidated 22-finding matrix** at
  `.ai/reports/consolidated-audit-2026-04-19.md`, which merges Kiro's 16 + Claude's
  findings + your 2026-04-18 findings into one deduplicated list.

Recommendation: handle Kiro's 026 first (simpler ask, 16 findings), then use the
6 additional findings in the consolidated matrix as the supplement for this 027.
OR you can do one combined vote file that covers all 22. Your call.

## Goal
Same as Kiro's 026 — 3-CLI consensus before any fixes. Specifically: your input is
critical on finding #2 (the `read JSON` stdin bug in your own hooks).

## Read first
- `.ai/reports/consolidated-audit-2026-04-19.md` — master matrix (22 findings)
- `.ai/reports/claude-audit-2026-04-19.md` — Claude's audit
- `.ai/reports/kiro-audit-2026-04-18.md` — Kiro's 2026-04-19 audit
- `.ai/reports/kimi-audit-2026-04-18.md` — your prior audit (please re-check against F-4)

## Required re-check (before voting)

**Finding #2 / Kiro F-4** — Your hooks at:
- `.kimi/hooks/root-guard.sh:6`
- `.kimi/hooks/framework-guard.sh:7`
- `.kimi/hooks/destructive-guard.sh:5`
- `.kimi/hooks/sensitive-guard.sh:6`

…all start with `read JSON` **before** the python `json.load(sys.stdin)` call.
The `read` builtin consumes stdin into the shell variable, so python gets EOF,
the `|| echo ""` fallback fires, `FILE_PATH` ends up empty, and the hook
fail-opens on line `[ -z "$FILE_PATH" ] && exit 0`.

If Kiro is right, **all 4 of your preToolUse hooks are effectively no-ops** —
including the Wave 1 fixes you landed for the dotfile allowlist and the Wave 2+3
destructive-guard expansion. The logic is correct; the plumbing is broken.

### Please verify via pipe-test

```bash
echo '{"tool_input":{"file_path":"evil.txt"}}' | bash .kimi/hooks/root-guard.sh
echo $?
# Exit 0 with no BLOCKED message → F-4 confirmed, hook is fail-open
# Exit 2 with BLOCKED message → F-4 is wrong, investigate why
```

Compare patterns:
- Your hooks: `read JSON` then `python3 -c "... json.load(sys.stdin) ..."`
- Kiro's hooks: no `read`; just `python3 -c "..."` reading stdin directly
- Claude's hooks: `input=$(cat)` then `echo "$input" | python -c "..."`

The Wave 1 activity-log note ("Pipe-tests on Windows bash were unreliable (all
returned exit 0)") would be explained by F-4: the hooks silently fail-open on
every input, regardless of what the case statement would have decided.

## Steps

1. Verify F-4 via the pipe-test. Report exit code + stderr output.
2. Read the consolidated matrix (`.ai/reports/consolidated-audit-2026-04-19.md`).
3. Vote on all 22 findings in `.ai/reports/kimi-vote-2026-04-19.md`:

        # Kimi vote on consolidated audit 2026-04-19

        ## Per-finding votes (22 items)

        | # | Agree? | Severity vote | Notes |
        |---|---|---|---|
        | 1 | ✓/✗/~ | BLOCKER / WARN / INFO / RESOLVED | ... |
        | 2 | ... | ... | ... |
        | ... | ... | ... | ... |

        ## Additional findings (beyond the 22)

        <Anything you see that neither Claude nor Kiro caught.>

        ## Top-5 fix priority

        Rank the ~13 BLOCKER+WARN items. Include rationale for your #1 pick.

        ## Severity disputes

        <Disagreements with proposed severity.>

4. Prepend activity-log entry.
5. Report back in chat with vote-file path + F-4 verification result.

## Special request — Finding #9

Finding #9 says your `.kimi/agents/reviewer.yaml` has `WriteFile`/`StrReplaceFile`
without path restriction. Question for your vote: would a hook-level fix
(e.g., `.kimi/hooks/reviewer-scope-guard.sh` that restricts reviewer writes to
`.ai/reports/reviewer-*.md`) be feasible in Kimi's hook model? Or is
soft-enforcement via prompt the only option? Your answer shapes whether #9
stays WARN or upgrades.

**Note:** if F-4 is real, any new hook you propose will have the same stdin bug
until the `read JSON` pattern is fixed across all scripts. Fix F-4 first, then
propose #9 enforcement.

## Verification
- (a) Vote file exists at `.ai/reports/kimi-vote-2026-04-19.md`
- (b) F-4 pipe-test result reported
- (c) All 22 findings voted
- (d) Top-5 fix priority ranked
- (e) Activity-log entry prepended

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Consensus vote on consolidated audit 2026-04-19 (per handoffs 026 Kiro + 027 Claude). Re-checked F-4 via pipe-test. Voted 22 findings. <F-4 verdict>.
    - Files: .ai/reports/kimi-vote-2026-04-19.md (new)
    - Decisions: <F-4 verdict, top-priority pick, any severity disputes>

## Report back with
- (a) Vote file path
- (b) F-4 verification — does pipe-test confirm fail-open? Exit code + stderr
- (c) Your #1 fix-priority pick + rationale
- (d) Any additional findings
- (e) Your position on #9 enforcement (hook-feasible vs prompt-only)

## When complete
Claude validates by reading the vote file. On validation, Claude synthesizes
the 3-way consensus into a wave-dispatch plan for user approval. Both handoffs
(026 and 027) move to `done/` once the vote is in.
