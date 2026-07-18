#!/bin/bash
# PreToolUse hook — matcher: Write|Edit
# Blocks writes that violate the territorial / sensitive-file / root-file policy.
# Reads tool call JSON from stdin; exit 2 + stderr to block with a reason.
#
# REFACTOR (bash-guard fix): all path normalization AND policy now live in the
# shared library .claude/hooks/lib/path-policy.sh, which pretool-bash.sh ALSO
# sources. This hook no longer contains a to_posix/collapse canonicalizer or a
# `case "$rel" in .kimi...` rule literal — it extracts file_path, canonicalizes
# via the library, and asks classify_path for the verdict. One classifier, two
# surfaces, zero drift. Behaviour is unchanged from the pre-refactor #50 version.

# Extract file_path + agent_type from the tool-call JSON on stdin.
# agent_type is present for SUBAGENT calls; absent/empty on the main thread.
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
# as MAIN-THREAD by classify_path (most restrictive path, Rule 2.5). No fail-open risk.

block() {
    echo "BLOCKED by hook: $1" >&2
    exit 2
}

# stdin was non-empty but no file_path parsed. A Write|Edit call always carries
# file_path, so an empty result means the parse failed — refuse to fail open.
if [ -z "$path" ]; then
    block "could not parse tool input (no file_path found) — refusing to fail open."
fi

# Source the shared normalization + policy library.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/path-policy.sh"
# shellcheck source=lib/path-policy.sh
. "$LIB" || block "could not source path-policy library ('$LIB') — refusing to fail open."

# Canonicalize the project root, then the file_path, via the shared library
# (fail-CLOSED: an un-canonicalizable shape is BLOCKED, never allowed).
project_root=$(canon_root "$(pwd 2>/dev/null)") || block "cannot canonicalize the project root (pwd) — refusing to evaluate write rules against an unknown root."

rel=$(canonicalize_and_relativize "$path" "$project_root") || block "$rel"

# Ask the single shared classifier for the verdict.
verdict=$(classify_path "$rel" "$project_root" "$agent_type")
case "$verdict" in
    ALLOW)   exit 0 ;;
    BLOCK:*) block "${verdict#BLOCK:*:}" ;;
    *)       block "policy classifier returned an unrecognized verdict ('$verdict') — refusing to fail open." ;;
esac

exit 0
