#!/bin/bash
# reconcile-done-handoffs.sh — self-heal a forgotten protocol-v4 self-retire.
#
# Protocol v4 (2026-07-16) requires a handoff recipient to MOVE its own file
# from .ai/handoffs/to-<cli>/open/ (or /review/) to the sibling done/ dir when it
# sets a terminal status (`Status: DONE`, `Status: IMPOSSIBLE`, or
# `Status: NOT-A-BUG`). If it forgets, the file sits in open/ or review/ marked
# terminal — misplaced: the dispatcher won't re-dispatch it, but it's in the
# wrong folder and invisible as "done". This script moves any such stray into
# done/.
#
# Usage (from repo root):
#   bash .ai/tools/reconcile-done-handoffs.sh          # scan ./.ai/handoffs
#   bash .ai/tools/reconcile-done-handoffs.sh <basedir>  # scan <basedir>/.ai/handoffs
#   HANDOFFS_DIR=/tmp/t bash .ai/tools/reconcile-done-handoffs.sh  # override (tests)
#
# Fail-open by contract: always exits 0. Wired into dispatch-handoffs.sh so every
# auto-dispatch cycle self-heals a forgotten self-retire before selecting work.
# Idempotent: no terminal-status-in-open -> no output, exit 0.

set -u

base="${1:-.}"
handoffs_dir="${HANDOFFS_DIR:-$base/.ai/handoffs}"

for to_dir in "$handoffs_dir"/to-*; do
    [ -d "$to_dir" ] || continue
    for sub in open review; do
        dir="$to_dir/$sub"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            case "$(basename "$f")" in
                README.md|template.md) continue ;;
            esac
            # Header check: parse `Status:` by key, case-insensitive.
            status="$(sed -n 's/^[[:space:]]*[Ss][Tt][Aa][Tt][Uu][Ss][[:space:]]*:[[:space:]]*//p' "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')"
            case "$status" in
                done|impossible|not-a-bug)
                    done_dir="$to_dir/done"
                    mkdir -p "$done_dir" 2>/dev/null
                    target="$done_dir/$(basename "$f")"
                    if [ -e "$target" ]; then
                        # Collision: a file with the same name already exists in done/.
                        # Fail-open contract requires exit 0, but we must never silently
                        # destroy the existing done/ file. Move the incoming file to a
                        # superseded name so both are preserved and the conflict is visible.
                        suffix="$(date -u +%Y%m%d%H%M%S)"
                        safe_target="$done_dir/$(basename "$f" .md)-superseded-$suffix.md"
                        if mv "$f" "$safe_target" 2>/dev/null; then
                            echo "reconcile-done: WARNING collision at $target; moved $f -> $safe_target (Status:${status^^} was left in $sub/)"
                        fi
                    else
                        if mv "$f" "$done_dir/" 2>/dev/null; then
                            echo "reconcile-done: moved $f -> done/ (Status:${status^^} was left in $sub/)"
                        fi
                    fi
                    ;;
            esac
        done
    done
done

exit 0
