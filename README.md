# rwn multi-CLI AI template

**A coordination framework that lets Claude Code, Kimi CLI, and Kiro CLI work on the same project in parallel — safely, with shared state and enforced write boundaries.**

> Status: pre-1.0 (last refreshed 2026-04-27). Solid for solo / small-team projects. Bash install path is battle-tested; the new Node.js installer at `tools/multi-cli-install/` is pre-release with fixture-only validation. Not yet battle-tested in production. See [Confidence & limitations](#confidence--limitations) for honest caveats.

---

## What is this?

A **template** — a starting point you drop into a project — that gives you:

1. **Three AI CLIs coordinating on shared state.** Claude Code (architect/orchestrator), Kimi CLI (high-throughput workhorse), Kiro CLI (premium reasoning via Opus 4.6). They read the same activity log, queue work for each other via file-based handoffs, share a single source of truth for agent definitions. A fourth CLI, OpenCode, participates as a narrow-scope ops/release operator (see `docs/architecture/0002-cli-role-topology.md`, amended 2026-07-09: OpenCode replaces Crush).

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
- **Diligence** — [entry-per-file activity spool](./.ai/activity/entries/) (one file per entry — concurrent writes can't clobber, ADR-0010) + [known-limitations doc](./.ai/known-limitations.md) for transparent, auditable collaboration.

## Prerequisites

Before running any install path, verify these:

- **Git installed.** `git --version` should print a version. Fresh installs of git default new repos to `main` since 2020 — keep that in mind for the Phase 6 follow-up below.
- **Git user configured globally.** The installer makes a commit; without global identity, git aborts with `fatal: unable to auto-detect email address`. Run once:
  ```
  git config --global user.email "you@example.com"
  git config --global user.name  "Your Name"
  ```
- **Bash available.** Linux/macOS: any system bash works. **Windows: prefer Git Bash** (`C:\Program Files\Git\bin\bash.exe`) over WSL bash. The two use different path conventions (Git Bash: `/c/Users/...`, WSL: `/mnt/c/Users/...`) and the installer's path resolution assumes Git Bash style on Windows.
- **Clean working tree** (Option B / adoption only). The installer refuses to run if `git status` is dirty. Commit or `git stash` first.

## Quick start

Three install paths. The bash scripts (A, B) are battle-tested. The Node.js installer (C) is pre-release and adds project inspection + layout reorganization.

### Windows users — read this first

- Use the **Git Bash** terminal (Start menu → "Git Bash") for the simplest experience. Every bash example below works there as written.
- **Do NOT paste bash multi-line blocks into PowerShell.** Backslash continuations and `#` comments don't translate; lines get parsed independently and you can end up running an unintended `git init` in the wrong directory. If you must use PowerShell, use the **Windows PowerShell** variants provided under each option.
- **`bash` on a Windows PATH may resolve to WSL bash**, not Git Bash. WSL bash uses `/mnt/c/Users/...`; if you hit "No such file or directory" with `/c/Users/...` paths even though `Test-Path` returns `True`, that's the cause. Either launch the Git Bash terminal directly, or invoke its binary explicitly from PowerShell:
  ```powershell
  & "C:\Program Files\Git\bin\bash.exe" "<script-path>" "<args>"
  ```
- **Default branch is `main`** on freshly-initialized repos. If a follow-up step says `git checkout main` and your branch is different, substitute.

| Mode | Path | When |
|---|---|---|
| **(A) New project** | `scripts/new-project.sh <name>` | Greenfield — fresh directory, framework pre-installed, ready to code in. Bash, proven. |
| **(B) Existing project** | `scripts/install-template.sh <path>` | Adoption — bolt the framework onto a codebase you already have. Bash, proven. |
| **(C) Node.js installer (pre-release)** | `node tools/multi-cli-install/bin/multi-cli-install.ts <target>` | Greenfield OR adoption with optional layout reorganization. v0.0.1, fixture-only validated. |

### Option A — New project (greenfield)

**Linux / macOS / Git Bash:**

```bash
# Clone the template once
git clone https://github.com/rwn34/rwn-multi-cli-skills.git ~/rwn-template

# Create a fresh project with the framework installed
cd ~/Code
bash ~/rwn-template/scripts/new-project.sh my-project

# Preview first with --dry-run
bash ~/rwn-template/scripts/new-project.sh my-project --dry-run
```

**Windows PowerShell:**

```powershell
git clone https://github.com/rwn34/rwn-multi-cli-skills.git C:\Users\<you>\rwn-template
cd C:\Users\<you>\Code
& "C:\Program Files\Git\bin\bash.exe" "C:\Users\<you>\rwn-template\scripts\new-project.sh" "my-project"
# Preview first:
& "C:\Program Files\Git\bin\bash.exe" "C:\Users\<you>\rwn-template\scripts\new-project.sh" "my-project" "--dry-run"
```

This creates `my-project/` with `git init`, stub `README.md` + `.gitignore`,
an initial commit, and the full framework installed on a safety branch. Pick
your stack next (`npm init` / `cargo init` / `go mod init` / etc.).

### Option B — Existing project (adoption)

**Linux / macOS / Git Bash:**

```bash
# Clone the template
git clone https://github.com/rwn34/rwn-multi-cli-skills.git ~/rwn-template

# Make sure your target's working tree is clean first
cd /path/to/your/existing/project && git status

# Run the installer against your existing project
bash ~/rwn-template/scripts/install-template.sh /path/to/your/existing/project

# Preview first with --dry-run
bash ~/rwn-template/scripts/install-template.sh /path/to/your/existing/project --dry-run
```

**Windows PowerShell:**

```powershell
git clone https://github.com/rwn34/rwn-multi-cli-skills.git C:\Users\<you>\rwn-template
cd C:\path\to\your\existing\project
git status   # must be clean; if not, commit or stash first
& "C:\Program Files\Git\bin\bash.exe" "C:\Users\<you>\rwn-template\scripts\install-template.sh" "."
# Preview first:
& "C:\Program Files\Git\bin\bash.exe" "C:\Users\<you>\rwn-template\scripts\install-template.sh" "." "--dry-run"
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

# Five invocation modes:

# 1. Inspect only — read-only, shows what the binary detects (always safe)
node bin/multi-cli-install.ts /path/to/project --inspect-only

# 2. Dry-run — read-only, shows the full plan (framework copy + reorganize moves)
node bin/multi-cli-install.ts /path/to/project --dry-run

# 3. Greenfield — create a new project with the framework
node bin/multi-cli-install.ts my-new-project --new

# 4. Existing-project install — copies framework + reorganizes layout
node bin/multi-cli-install.ts /path/to/existing/project

# 5. Refresh context — regenerates .ai/project-context.md only
node bin/multi-cli-install.ts /path/to/project --refresh-context
```

**First-run safety:** Before mode 4 against a real codebase, run mode 1 then mode 2 to preview. The installer refuses to write if the target's git tree is dirty, so you can always `git reset --hard` after a failed run.

### Which option to use

| Situation | Recommended option |
|---|---|
| New project (greenfield) | **A** (proven) — or C `--new` if you want the newer pipeline |
| Existing project, framework adoption only | **B** (proven, canonical) |
| Existing project, want layout reorganized into the framework's canonical structure | **C** — but always run `--inspect-only` then `--dry-run` first; only `npm test` afterwards |
| Just exploring what the installer thinks of your repo | **C** `--inspect-only` (read-only, always safe) |

The bash path will stay canonical until the Node.js installer reaches v1.0.0 with at least one real-project validation. See [`.ai/known-limitations.md`](./.ai/known-limitations.md).

### After install — merge the install branch

The installer leaves you on the `ai-template-install` branch with one commit. Merge it into your default branch (`main`):

```bash
# Pick whichever is your default branch
git checkout main
git merge --no-ff ai-template-install
```

### After install — wire Kimi's global hooks (one manual step)

Kimi reads hooks from `~/.kimi/config.toml` (user-global, not per-project). Append the generated snippet.

**Linux / macOS / Git Bash:**

```bash
mkdir -p ~/.kimi
cat .ai/config-snippets/kimi-hooks.toml >> ~/.kimi/config.toml
```

**Windows PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.kimi" | Out-Null
Get-Content ".\.ai\config-snippets\kimi-hooks.toml" | Add-Content "$HOME\.kimi\config.toml"
```

Restart Kimi. You're done.

## Troubleshooting

Common errors and the fastest fix.

### `fatal: destination path '.../rwn-template' already exists`

Leftover from a prior attempt. Either delete the dir or clone elsewhere.

```bash
rm -rf ~/rwn-template                                    # Linux/macOS/Git Bash
```
```powershell
Remove-Item C:\Users\<you>\rwn-template -Recurse -Force  # PowerShell
```

### `fatal: unable to auto-detect email address`

Git's global identity isn't set; the installer's commit step fails. Run the two `git config --global` commands from [Prerequisites](#prerequisites) and re-run.

### `/bin/bash: <path>: No such file or directory` (but `Test-Path` returns `True`)

You're invoking WSL bash, which doesn't see Windows paths the same way. Either launch the **Git Bash terminal** directly, or call its binary explicitly:

```powershell
& "C:\Program Files\Git\bin\bash.exe" "<your-script-path>" "<args>"
```

### `error: pathspec 'master' did not match any file(s) known to git`

Modern git defaults to `main`. Substitute: `git checkout main`. (Confirm with `git branch --show-current`.)

### PowerShell ate my multi-line command

Backslash continuations and `#`-comments inside a bash block don't survive PowerShell parsing — lines run independently and an accidental `git init` can pollute the wrong directory. Run each command on its own line, or save the block to `install.ps1` and execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### `Target working tree is dirty. Commit or stash first.`

The adoption installer refuses to run on an uncommitted tree. Run `git status`, then `git commit` or `git stash` your changes and retry.

### `Permission denied` when running `scripts/install-template.sh`

Linux/macOS only — the file lost its executable bit. Either invoke via `bash`, or restore the bit:

```bash
chmod +x scripts/install-template.sh
```

## Upgrading an existing framework install

### Status

A proper `--upgrade` flag is in design (see `.ai/research/framework-upgrade-mode-plan.md` once that lands). Until it ships, the recipe below is the documented manual cherry-pick procedure — not automated, not yet tested across multiple adopter projects.

### When you need this

The installers (`scripts/install-template.sh`, `npx @rwn34/multi-cli-install`) are first-install-only. Cherry-pick a newer release into an already-adopted project when:

- A new release added an SSOT your installed framework predates (e.g., `self-grep-verify` landed in `v0.0.2-pre.5`).
- You want the drift-checker oversight fix from pre.5 — it now validates **18 replicas vs 12** (the prior version silently skipped `code-graphs`).
- You want the updated reference text in `AGENTS.md` / `CLAUDE.md` that points at the new framework rules.

### The recipe (Linux / macOS / Git Bash)

**Preconditions.** Clean git working tree on your project (`git status` empty), and pick a target release — `v0.0.2-pre.5` is the recommended floor since it includes the drift-checker fix.

**1. Download and extract the release tarball.**

```bash
cd /tmp
curl -L -o multi-cli-install.tar.gz \
  https://github.com/rwn34/rwn-multi-cli-skills/releases/download/v0.0.2-pre.5/multi-cli-install-v0.0.2-pre.5.tar.gz
tar -xzf multi-cli-install.tar.gz
# Contents land at /tmp/package/ — npm tarball convention.
# The framework template lives at /tmp/package/assets/.
```

**2. Copy new SSOT additions** (safe — these are new files, no merge conflict possible):

```bash
# self-grep-verify quartet (1 SSOT + 3 CLI replicas) added in pre.5
cp -r /tmp/package/assets/.ai/instructions/self-grep-verify <PROJECT>/.ai/instructions/
cp -r /tmp/package/assets/.claude/skills/self-grep-verify   <PROJECT>/.claude/skills/
cp    /tmp/package/assets/.kimi/steering/self-grep-verify.md <PROJECT>/.kimi/steering/
cp    /tmp/package/assets/.kiro/steering/self-grep-verify.md <PROJECT>/.kiro/steering/
```

For any other new SSOT in future releases, follow the same pattern: copy `assets/.ai/instructions/<name>/`, `assets/.claude/skills/<name>/`, `assets/.kimi/steering/<name>.md`, `assets/.kiro/steering/<name>.md`.

**3. Merge the 4 reference files manually** — these may contain your customizations, so diff and port:

```bash
diff -u <PROJECT>/.ai/sync.md           /tmp/package/assets/.ai/sync.md
diff -u <PROJECT>/AGENTS.md             /tmp/package/assets/AGENTS.md
diff -u <PROJECT>/CLAUDE.md             /tmp/package/assets/CLAUDE.md
diff -u <PROJECT>/.ai/tools/check-ssot-drift.sh /tmp/package/assets/.ai/tools/check-ssot-drift.sh
```

For each, eyeball the diff and port the additions into your project file. Specifically:

- **`.ai/sync.md`** — port the new rows + the new `cp` blocks for `self-grep-verify`.
- **`AGENTS.md`**, **`CLAUDE.md`** — port the new SSOT-pointer sections. If you've heavily customized these, just port the pointer paragraphs and leave your edits intact.
- **`.ai/tools/check-ssot-drift.sh`** — add these 6 lines verbatim (3 for `code-graphs` if your installed version was missing it, plus 3 for the new `self-grep-verify`):

```bash
# code-graphs / principles
check_pair ".ai/instructions/code-graphs/principles.md"         ".claude/skills/code-graphs/SKILL.md"            yes
check_pair ".ai/instructions/code-graphs/principles.md"         ".kimi/steering/code-graphs.md"                  no
check_pair ".ai/instructions/code-graphs/principles.md"         ".kiro/steering/code-graphs.md"                  no
# self-grep-verify / principles
check_pair ".ai/instructions/self-grep-verify/principles.md"    ".claude/skills/self-grep-verify/SKILL.md"       yes
check_pair ".ai/instructions/self-grep-verify/principles.md"    ".kimi/steering/self-grep-verify.md"             no
check_pair ".ai/instructions/self-grep-verify/principles.md"    ".kiro/steering/self-grep-verify.md"             no
```

**4. Verify the upgrade.**

```bash
cd <PROJECT>
bash .ai/tools/check-ssot-drift.sh   # expect "Checked: 18 replicas, Drift: 0"
bash .claude/hooks/test_hooks.sh     # expect 24/24 PASS
bash .kimi/hooks/test_hooks.sh       # expect 29/29 PASS
bash .kiro/hooks/test_hooks.sh       # expect 25/25 PASS
```

**5. Commit.**

```bash
git checkout -b framework-upgrade-pre5
git add .
git commit -m "chore(framework): upgrade to multi-cli-skills v0.0.2-pre.5"
```

### Windows PowerShell variant

```powershell
# 1. Download and extract
Set-Location $env:TEMP
Invoke-WebRequest `
  -Uri "https://github.com/rwn34/rwn-multi-cli-skills/releases/download/v0.0.2-pre.5/multi-cli-install-v0.0.2-pre.5.tar.gz" `
  -OutFile multi-cli-install.tar.gz
# tar ships with Windows 10+; if missing, use Expand-Archive on a .zip release instead.
tar -xzf multi-cli-install.tar.gz
# Tarball extracts to $env:TEMP\package\ ; framework template at $env:TEMP\package\assets\

# 2. Copy new SSOT additions
Copy-Item "$env:TEMP\package\assets\.ai\instructions\self-grep-verify" `
          "<PROJECT>\.ai\instructions\" -Recurse
Copy-Item "$env:TEMP\package\assets\.claude\skills\self-grep-verify" `
          "<PROJECT>\.claude\skills\" -Recurse
Copy-Item "$env:TEMP\package\assets\.kimi\steering\self-grep-verify.md" `
          "<PROJECT>\.kimi\steering\"
Copy-Item "$env:TEMP\package\assets\.kiro\steering\self-grep-verify.md" `
          "<PROJECT>\.kiro\steering\"

# 3. Diff the 4 reference files (PowerShell's Compare-Object, or use git diff --no-index)
git diff --no-index "<PROJECT>\AGENTS.md"             "$env:TEMP\package\assets\AGENTS.md"
git diff --no-index "<PROJECT>\CLAUDE.md"             "$env:TEMP\package\assets\CLAUDE.md"
git diff --no-index "<PROJECT>\.ai\sync.md"           "$env:TEMP\package\assets\.ai\sync.md"
git diff --no-index "<PROJECT>\.ai\tools\check-ssot-drift.sh" `
                    "$env:TEMP\package\assets\.ai\tools\check-ssot-drift.sh"
# Port additions into your project files by hand. The 6 check_pair lines from
# the bash recipe above paste verbatim into check-ssot-drift.sh.

# 4. Verify (run via Git Bash since the test scripts are bash)
& "C:\Program Files\Git\bin\bash.exe" "<PROJECT>\.ai\tools\check-ssot-drift.sh"
& "C:\Program Files\Git\bin\bash.exe" "<PROJECT>\.claude\hooks\test_hooks.sh"
& "C:\Program Files\Git\bin\bash.exe" "<PROJECT>\.kimi\hooks\test_hooks.sh"
& "C:\Program Files\Git\bin\bash.exe" "<PROJECT>\.kiro\hooks\test_hooks.sh"

# 5. Commit
Set-Location "<PROJECT>"
git checkout -b framework-upgrade-pre5
git add .
git commit -m "chore(framework): upgrade to multi-cli-skills v0.0.2-pre.5"
```

### Caveats

- **Assumes minimal customization of framework files.** If you've forked the contents of `AGENTS.md`, `CLAUDE.md`, `.ai/sync.md`, or any SSOT, you'll need a three-way merge (your version vs. old upstream vs. new upstream) — `diff -u` only shows you-vs-new, which collapses your edits and the upstream additions into one combined diff.
- **Runtime state is never touched.** `.ai/activity/log.md`, `.ai/handoffs/`, `.ai/reports/`, `.ai/research/` are yours — the recipe deliberately doesn't `cp` over them.
- **No version marker yet.** After upgrade, your installed framework version is unrecorded. Phase A of the upgrade-mode plan will add `.ai/.framework-version` to fix this; until then, track your floor release in your project's README.

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
| OpenCode | `.ai/**` (activity log, reports, handoffs) | Everything else — no project-source writes, no other CLI dirs (harness-level permissions + `.opencode/plugin/` framework-guard) |

Enforced by pre-write hooks on all three CLIs. Violations are blocked before filesystem writes happen. OpenCode's boundaries are enforced mechanically too — harness-level `allow`/`ask`/`deny` permissions plus a JS framework-guard plugin (see `.ai/known-limitations.md` for history).

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

## Code knowledge graph (optional)

Claude Code has an optional local code-knowledge-graph tool — **CodeGraph** (tree-sitter parser → SQLite index → MCP server). It drops typical exploration from 10+ file reads to a single graph query. It is **optional** — the framework works fine without it.

| CLI | Tool | Install command |
|---|---|---|
| Claude | CodeGraph | `npx @colbymchenry/codegraph` |

KimiGraph (Kimi) and KiroGraph (Kiro) were removed 2026-07-09 by owner directive — see the ADR-0003 amendment in [`docs/architecture/0003-code-graph-rationalization.md`](./docs/architecture/0003-code-graph-rationalization.md). CodeGraph is the only graph in the framework. Write boundary: only Claude writes `.codegraph/`; the pretool hook blocks other writes. Structural-only at adoption (no embeddings).

The canonical usage rules live in [`.ai/instructions/code-graphs/principles.md`](./.ai/instructions/code-graphs/principles.md) — AI agents in this project follow that SSOT automatically when the graph is active, preferring graph queries over file reads for structural questions.

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
│   ├── activity/entries/             Chronological audit spool — one file per entry (log.md is a generated view, ADR-0010)
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
3. **Concurrency at the coordination plane is partly convention-based.** The activity-log write race is closed structurally (ADR-0010, 2026-07-13): each entry is its own file in `.ai/activity/entries/`, so concurrent writers never share a write — demonstrated with 40/40 same-second writers surviving intact. Handoff-queue numbering and SSOT-replica regeneration remain convention-guarded; the manual protocol at [`.ai/tests/concurrency-test-protocol.md`](./.ai/tests/concurrency-test-protocol.md) covers the residual scenarios.
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
- [`.ai/instructions/code-graphs/principles.md`](./.ai/instructions/code-graphs/principles.md) — Code-graphs SSOT (cross-CLI graph principles)
- [`scripts/README.md`](./scripts/README.md) — Install script details
- [`.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md`](./.ai/research/codegraph-kirograph-kimigraph-adoption-plan.md) — Code-graph adoption plan (historical — KimiGraph/KiroGraph removed 2026-07-09, CodeGraph only)

## License

MIT — see [LICENSE](./LICENSE).

## Acknowledgements

Behavioral guidelines adapted from [Andrej Karpathy's observations on LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876), via [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills).
