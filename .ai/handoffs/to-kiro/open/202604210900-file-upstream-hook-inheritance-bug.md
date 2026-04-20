# File upstream bug — subagent hook inheritance broken
Status: OPEN
Sender: claude-code (orchestrator, on behalf of user)
Recipient: kiro-cli
Created: 2026-04-21 09:00

## Goal
File the "subagent hook inheritance broken" bug report against Kiro CLI's
upstream issue tracker. The paste-ready report has been sitting in
`.ai/reports/kiro-bug-subagent-hook-inheritance.md` since 2026-04-19 but was
never filed — user wants it in front of the Kiro team now.

You (Kiro CLI) know where Kiro's issue tracker lives and what format issues
should take. Use that knowledge.

## Current state

- Report: `.ai/reports/kiro-bug-subagent-hook-inheritance.md`
  - Title, severity (High), environment (Windows Git Bash)
  - Summary + full repro (empirically confirmed 2026-04-19 21:22 and 2026-04-19 22:22)
  - Expected vs observed behavior
  - Impact on multi-CLI safety model
  - Current workarounds (tool-level `deniedPaths`, prompt hardening)
- `<FILL IN>` placeholder for `kiro --version` — fill this in with the actual
  version on this machine before filing.

## Steps

1. **Read the report** at `.ai/reports/kiro-bug-subagent-hook-inheritance.md`
   in full. Confirm the repro steps are accurate on your current runtime
   (spawn a coder subagent with an `fs_write` hook declared, ask it to write
   `evil.txt` at root, check if the hook fires).

2. **Fill in `<FILL IN>`** with the current `kiro --version` output. If the
   version field needs additional metadata (build hash, platform), add it.

3. **Determine the correct upstream location:**
   - If Kiro CLI has an official GitHub issue tracker, file there.
   - If Kiro CLI uses a feedback/bug form or Discord / support channel, use
     that.
   - If Kiro CLI has internal tooling for submitting bugs (similar to how
     some CLIs have `kiro bug-report` subcommand), use that.
   - If none of the above exists / you can't determine the right place:
     STOP. Mark this handoff BLOCKED with an explanation of why, so the user
     can file manually via their own account.

4. **Submit the report.** Use the report's title, severity, environment,
   summary, repro, and impact sections as-is. Copy verbatim where possible.

5. **Record the issue URL** in your response. Orchestrator will update
   `.ai/known-limitations.md` to link the filed issue so anyone reading about
   the hook-inheritance limitation can track upstream progress.

## Verification

- (a) Bug is filed upstream; issue URL returned.
- (b) Version placeholder no longer says `<FILL IN>` — either in the filed
  issue, in the local report, or both.
- (c) If filing was not possible: handoff is BLOCKED with clear reason.

## Activity log template

    ## YYYY-MM-DD HH:MM — kiro-cli
    - Action: Filed upstream bug per handoff 202604210900. Issue: <URL>
    - Files: .ai/reports/kiro-bug-subagent-hook-inheritance.md (edit — filled in version)
    - Decisions: <e.g. which tracker was used, why>

## Report back with

- (a) Issue URL (if filed), OR blocker reason (if not).
- (b) `kiro --version` output you filled in.
- (c) Any tracker-specific details orchestrator should know (e.g., issue
  number format, expected triage time, if it was assigned to anyone).

## When complete

On successful filing:
- You edit `.ai/reports/kiro-bug-subagent-hook-inheritance.md` to append a
  "Filed upstream: <URL> on <date>" line at top.
- Move this handoff to `.ai/handoffs/to-kiro/done/`.
- Orchestrator (next Claude session) will update `.ai/known-limitations.md`
  with the URL.

On BLOCKED (can't file):
- Leave this handoff in `open/`, set Status to `BLOCKED`.
- Append `## Blocker` section explaining why.
- User files manually via their own account using the report.
