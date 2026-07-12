#!/bin/bash
# Hook 5: Worktree confinement + fleet whitelist guard (ADR-0004)
# Blocks executor sessions in .wt/<project>/<executor>/ from escaping the worktree,
# and limits .fleet/handoffs/to-<project>/ writes to the fleet registry whitelist.

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

extract_path() {
    local out
    out=$(printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | python  -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
}

path=$(extract_path "$INPUT")

if [ -z "$path" ]; then
    echo "BLOCKED: Could not parse tool input path; failing closed against worktree/fleet writes." >&2
    exit 2
fi

# --- lexical path canonicalizer (pure bash; NO realpath/cygpath) -----------
# The runtime emits Windows-ABSOLUTE paths (C:\..., C:/...) while pwd yields
# the MSYS form (/c/...). The old prefix compare across those forms never
# matched, so: (1) a sibling-prefix escape (/c/repo-evil/x) was read as
# IN-TREE and allowed, and (2) a legitimate in-tree write emitted as
# C:/<worktree>/... was blocked as a false-positive escape (handoff
# 202607120059; same class as Kiro's T-K2 fix of 2026-07-09).
#
# canon_path handles: relative, C:\x, C:/x, /c/x, mixed separators, drive
# case (C: vs c:), and . / .. segments — all LEXICALLY. Fail-CLOSED: a shape
# we refuse (bare drive `C:`, drive-relative `C:foo`) blocks the write, and
# a refusal is FINAL.
#
# Why not realpath/cygpath (proven traps):
#   - cygpath -u 'C:' → '/c' and cygpath -u 'C:foo\bar' SUCCEEDS — the
#     refused shapes come back looking canonical and sail through to exit 0.
#   - realpath / cygpath -a resolve reparse points; per ADR-0004 .ai/ inside
#     a worktree IS a Windows junction — resolving it relocates every .ai/
#     write outside the worktree root and breaks legitimate handoff writes.
canon_collapse() {
    # Lexically collapse . and .. (no filesystem access). Absolute: .. at the
    # root is a no-op. Relative: leading .. is preserved so the confinement
    # rule below still sees the escape.
    local p="$1" absolute=0 seg joined=""
    case "$p" in /*) absolute=1 ;; esac
    local parts=() stack=()
    local old_ifs="$IFS"; IFS='/'
    read -r -a parts <<< "$p"
    IFS="$old_ifs"
    for seg in "${parts[@]}"; do
        case "$seg" in
            ""|.) ;;
            ..)
                if [ "${#stack[@]}" -gt 0 ] && [ "${stack[$((${#stack[@]}-1))]}" != ".." ]; then
                    stack=("${stack[@]:0:$((${#stack[@]}-1))}")
                elif [ "$absolute" -eq 0 ]; then
                    stack+=("..")
                fi
                ;;
            *) stack+=("$seg") ;;
        esac
    done
    for seg in ${stack[@]+"${stack[@]}"}; do joined="$joined/$seg"; done
    if [ "$absolute" -eq 1 ]; then
        printf '%s' "${joined:-/}"
    else
        joined="${joined#/}"
        printf '%s' "${joined:-.}"
    fi
}

canon_path() {
    # $1 = raw tool-emitted path. Prints the canonical form; returns 1 for a
    # refused shape (bare drive / drive-relative).
    local p d
    p=$(printf '%s' "$1" | tr '\\' '/')
    case "$p" in
        [A-Za-z]:/*)
            d=$(printf '%s' "${p:0:1}" | tr 'A-Z' 'a-z')
            p="/$d${p:2}" ;;
        [A-Za-z]:*)
            return 1 ;;
    esac
    canon_collapse "$p"
}

project_root=$(canon_collapse "$(pwd | tr '\\' '/')")
path_canon=$(canon_path "$path") || {
    echo "BLOCKED: path '$path' has a refused shape (bare drive or drive-relative) — failing closed against worktree/fleet writes." >&2
    exit 2
}
# Relativize ONLY when genuinely under project_root: case-folded compare plus
# a trailing-'/' boundary, so /c/repo-evil/x is NOT read as under /c/repo.
# Outside paths STAY ABSOLUTE — Rules 1 and 2 below match the absolute form.
_pr=$(printf '%s' "$project_root" | tr 'A-Z' 'a-z')
_pp=$(printf '%s' "$path_canon" | tr 'A-Z' 'a-z')
if [ "$_pp" = "$_pr" ]; then
    rel="."
elif [ "${_pp:0:${#_pr}}" = "$_pr" ] && [ "${_pp:${#_pr}:1}" = "/" ]; then
    rel="${path_canon:$((${#project_root}+1))}"
else
    rel="$path_canon"
fi
unset _pr _pp

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
