# Provide owner paste-ready prompt to live-test Kimi guard hooks in a fresh session
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-09 10:14
Auto: yes
Risk: A

## Goal
The owner will open a brand-new Kimi terminal session to verify that the just-fixed PreToolUse guard hooks actually fire and block forbidden writes. Claude Code should prepare and return a concise, paste-ready prompt the owner can drop into that new Kimi session to run the verification.

## Background
- Kimi guard scripts were just rewritten to be python-independent and fail-closed:
  - `.kimi/hooks/framework-guard.sh`
  - `.kimi/hooks/sensitive-guard.sh`
  - `.kimi/hooks/root-guard.sh`
  - `.kimi/hooks/destructive-guard.sh`
  - `.kimi/hooks/worktree-fleet-guard.sh`
- `bash .kimi/hooks/test_hooks.sh` passes `48/48`.
- Manual stdin tests show the scripts block `.kiro/`, `.env`, root files, and destructive commands, and fail-closed on unparseable non-empty input.
- Live verification in the current Kimi session is impossible because this session's config is cached from start time and Kimi did not reload hooks mid-session.
- `~/.kimi-code/config.toml` has been restored with the full `[[hooks]]` list.

## What the owner needs
A single paste-ready prompt to give the new Kimi session. The prompt should instruct Kimi to:

1. Attempt to write `.kiro/probe.txt` with content `x` and report whether it is blocked.
2. Attempt to write `.env` with content `PROBE=1` and report whether it is blocked.
3. Attempt to write `disallowed-root-file.txt` at the repo root and report whether it is blocked.
4. Run `bash .kimi/hooks/test_hooks.sh` and paste the result.
5. For each attempted write, run `ls -la <path>` afterward to confirm the file does not exist.

The prompt should explicitly tell Kimi **not to pre-refuse** — it must actually call the `Write` tool so the PreToolUse hooks can fire.

## Report back with
- The exact paste-ready prompt text (in a code block) that the owner can copy.
- Any caveats you want the owner to know before running it (e.g., start a brand-new `kimi` session, do not restore the old session).

## Activity log template
    ## 2026-07-09 HH:MM — claude-code
    - Action: Per handoff 202607091014-kimi-guard-live-test-prompt — provided owner with paste-ready Kimi guard verification prompt
    - Files: —
    - Decisions: —

## When complete
Sender validates by reading the prompt. On success, move this file to `.ai/handoffs/to-claude/done/`. On failure, leave it in `open/`, change Status to `BLOCKED`, and append a `## Blocker` section.

---

## Completed by claude-code — 2026-07-09

Verified all five rewritten guard scripts plus `test_hooks.sh` exist under
`.kimi/hooks/`. Paste-ready owner prompt below.

### Paste-ready prompt for the fresh Kimi session

```
I need you to LIVE-TEST the PreToolUse guard hooks in this session. Do NOT
pre-refuse or reason about whether these writes are allowed — you MUST actually
call the Write tool for each one so the PreToolUse hooks get a chance to fire.
If a hook blocks the write, report the exact block message. Run these steps in
order and report each result:

1. Use the Write tool to create `.kiro/probe.txt` with content `x`.
   Report: was it BLOCKED or ALLOWED? Paste the hook message if blocked.
   Then run `ls -la .kiro/probe.txt` and paste the output.

2. Use the Write tool to create `.env` with content `PROBE=1`.
   Report: was it BLOCKED or ALLOWED? Paste the hook message if blocked.
   Then run `ls -la .env` and paste the output.

3. Use the Write tool to create `disallowed-root-file.txt` at the repo root
   with content `x`.
   Report: was it BLOCKED or ALLOWED? Paste the hook message if blocked.
   Then run `ls -la disallowed-root-file.txt` and paste the output.

4. Run `bash .kimi/hooks/test_hooks.sh` and paste the full result line
   (expect 48/48 passing).

5. Summarize: for steps 1-3, confirm each target file does NOT exist on disk
   (the `ls -la` should report "No such file or directory" for a correct block).

Expected outcome: steps 1-3 are all BLOCKED and the files do not exist; step 4
passes 48/48. Report any deviation.
```

### Caveats for the owner
- **Start a brand-new `kimi` session** before pasting — do not resume/restore the
  old session. Kimi caches its hook config at session start, so only a fresh
  session picks up the rewritten `[[hooks]]` list from `~/.kimi-code/config.toml`.
- Run it from the **repo root** (`rwn-multi-cli-skills/`) so the relative paths
  resolve.
- A correct block leaves **no file on disk** — the `ls -la` confirmation is the
  ground-truth check, not just Kimi's self-report.
- If any write is ALLOWED (not blocked), that's a hook regression — leave the
  probe files out of any commit and report back so we can re-open this handoff.
