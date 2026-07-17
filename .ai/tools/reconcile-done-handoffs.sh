#!/bin/bash
# reconcile-done-handoffs.sh — self-heal a forgotten protocol-v3 self-retire.
#
# Protocol v3 (2026-07-09) requires a handoff recipient to MOVE its own file
# from .ai/handoffs/to-<cli>/open/ (or /review/) to the sibling done/ dir when it
# sets `Status: DONE`. If it forgets, the file sits in open/ or review/ marked
# DONE — misplaced: the dispatcher won't re-dispatch it, but it's in the wrong
# folder and invisible as "done". This script moves any such stray into done/.
#
# Usage (from repo root):
#   bash .ai/tools/reconcile-done-handoffs.sh          # scan ./.ai/handoffs
#   bash .ai/tools/reconcile-done-handoffs.sh <basedir>  # scan <basedir>/.ai/handoffs
#   HANDOFFS_DIR=/tmp/t bash .ai/tools/reconcile-done-handoffs.sh  # override (tests)
#
# Fail-open by contract: always exits 0. Wired into dispatch-handoffs.sh so every
# auto-dispatch cycle self-heals a forgotten self-retire before selecting work.
# Idempotent: no DONE-in-open -> no output, exit 0.

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
            # Header check: first ~10 lines, case-insensitive `Status: DONE`.
            if head -10 "$f" 2>/dev/null | grep -qiE '^Status:[[:space:]]*DONE'; then
                done_dir="$to_dir/done"
                mkdir -p "$done_dir" 2>/dev/null
                if mv "$f" "$done_dir/" 2>/dev/null; then
                    echo "reconcile-done: moved $f -> done/ (Status:DONE was left in $sub/)"
                fi
            fi
        done
    done
done

exit 0
