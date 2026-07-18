#!/bin/bash
# reconcile-done-handoffs.sh — self-heal a forgotten protocol-v4 self-retire,
# AND kill ghost handoffs (a retired handoff that never lost its open/ copy).
#
# Protocol v4 (2026-07-16) requires a handoff recipient to MOVE its own file
# from .ai/handoffs/to-<cli>/open/ (or /review/) to the sibling done/ dir when it
# sets a terminal status (`Status: DONE`, `Status: IMPOSSIBLE`, or
# `Status: NOT-A-BUG`). If it forgets, the file sits in open/ or review/ marked
# terminal — misplaced: the dispatcher won't re-dispatch it, but it's in the
# wrong folder and invisible as "done". This script moves any such stray into
# done/.
#
# Ghost-handoff guard (2026-07-13, handoff 202607131035): a SECOND, distinct
# defect the terminal-status check below cannot see — a handoff retired by
# *copying* open/ -> done/ and editing only the done/ copy (rather than
# *moving* the file, as protocol v4 requires) leaves a STALE open/ copy behind
# that still says `Status: OPEN`. That copy is dispatcher-visible forever: it
# re-dispatches a decision that was already closed, silently burning a full
# session's context every time. The terminal-status check is blind to this by
# construction — it only ever looks at the open/ copy's OWN content, and this
# ghost's open/ copy says OPEN, not DONE. Rule: the SAME basename existing in
# BOTH open/ (or review/) and done/ of the same queue is always an error; done/
# wins (a handoff is only ever retired forward, never backward) — retire the
# open/ copy by moving it into done/ as a `.duplicate-<UTC>` sidecar (never
# silently deleted — see rationale below) and log loudly.
#
# Usage (from repo root):
#   bash .ai/tools/reconcile-done-handoffs.sh          # scan ./.ai/handoffs
#   bash .ai/tools/reconcile-done-handoffs.sh <basedir>  # scan <basedir>/.ai/handoffs
#   HANDOFFS_DIR=/tmp/t bash .ai/tools/reconcile-done-handoffs.sh  # override (tests)
#
# Fail-open by contract: always exits 0. Wired into dispatch-handoffs.sh so every
# auto-dispatch cycle self-heals a forgotten self-retire (and any ghost) before
# selecting work. Idempotent: no terminal-status-in-open and no open/done
# duplicate -> no output, exit 0.

set -u

base="${1:-.}"
handoffs_dir="${HANDOFFS_DIR:-$base/.ai/handoffs}"

# Ghost-handoff guard: first pass — any basename present in both a source dir
# (open/review) AND done/ is stale; done/ wins. This runs before the
# terminal-status pass so a ghost whose open/ copy still says OPEN is caught.
for to_dir in "$handoffs_dir"/to-*; do
    [ -d "$to_dir" ] || continue
    done_dir="$to_dir/done"
    for sub in open review; do
        dir="$to_dir/$sub"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            base_name="$(basename "$f")"
            case "$base_name" in
                README.md|template.md) continue ;;
            esac
            # Only treat as a ghost if the source copy is NON-terminal. A terminal
            # status in open/ is a forgotten self-retire, not a ghost; the second
            # pass below handles it (with superseded-name collision logic).
            src_status="$(sed -n 's/^[[:space:]]*[Ss][Tt][Aa][Tt][Uu][Ss][[:space:]]*:[[:space:]]*//p' "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')"
            case "$src_status" in
                done|impossible|not-a-bug) ;;
                *)
                    if [ -e "$done_dir/$base_name" ]; then
                        mkdir -p "$done_dir" 2>/dev/null
                        ts=$(date -u +%Y%m%d%H%M%S)
                        sidecar="$done_dir/${base_name%.md}.duplicate-$ts.md"
                        if mv "$f" "$sidecar" 2>/dev/null; then
                            echo "reconcile-done: GHOST retired -- $f duplicated done/$base_name; $sub/ copy moved to $sidecar (done/ wins)"
                        fi
                    fi
                    ;;
            esac
        done
    done
done

# Pre-compute v4 lint errors so terminal handoffs that fail sender-side evidence
# discipline are not silently moved to done/. The lint script scans open/ and
# review/ itself; we just check whether a given file's relative path appears in
# its error output. Missing lint script = skip the gate (e.g. minimal test fixtures).
lint_script="$base/.ai/tools/lint-handoff.sh"
lint_errors=""
if [ -f "$lint_script" ]; then
    lint_errors="$(HANDOFFS_DIR="$handoffs_dir" bash "$lint_script" 2>&1 || true)"
fi

# Second pass: move terminal-status files left in open/ or review/ into done/.
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
            rel="${f#$handoffs_dir/}"
            # Header check: parse `Status:` by key, case-insensitive.
            status="$(sed -n 's/^[[:space:]]*[Ss][Tt][Aa][Tt][Uu][Ss][[:space:]]*:[[:space:]]*//p' "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')"
            case "$status" in
                done|impossible|not-a-bug)
                    # Retirement gate: terminal statuses need evidence sections.
                    if [ -n "$lint_errors" ] && printf '%s\n' "$lint_errors" | grep -qF "$rel"; then
                        echo "reconcile-done: WARNING $rel fails v4 lint; leaving in $sub/ for correction"
                        continue
                    fi
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
