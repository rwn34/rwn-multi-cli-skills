# Orchestrator / Delegation Architecture — Claude Code

Research doc produced for handoff `.ai/handoffs/to-claude/open/001-orchestrator-delegation-research.md` from kiro-cli. Covers Claude Code's subagent/delegation model, tool restriction, failure handling, and a proposed read-only-orchestrator + write-capable-subagents setup. **Design only — not implementation.**

## Executive summary

Claude Code can support the target architecture using native mechanisms, no workarounds. Four pieces:

1. **Custom subagents** — `.claude/agents/<name>.md` files (markdown + YAML frontmatter).
2. **Per-agent tool restriction** — whitelist via `tools:` frontmatter field.
3. **Main-thread agent** — `.claude/settings.json → "agent": "<name>"` makes the named agent the persona for the main conversation thread (not just for subagent invocations).
4. **Subagent invocation** — built-in `Agent` tool with `subagent_type: "<name>"`.

All four are first-class Claude Code features. The architecture translates cleanly.

## How Claude Code's subagent model works

### Agent definition

File location: `.claude/agents/<name>.md` (project-local) or `~/.claude/agents/<name>.md` (user-level). Structure:

    ---
    name: <agent-name>
    description: <one-paragraph trigger/purpose description>
    tools: Read, Grep, Glob, Bash, Edit, Write, ...    # comma-separated WHITELIST
    model: sonnet | opus | haiku | <full-id>           # optional; inherits parent if omitted
    ---

    <system prompt body — what the agent sees as its role description>

Rules:
- `tools:` is a **whitelist**. Tools not listed are not in the agent's available-tools schema.
- If `tools:` is omitted entirely, the agent inherits all tools from its invoking context. For a locked-down orchestrator you MUST specify `tools:` explicitly.
- `model:` is optional; omitting inherits from the main agent.
- Agents are discovered at session start; their name + description are listed in the main agent's available-agents table so it knows what it can delegate to.

### Subagent invocation

The main agent invokes a subagent via the built-in `Agent` tool:

    Agent({
      description: "short 3-5 word task label",
      subagent_type: "<name>",
      prompt: "<full task brief for the subagent>",
      model: <optional override>,
      isolation: <optional — "worktree" creates an isolated git worktree>,
      run_in_background: <optional true/false>
    })

The subagent starts with a **fresh context** — it only sees the prompt the orchestrator passes, not the main-thread conversation history. It runs its own tool-call loop, and returns a **single summary message**. The main agent cannot intervene mid-run — subagents run to completion.

### Main-thread agent (the key insight for this architecture)

Claude Code's settings schema has an `"agent"` field at the top level:

    {
      "agent": "orchestrator"
    }

Setting this makes the named agent the persona for the **main conversation thread** — its system prompt, tool restrictions, and model apply to every turn of the main thread. Not just to subagent invocations.

**This is how "orchestrator is read-only" gets enforced:** the main thread *is* the orchestrator agent. Without `"agent"` set, the main thread runs with the full built-in system prompt and full tool access (the defaults you see in a vanilla Claude Code session).

## Tool restriction — what works

| Mechanism | What it does | Applies to |
|---|---|---|
| Agent `tools:` frontmatter | Hard-whitelists which tools the agent sees. Missing tools don't exist for that agent. | Per-agent, including main thread when `"agent"` is set. |
| `permissions.allow/deny/ask` in settings | Runtime gate on individual tool calls by tool name + argument pattern. Can prompt or block. | Project/user settings; orthogonal to agent tool lists. |
| `disableSkillShellExecution` | Disables shell execution *inside skills and slash commands*. | Global; doesn't affect direct Bash calls from agents. |

For the orchestrator, **use frontmatter `tools:`** — it's a schema-level restriction. If `Edit` isn't in the list, the orchestrator's tool schema literally doesn't contain `Edit`, so it cannot attempt to call it. Much stronger than permission rules (which only fire on call attempt).

## Failure handling — observed behavior

- Subagent runs to completion and returns **one summary message**.
- Subagent errors (tool-call failures, permission denials, timeouts, model errors) surface as text inside that summary.
- The main agent receives the summary and decides what to do — no automatic retry, no takeover.
- The main agent **cannot** "continue" a failed subagent's loop. It can only re-invoke the subagent with a corrected prompt.

