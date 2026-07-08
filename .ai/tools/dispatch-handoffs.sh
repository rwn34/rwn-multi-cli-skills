#!/bin/bash
# dispatch-handoffs.sh — trigger recipient CLIs for auto-dispatchable handoffs.
#
# Protocol v2 (2026-07-08): scans .ai/handoffs/to-<cli>/open/*.md for
# `Auto: yes` AND `Risk: A|B` in the status block. For each match, launches the
# recipient CLI HEADLESS (one-shot) with a prompt to process that handoff.
# Risk C (or a missing Risk line — treated as C) is NEVER auto-dispatched,
# regardless of Auto: — those stay human-relayed. `Auto: no` also stays manual.
#
# Usage (from repo root):
#   bash .ai/tools/dispatch-handoffs.sh           # list what would dispatch (dry-run default)
#   bash .ai/tools/dispatch-handoffs.sh --exec    # actually launch recipient CLIs
#
# Design notes (see .ai/research/4ai-panes-integration-notes.md):
# - Windows Terminal cannot inject input into live panes, so we launch one-shot
#   headless instances instead of driving the interactive 4AI-panes session.
# - A CLI not found on PATH is skipped with a notice (matches 4AI-panes behavior).
# - Safe to run repeatedly (idle CLIs, polling loops, or the user): dispatched
#   handoffs get Status updated by the recipient, so re-runs skip them once
#   they leave OPEN state. The human gate applies only to Risk C.

set -u

MODE="dry-run"
[ "${1:-}" = "--exec" ] && MODE="exec"

root="$(pwd)"
[ -d "$root/.ai/handoffs" ] || { echo "Run from repo root (no .ai/handoffs found)."; exit 1; }

# Headless invocation per CLI. Verify locally before relying on kimi/kiro forms —
# flags differ across versions (see .ai/cli-map.md § headless invocation).
headless_cmd() {
    local cli="$1" file="$2"
    local prompt="Process the open handoff at $file per the protocol in .ai/handoffs/README.md. Execute the steps, prepend an activity-log entry, update the handoff Status, and report."
    case "$cli" in
        claude) printf '%s' "claude -p \"$prompt\" --permission-mode acceptEdits" ;;
        kimi)   printf '%s' "kimi --agent-file .kimi/agents/orchestrator.yaml -p \"$prompt\"" ;;
        kiro)   printf '%s' "kiro-cli chat --no-interactive \"$prompt\"" ;;
        crush)  printf '%s' "crush run \"$prompt\"" ;;
        *)      return 1 ;;
    esac
}

bin_for() {
    case "$1" in
        claude) echo "claude" ;;
        kimi)   echo "kimi" ;;
        kiro)   echo "kiro-cli" ;;
        crush)  echo "crush" ;;
    esac
}

found=0
for dir in "$root"/.ai/handoffs/to-*/open; do
    [ -d "$dir" ] || continue
    cli=$(basename "$(dirname "$dir")")   # to-<cli>
    cli="${cli#to-}"
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        # Status block check: dispatch only OPEN handoffs explicitly marked Auto: yes
        head -20 "$f" | grep -qiE '^Auto:[[:space:]]*yes' || continue
        head -20 "$f" | grep -qiE '^Status:[[:space:]]*OPEN' || continue
        # Risk gate (protocol v2): only Risk A/B auto-dispatch. Missing Risk = C.
        if ! head -20 "$f" | grep -qiE '^Risk:[[:space:]]*[AB][[:space:]]*$'; then
            echo "HOLD  [$cli] ${f#$root/} — Risk C or no Risk field (human relays)"
            continue
        fi
        found=$((found+1))
        rel="${f#$root/}"
        bin=$(bin_for "$cli")
        if ! command -v "$bin" >/dev/null 2>&1; then
            echo "SKIP  [$cli] $rel — '$bin' not on PATH"
            continue
        fi
        cmd=$(headless_cmd "$cli" "$rel")
        if [ "$MODE" = "exec" ]; then
            echo "DISPATCH [$cli] $rel"
            ( cd "$root" && eval "$cmd" )
            echo "---- [$cli] finished (exit $?) ----"
        else
            echo "WOULD DISPATCH [$cli] $rel"
            echo "    $cmd"
        fi
    done
done

if [ "$found" -eq 0 ]; then
    echo "No open handoffs marked 'Auto: yes'."
fi
[ "$MODE" = "dry-run" ] && [ "$found" -gt 0 ] && echo "(dry-run — pass --exec to launch)"
exit 0
