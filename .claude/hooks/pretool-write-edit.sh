#!/bin/bash
# PreToolUse hook — matcher: Write|Edit
# Blocks writes that violate (1) framework-dir rule, (2) sensitive-file rule, (3) root-file policy.
# Reads tool call JSON from stdin; exit 2 + stderr to block with a reason.

# Extract file_path + agent_type from the tool-call JSON on stdin.
# agent_type is present in hook input for SUBAGENT tool calls; absent/empty on the main thread.
#
# CRITICAL (fail-CLOSED): extraction MUST NOT depend on python. In the live Claude
# hook runtime python3 can resolve to a Windows Store alias stub that prints nothing
# and exits 0 — a `|| python` chain keyed on exit status never fires, path comes back
# empty, and the old `[ -z "$path" ] && exit 0` made every rule a no-op (fail-open).
# So: python is only an OPTIONAL first attempt (fast, handles JSON escapes); the real
# extractor is a pure-bash/sed fallback that runs whenever the python result is EMPTY
# (not merely when it exits non-zero). jq is not reliably installed on Windows/Git Bash.
input=$(cat)

# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$input" | tr -d '[:space:]')" ]; then
    exit 0
fi

path=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$path" ] && path=$(printf '%s' "$input" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$path" ] && path=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

agent_type=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_type','') or '')" 2>/dev/null)
[ -z "$agent_type" ] && agent_type=$(printf '%s' "$input" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_type','') or '')" 2>/dev/null)
[ -z "$agent_type" ] && agent_type=$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# agent_type may legitimately be absent (main thread) — an empty value here is treated
# as MAIN-THREAD below (most restrictive path, Rule 2.5). No fail-open risk.

# stdin was non-empty but no file_path parsed. A Write|Edit call always carries
# file_path, so an empty result means the parse failed — refuse to fail open.
if [ -z "$path" ]; then
    echo "BLOCKED by hook: could not parse tool input (no file_path found) — refusing to fail open." >&2
    exit 2
fi

# Normalize absolute path → relative if under project root
project_root=$(pwd)
# Handle Windows-style paths as well as POSIX
# Strip trailing slash from project_root if present
project_root="${project_root%/}"
if [ "${path:0:${#project_root}}" = "$project_root" ]; then
    rel="${path:${#project_root}}"
    rel="${rel#/}"
else
    rel="$path"
fi
# Also handle backslash-style paths (Windows)
rel=$(echo "$rel" | tr '\\' '/')

block() {
    echo "BLOCKED by hook: $1" >&2
    exit 2
}

# Rule 1 — framework dirs for other CLIs. Hard block, no exceptions.
case "$rel" in
    .kimi|.kimi/*)
        block ".kimi/ is Kimi CLI's territory. Claude never writes there. Use .ai/handoffs/to-kimi/open/YYYYMMDDHHMM-slug.md to request the change." ;;
    .kiro|.kiro/*)
        block ".kiro/ is Kiro CLI's territory. Claude never writes there. Use .ai/handoffs/to-kiro/open/YYYYMMDDHHMM-slug.md to request the change." ;;
    # TOMBSTONE (2026-07-09): KimiGraph/KiroGraph removed entirely per ADR-0003
    # amendment (owner directive). Blocks retained against accidental recreation
    # of the dirs — nothing should ever write here again.
    .kimigraph|.kimigraph/*)
        block ".kimigraph/ was KimiGraph's dir — tool REMOVED 2026-07-09 (ADR-0003 amendment). Nothing writes here anymore." ;;
    .kirograph|.kirograph/*)
        block ".kirograph/ was KiroGraph's dir — tool REMOVED 2026-07-09 (ADR-0003 amendment). Nothing writes here anymore." ;;
esac

# Rule 2 — sensitive-file patterns. Block even for orchestrator; user must write manually.
case "$rel" in
    .env|.env.*|*/\.env|*/\.env.*)
        block "Sensitive file pattern (.env*). Do not write secrets from an agent. Ask the user to edit this manually." ;;
    *.key|*.pem|*.p12|*.pfx|*/\.key|*/\.pem|*/*.p12|*/*.pfx)
        block "Sensitive file pattern (*.key, *.pem, *.p12, *.pfx). Do not write cryptographic material from an agent. Ask the user to edit manually." ;;
    id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|*/id_rsa*|*/id_ed25519*)
        block "SSH private key pattern. Do not write SSH keys from an agent. Ask the user to edit manually." ;;
    .aws|.aws/*|*/\.aws|*/\.aws/*)
        block "AWS credentials directory (.aws/). Do not write AWS credentials from an agent. Ask the user to edit manually." ;;
    .ssh|.ssh/*|*/\.ssh|*/\.ssh/*)
        block "SSH config directory (.ssh/). Do not write SSH configs from an agent. Ask the user to edit manually." ;;
    secrets.*|*.secrets|*-secrets.*|secrets/*|*/secrets.*|*/*.secrets|*/*-secrets.*|credentials|credentials.*|*-credentials.*|*/credentials|*/credentials.*|*/*-credentials.*)
        block "Secrets/credentials file pattern. Do not write secret material from an agent. Ask the user to edit manually." ;;
esac

# Rule 2.6 — worktree confinement (ADR-0004).
# Executor worktree sessions live at <parent>/.wt/<project>/<executor>/ (see
# docs/architecture/0004-worktree-multi-project-topology.md). Inside one, the
# only legal write targets are paths inside the worktree itself (including the
# junctioned .ai/, which resolves as a relative path). Absolute paths that did
# not normalize to relative are escapes; so are ../ climbs.
case "$project_root" in
    */.wt/*/*)
        case "$rel" in
            /*|[A-Za-z]:/*)
                block "Worktree confinement (ADR-0004): this session runs in executor worktree '$project_root' and may write only inside it (+ the junctioned .ai/). Escaping to '$rel' is blocked — cross-tree changes go through .ai/handoffs/." ;;
            ..|../*|*/..|*/../*)
                block "Worktree confinement (ADR-0004): relative path escapes the worktree ('$rel'). Write only inside this worktree; cross-tree changes go through .ai/handoffs/." ;;
        esac ;;
esac

# Rule 2.7 — fleet whitelist (ADR-0004).
# Cross-orchestrator handoffs live at <root>/.fleet/handoffs/to-<project>/.
# A write there is legal only if THIS project's talks_to list in the fleet
# registry (<root>/.fleet/registry.json) includes the target project.
# Non-handoff .fleet paths (activity log, README) are allowed.
# NOTE: fail-CLOSED — missing registry or missing python blocks the write
# (fleet writes are rare and cross-project; conservatism is correct here).
fleet_norm="$rel"
case "$fleet_norm" in
    .fleet/*) fleet_norm="./$fleet_norm" ;;
esac
case "$fleet_norm" in
    */.fleet/handoffs/to-*)
        fleet_target=$(printf '%s' "$fleet_norm" | sed -n 's|.*/\.fleet/handoffs/to-\([^/]*\).*|\1|p')
        fleet_root=$(printf '%s' "$fleet_norm" | sed -n 's|\(.*/\.fleet\)/.*|\1|p')
        registry="$fleet_root/registry.json"
        project_name=$(basename "$project_root")
        [ -f "$registry" ] || block "Fleet whitelist (ADR-0004): no registry at '$registry' — cannot verify talks_to for '$fleet_target'. Scaffold the fleet tier first (scripts/fleet-init.sh)."
        fleet_check() { "$1" -c "
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
talks = d.get('projects', {}).get(sys.argv[2], {}).get('talks_to', [])
sys.exit(0 if sys.argv[3] in talks else 1)
" "$registry" "$project_name" "$fleet_target"; }
        if fleet_check python3 2>/dev/null || fleet_check python 2>/dev/null; then
            exit 0   # whitelisted cross-orchestrator handoff write
        else
            block "Fleet whitelist (ADR-0004): '$project_name' is not whitelisted to talk to '$fleet_target' (registry: $registry). Add it to talks_to (owner decision) or route via an allowed project."
        fi
        ;;
    */.fleet/*)
        exit 0 ;;   # fleet activity log / README / registry — not handoff-guarded here
esac

# Rule 2.5 — main-thread delegation enforcement (orchestrator pattern / ADR-0002).
# Subagent tool calls carry agent_type in hook input; main-thread (orchestrator)
# calls do not. The orchestrator writes only framework paths — project-source
# mutations must come from subagents. Delegation becomes mechanical, not aspirational.
if [ -z "$agent_type" ]; then
    case "$rel" in
        .ai|.ai/*) : ;;                                  # shared framework state
        .claude|.claude/*) : ;;                          # Claude config
        CLAUDE.md|AGENTS.md) : ;;                        # Claude-owned root contracts
        opencode.json|.opencode|.opencode/*) : ;;        # OpenCode custodianship (ADR-0001/0002 amendments 2026-07-09)
        .codegraph|.codegraph/*) : ;;                    # Claude's graph dir
        .mcp.json|.mcp.json.example) : ;;                # Claude's MCP config
        *)
            block "Main-thread (orchestrator) write to project path '$rel'. Delegate this to a subagent (coder, doc-writer, tester, ...) — the orchestrator writes only framework paths. See .ai/instructions/orchestrator-pattern/principles.md." ;;
    esac
fi

# Rule 3 — root-file policy.
# Authoritative allowlist: docs/architecture/0001-root-file-exceptions.md.
# Path is at root iff it contains no "/" and is not empty.
case "$rel" in
    */*) exit 0 ;;    # has slash → not at root → allow
    "") exit 0 ;;     # empty → skip
    # Category A — docs entry points
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    LICENSE|LICENSE.*) exit 0 ;;
    CHANGELOG|CHANGELOG.*) exit 0 ;;
    CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) exit 0 ;;
    # Category B — git-mandated dotfiles
    .gitignore|.gitattributes) exit 0 ;;
    # Category C — editor-mandated dotfile
    .editorconfig) exit 0 ;;
    # Category D — platform / CI-vendor dotfiles at root
    .dockerignore|.gitlab-ci.yml) exit 0 ;;
    # Category E — MCP convention + OpenCode config (Claude is OpenCode's custodian per ADR-0001/0002
    # amendments 2026-07-09)
    .mcp.json|.mcp.json.example|opencode.json) exit 0 ;;
    # Categories F/G/H — amend this allowlist alongside the ADR when a language or tool is chosen.
    # Examples to uncomment later: package.json, pyproject.toml, Cargo.toml, go.mod, .nvmrc, .python-version, .tool-versions
    *)
        block "Writing '$rel' at repo root violates the root-file policy. See docs/architecture/0001-root-file-exceptions.md for the allowlist. If this is a tooling-required exception not yet in the ADR, surface it to the user for approval + ADR amendment before creating." ;;
esac

exit 0
