# rwn multi-CLI AI template

**A coordination framework that lets Claude Code, Kimi CLI, and Kiro CLI work on the same project in parallel — safely, with shared state and enforced write boundaries.**

> Status: pre-1.0 (last refreshed 2026-04-27). Solid for solo / small-team projects. Bash install path is battle-tested; the new Node.js installer at `tools/multi-cli-install/` is pre-release with fixture-only validation. Not yet battle-tested in production. See [Confidence & limitations](#confidence--limitations) for honest caveats.

---

## What is this?

A **template** — a starting point you drop into a project — that gives you:

1. **Three AI CLIs coordinating on shared state.** Claude Code (architect/orchestrator), Kimi CLI (high-throughput workhorse), Kiro CLI (premium reasoning via Opus 4.6). They read the same activity log, queue work for each other via file-based handoffs, share a single source of truth for agent definitions.

2. **Hard write boundaries.** Each CLI can edit only its own config dir + shared `.ai/` + your project code. A hook layer enforces this — if Claude tries to write to `.kiro/`, the write is blocked before it hits disk.

3. **13 scoped subagents per CLI.** Every CLI has the same roster (`coder`, `reviewer`, `tester`, `debugger`, `refactorer`, `doc-writer`, `security-auditor`, `ui-engineer`, `e2e-tester`, `infra-engineer`, `release-engineer`, `data-migrator`, plus `orchestrator`) with matching scopes and safety rules, so you can delegate the same way regardless of which CLI you're driving.

4. **A shippable install script.** One command adopts this template into an existing project: `./scripts/install-template.sh /path/to/your/project`.

## The problem it solves

If you use multiple AI CLIs on one project, you'll hit these within days:

- **"Which CLI edited this file last?"** — no shared log, no audit trail.
- **"Why did the other CLI overwrite my change?"** — no write boundaries, everyone competes for the same files.
- **"How do I make sure all three CLIs follow the same rules?"** — steering files drift out of sync, policies diverge.
- **"My subagent just `rm -rf /`'d something important"** — no enforced safety hooks.
- **"I want to hand work between CLIs without copying output into each chat manually"** — no handoff protocol.

This template solves each: shared `.ai/activity/log.md` for the audit trail; a `pretool-write-edit` hook in each CLI for write boundaries; a single-source-of-truth `principles.md` that regenerates into each CLI's native steering format (byte-identical, drift-checked); a `sensitive-file-guard` + `destructive-cmd-guard` + `root-file-guard` for safety; a `to-<cli>/open/` + `done/` handoff queue for cross-CLI work.

## Who it's for

- **Solo developers** running multiple AI CLIs and wanting coherence between sessions.
- **Small teams** (2-5 devs) where each dev may prefer a different CLI.
- **Research / exploration projects** where you want strong safety rails but light ceremony.
- **Template adopters** — use the installer to bolt this framework onto an existing project in ~10 minutes.

**Not yet ready for:** production systems with compliance requirements (needs RBAC, observability, immutable audit logs — all flagged in [`.ai/known-limitations.md`](./.ai/known-limitations.md)).

## Grounded in Anthropic's 4Ds of AI Fluency

[Anthropic's AI Fluency framework](https://aifluencyframework.org/) defines four competencies for effective human–AI collaboration — **Delegation, Description, Discernment, Diligence**. This template is an opinionated implementation of them applied to multi-agent coding:

- **Delegation** — scoped 13-subagent roster per CLI with explicit write boundaries enforced at the tool layer.
- **Description** — structured [handoff protocol](./.ai/handoffs/README.md) for cross-CLI work (paste-ready instruction files, not ad-hoc chat).
- **Discernment** — [safety hooks](./.claude/hooks/) + [SSOT drift checker](./.ai/tools/check-ssot-drift.sh) + CI test suites as systematic quality gates.
- **Diligence** — [append-only activity log](./.ai/activity/log.md) + [known-limitations doc](./.ai/known-limitations.md) for transparent, auditable collaboration.

## Quick start

Two modes, two scripts. Pick one:

| Mode | Script | When |
|---|---|---|
| **(A) New project** | `scripts/new-project.sh <name>` | Greenfield — fresh directory, framework pre-installed, ready to code in. |
| **(B) Existing project** | `scripts/install-template.sh <path>` | Adoption — bolt the framework onto a codebase you already have. |

### Option A — New project (greenfield)

```bash
# Clone the template once
git clone https://github.com/rwn34/rwn-multi-cli-skills.git /tmp/rwn-template

# Create a fresh project with the framework installed
cd ~/Code
bash /tmp/rwn-template/scripts/new-project.sh my-project

# Preview first with --dry-run
bash /tmp/rwn-template/scripts/new-project.sh my-project --dry-run
```

This creates `my-project/` with `git init`, stub `README.md` + `.gitignore`,
an initial commit, and the full framework installed on a safety branch. Pick
your stack next (`npm init` / `cargo init` / `go mod init` / etc.).

### Option B — Existing project (adoption)

```bash
# Clone the template
git clone https://github.com/rwn34/rwn-multi-cli-skills.git /tmp/rwn-template

# Run the installer against your existing project
bash /tmp/rwn-template/scripts/install-template.sh /path/to/your/existing/project

# Preview first with --dry-run
bash /tmp/rwn-template/scripts/install-template.sh /path/to/your/project --dry-run
```

The installer:
- Copies framework dirs into your project (`.ai/`, `.claude/`, `.kimi/`, `.kiro/`, `.archive/`, ADR, CI workflow)
- Wipes template-specific state (activity log, handoffs, audit reports)
- Auto-detects your language (Node / Rust / Python / Go / Ruby) and amends the root-file policy accordingly
- Merges your existing `.gitignore`
- Runs the test suites (hooks × 3 CLIs + SSOT drift check) to verify clean install
- Commits on a safety branch so you can roll back easily

See [`scripts/README.md`](./scripts/README.md) for details on both scripts.

### Option C — Node.js installer (pre-release)

**Status: pre-release (v0.0.1).** A new Node.js installer is in development at `tools/multi-cli-install/` that consolidates Options A and B into a single `npx`-installable binary with project inspection, layout reorganization for existing projects, and AI-behavior adaptation. It has been validated against fixture projects only — see [`.ai/known-limitations.md`](./.ai/known-limitations.md) for the full risk assessment. Use Options A or B for now if you want a battle-tested install path.

```bash
# Build locally (not yet published to npm)
cd tools/multi-cli-install
npm install && npm run build

# Use against a target
node bin/multi-cli-install.ts /path/to/project --dry-run    # preview
node bin/multi-cli-install.ts my-new-project --new          # greenfield
```

### After install — wire Kimi's global hooks (one manual step)

Kimi reads hooks from `~/.kimi/config.toml`. Append the generated snippet:

```bash
cat .ai/config-snippets/kimi-hooks.toml >> ~/.kimi/config.toml
```

Restart Kimi. You're done.

## How it works

### Architecture: read-only orchestrator + specialized subagents

Each CLI has an **orchestrator** (default agent) that:
- Reads context, asks clarifying questions, plans the work
- Delegates actual mutations to **specialized subagents**
- Verifies subagent output by reading touched files
- Never writes project source directly (only framework dirs + shared `.ai/`)

**Subagents** are scoped:
- `coder` — writes src/, tests/; runs builds
- `reviewer` — read-only; reports to `.ai/reports/`
- `tester` — writes tests only
- `debugger` — repros bugs, small fixes
- `refactorer` — behavior-preserving restructuring, tests-before-and-after
- `doc-writer` — docs only; never implements features
- `security-auditor` — reports; never patches
- `ui-engineer` — frontend + browser automation
- `e2e-tester` — end-to-end browser flows
- `infra-engineer` — CI, Docker, git operations
- `release-engineer` — version bumps, tags, publishes (highest-risk)
- `data-migrator` — DB schema + reversible migrations

The catalog is the single source of truth: [`.ai/instructions/agent-catalog/principles.md`](./.ai/instructions/agent-catalog/principles.md).

### Write boundaries (who can write where)

| CLI | Can write | Cannot write |
|---|---|---|
| Claude Code | `.claude/**`, `.ai/**`, project source | `.kimi/**`, `.kiro/**` |
| Kimi CLI | `.kimi/**`, `.ai/**`, project source | `.claude/**`, `.kiro/**` |
| Kiro CLI | `.kiro/**`, `.ai/**`, project source | `.claude/**`, `.kimi/**` |

Enforced by pre-write hooks on all three CLIs. Violations are blocked before filesystem writes happen.

### Safety hooks (what they block)

Each CLI has four pre-tool hooks:

1. **Root-file guard** — blocks writes to repo root unless the file is in the ADR-0001 allowlist (e.g., README.md, .gitignore, package.json once amended).
2. **Framework-dir guard** — blocks cross-CLI config edits (above).
3. **Sensitive-file guard** — blocks writes to `.env*`, `*.key`, `*.pem`, `id_rsa*`, `id_ed25519*`, `secrets.*`, `credentials*`, `.aws/`, `.ssh/`.
4. **Destructive-cmd guard** — blocks `rm -rf /`, `git push --force`, `git reset --hard`, `DROP DATABASE`, `TRUNCATE TABLE`.

All four are verified by regression test scripts: [`.claude/hooks/test_hooks.sh`](./.claude/hooks/test_hooks.sh), `.kimi/hooks/test_hooks.sh`, `.kiro/hooks/test_hooks.sh`. These run on every PR via [`.github/workflows/framework-check.yml`](./.github/workflows/framework-check.yml).

### Handoff protocol (cross-CLI work queueing)

When Claude (or any CLI) needs another CLI to execute something in its own territory, it writes a paste-ready instruction file to `.ai/handoffs/to-<recipient>/open/YYYYMMDDHHMM-<slug>.md`. The recipient reads it in their next session, executes, moves it to `done/`. Full protocol in [`.ai/handoffs/README.md`](./.ai/handoffs/README.md).

Example flow:

```
You → Claude: "Add authentication endpoint"
Claude (orchestrator): plans, writes docs/specs/auth.md
Claude dispatches handoff → Kiro: "Implement per docs/specs/auth.md"
(next Kiro session)
Kiro: reads handoff, dispatches to its coder + tester subagents
Kiro logs completion to .ai/activity/log.md
You → Claude: "Verify Kiro's work"
Claude: reads diff, approves or requests changes
Claude (via infra-engineer): commits + pushes
```

### SSOT + drift check (keeping the three CLIs honest)

Shared instruction content (orchestrator rules, agent catalog, coding guidelines) lives at `.ai/instructions/<name>/principles.md`. Each CLI has a replica in its native steering format (`.claude/skills/`, `.kimi/steering/`, `.kiro/steering/`).

[`.ai/tools/check-ssot-drift.sh`](./.ai/tools/check-ssot-drift.sh) diffs each source against its replicas. It runs in CI on every PR. If someone edits a replica without updating the SSOT, CI fails.

### Handoff numbering

Filenames use UTC timestamps: `YYYYMMDDHHMM-slug.md` (e.g., `202604201530-add-auth-endpoint.md`). This avoids the race condition that `NNN-slug.md` creates when two CLIs dispatch handoffs in the same second. Legacy `NNN-slug.md` handoffs are grandfathered.

## Code knowledge graphs (optional)

Each CLI has its own optional local code-knowledge-graph tool — **CodeGraph** (Claude), **KimiGraph** (Kimi), **KiroGraph** (Kiro). All three share the same architecture (tree-sitter parser → SQLite index → MCP server) and drop typical exploration from 10+ file reads to a single graph query. All three are **optional** — the framework works fine without them.

| CLI | Tool | Install command |
|---|---|---|
| Claude | CodeGraph | `npx @colbymchenry/codegraph` |
| Kimi | KimiGraph | `npm install -g rwn-kimigraph` then `kimigraph install` |
| Kiro | KiroGraph | source-build from `https://github.com/davide-desio-eleva/kirograph` (no npm release yet — see plan for steps) |

Write boundaries: each CLI can only write to its own graph dir (`.codegraph/`, `.kimigraph/`, `.kirograph/`); cross-graph writes are blocked by the existing pretool hook. At adoption these are structural-only (no embeddings); semantic similarity can be enabled later via each tool's own opt-in config.

See [.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md](./.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md) for the full rationale and per-tool tradeoffs.

## Directory map

```
.                                     repo root (policy: strict, see ADR-0001)
│
├── .ai/                              SHARED multi-CLI framework state
│   ├── instructions/                 Single source of truth (SSOT) for cross-CLI rules
│   │   ├── orchestrator-pattern/     Orchestrator + subagent architecture rules
│   │   ├── agent-catalog/            13-agent roster with scopes
│   │   └── karpathy-guidelines/      Coding discipline rules
│   ├── handoffs/                     Cross-CLI work queue
│   │   ├── template.md               Paste-ready handoff shape
│   │   ├── to-claude/{open,done}/    Work queued for Claude
│   │   ├── to-kimi/{open,done}/      Work queued for Kimi
│   │   └── to-kiro/{open,done}/      Work queued for Kiro
│   ├── activity/log.md               Chronological audit log (newest first)
│   ├── reports/                      Audit / review / security reports
│   ├── tools/                        Framework tooling (drift checker, etc.)
│   ├── tests/                        Framework regression protocols
│   ├── config-snippets/              Paste-ready config snippets for CLI setup
│   ├── known-limitations.md          Standing registry of platform quirks
│   └── sync.md                       SSOT replica regeneration commands
│
├── .claude/                          Claude Code config (owned by Claude only)
│   ├── agents/                       13-agent subagent definitions
│   ├── skills/                       Claude skills (SSOT replicas)
│   ├── hooks/                        Pre-tool safety hooks
│   └── settings.json                 Hook wiring + permissions
│
├── .kimi/                            Kimi CLI config (owned by Kimi only)
│   ├── agents/                       13-agent subagent definitions
│   ├── steering/                     Always-loaded instructions
│   ├── skills/                       On-demand skills
│   ├── resource/                     On-demand resources
│   └── hooks/                        Pre-tool safety hooks
│
├── .kiro/                            Kiro CLI config (owned by Kiro only)
│   ├── agents/                       13-agent subagent definitions
│   ├── steering/                     Always-loaded instructions
│   ├── skills/                       On-demand skills
│   └── hooks/                        Pre-tool safety hooks
│
├── .archive/                         Cold storage for old reports / handoffs
├── .github/workflows/                CI workflows (framework self-test)
│
├── docs/                             PROJECT docs (your code lives here + below)
│   └── architecture/                 ADRs — authoritative decisions
│       └── 0001-root-file-exceptions.md   Root file policy (all 3 CLIs reference this)
│
├── scripts/                          Project scripts
│   └── install-template.sh           Installs this framework into another project
│
├── src/                              YOUR source code (currently empty in the template)
├── tests/                            YOUR tests
├── infra/                            YOUR infrastructure-as-code
├── migrations/                       YOUR DB migrations
├── tools/                            YOUR dev tooling
│   └── multi-cli-install/            framework's own Node.js installer (v0.0.1, pre-release)
├── config/                           YOUR runtime config (non-secret)
├── assets/                           YOUR static assets
│
├── README.md                         this file
├── CLAUDE.md                         Claude's always-loaded contract
├── AGENTS.md                         Multi-CLI contract pointer
├── LICENSE                           MIT
└── .gitignore
```

## Benefits at a glance

- **Coherent multi-CLI workflow** — no more re-explaining context to a different CLI mid-project.
- **Safety by default** — hooks block the most common AI mistakes (root-file pollution, secret leaks, destructive commands) before they happen.
- **Single source of truth** — edit policies in one place, they propagate to all three CLIs with drift detection.
- **Audit trail** — every substantive action gets an activity-log entry. Scroll back to see what changed, when, and why.
- **Low ceremony for small work** — activity log + direct edits for tiny changes.
- **Structured ceremony for big work** — handoff protocol for cross-CLI coordination.
- **Budget-aware** — scoped subagents let you route expensive reasoning (Opus via Kiro) only where it matters, use cheaper CLIs for bulk work.
- **Shippable install** — one script, one command, ~10 minutes to adopt into an existing project.
- **CI self-tests** — every push runs 53 hook regression tests + SSOT drift check. Regressions fail CI, not production.

## Confidence & limitations

**Current assessment (2026-04-27):** ~80% confidence for real-project work via the bash install path, ~50% via the new Node.js installer (fixture-only validated, see [`.ai/known-limitations.md`](./.ai/known-limitations.md)). ~55% for production-grade systems regardless of install path.

**Honest weaknesses** (tracked in [`.ai/known-limitations.md`](./.ai/known-limitations.md)):

1. **Kiro runtime doesn't fire hooks for spawned subagents** (platform bug, upstream-pending). Mitigated by prompt-level SAFETY RULES in every Kiro subagent config — soft enforcement, empirically tested to refuse `evil.txt` writes, but not a hard guarantee under adversarial context.
2. **Kimi hooks require manual install step** (paste snippet to `~/.kimi/config.toml`) — not auto-wired because it's user-scope config.
3. **Concurrency is characterized but not tested.** Three CLIs writing to `.ai/activity/log.md` simultaneously has known race potential; a manual test protocol exists at [`.ai/tests/concurrency-test-protocol.md`](./.ai/tests/concurrency-test-protocol.md) but hasn't been run.
4. **No RBAC** — any user running any CLI has full framework power. Solo / small team only.
5. **No observability / metrics** — activity log is the only audit mechanism; editable by convention, not enforcement.
6. **Handoff protocol is heavyweight for quick fixes** — 30-line change requires a file, a move, a log entry. Fine for real work; ceremony-heavy for typos.
7. **Node.js installer is pre-release.** `tools/multi-cli-install/` v0.0.1 is fixture-only validated — real-project validation deferred per [`.ai/known-limitations.md`](./.ai/known-limitations.md). Use bash scripts for canonical install until v1.0.0.

For a full list and the mitigation plan, read [`.ai/known-limitations.md`](./.ai/known-limitations.md).

## Root file policy

Root is strict. The authoritative allowlist lives in [`docs/architecture/0001-root-file-exceptions.md`](./docs/architecture/0001-root-file-exceptions.md) — new root files require an ADR amendment before creation. The `.claude/hooks/pretool-write-edit.sh` hook and the Kimi/Kiro equivalents enforce this at the tool layer.

## Contributing

This template is actively maintained. Expect iteration, expect some things to move around. When contributing:

1. Read [CLAUDE.md](./CLAUDE.md) — the multi-CLI contract for AI agents.
2. Write code in `src/`, tests in `tests/`, docs in `docs/`.
3. Never edit another CLI's config directory (hooks will block you anyway).
4. Log substantive changes to `.ai/activity/log.md` — one entry per action.
5. Submit a PR. CI will run the framework self-tests automatically.

## Further reading

- [`CLAUDE.md`](./CLAUDE.md) — AI contract (the rules every AI CLI must follow)
- [`AGENTS.md`](./AGENTS.md) — Multi-CLI coordination pointer
- [`docs/architecture/0001-root-file-exceptions.md`](./docs/architecture/0001-root-file-exceptions.md) — Root-file policy (authoritative ADR)
- [`.ai/README.md`](./.ai/README.md) — SSOT layout explanation
- [`.ai/known-limitations.md`](./.ai/known-limitations.md) — What's weak (updated every cycle)
- [`.ai/sync.md`](./.ai/sync.md) — How to regenerate SSOT replicas
- [`.ai/instructions/orchestrator-pattern/principles.md`](./.ai/instructions/orchestrator-pattern/principles.md) — Delegation architecture
- [`.ai/instructions/agent-catalog/principles.md`](./.ai/instructions/agent-catalog/principles.md) — 13-agent roster
- [`scripts/README.md`](./scripts/README.md) — Install script details
- [`.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`](./.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md) — Code-graph adoption plan (CodeGraph/KimiGraph/KiroGraph)

## License

MIT — see [LICENSE](./LICENSE).

## Acknowledgements

Behavioral guidelines adapted from [Andrej Karpathy's observations on LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876), via [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills).
