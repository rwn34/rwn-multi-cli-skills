#!/bin/bash
# Hook: preToolUse — block writes to project root unless the file is on the ADR-0001 allowlist

FILE_PATH=$(python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            python  -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || \
            echo "")
[ -z "$FILE_PATH" ] && exit 0

# Check if file is at root (no directory separator)
DIR=$(dirname "$FILE_PATH")
if [ "$DIR" = "." ]; then
  BASE=$(basename "$FILE_PATH")
  case "$BASE" in
    # ADR category A — docs entry points
    AGENTS.md|README.md|CLAUDE.md) exit 0 ;;
    LICENSE|LICENSE.*) exit 0 ;;
    CHANGELOG|CHANGELOG.*) exit 0 ;;
    CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) exit 0 ;;
    # ADR category E (partial) — MCP convention
    .mcp.json|.mcp.json.example) exit 0 ;;
    # Category B — git-mandated dotfiles
    .gitignore|.gitattributes) exit 0 ;;
    # Category C — editor-mandated
    .editorconfig) exit 0 ;;
    # Category D — platform / CI-vendor dotfiles at root
    .dockerignore|.gitlab-ci.yml) exit 0 ;;
    # Categories F/G/H — amend alongside the ADR when a language/tool is chosen.
    # See docs/architecture/0001-root-file-exceptions.md for the full allowlist.
    *) echo "BLOCKED: Root file policy — '$BASE' not in the allowlist from docs/architecture/0001-root-file-exceptions.md. Place this file in the appropriate directory (src/, config/, infra/, etc.) or amend the ADR if it's a tooling-required exception." >&2; exit 2 ;;
  esac
fi
exit 0
