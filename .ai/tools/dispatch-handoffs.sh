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
#   bash .ai/tools/dispatch-handoffs.sh                    # dry-run: list what would dispatch
#   bash .ai/tools/dispatch-handoffs.sh --exec             # launch recipient CLIs (all queues)
#   bash .ai/tools/dispatch-handoffs.sh --exec --only claude  # scope to one queue (to-claude)
#
# Recursion guard: in --exec mode each spawned CLI child inherits
# AI_HANDOFF_DISPATCH=1 in its environment. A SessionStart/Stop hook that itself
# calls this script (e.g. .claude/hooks/dispatch-own-queue.sh) checks that var
# and no-ops, so a dispatched session never re-dispatches — no fork-bomb.
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
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --exec)     MODE="exec" ;;
        --only)     ONLY="${2:-}"; shift ;;
        --only=*)   ONLY="${1#--only=}" ;;
        *)          echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

root="$(pwd)"
[ -d "$root/.ai/handoffs" ] || { echo "Run from repo root (no .ai/handoffs found)."; exit 1; }

# Self-heal (gap C3): before selecting/dispatching, move any handoff left in
# open/ but already marked Status:DONE into its sibling done/ dir — a forgotten
# protocol-v3 self-retire. Fail-open: reconcile is exit-0 by contract and any
# hiccup here must never block dispatch (hence the trailing `|| true`).
if [ "$MODE" = "exec" ]; then
    bash "$root/.ai/tools/reconcile-done-handoffs.sh" "$root" || true
fi

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
        # Headless dispatch stays on v2 (NO --v3). Per the v3 docs
        # (<https://kiro.dev/docs/cli/v3/> "Known gaps", verified 2026-07-09):
        # "The legacy non-TUI mode (kiro-cli chat without the TUI) does not
        # support the v3 engine. Use the TUI." --no-interactive IS that classic
        # non-TUI mode, so `kiro-cli --v3 chat --no-interactive` would silently
        # fall back to the v2 engine — the --v3 flag here was dead text. v3
        # enforces only in the interactive TUI; there is no v3 headless surface.
        # Headless Kiro therefore runs v2, and the git pre-commit backstop
        # (ADR-0005) is the version-agnostic mechanical floor for these commits.
        # (--trust-all-tools + --agent orchestrator rationale unchanged: see the
        # dispatch-failure report + T-K2 default-agent gap, 2026-07-09.)
        kiro)   printf '%s' "kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator \"$prompt\"" ;;
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

# --- Per-handoff claim-lock (ADR-0009 §3, contract in .ai/handoffs/.claims/README.md) ---
# Prevents this dispatcher and a live 4AI pane-runner from processing the SAME
# handoff twice. Sidecar path: .ai/handoffs/.claims/<recipient>__<slug>.claim.json.
# Single-host semantics (this fleet runs on one machine): a claim is LIVE when its
# file mtime is within CLAIM_STALE_MIN AND (same host) its pid is still alive.
# Everything here is fail-open — a claim-tooling error must never block dispatch.
CLAIM_STALE_MIN=15
claim_dir="$root/.ai/handoffs/.claims"

# 0 (true) if a LIVE claim by another consumer holds this handoff -> we must skip.
handoff_claimed_by_other() {
    local claim="$1"
    [ -f "$claim" ] || return 1
    # Stale by mtime -> reclaimable, not live.
    [ -n "$(find "$claim" -mmin -"$CLAIM_STALE_MIN" 2>/dev/null)" ] || return 1
    local chost cpid myhost
    myhost=$(hostname 2>/dev/null)
    chost=$(grep -oE '"host"[[:space:]]*:[[:space:]]*"[^"]*"' "$claim" 2>/dev/null | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')
    cpid=$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' "$claim" 2>/dev/null | grep -oE '[0-9]+$')
    # Same host + a pid we can probe: dead pid -> stale (reclaimable).
    if [ -n "$chost" ] && [ "$chost" = "$myhost" ] && [ -n "$cpid" ]; then
        kill -0 "$cpid" 2>/dev/null || return 1
    fi
    return 0
}

# Atomically acquire the claim. 0 = won (we own it), 1 = lost/could not.
acquire_claim() {
    local claim="$1" cli="$2" slug="$3"
    mkdir -p "$claim_dir" 2>/dev/null
    if ! ( set -o noclobber; : > "$claim" ) 2>/dev/null; then
        # File already exists: reclaim only if it is NOT a live foreign claim.
        handoff_claimed_by_other "$claim" && return 1
        : > "$claim" 2>/dev/null || return 1
    fi
    printf '{"handoff":"%s","recipient":"%s","owner":"claude-auto","pid":%s,"host":"%s","claimed_at":"%s"}\n' \
        "$slug" "$cli" "$$" "$(hostname 2>/dev/null)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$claim" 2>/dev/null
    return 0
}

found=0
for dir in "$root"/.ai/handoffs/to-*/open; do
    [ -d "$dir" ] || continue
    cli=$(basename "$(dirname "$dir")")   # to-<cli>
    cli="${cli#to-}"
    # Queue scoping (--only <cli>): skip queues other than the requested one.
    [ -n "$ONLY" ] && [ "$cli" != "$ONLY" ] && continue
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
        slug=$(basename "$f" .md)
        claim="$claim_dir/${cli}__${slug}.claim.json"
        if [ "$MODE" = "exec" ]; then
            # Claim-lock gate: never double-process a handoff a live pane holds.
            if handoff_claimed_by_other "$claim"; then
                echo "SKIP  [$cli] $rel — live claim held by another consumer"
                continue
            fi
            if ! acquire_claim "$claim" "$cli" "$slug"; then
                echo "SKIP  [$cli] $rel — could not acquire claim (raced)"
                continue
            fi
            echo "DISPATCH [$cli] $rel"
            out_tmp=$(mktemp)
            # AI_HANDOFF_DISPATCH=1 marks the spawned CLI's environment so its own
            # SessionStart/Stop dispatch hook no-ops (recursion guard — see header).
            ( cd "$root" && export AI_HANDOFF_DISPATCH=1 && eval "$cmd" ) 2>&1 | tee "$out_tmp"
            rc=${PIPESTATUS[0]}
            echo "---- [$cli] finished (exit $rc) ----"
            # Failure alerting (Tier B — act, then notify): non-zero exit writes a
            # report so a failed headless dispatch is never silent.
            if [ "$rc" -ne 0 ]; then
                ts=$(date -u +%Y%m%d%H%M%S)
                # Filename includes the handoff slug: same-second failures for one
                # CLI must not overwrite each other (bug found by stub-binary test
                # 2026-07-09 — three same-second claude failures collided). $slug is
                # already set above (claim path); reuse it.
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
            # Release the claim: the recipient self-retires the handoff (moves it
            # to done/) or leaves it OPEN/BLOCKED. Either way our lease is over —
            # drop the sidecar so a re-run (or a pane) can reclaim if still OPEN.
            rm -f "$claim"
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
