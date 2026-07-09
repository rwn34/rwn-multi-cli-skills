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
        # kimi-code has no --agent-file/--agent flag (verified via `kimi --help`
        # 2026-07-09); prompt-only headless invocation via -p.
        kimi)   printf '%s' "kimi -p \"$prompt\"" ;;
        # --trust-all-tools REQUIRED headless: without it kiro-cli aborts with
        # "Tool approval required but --no-interactive was specified. Use
        # --trust-all-tools" (dispatch failure 2026-07-09, see
        # .ai/reports/dispatch-failure-20260709015110-kiro-*.md).
        # --agent orchestrator REQUIRED: chat.defaultAgent is unset, so a bare
        # `kiro-cli chat` runs the BUILT-IN default agent which carries NO guard
        # hooks — every one of the 13 .kiro/agents/*.json wires the guards, the
        # built-in default does not. Pinning the orchestrator gives the headless
        # session the framework-dir/root/sensitive/ADR-0004 guards (validation
        # T-K2 default-agent gap, 2026-07-09).
        # --v3 is a TOP-LEVEL flag (kiro-cli --help: "--v3  Launch the next
        # generation Kiro agent"; NOT a `chat` subcommand flag) — launches Kiro
        # CLI v3 for headless dispatch too.
        kiro)   printf '%s' "kiro-cli --v3 chat --no-interactive --trust-all-tools --agent orchestrator \"$prompt\"" ;;
        # --auto is REQUIRED headless: with edit:"ask" opencode auto-rejects all
        # writes; the framework-guard plugin fires before the permission layer
        # and remains the mechanical lane barrier (verified 2026-07-09).
        # --agent opencode pins the contract-carrying agent (.opencode/contract.md);
        # without it the default build agent runs and never loads the contract
        # (ADR-0001 NOTE 2026-07-09: no dead text — pin the load path).
        opencode) printf '%s' "opencode run --auto --agent opencode \"$prompt\"" ;;
        *)      return 1 ;;
    esac
}

bin_for() {
    case "$1" in
        claude) echo "claude" ;;
        kimi)   echo "kimi" ;;
        kiro)   echo "kiro-cli" ;;
        opencode) echo "opencode" ;;
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
            out_tmp=$(mktemp)
            ( cd "$root" && eval "$cmd" ) 2>&1 | tee "$out_tmp"
            rc=${PIPESTATUS[0]}
            echo "---- [$cli] finished (exit $rc) ----"
            # Failure alerting (Tier B — act, then notify): non-zero exit writes a
            # report so a failed headless dispatch is never silent.
            if [ "$rc" -ne 0 ]; then
                ts=$(date -u +%Y%m%d%H%M%S)
                # Filename includes the handoff slug: same-second failures for one
                # CLI must not overwrite each other (bug found by stub-binary test
                # 2026-07-09 — three same-second claude failures collided).
                slug=$(basename "$f" .md)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (exit $rc)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- Command: $cmd"
                    echo "- UTC: $ts"
                    echo ""
                    echo "## Output tail (last 40 lines)"
                    echo '```'
                    tail -40 "$out_tmp"
                    echo '```'
                    echo ""
                    echo "Triage: re-run manually, or relay the handoff by hand. The handoff"
                    echo "stays OPEN — the dispatcher will retry it on the next --exec run."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
            fi
            rm -f "$out_tmp"
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
