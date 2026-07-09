#!/bin/bash
# Hook 5: Worktree confinement + fleet whitelist guard (ADR-0004)
# Blocks executor sessions in .wt/<project>/<executor>/ from escaping the worktree,
# and limits .fleet/handoffs/to-<project>/ writes to the fleet registry whitelist.

input=$(cat)
path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null || \
      printf '%s' "$input" | python  -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null || \
      echo "")

# Fail open if we cannot parse a path
[ -z "$path" ] && exit 0

project_root=$(pwd)
project_root="${project_root%/}"

# Normalize absolute path → relative if under project_root
if [ "${path:0:${#project_root}}" = "$project_root" ]; then
    rel="${path:${#project_root}}"
    rel="${rel#/}"
else
    rel="$path"
fi
# Normalize Windows backslashes
rel=$(echo "$rel" | tr '\\' '/')

block() {
    echo "BLOCKED by worktree-fleet-guard: $1" >&2
    exit 2
}

# Rule 1 — worktree confinement (ADR-0004).
# Executor worktree sessions live at <parent>/.wt/<project>/<executor>/.
# Only in-tree writes (including the junctioned .ai/, which resolves relatively)
# are allowed. Absolute outside paths and ../ climbs are escapes.
case "$project_root" in
    */.wt/*/*)
        case "$rel" in
            /*|[A-Za-z]:/*)
                block "Worktree confinement (ADR-0004): this session runs in executor worktree '$project_root' and may write only inside it (+ the junctioned .ai/). Escaping to '$rel' is blocked — cross-tree changes go through .ai/handoffs/." ;;
            ..|../*|*/..|*/../*)
                block "Worktree confinement (ADR-0004): relative path escapes the worktree ('$rel'). Write only inside this worktree; cross-tree changes go through .ai/handoffs/." ;;
        esac ;;
esac

# Rule 2 — fleet whitelist (ADR-0004).
# Cross-orchestrator handoffs live at <root>/.fleet/handoffs/to-<project>/.
# A write there is legal only if THIS project's talks_to list in the fleet
# registry (<root>/.fleet/registry.json) includes the target project.
# Other .fleet paths (activity log, README, registry) are allowed.
# Fail-closed: missing registry or missing python blocks the write.
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

exit 0
