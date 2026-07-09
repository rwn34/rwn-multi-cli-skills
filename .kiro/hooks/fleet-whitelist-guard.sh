#!/bin/bash
# Hook: preToolUse — fleet whitelist (ADR-0004 Rule 2.7)
# Cross-orchestrator handoffs live at <root>/.fleet/handoffs/to-<project>/.
# A write there is legal only if THIS project's talks_to list in the fleet
# registry (<fleetroot>/registry.json) includes the target project.
# Non-handoff .fleet paths (activity log, README) are allowed.
# Fail-CLOSED: missing registry or missing python blocks the write.

INPUT=$(cat)
# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ]; then
    exit 0
fi
# Extraction MUST NOT depend on python (fail-CLOSED). python3 can resolve to a
# Windows Store alias stub (empty stdout, exit 0); a `|| python` chain keyed on
# exit status silently no-ops → fail-OPEN. python optional-first; pure-sed fallback
# on EMPTY output; fail-CLOSED if nothing parses. Matched to fs_write only.
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: could not parse tool input (no file_path found) — refusing to fail open." >&2
    exit 2
fi

# Normalize backslashes to forward slashes
FILE_PATH=$(echo "$FILE_PATH" | tr '\\' '/')

# Normalize: ensure .fleet paths can be matched consistently
fleet_norm="$FILE_PATH"
case "$fleet_norm" in
  .fleet/*) fleet_norm="./$fleet_norm" ;;
esac

# Only applies to .fleet/handoffs/to-<target> paths
case "$fleet_norm" in
  */.fleet/handoffs/to-*)
    # Extract target project name and fleet root
    fleet_target=$(printf '%s' "$fleet_norm" | sed -n 's|.*/\.fleet/handoffs/to-\([^/]*\).*|\1|p')
    fleet_root=$(printf '%s' "$fleet_norm" | sed -n 's|\(.*/\.fleet\)/.*|\1|p')
    registry="$fleet_root/registry.json"
    project_name=$(basename "$(pwd)")

    # Fail-closed: no registry → block
    if [ ! -f "$registry" ]; then
      echo "BLOCKED: Fleet whitelist (ADR-0004) — no registry at '$registry'. Cannot verify talks_to for '$fleet_target'. Scaffold the fleet tier first (scripts/fleet-init.sh)." >&2
      exit 2
    fi

    # Check if this project is whitelisted to talk to the target
    fleet_check() {
      "$1" -c "
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
talks = d.get('projects', {}).get(sys.argv[2], {}).get('talks_to', [])
sys.exit(0 if sys.argv[3] in talks else 1)
" "$registry" "$project_name" "$fleet_target"
    }

    if fleet_check python3 2>/dev/null || fleet_check python 2>/dev/null; then
      exit 0   # whitelisted — allow
    else
      echo "BLOCKED: Fleet whitelist (ADR-0004) — '$(basename "$(pwd)")' is not whitelisted to talk to '$fleet_target' (registry: $registry). Add it to talks_to (owner decision) or route via an allowed project." >&2
      exit 2
    fi
    ;;
  */.fleet/*)
    exit 0 ;;   # fleet activity log / README / registry — not handoff-guarded
esac

# Not a fleet path at all — allow
exit 0
