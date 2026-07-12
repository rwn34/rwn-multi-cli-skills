#!/bin/bash
# Hook 2: Framework directory guard
# Block writes to other CLIs' framework directories (.claude/, .kiro/)
# .kimi/ is Kimi's own territory. .ai/ is shared with other CLIs
# (allowed for orchestrator; subagent writes restricted per agent config).

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

FILE_PATH=$(extract_path "$INPUT")

if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: Could not parse tool input path; failing closed against cross-CLI writes." >&2
    exit 2
fi

# --- lexical path canonicalizer (pure bash; NO realpath/cygpath) -----------
# The runtime emits Windows-ABSOLUTE paths (C:\..., C:/...) while pwd yields
# the MSYS form (/c/...). The old anchored relative-only globs let every
# absolute form, backslash separator, and . / .. laundering (.kimi/../.claude)
# fall through to exit 0 — Kimi could write into .claude/ and .kiro/ freely
# (handoff 202607120059; same class as Kiro's T-K2 fix of 2026-07-09).
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
    # root is a no-op. Relative: leading .. is preserved so escape rules in
    # sibling guards still see it.
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
path_canon=$(canon_path "$FILE_PATH") || {
    echo "BLOCKED: path '$FILE_PATH' has a refused shape (bare drive or drive-relative) — failing closed against cross-CLI writes." >&2
    exit 2
}
# Relativize ONLY when genuinely under project_root: case-folded compare plus
# a trailing-'/' boundary, so /c/repo-evil/x is NOT read as under /c/repo.
# Outside paths STAY ABSOLUTE — an absolute path outside this repo is not
# this guard's territory (confinement is the worktree-fleet guard's job).
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

# Block other CLIs' framework and graph directories (repo-root anchored, on
# the canonical relative form — so every absolute/backslash/dotdot shape of
# an in-repo .claude/ or .kiro/ write lands here too).
case "$rel" in
    .claude|.claude/*|.kiro|.kiro/*|.codegraph|.codegraph/*|.kirograph|.kirograph/*|.kimigraph|.kimigraph/*)
        echo "BLOCKED: Writing to '$FILE_PATH' is not allowed. That path is owned by another CLI. Use .ai/ or .kimi/ for framework-level files." >&2
        exit 2
        ;;
    *)
        exit 0
        ;;
esac