This naturally matches architecture rule (4): "Subagent failure does NOT cause orchestrator to take over." The orchestrator is incapable of taking over anyway — it has no write tools. It reports failure to the user and asks what to do next.

## Proposed configs

### `.claude/agents/orchestrator.md`

    ---
    name: orchestrator
    description: Read-only orchestrator. Consults, plans, analyzes, and delegates all mutations to specialized subagents via the Agent tool. Cannot write files or run shell commands.
    tools: Read, Grep, Glob, Agent, TaskCreate, TaskUpdate, TaskList, WebFetch, WebSearch, Skill
    ---

    You are the orchestrator for this project. Your job:

    1. Understand the user's request — ask clarifying questions before assuming scope.
    2. Gather context via Read / Grep / Glob / WebFetch — build a grounded mental model.
    3. Plan the work. For non-trivial tasks, break into steps with verification criteria.
    4. Delegate mutations to subagents via the Agent tool:
       - `coder` — for file edits, shell commands, test runs, build/deploy actions
       - `reviewer` — for read-only code review (you can do simple reads yourself)
       - If no existing subagent fits: describe what's needed (tools, purpose, skills it should load), ask the user to approve creating one. Do NOT attempt the work yourself.
    5. After a subagent returns, read the touched files to verify the work landed correctly. If something is off, report to the user and possibly re-invoke with corrections — do not patch directly.
    6. If a subagent fails, report the failure and the cause it gave. Do not retry silently.

    You do NOT have Edit, Write, Bash, or NotebookEdit. Attempting to mutate state yourself is a bug — always delegate.

### `.claude/agents/coder.md`

    ---
    name: coder
    description: Executes code changes, writes files, runs shell commands, runs tests. Use when the orchestrator needs concrete mutations applied and verified.
    tools: Read, Edit, Write, Bash, Grep, Glob, NotebookEdit, TaskCreate, TaskUpdate, TaskList, Skill
    ---

    You are the coder. The orchestrator has delegated a concrete change. Execute it and report back what changed.

    Follow the Karpathy guidelines (see your available skills):
    - Surgical changes only — touch what's requested, nothing more.
    - Simplicity first — no speculative abstractions.
    - Verify via tests / re-reads before reporting done.

    Report back: files touched (absolute paths), commands run, test results, and any deviations from the orchestrator's brief.

### `.claude/agents/reviewer.md`

    ---
    name: reviewer
    description: Read-only code review — correctness, style, security, test coverage. No writes. Use for PR-style review passes, security audits, second-opinion reads.
    tools: Read, Grep, Glob, Skill
    ---

    You are the reviewer. The orchestrator has handed you a scope to review. Read the relevant files, identify issues, suggest improvements. You cannot modify anything.

    Return a structured report: summary, issues (by severity: critical / high / medium / low), concrete suggestions with file paths and line numbers where possible.

### `.claude/settings.json` addition

Merge into the existing settings (preserving the hooks block already in place):

    {
      "$schema": "https://json.schemastore.org/claude-code-settings.json",
      "agent": "orchestrator",
      "hooks": { ... existing UserPromptSubmit + Stop hooks preserved ... }
    }

That one field flips the main thread into orchestrator mode.

## Proposed workflow (walk-through)

1. User: "add rate limiting to the API"
2. Orchestrator reads the API code, finds existing middleware patterns, drafts a plan.
3. Orchestrator writes a plan to the user (steps with verify criteria), asks which approach.
4. User approves.
5. Orchestrator: `Agent({ subagent_type: "coder", prompt: "<specific task brief with file paths, expected changes, tests to run>" })`.
6. Coder writes the code, runs tests, returns a summary with paths + test results.
7. Orchestrator reads the changed files to confirm. If something's off, re-invokes coder with corrections.
8. Orchestrator reports back to the user with file paths + verification summary.

Swap `coder` for `reviewer` for review-only flows. For unfamiliar scopes, orchestrator recommends creating a new specialized subagent rather than overloading `coder`.

## Known limitations

