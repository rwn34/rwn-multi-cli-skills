# scripts/

Operational scripts for this template. Per ADR-0001, `scripts/` is a
permitted project directory.

> **Note:** A new Node.js installer at `tools/multi-cli-install/` is under
> development that will eventually consolidate `new-project.sh` and
> `install-template.sh` into a single `npx`-installable command. The new
> installer is currently pre-release (v0.0.1, fixture-only validated — see
> [`.ai/known-limitations.md`](../.ai/known-limitations.md)). The bash scripts
> in this directory remain the canonical install path until the Node.js
> installer reaches v1.0.0 with real-project validation.

## Two modes, two scripts

| Script | When to use |
|---|---|
| `new-project.sh <name>` | Greenfield — create a fresh project directory with the framework pre-installed, ready to start coding in. |
| `install-template.sh <path>` | Adoption — bolt the framework onto an existing project you already have code in. |

Pick one based on whether you're starting from scratch or bringing an
existing codebase.

---

## `new-project.sh`

Creates `<name>/`, initializes git, writes stub `README.md` + `.gitignore`,
commits an initial scaffold, then invokes `install-template.sh` against the
new directory. Minimal — no stack detection, no language prompts, no fancy
scaffolding. You pick your stack next by running `npm init` / `cargo init` /
`python -m venv` / etc.

### Usage

```bash
# Dry-run first:
bash scripts/new-project.sh my-project --dry-run

# Real run:
bash scripts/new-project.sh my-project
cd my-project
# add your stack: npm init / cargo init / go mod init / etc.
```

Name must be lowercase alphanumeric + hyphens. Directory must not already
exist.

### Flags

- `--dry-run` — print planned actions, touch nothing.
- `--help` / `-h` — usage.

---

## `install-template.sh`

Copies the multi-CLI AI coordination framework from this template into an
existing project and adapts it (merges `.gitignore`, detects language, amends
the root-file ADR, patches root-guard hooks, resets activity log + handoffs,
runs the framework test suites, commits on a dedicated install branch).

### Usage

```bash
# Dry-run first (prints what would happen, writes nothing):
bash scripts/install-template.sh /path/to/your/project --dry-run

# Real run:
bash scripts/install-template.sh /path/to/your/project
```

Target must be a clean git repo. The script creates branch
`ai-template-install`, makes one commit, and leaves Phase 6 (merge to main)
as a printed follow-up.

### Flags

- `--dry-run` — print planned actions, touch nothing.
- `--help` / `-h` — usage.

### Rollback

```bash
cd /path/to/your/project
git checkout main
git branch -D ai-template-install
rm .ai-install-rollback-point.txt
```

See the script's `--help` for a full phase-by-phase description.

---

## Requirements (both scripts)

Bash, git, sed, awk, find, diff. No jq, no python. Tested on Git Bash
(Windows) + Linux.
