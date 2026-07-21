#!/usr/bin/env bash
# render-activity-log.sh — generate a human-readable .ai/activity/log.md view
# from the entry-per-file spool (ADR-0010 Wave-3).
#
# Usage:
#   bash .ai/tools/render-activity-log.sh [project-dir]
#
# Reads .ai/activity/entries/*.md in reverse filename order (newest first),
# concatenates them, and appends a pointer to the frozen pre-spool archive.
# Never reads .ai/activity/archive/**.
#
# The rendered file is a generated view, not a source of truth. It must NOT be
# committed; .gitignore should exclude .ai/activity/log.md.

set -u

ROOT="${1:-$PWD}"
ENTRIES_DIR="$ROOT/.ai/activity/entries"
ARCHIVE_DIR="$ROOT/.ai/activity/archive"
OUTPUT="$ROOT/.ai/activity/log.md"
PRE_SPOOL="$ARCHIVE_DIR/log-pre-spool.md"

mkdir -p "$ROOT/.ai/activity"

{
  if [ -d "$ENTRIES_DIR" ]; then
    # Newest entries first: UTC basic ISO filenames sort lexicographically == chronologically.
    find "$ENTRIES_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
      | LC_ALL=C sort -z -r \
      | while IFS= read -r -d '' f; do
          cat "$f"
          printf '\n'
        done
  fi

  if [ -f "$PRE_SPOOL" ]; then
    printf -- '\n---\n'
    printf 'Pre-spool history frozen at %s\n' "$PRE_SPOOL"
    printf -- '---\n\n'
  fi
} > "$OUTPUT.new"

mv "$OUTPUT.new" "$OUTPUT"
echo "[render-activity-log] wrote $OUTPUT"
