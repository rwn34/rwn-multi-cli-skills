#!/bin/bash
# Hook 1: Root file guard
# Block writes to project root except files listed in ADR Category A
# See docs/architecture/0001-root-file-exceptions.md for the full allowlist

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
    echo "BLOCKED: Could not parse tool input path; failing closed against root writes." >&2
    exit 2
fi

# --- lexical path canonicalizer (pure bash; NO realpath/cygpath) -----------
# The runtime emits Windows-ABSOLUTE paths (C:\..., C:/...) while pwd yields
# the MSYS form (/c/...). The old guard tested "contains a slash ⇒ not at
# root ⇒ allow", so EVERY absolute path — including C:/<repo>/evil.txt, a
# write straight at the repo root — was allowed unconditionally (handoff
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
    echo "BLOCKED: path '$FILE_PATH' has a refused shape (bare drive or drive-relative) — failing closed against root writes." >&2
    exit 2
}
# Relativize ONLY when genuinely under project_root: case-folded compare plus
# a trailing-'/' boundary, so /c/repo-evil/x is NOT read as under /c/repo.
# Outside paths STAY ABSOLUTE (they are not repo-root writes; confinement is
# the worktree-fleet guard's job).
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

# A canonical repo-root file has no '/' in its relative form; anything with a
# directory component (including absolute outside-root paths) is not a root
# write and is out of this guard's jurisdiction.
case "$rel" in
    */*) exit 0 ;;
esac

# Path is at root level — check allowlist (ADR categories A–E)
case "$rel" in
    # Category A — docs entry points
    AGENTS.md|README.md|CLAUDE.md|LICENSE|LICENSE.*|CHANGELOG|CHANGELOG.*|CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md)
        exit 0
        ;;
    # Categories B/C/D/E — dotfiles and tooling
    .gitignore|.gitattributes)
        exit 0
        ;;
    .editorconfig)
        exit 0
        ;;
    .dockerignore|.gitlab-ci.yml)
        exit 0
        ;;
    .mcp.json|.mcp.json.example)
        exit 0
        ;;

    *)
        echo "BLOCKED: Writing '$rel' to project root is not allowed. See docs/architecture/0001-root-file-exceptions.md for the full allowlist. Move this file to the appropriate subdirectory (e.g., config/, infra/, src/)." >&2
        exit 2
        ;;
esac