1. **Subagent context is ephemeral.** Subagent gets only the orchestrator's prompt — no shared history. The orchestrator must brief well.
2. **Subagent return is a single message.** No streaming, no partial results. Long runs feel opaque.
3. **Re-verification is manual.** Orchestrator must re-read files to confirm subagent's claims. There's no "return a structured diff" protocol.
4. **No cross-subagent communication.** `coder` can't call `reviewer` directly. Orchestrator mediates (coder returns → orchestrator invokes reviewer).
5. **Tool whitelisting is all-or-nothing per tool.** Can include or exclude `Bash`, but "Bash only for test commands" is a permission-rules concern, not a tool-list concern.
6. **Skills are scoped per agent.** A skill visible to the orchestrator isn't automatically visible to the coder. For a shared skill (like karpathy-guidelines), each agent's system prompt should reference it explicitly, or the skill must be user-level and globally enabled.
7. **Main-thread hooks fire regardless of which agent is active.** The existing `UserPromptSubmit` / `Stop` hooks in `.claude/settings.json` will still run — fine for activity-log auto-injection, but worth knowing.
8. **Agent reload requires session restart.** Changes to `.claude/agents/*.md` are picked up at session start, not hot-swapped. Restart Claude Code after editing an agent to see changes.

## Comparison to Kiro's model

(Reference: `.ai/cli-map.md` and `.kiro/agents/project.json`.)

| Axis | Claude Code | Kiro CLI |
|---|---|---|
| Agent config format | Markdown + YAML frontmatter at `.claude/agents/<name>.md` | JSON at `.kiro/agents/<name>.json` |
| Main-thread agent selector | `.claude/settings.json → "agent": "<name>"` | `--agent <name>` flag or `chat.defaultAgent` setting |
| Subagent spawn tool | `Agent` (`subagent_type: "<name>"`) | `subagent` |
| Tool restriction | `tools:` frontmatter whitelist | `tools` array in agent JSON |
| Built-in subagents shipped | Yes (Explore, Plan, general-purpose, claude-code-guide, statusline-setup) | No — all user-defined |
| Inheritance between agents | None | None (per Kiro's own research) |
| Lifecycle hooks | `.claude/settings.json → hooks` (session-level) | `agentSpawn` / `stop` in agent JSON (agent-level) |
| Skill loading | `description` frontmatter match, agent-scoped | `skill://` URIs in agent's `resources` array |

**Functional parity on the orchestrator pattern.** Both can do read-only main + write-capable subagents with the same shape. The translation is almost 1:1 — just different file formats and key names.

**Key divergence**: Claude has built-in subagent types (Explore, Plan, etc.) that work out of the box. Kiro does not. The orchestrator in Claude can lean on those for research-heavy tasks (e.g. delegate broad exploration to Explore) while we custom-build coder/reviewer for project-specific mutation work.

## Recommended next steps

1. **Create the three agent files** — `.claude/agents/{orchestrator,coder,reviewer}.md` with the configs above. One handoff / PR.
2. **Wire `"agent": "orchestrator"` in `.claude/settings.json`** — single-line edit, preserve the existing hooks block.
3. **Restart Claude Code** — agent changes need a fresh session to take effect.
4. **Dry-run on a trivial task** — e.g. have the orchestrator delegate a comment-typo fix to `coder`. Verify the orchestrator's tool list lacks Edit/Write/Bash; verify delegation + readback works end-to-end.
5. **Iterate on system prompts** — the orchestrator's system prompt is the piece most likely to need tuning. Run a few real tasks and watch where it mis-plans or tries to work itself.
6. **Decide on additional specialized agents** as they're needed — `db-migrator`, `test-runner`, `sdk-publisher`, etc. Each new handoff creates one new agent file.

## Confidence notes

- **High confidence**: agent file format, `tools:` whitelist semantics, `Agent` tool signature, `"agent"` setting in schema. All verified via the Claude Code settings JSON schema and the Agent tool signature available in this session.
- **Medium confidence**: exact behavior when a subagent fails mid-run. The "returns one summary message" shape is the documented contract; I have not stress-tested subagent failures in this specific project.
- **Lower confidence**: skill scoping across parent/child agents. Behavior depends on Claude Code version. Worth a dry-run to confirm whether `coder` sees the karpathy-guidelines skill with or without extra configuration.

No aspirational features in this doc — everything proposed is a first-class Claude Code mechanism available today.
