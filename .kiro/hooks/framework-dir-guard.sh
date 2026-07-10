#!/bin/bash
# Hook: preToolUse — block writes to other CLIs' framework dirs

# Extraction MUST NOT depend on python (fail-CLOSED). On this host python3 can
# resolve to a Windows Store alias stub that prints nothing and exits 0, so a
# `|| python` chain keyed on EXIT STATUS never falls through — path comes back
# empty and the old `[ -z ] && exit 0` made every rule a silent no-op (fail-OPEN).
# Fix mirrors .claude/hooks/pretool-write-edit.sh (commit 588ed9c): python is an
# OPTIONAL first attempt; the real extractor is a pure-sed fallback that runs
# whenever the python result is EMPTY (not merely on non-zero exit). This guard
# is matched to fs_write only, so stdin always carries file_path.
INPUT=$(cat)
# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ]; then
    exit 0
fi
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# Kiro's fs_write / str_replace tool_input carries the target under "path", not
# "file_path" — fall back to it so str_replace/fs_write edits are actually
# path-evaluated (not blanket fail-CLOSED-blocked). python optional-first,
# pure-sed fallback on EMPTY output; the sed pattern needs a literal quote
# before "path" so it never mis-matches "file_path".
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null)
[ -z "$FILE_PATH" ] && FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
# Non-empty stdin but no file_path/path parsed → refuse to fail open.
if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: could not parse tool input (no file_path or path found) — refusing to fail open." >&2
    exit 2
fi

# Normalize backslashes → slashes so absolute Windows paths compare correctly.
# Kiro's runtime emits ABSOLUTE file_path (e.g. C:/…/.claude/…). The globs below
# match the framework dir as a path SEGMENT (anywhere in the path), so the guard
# fires for both relative (.claude/x) and absolute (…/.claude/x) forms. Before
# this, the anchored relative-only globs let absolute paths fall through to
# exit 0 — validation T-K2 FAIL, 2026-07-09.
REL=$(printf '%s' "$FILE_PATH" | tr '\\' '/')

case "$REL" in
  .kimi|.kimi/*|*/.kimi|*/.kimi/*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimi/. Create a handoff to .ai/handoffs/to-kimi/open/ instead." >&2; exit 2 ;;
  .claude|.claude/*|*/.claude|*/.claude/*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .claude/. Create a handoff to .ai/handoffs/to-claude/open/ instead." >&2; exit 2 ;;
  .codegraph|.codegraph/*|*/.codegraph|*/.codegraph/*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .codegraph/ (Claude's graph dir)." >&2; exit 2 ;;
  .kimigraph|.kimigraph/*|*/.kimigraph|*/.kimigraph/*) echo "BLOCKED: Edit-boundary rule — Kiro cannot write to .kimigraph/ (Kimi's graph dir)." >&2; exit 2 ;;
  .kirograph|.kirograph/*|*/.kirograph|*/.kirograph/*) echo "BLOCKED: KiroGraph removed 2026-07-09 (ADR-0003 amendment). No re-enable path short of a fresh ADR." >&2; exit 2 ;;
esac
exit 0
