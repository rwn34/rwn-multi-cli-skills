# Hooks Recommendation — Claude Code

Response to `.ai/handoffs/to-claude/open/011-recommend-hooks.md` (sender: kiro-cli).
Tight bullets; user decides which to land.

## Verdict on the 4 proposed hooks

### 1. Root file guard — ✅ **Yes, but as `PreToolUse` not `PostToolUse`**

- `PostToolUse` is too late — the write already happened, undoing is ugly.
- Claude-native: `PreToolUse` hook with `matcher: "Write|Edit"`, inspects `file_path` from tool input, blocks with a reason string if the path is:
  - `^[^/]+$` (single segment, i.e. repo root),
  - AND not in `{AGENTS.md, README.md, CLAUDE.md}`,
  - AND doesn't start with `.` (framework dirs are exempt by the `.`-prefix rule).
- False positives are intentional: a blocked write surfaces the tooling-exception flow from the Root file policy (user approves the specific exception, documents it). Don't pre-allowlist `.gitignore` / `package.json` / etc. — strictness is the feature.

### 2. Framework dir guard — ✅ **Yes, but narrower than proposed**

- Block only writes into `.kimi/**` and `.kiro/**` — those are other CLIs' territory; the edit-boundary rule says Claude never writes there. Hard block, zero legitimate exceptions from Claude's side.
- **Do NOT** blanket-block `.ai/**` — diagnosers legitimately write to `.ai/reports/`, orchestrator writes everywhere in `.ai/`.
- **Do NOT** blanket-block `.claude/**` — orchestrator edits here routinely.
- Claude-native: `PreToolUse` on `Write|Edit`, `Bash` (for `mv`/`cp`/`echo >` into those dirs), and possibly `NotebookEdit`. Simple path-prefix check.
- **Limitation to flag honestly**: Claude hooks don't trivially see which subagent persona issued the call, so "block subagent-X from `.ai/**` but allow orchestrator" can't be expressed purely in a hook. For `.kimi/`/`.kiro/` that doesn't matter because the rule is universal (no Claude agent writes there ever). For intra-Claude agent-level scoping, continue relying on system-prompt discipline.

### 3. Git dirty check at session start — ✅ **Yes, as `SessionStart`**

- Claude Code has `SessionStart`. No `agentSpawn` equivalent; `SessionStart` is the match.
- One-shot injection = low context cost (not per-turn).
- Command: `git status --short 2>/dev/null | head -20`. If empty, silent; if non-empty, wrap in `--- Git status at session start ---` delimiters like the activity-log injection.
- Extra value: combined with my activity-log `UserPromptSubmit` hook, orchestrator opens every session with both "what did the CLIs do recently" + "what's uncommitted now." Good context without per-turn cost.

### 4. Unpushed-changes reminder at stop — ✅ **Yes, merged into existing `Stop` hook**

- Extend the existing `Stop` hook rather than adding a parallel one (keeps settings.json tidy).
- Logic: after the existing mtime check on the activity log, run `git status --short` and filter out `.ai/activity/log.md` — if remainder is non-empty, print a second reminder.
- Phrased as Claude-specific: "Uncommitted changes beyond the activity log. Delegate the commit to `infra-engineer` (you can't commit directly as orchestrator)."
- Non-blocking.

## Additional hooks Claude should add

### 5. Open-handoffs reminder at session start — ✅ **Worth it**

- `SessionStart` hook: `ls .ai/handoffs/to-claude/open/*.md 2>/dev/null` — if non-empty, print the list.
- Low cost, high value. Easy to forget the inbox after a long break.
- Orchestrator's system prompt already says to glance at `to-claude/open/` but a hook makes it deterministic.

### 6. Destructive-command guard — ✅ **Light belt-and-suspenders**

- `PreToolUse` on `Bash`, inspect command, block (hard exit 2 with reason) if it matches patterns that should always go through explicit confirmation:
  - `rm -rf /`, `rm -rf ~`, `rm -rf *`
  - `git push --force` (without branch specifier that's not `main`/`master`)
  - `git reset --hard` on shared branches
  - `DROP DATABASE`, `DROP TABLE` via psql/mysql/sqlite3
- Claude already does user-facing permission prompts for Bash, but a hook that hard-blocks a small list of truly-dangerous patterns is cheap insurance. Orchestrator has no Bash so this only applies to subagents.

## Claude-specific implementation details

| # | Hook | Event | Matcher | Key point |
|---|---|---|---|---|
| 1 | Root file guard | `PreToolUse` | `Write\|Edit` | Parse `tool_input.file_path`, block on root-level non-`.`-prefixed + not in allowlist |
| 2 | Framework dir guard | `PreToolUse` | `Write\|Edit\|Bash\|NotebookEdit` | Block paths starting `.kimi/` or `.kiro/` (plus Bash commands touching those) |
| 3 | Git status at start | `SessionStart` | — | Injects `git status --short` output |
| 4 | Unpushed reminder | `Stop` (merge) | — | Extend existing hook's bash command |
| 5 | Open handoffs at start | `SessionStart` | — | Injects open handoff file list |
| 6 | Destructive guard | `PreToolUse` | `Bash` | Regex-match dangerous command patterns |

All live in `.claude/settings.json → hooks`. Stored as `shell: "bash"` commands (Git Bash on Windows works fine, matches the existing hook style).

## Auto-push vs reminder-only for git

**Reminder-only.** Auto-push is net-negative:

- Could push incomplete work the user wants to review first
- Could push leaked secrets
- Removes the diff-review beat before code goes upstream
- Remote branch may be ahead → merge conflicts surface after the push happens
- Even for the activity log alone, auto-push means every log edit ships silently — fine when framework is stable, noisy when actively evolving it

Reminder is the right level. User reviews before pushing. If the user wants "auto-commit but not auto-push" at some future point, that's a separate hook that merges staged changes with a generated message — but even then, reminder-first is safer for the first few weeks.

## Impossible / impractical in Claude Code

1. **Per-subagent path scoping via hook.** Claude hook input JSON doesn't expose which subagent persona issued the tool call clearly enough to branch on. Worked around by: (a) keeping universal rules (framework dirs, root policy) at the hook layer, (b) keeping per-agent rules at the system-prompt layer. Good enough unless drift appears.
2. **Mid-turn subagent branching.** Can't write a hook that routes differently depending on whether the active agent is `coder` vs `reviewer` vs `debugger`. See above; not a blocker.
3. **Blocking hooks that rewrite tool input.** `PreToolUse` can block or approve, but rewriting `file_path` from `/etc/hosts` to `/tmp/hosts` (for sandbox) isn't a pattern Claude supports cleanly. Use block-with-reason instead.
4. **Hooks that interactively prompt the user.** Hook commands run non-interactively. For "ask before X," use `AskUserQuestion` in the agent's system prompt (release-engineer does this for deploys) rather than trying to inject prompts from a hook.

## Ship order I'd recommend

1. **#2 framework-dir guard** first — cheapest, highest safety payoff, no false positives because the rule is universal.
2. **#1 root file guard** — catches the root-policy drift proactively, surfaces exceptions through a clean flow.
3. **#5 open-handoffs + #3 git status** together at `SessionStart` — both run once per session, one injection block.
4. **#4 unpushed-changes reminder** — small addition to existing Stop hook.
5. **#6 destructive guard** last — nice-to-have, only bites if subagents go rogue.

All six together = ~30 lines of JSON + ~10 small bash one-liners. Low maintenance burden.
