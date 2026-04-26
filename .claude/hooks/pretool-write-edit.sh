#!/bin/bash
# PreToolUse hook — matcher: Write|Edit
# Blocks writes that violate (1) framework-dir rule, (2) sensitive-file rule, (3) root-file policy.
# Reads tool call JSON from stdin; exit 2 + stderr to block with a reason.

# Extract file_path via python (jq not reliably installed on Windows/Git Bash)
path=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
      python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
      echo "")

# No path? allow (nothing to evaluate)
[ -z "$path" ] && exit 0

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
        block ".kimi/ is Kimi CLI's territory. Claude never writes there. Use .ai/handoffs/to-kimi/open/NNN-slug.md to request the change." ;;
    .kiro|.kiro/*)
        block ".kiro/ is Kiro CLI's territory. Claude never writes there. Use .ai/handoffs/to-kiro/open/NNN-slug.md to request the change." ;;
    .kimigraph|.kimigraph/*)
        block ".kimigraph/ is Kimi's code-graph territory (KimiGraph tool). Claude never writes there." ;;
    .kirograph|.kirograph/*)
        block ".kirograph/ is Kiro's code-graph territory (KiroGraph tool). Claude never writes there." ;;
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
    # Category E — MCP convention
    .mcp.json|.mcp.json.example) exit 0 ;;
    # Categories F/G/H — amend this allowlist alongside the ADR when a language or tool is chosen.
    # Examples to uncomment later: package.json, pyproject.toml, Cargo.toml, go.mod, .nvmrc, .python-version, .tool-versions
    *)
        block "Writing '$rel' at repo root violates the root-file policy. See docs/architecture/0001-root-file-exceptions.md for the allowlist. If this is a tooling-required exception not yet in the ADR, surface it to the user for approval + ADR amendment before creating." ;;
esac

exit 0
