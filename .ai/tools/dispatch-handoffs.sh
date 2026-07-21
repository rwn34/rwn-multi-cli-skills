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
#   bash .ai/tools/dispatch-handoffs.sh                       # dry-run: list what would dispatch
#   bash .ai/tools/dispatch-handoffs.sh --exec                # launch recipient CLIs (all queues)
#   bash .ai/tools/dispatch-handoffs.sh --exec --only claude  # scope to one queue (to-claude)
#   bash .ai/tools/dispatch-handoffs.sh --exec --one          # dispatch exactly one handoff and exit
#   bash .ai/tools/dispatch-handoffs.sh --exec --only opencode --handoff .ai/handoffs/to-opencode/open/YYYYMMDDHMM-slug.md
#                                                            # dispatch exactly that handoff
#   bash .ai/tools/dispatch-handoffs.sh --exec --reuse-dirty  # reuse worktrees on a different branch or with uncommitted non-.ai changes
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
#
# Worktree-per-CLI (ADR-0004 amendment + ADR-0016 snapshot-copy, 2026-07-11/17):
# every dispatched CLI runs inside its OWN git worktree at
# <parent>/.wt/<project>/<cli>/, never in the primary checkout. This closes the
# shared-HEAD race that let two concurrently dispatched CLIs clobber each other's
# working files via `git checkout` (see the ADR amendment's "2026-07-11
# near-miss"). Rules, enforced below:
#   - Worktree creation reuses scripts/wt-bootstrap.sh (single implementation).
#   - An existing healthy worktree is REUSED, never destroyed.
#   - Worktree setup failure => the dispatch for that handoff FAILS (non-zero
#     item, handoff stays OPEN, failure report written). Falling back to the
#     primary checkout is FORBIDDEN — see ensure_cli_worktree()'s contract.
#   - Each dispatch cuts (or reuses) a per-handoff branch `exec/<cli>/<slug>`
#     from a DECLARED base — the repo's default branch (auto-discovered
#     offline-first from origin/HEAD, falling back to origin/main, local main,
#     then HEAD), or the handoff's explicit `Base:` field — never from ambient
#     HEAD. This is a second, independent defect from the shared-HEAD one
#     (see ensure_declared_base_branch()).
#   - The shared .ai/ coordination plane is copied into the worktree as ordinary
#     files before launch (.ai/tools/sync-ai-state.sh snapshot) and synced back
#     to the primary checkout after the CLI exits (sync-ai-state.sh sync-back).
#     There is NO junction/symlink, eliminating the reverse-write hazard that
#     caused the 2026-07-16 canonical .ai/ deletion incident.

set -u

# Prevent any git subcommand from blocking on an interactive credential prompt
# when running headless. A failed fetch is always handled fail-open below.
export GIT_TERMINAL_PROMPT=0

MODE="dry-run"
ONLY=""
HANDOFF=""
REUSE_DIRTY=0
ONE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --exec)        MODE="exec" ;;
        --reuse-dirty) REUSE_DIRTY=1 ;;
        --only)        ONLY="${2:-}"; shift ;;
        --only=*)      ONLY="${1#--only=}" ;;
        --handoff)     HANDOFF="${2:-}"; shift ;;
        --handoff=*)   HANDOFF="${1#--handoff=}" ;;
        --one)         ONE=1 ;;
        *)             echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Track hard dispatch failures that should make --exec exit non-zero so CI,
# fleet-health.sh, and the supervisor can see them. Currently scoped to
# declared-base branch-cut failures per ADR-0004 amendment.
EXEC_FAILED=0

root="$(pwd)"
[ -d "$root/.ai/handoffs" ] || { echo "Run from repo root (no .ai/handoffs found)."; exit 1; }

# S3-3: ensure every discovered recipient queue has open/review/done dirs.
# Missing dirs are auto-created here so handoffs always have somewhere to land.
ensure_queue_dirs() {
    local dir
    shopt -s nullglob
    for dir in "$root"/.ai/handoffs/to-*; do
        [ -d "$dir" ] || continue
        mkdir -p "$dir"/open "$dir"/review "$dir"/done 2>/dev/null || true
    done
}
ensure_queue_dirs

# Fleet Telegram notifications for the HEADLESS path (closes the coverage gap:
# before this, only the PS pane-runner notified — bash-dispatched handoffs were
# silent). Sourced fail-open: if notify.sh is missing/broken, define a no-op so a
# notify call can never abort a dispatch. fleet_notify itself always returns 0 and
# no-ops when the feature is off (unresolved token/chat_id). It shares the throttle
# file .ai/handoffs/.claims/.fleet-notify-throttle.json with notify.ps1 (60s dedup)
# so the two paths never double-send.
# shellcheck source=notify.sh disable=SC1091
. "$root/.ai/tools/notify.sh" 2>/dev/null || true
command -v fleet_notify >/dev/null 2>&1 || fleet_notify() { :; }
project_name="$(basename "$root")"

# The recipient CLI's activity-log identity (mirrors pane-runner.ps1 Get-DefaultOwner).
# Six-actor model: bare names are auto panes; only claude and kimi have a
# cockpit suffix. Cockpit queues are non-dispatchable and exist only for human
# routing.
owner_for() {
    case "$1" in
        claude|claude-auto)              echo "claude" ;;
        claude-cockpit)                  echo "claude-cockpit" ;;
        kimi|kimi-auto|kimai-auto)       echo "kimi" ;;
        kimi-cockpit|kimai-cockpit)      echo "kimi-cockpit" ;;
        kiro|kiro-auto)                  echo "kiro" ;;
        opencode|opencode-auto)          echo "opencode" ;;
        *)                               echo "$1" ;;
    esac
}

# framework_version -> echoes the framework_version field from .ai/.framework-version
# (installed by the framework installer), or "unknown" if missing/unparseable.
framework_version() {
    local vf="$root/.ai/.framework-version"
    if [ -f "$vf" ]; then
        local v
        v="$(sed -n 's/.*"framework_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$vf" 2>/dev/null | head -1)"
        [ -n "$v" ] && { echo "$v"; return 0; }
    fi
    echo "unknown"
}

# Self-heal (gap C3): before selecting/dispatching, move any handoff left in
# open/ but already marked Status:DONE into its sibling done/ dir — a forgotten
# protocol-v3 self-retire. Fail-open: reconcile is exit-0 by contract and any
# hiccup here must never block dispatch (hence the trailing `|| true`).
if [ "$MODE" = "exec" ]; then
    bash "$root/.ai/tools/reconcile-done-handoffs.sh" "$root" || true
fi

# S3-1: cheap encoding assertion + auto-repair for shared-state files. Bad
# encoding makes grep-based history lookups silently lie and git treat the file
# as binary. Fail-open: repair the common cases, warn+notify if repair fails.
check_shared_encoding() {
    local f out norm_out
    # ADR-0010: source of truth is the entry spool. Check README and up to five
    # newest entries; also check the rendered view if it still exists during the
    # transition.
    local files="$root/.ai/handoffs/README.md"
    if [ -f "$root/.ai/activity/log.md" ]; then
        files="$files $root/.ai/activity/log.md"
    fi
    if [ -d "$root/.ai/activity/entries" ]; then
        for f in $(ls -1 "$root/.ai/activity/entries"/*.md 2>/dev/null | tail -5); do
            files="$files $f"
        done
    fi
    for f in $files; do
        [ -f "$f" ] || continue
        out="$(bash "$root/.ai/tools/check-encoding.sh" "$f" 2>&1)" || true
        if [ -n "$out" ]; then
            echo "WARN: $out" >&2
            norm_out="$(bash "$root/.ai/tools/normalize-encoding.sh" "$f" 2>&1)" || true
            if [ -n "$norm_out" ]; then
                echo "WARN: attempted repair: $norm_out" >&2
            fi
            if bash "$root/.ai/tools/check-encoding.sh" "$f" >/dev/null 2>&1; then
                echo "WARN: encoding repaired: $f" >&2
                fleet_notify alert "$project_name" "encoding-repaired" "bash" "kimi-cli" >/dev/null 2>&1 || true
            else
                echo "WARN: encoding repair failed for $f" >&2
                fleet_notify alert "$project_name" "encoding-check" "bash" "kimi-cli" >/dev/null 2>&1 || true
            fi
        fi
    done
}
check_shared_encoding

# Headless invocation per CLI. Verify locally before relying on kimi/kiro forms —
# flags differ across versions (see .ai/cli-map.md § headless invocation).
#
# SECURITY: populates the global argv ARRAY `HEADLESS_ARGV` (exe + args), never a
# command STRING. The prompt embeds $file (the handoff rel path, derived from an
# attacker-controllable filename); as a single array element it is inert data that
# is run via "${HEADLESS_ARGV[@]}" and never re-parsed by the shell. This replaced
# a printf'd string that was executed with `eval` — a filename like `x$(cmd).md`
# ran arbitrary code. Do NOT reintroduce a string form or `eval`. This MUST match
# tools/4ai-panes/pane-runner.ps1 Get-HeadlessCmd (also argv-array form).
headless_cmd() {
    local cli="$1" file="$2"
    local prompt="Process the open handoff at $file per the protocol in .ai/handoffs/README.md. Execute the steps, write an activity-log entry, update the handoff Status, and report."
    case "$cli" in
        # --dangerously-skip-permissions (not --permission-mode acceptEdits):
        # acceptEdits auto-approves ONLY Edit/Write; a Bash call outside
        # .claude/settings.local.json's allow-list (git/mv/rm are NOT on it)
        # was auto-DENIED with no human available headless to approve it —
        # the headless Claude lane was strictly weaker than every other CLI's
        # headless invocation AND weaker than Claude's OWN interactive pane
        # (which already runs --dangerously-skip-permissions). SAFE because
        # permissions and hooks are different layers: this flag bypasses the
        # permission PROMPT only — the PreToolUse guard hooks (cross-CLI dir,
        # sensitive-file, root-file, destructive-cmd) still fire and remain
        # the mechanical floor (F2 handoff, 2026-07-12; verified empirically,
        # see docs/architecture/0005-commit-governance-backstop.md). This
        # MUST match tools/4ai-panes/pane-runner.ps1 Get-HeadlessCmd.
        claude) HEADLESS_ARGV=(claude -p "$prompt" --dangerously-skip-permissions) ;;
        # kimi-code has no --agent-file/--agent flag (verified via `kimi --help`
        # 2026-07-09); prompt-only headless invocation via -p.
        kimi)   HEADLESS_ARGV=(kimi -p "$prompt") ;;
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
        kiro)   HEADLESS_ARGV=(kiro-cli chat --no-interactive --trust-all-tools --agent orchestrator "$prompt") ;;
        # --auto is REQUIRED headless: with edit:"ask" opencode auto-rejects all
        # writes; the framework-guard plugin fires before the permission layer
        # and remains the mechanical lane barrier (verified 2026-07-09).
        # --agent opencode pins the contract-carrying agent (.opencode/contract.md);
        # without it the default build agent runs and never loads the contract
        # (ADR-0001 NOTE 2026-07-09: no dead text — pin the load path).
        opencode) HEADLESS_ARGV=(opencode run --auto --agent opencode "$prompt") ;;
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

# --- Worktree-per-CLI (ADR-0004 amendment, 2026-07-11) ---
#
# Every dispatched CLI runs inside <parent>/.wt/<project>/<cli>/, never the
# primary checkout. WT_BOOTSTRAP resolves relative to $root (the project root)
# rather than this script's location: .ai/ is a Windows directory junction /
# POSIX symlink into the canonical coordination plane, so resolving from
# BASH_SOURCE would follow the junction and land in the wrong checkout's
# scripts/ directory when the dispatcher runs from an executor worktree.
WT_BOOTSTRAP="$root/scripts/wt-bootstrap.sh"

# worktree_path_for <cli> -> echoes the absolute worktree path for that CLI.
# Pure path arithmetic — matches wt-bootstrap.sh's own WT_CONTAINER derivation
# (sibling .wt/<project>/<cli> next to the primary checkout). No side effects.
worktree_path_for() {
    local cli="$1"
    local project_dir parent_dir project_name
    project_dir="$root"
    parent_dir="$(dirname "$project_dir")"
    project_name="$(basename "$project_dir")"
    echo "$parent_dir/.wt/$project_name/$cli"
}

# ensure_cli_worktree <cli> -> 0 + prints the worktree path on success.
# 1 on failure. NEVER prints/returns the primary checkout as a substitute —
# callers MUST treat a non-zero return as "this dispatch cannot proceed", full
# stop. Idempotent: delegates entirely to wt-bootstrap.sh, which reuses an
# existing healthy worktree and never destroys one (see that script's header).
ensure_cli_worktree() {
    local cli="$1"
    local wt_path
    wt_path="$(worktree_path_for "$cli")"

    if [ ! -f "$WT_BOOTSTRAP" ]; then
        echo "ERROR: worktree bootstrap script not found at $WT_BOOTSTRAP" >&2
        return 1
    fi

    # bash scripts/wt-bootstrap.sh <project-dir> <cli> — creates-or-reuses.
    # Its own idempotency guard (git worktree already a valid worktree -> skip)
    # is exactly the "reuse, never destroy" contract this function relies on.
    if ! bash "$WT_BOOTSTRAP" "$root" "$cli" >&2; then
        echo "ERROR: wt-bootstrap.sh failed for cli=$cli (see output above)" >&2
        return 1
    fi

    # Belt-and-suspenders: confirm the path is actually a git worktree before
    # handing it back. wt-bootstrap.sh dies loudly on a non-worktree collision,
    # but re-verify here so a future refactor of that script can't silently
    # regress this contract.
    if ! git -C "$wt_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ERROR: $wt_path exists but is not a usable git worktree" >&2
        return 1
    fi

    echo "$wt_path"
    return 0
}

# snapshot_ai <wt_path> — copy canonical .ai/ into the worktree as ordinary files.
# Uses .ai/tools/sync-ai-state.sh snapshot. Idempotent: re-running refreshes the
# snapshot to match the current canonical state. Returns 0 on success, 1 on failure.
snapshot_ai() {
    local wt_path="$1"
    if ! bash "$root/.ai/tools/sync-ai-state.sh" snapshot "$root/.ai" "$wt_path/.ai" 2>&1; then
        echo "ERROR: could not snapshot canonical .ai/ into $wt_path" >&2
        return 1
    fi
    return 0
}

# sync_back_ai <wt_path> — replay worktree .ai/ changes into canonical .ai/ and
# remove the worktree copy. Mostly fail-open (a sync-back CONTENT failure is
# logged but does not abort dispatch — the canonical .ai/ may still be usable,
# a human can reconcile) EXCEPT for a missing sync-ai-state.sh script, which is
# a signal, not noise (2026-07-21 canonical .ai/ deletion incident trace:
# "bash .../.ai/tools/sync-ai-state.sh: No such file or directory", previously
# swallowed by this function's blanket "|| true" and the run still exited 0).
# A missing script means $root itself is not what the dispatcher thinks it is
# (a mis-anchored root, a worktree whose .ai/ never got a real snapshot, etc.)
# and sync-back cannot safely run at all -- surface that as a hard failure
# instead of silently doing nothing.
sync_back_ai() {
    local wt_path="$1"
    local sync_script="$root/.ai/tools/sync-ai-state.sh"
    if [ ! -f "$sync_script" ]; then
        echo "ERROR: sync_back_ai: $sync_script does not exist -- refusing to no-op silently (this root may be mis-anchored)" >&2
        return 1
    fi
    bash "$sync_script" sync-back "$wt_path" "$root" 2>&1 || true
}

# ensure_declared_base_branch <wt_path> <cli> <slug> <base> -> 0 on success
# (worktree HEAD is now on the per-handoff branch, or on an existing branch
# with the dispatcher's own uncommitted work preserved), 1 on hard failure.
#
# Fixes the SECOND, independent defect from the ADR-0004 amendment: even with
# one worktree per CLI, a branch cut from "whatever HEAD happens to be" can
# entangle one handoff's history with a prior one's (the incident's
# Kimi-off-Kiro's-branch cut). Every dispatch therefore:
#   1. `git fetch origin` for a fresh base (best-effort — network hiccups warn,
#      never abort; a locally-cached ref is still a DECLARED base, just stale).
#   2. Cuts/reuses `exec/<cli>/<slug>` FROM that declared base explicitly.
#   3. Never touches a worktree with pre-existing uncommitted changes on a
#      DIFFERENT branch — reports and lets the caller skip instead of
#      clobbering live work (mirrors wt-bootstrap.sh's own safety posture).
ensure_declared_base_branch() {
    local wt_path="$1" cli="$2" slug="$3" base="$4"
    local branch="exec/$cli/$slug"

    # Uncommitted work already sitting in this worktree, on ANY branch, is
    # never touched by a checkout/branch-create here — that is precisely the
    # class of mutation (`git checkout` reverting on-disk files) the ADR
    # amendment names as the root cause. Report and let the caller decide.
    # Uncommitted work already sitting in this worktree, on ANY branch, is
    # never touched by a checkout/branch-create here — that is precisely the
    # class of mutation (`git checkout` reverting on-disk files) the ADR
    # amendment names as the root cause. Report and let the caller decide.
    #
    # EXCLUDE .ai/** from this check. `.ai` is a SNAPSHOT COPY of the canonical
    # coordination plane into the worktree, populated by snapshot_ai() before
    # each dispatch. It is intentionally mutable (activity log, handoff queues,
    # reports) and is synced back after the CLI exits. Treating its normal churn
    # as "uncommitted work" would make every dispatch spuriously skip the branch
    # cut. This grep is scoped to exactly that known false-positive.
    local current
    current="$(git -C "$wt_path" branch --show-current 2>/dev/null)"
    dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null | grep -v ' \.ai/' || true)"
    if [ -n "$dirty" ]; then
        if [ "${REUSE_DIRTY:-0}" = "1" ]; then
            echo "WARN: $wt_path is dirty (branch '$current', expected '$branch'; uncommitted non-.ai changes) — reusing as-is, not cutting $branch" >&2
            return 0
        fi
        echo "ERROR: $wt_path is dirty (branch '$current', expected '$branch'; uncommitted non-.ai changes) — refusing to reuse; dispatch aborted" >&2
        return 1
    fi

    # Best-effort fetch for a fresh base ref. Fetch from the primary checkout
    # rather than the worktree: worktrees may inherit a relative local remote
    # URL that does not resolve from the worktree path (common in sandbox
    # tests), and the remote-tracking refs are shared anyway.
    if ! git -C "$root" fetch origin >/dev/null 2>&1; then
        echo "WARN: git fetch origin failed in $root — using cached '$base'" >&2
    fi

    # Resolve the base ref in the PRIMARY checkout. Worktrees share
    # remote-tracking refs but NOT local branches; a local 'main' may exist in
    # $root (e.g. sync-ai-state auto-commits advanced it past origin/main) but
    # not in $wt_path. Use the commit SHA for all worktree operations so the
    # branch is cut from the exact declared base regardless of local-branch
    # visibility inside the worktree.
    base_sha="$(git -C "$root" rev-parse --verify --quiet "$base^{commit}" 2>/dev/null || true)"
    if [ -z "$base_sha" ]; then
        echo "ERROR: declared base '$base' does not resolve in $root (no network + no local cache?)" >&2
        return 1
    fi
    if ! git -C "$wt_path" rev-parse --verify --quiet "$base_sha^{commit}" >/dev/null; then
        echo "ERROR: declared base '$base' ($base_sha) is not reachable in $wt_path" >&2
        return 1
    fi

    # Attach HEAD to exec/<cli>/<slug> WITHOUT a checkout. A plain `git
    # checkout` (or `checkout -b`) would rewrite files in the worktree and can
    # entangle concurrent dispatches. symbolic-ref moves HEAD without rewriting
    # a single file; the restore then converges worktree+index onto the branch
    # tip for everything EXCEPT .ai/. .ai/ is a snapshot copy populated by
    # snapshot_ai() before each dispatch. It is intentionally mutable (activity
    # log, handoff queues, reports) and is synced back after the CLI exits.
    # `git restore` with an explicit --source defaults to --no-overlay: files
    # absent on the branch are removed from the worktree too (verified
    # empirically). Keep in lockstep with
    # tools/4ai-panes/pane-runner.ps1 Ensure-DeclaredBaseBranchReal.
    if ! git -C "$wt_path" show-ref --verify --quiet "refs/heads/$branch"; then
        if ! git -C "$wt_path" branch "$branch" "$base_sha" 2>/dev/null; then
            echo "ERROR: could not create branch $branch at $base ($base_sha) in $wt_path" >&2
            return 1
        fi
    fi
    if ! git -C "$wt_path" symbolic-ref HEAD "refs/heads/$branch" 2>/dev/null; then
        echo "ERROR: could not attach HEAD to $branch in $wt_path" >&2
        return 1
    fi
    if ! git -C "$wt_path" restore --source="$branch" --staged --worktree -- . ':!.ai' 2>/dev/null; then
        echo "ERROR: could not sync $wt_path to $branch (excluding .ai/)" >&2
        return 1
    fi
    if ! git -C "$wt_path" restore --source="$branch" --staged -- .ai 2>/dev/null; then
        echo "ERROR: could not sync the .ai/ index entries in $wt_path" >&2
        return 1
    fi
    return 0
}

# header_value <file> <key> -> echoes the value of the first matching key in
# the handoff's status block. The status block is defined as all consecutive
# header lines ("Key: value") at the top of the file, stopping at the first
# `## ` section header. Blank lines and lines without a `Key: value` shape are
# skipped rather than terminating the scan, so real handoffs that put a blank
# line between `# Title` and `Status:` are parsed correctly. Keys are matched
# case-insensitively and trailing CR characters are stripped. This replaces the
# brittle `head -20 | grep` scan (S3-4).
header_value() {
    local file="$1" key="$2"
    awk -v key="$key" '
        BEGIN { k = tolower(key) }
        /^## / { exit }
        /^[[:space:]]*$/ { next }
        {
            line = $0
            sub(/\r$/, "", line)
            pos = index(line, ":")
            if (pos > 0) {
                kpart = substr(line, 1, pos - 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", kpart)
                if (tolower(kpart) == k) {
                    val = substr(line, pos + 1)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                    print val
                    exit
                }
            }
        }
    ' "$file"
}

# evidence_value <file> -> echoes the first token of the Evidence: header,
# lowercased. Empty string if absent or not a recognized value.
evidence_value() {
    local val
    val="$(header_value "$1" Evidence)"
    if [ -n "$val" ]; then
        echo "$val" | awk '{print tolower($1)}'
    fi
}

# observed_in_sha <file> -> echoes the SHA from an Observed-in: <branch>@<sha>
# header. Empty if absent or malformed.
observed_in_sha() {
    local val
    val="$(header_value "$1" Observed-in)"
    if [ -n "$val" ]; then
        # Extract the part after the last '@'.
        echo "${val##*@}"
    fi
}

# gate_satisfied_by <file> -> echoes the Gate-satisfied-by: value, stripped.
gate_satisfied_by() {
    header_value "$1" Gate-satisfied-by
}

# gate_value <file> -> echoes the Gate: value, stripped.
gate_value() {
    header_value "$1" Gate
}

# is_hard_gate <value> -> 0 if the Gate: value names an owner's hard gate that
# must never auto-dispatch, regardless of Gate-satisfied-by. Matching is
# case-insensitive and strips non-alphanumeric characters, then uses
# substring matching so that "Production deploy v2.3.1" still triggers the
# hard-gate rule.
is_hard_gate() {
    local val="${1:-}"
    [ -n "$val" ] || return 1
    local norm
    norm="$(echo "$val" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
    case "$norm" in
        *"productiondeploy"*)        return 0 ;;
        *"publishtoapublicregistry"*) return 0 ;;
        *"tagrelease"*)              return 0 ;;
        *"forcepush"*)               return 0 ;;
        *"destructiveopsonsharedhistory"*) return 0 ;;
        *"gitresethard"*)            return 0 ;;
        *"secrets"*)                 return 0 ;;
        *"productiondata"*)          return 0 ;;
    esac
    return 1
}

# base_for <file> -> echoes the declared base ref for a handoff. Reads an
# If the local `main` branch is strictly ahead of `origin/main`, echo `main`;
# otherwise echo nothing. This keeps dispatch bases aligned with
# Observed-in: main@HEAD when sync-ai-state auto-commits have advanced local
# main past the remote (no push required).
prefer_local_main_if_ahead() {
    local local_main_sha origin_main_sha
    local_main_sha="$(git -C "$root" rev-parse --verify --quiet 'main^{commit}' 2>/dev/null || true)"
    origin_main_sha="$(git -C "$root" rev-parse --verify --quiet 'origin/main^{commit}' 2>/dev/null || true)"
    if [ -n "$local_main_sha" ] && [ -n "$origin_main_sha" ] && \
       [ "$local_main_sha" != "$origin_main_sha" ] && \
       git -C "$root" merge-base --is-ancestor "$origin_main_sha" "$local_main_sha" 2>/dev/null; then
        echo "main"
    fi
}

# optional `Base:` line from the status block (first 20 lines, mirrors the
# Auto:/Risk: scan below); if absent, discovers the repo's default branch
# offline-first so the dispatcher never hardcodes `origin/master`.
# The value may carry trailing annotations (e.g. "origin/main (4df2cbf)" or
# "origin/main # after PR #70"); only the first whitespace-delimited token
# is passed to git, so annotations are ignored but the token itself must still
# resolve.
base_for() {
    local file="$1" base sym candidate
    base="$(header_value "$file" Base | awk '{print $1}')"
    if [ -n "$base" ]; then
        # Validate the explicit base resolves. If it doesn't, fall back to the
        # default branch resolution chain — but only for the historical
        # `origin/master` default; other unresolvable bases remain errors
        # (tested in 4b).
        if git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
            echo "$base"
            return 0
        fi
        if [ "$base" = "origin/master" ]; then
            echo "WARN: explicit Base: origin/master does not resolve; falling back to default branch resolution" >&2
        else
            echo "ERROR: explicit Base: $base does not resolve" >&2
            return 1
        fi
        # fall through to default-branch discovery below
    fi

    # No explicit Base: — discover the repo's default branch. Order of
    # preference, first resolvable wins:
    #   1. Best-effort fetch so cached origin/HEAD and origin/<branch> refs are
    #      as fresh as possible before we choose. A failed fetch is not fatal.
    #   2. Remote default branch head (origin/HEAD), offline first.
    #   3. If origin/HEAD is not cached, best-effort auto-detect over network.
    #   4. origin/main (with local-main-ahead override).
    #   5. Local main.
    #   6. HEAD.
    # Each candidate is validated with `git rev-parse --verify --quiet` so a
    # non-existent ref is skipped, never passed to the branch cut.
    if ! git -C "$root" fetch origin >/dev/null 2>&1; then
        echo "WARN: git fetch origin failed in $root — using cached refs for base resolution" >&2
    fi

    sym="$(git -C "$root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||')"
    if [ -n "$sym" ] && git -C "$root" rev-parse --verify --quiet "$sym^{commit}" >/dev/null 2>&1; then
        # If origin/HEAD points to origin/main but the local main branch is strictly
        # ahead of it, dispatch from local main so Observed-in: main@HEAD and the cut
        # base agree. Otherwise the worktree would be cut behind the evidence.
        if [ "$sym" = "origin/main" ]; then
            if [ -n "$(prefer_local_main_if_ahead)" ]; then
                echo "main"
                return 0
            fi
        fi
        echo "$sym"
        return 0
    fi

    # No cached origin/HEAD. Try to set it from the remote (network allowed),
    # but never fail if the network is unreachable — fall back to the chain.
    git -C "$root" remote set-head origin -a >/dev/null 2>&1 || true
    sym="$(git -C "$root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||')"
    if [ -n "$sym" ] && git -C "$root" rev-parse --verify --quiet "$sym^{commit}" >/dev/null 2>&1; then
        if [ "$sym" = "origin/main" ]; then
            if [ -n "$(prefer_local_main_if_ahead)" ]; then
                echo "main"
                return 0
            fi
        fi
        echo "$sym"
        return 0
    fi

    for candidate in origin/main main HEAD; do
        if git -C "$root" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null 2>&1; then
            if [ "$candidate" = "origin/main" ]; then
                if [ -n "$(prefer_local_main_if_ahead)" ]; then
                    echo "main"
                    return 0
                fi
            fi
            echo "$candidate"
            return 0
        fi
    done

    echo "ERROR: could not resolve a declared base for $file (tried: origin/HEAD auto-detect, origin/main, main, HEAD)" >&2
    return 1
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
# RACE (latent-issue audit #10, MED): the old form created the claim empty with
# noclobber `:>` and filled it with a SEPARATE `printf`, leaving a window where
# the file existed but was 0 bytes — the cross-consumer PS pane-runner reads that
# as UNCLAIMED and double-processes. Now the COMPLETE claim is written to a temp
# file first and published atomically, so the claim name never points at an empty
# file. Mirrors pane-runner.ps1 Write-Claim (temp + atomic rename). Fail-open.
acquire_claim() {
    local claim="$1" cli="$2" slug="$3"
    mkdir -p "$claim_dir" 2>/dev/null
    local tmp="$claim_dir/.${cli}__${slug}.$$.tmp"
    local owner
    owner="$(owner_for "$cli")"
    printf '{"handoff":"%s","recipient":"%s","owner":"%s","pid":%s,"host":"%s","claimed_at":"%s"}\n' \
        "$slug" "$cli" "$owner" "$$" "$(hostname 2>/dev/null)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    # Exclusive publish: a hard link fails if the claim already exists, so two
    # racers can't both win, AND the claim name appears already pointing at the
    # fully-written inode — never a 0-byte window (the noclobber `:>` analog, but
    # with content). Won -> drop the temp name (inode lives on under $claim).
    if ln "$tmp" "$claim" 2>/dev/null; then
        rm -f "$tmp"
        return 0
    fi
    # Publish failed. If NO claim exists, the FS lacks hardlinks (rare) — fall back
    # to an atomic rename, which also never leaves the target empty.
    if [ ! -e "$claim" ]; then
        mv -f "$tmp" "$claim" 2>/dev/null && return 0
        rm -f "$tmp"; return 1
    fi
    # A claim already exists: reclaim only if it is NOT a live foreign claim.
    if handoff_claimed_by_other "$claim"; then
        rm -f "$tmp"
        return 1
    fi
    # Stale claim -> take it over via atomic rename (overwrites; never empty).
    mv -f "$tmp" "$claim" 2>/dev/null || { rm -f "$tmp"; return 1; }
    return 0
}

# Library mode: sourcing with DISPATCH_LIB=1 defines the helper functions
# without running the dispatch body, so unit tests can exercise owner_for(),
# bin_for(), etc. directly.
if [ -n "${DISPATCH_LIB:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

found=0
for to_dir in "$root"/.ai/handoffs/to-*; do
    [ -d "$to_dir" ] || continue
    cli=$(basename "$to_dir")   # to-<cli>
    cli="${cli#to-}"
    # Queue scoping (--only <cli>): skip queues other than the requested one.
    [ -n "$ONLY" ] && [ "$cli" != "$ONLY" ] && continue
    for sub in open review; do
        dir="$to_dir/$sub"
        [ -d "$dir" ] || continue
        for f in "$dir"/*.md; do
            [ -f "$f" ] || continue
            rel="${f#$root/}"
            slug=$(basename "$f" .md)

            # --handoff scoping: if a specific handoff path was requested, skip
            # every other file. Accepts either a project-relative path
            # (.ai/handoffs/to-<cli>/open/...) or just the basename.
            if [ -n "$HANDOFF" ]; then
                case "$HANDOFF" in
                    .ai/handoffs/*)
                        [ "$rel" = "$HANDOFF" ] || continue ;;
                    *)
                        [ "$(basename "$f")" = "$HANDOFF" ] || continue ;;
                esac
            fi

            # Ghost-handoff refusal (belt-and-braces, handoff 202607131035): even
            # though reconcile-done-handoffs.sh already ran at the top of this
            # script and should have retired any open/+done/ duplicate, a ghost
            # that survives reconcile (e.g. this script invoked standalone, or a
            # race with a concurrent writer) must still never be DISPATCHED. Same
            # rule as the reconcile guard: done/ wins.
            dup_done="$to_dir/done/$(basename "$f")"
            if [ -e "$dup_done" ]; then
                echo "SKIP  [$cli] $rel — ghost: duplicate exists at ${dup_done#$root/} (done/ wins, refusing to dispatch)"
                continue
            fi

            # Status block check: dispatch only OPEN handoffs explicitly marked Auto: yes
            auto_val="$(header_value "$f" Auto | tr '[:upper:]' '[:lower:]')"
            status_val="$(header_value "$f" Status | tr '[:upper:]' '[:lower:]')"
            risk_val="$(header_value "$f" Risk | tr '[:upper:]' '[:lower:]')"
            evidence_val="$(evidence_value "$f")"
            [ "$auto_val" = "yes" ] || continue
            [ "$status_val" = "open" ] || continue

            # Evidence gate (protocol v4, ADR-0015): HYPOTHESIS dispatches at Risk
            # A/B with premise-verification as the recipient's first step. HYPOTHESIS
            # capped at Risk A/B; Risk C HYPOTHESIS is a lint error and falls through
            # to the Risk-C gate (which will HOLD without a non-hard Gate:).
            if [ "$evidence_val" = "hypothesis" ] && { [ "$risk_val" = "a" ] || [ "$risk_val" = "b" ]; }; then
                echo "DISPATCH [$cli] $rel — Evidence: HYPOTHESIS at Risk $risk_val; recipient verifies premise"
            fi

            # Risk gate (protocol v2/v4): Risk A/B auto-dispatch by default. Risk C
            # requires an explicit Gate: and Gate-satisfied-by:, unless the Gate: names
            # an owner's hard gate (ADR-0015) — those always HOLD for a cockpit.
            case "$risk_val" in
                a|b) ;;
                c)
                    gate_val="$(gate_value "$f")"
                    if [ -z "$gate_val" ]; then
                        echo "HOLD  [$cli] $rel — Risk C with no Gate: (human relays)"
                        continue
                    fi
                    if is_hard_gate "$gate_val"; then
                        echo "HOLD  [$cli] $rel — Risk C hard gate '$gate_val' requires cockpit, regardless of Gate-satisfied-by"
                        continue
                    fi
                    if [ -n "$(gate_satisfied_by "$f")" ]; then
                        echo "DISPATCH [$cli] $rel — Risk C with non-hard Gate: and satisfied Gate-satisfied-by"
                    else
                        echo "HOLD  [$cli] $rel — Risk C with non-hard Gate: but no Gate-satisfied-by"
                        continue
                    fi
                    ;;
                *)
                    echo "HOLD  [$cli] $rel — Risk C or no Risk field (human relays)"
                    continue
                    ;;
            esac
            found=$((found+1))
            # S2-4: a handoff sent to itself would loop — reject before launching.
            sender_val="$(header_value "$f" Sender)"
            recipient_val="$(header_value "$f" Recipient)"
            if [ -n "$sender_val" ] && [ -n "$recipient_val" ]; then
                s_low="$(echo "$sender_val" | tr '[:upper:]' '[:lower:]')"
                r_low="$(echo "$recipient_val" | tr '[:upper:]' '[:lower:]')"
                if [ "$s_low" = "$r_low" ]; then
                    echo "FAIL  [$cli] $rel — self-addressed handoff (Sender == Recipient: $sender_val); refusing to dispatch" >&2
                    EXEC_FAILED=$((EXEC_FAILED+1))
                    ts=$(date -u +%Y%m%d%H%M%S)
                    report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                    {
                        echo "# Dispatch failure — $cli (self-addressed)"
                        echo ""
                        echo "- Handoff: $rel"
                        echo "- UTC: $ts"
                        echo "- Framework: $(framework_version)"
                        echo "- Sender: $sender_val"
                        echo "- Recipient: $recipient_val"
                        echo "- Stage: status-block validation (S2-4)"
                        echo ""
                        echo "A handoff cannot be sent to itself. Correct the Sender/Recipient fields"
                        echo "or retire this handoff manually. It remains OPEN until a human resolves it."
                    } > "$report"
                    echo "ALERT: dispatch failed — report written to ${report#$root/}"
                    fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                    continue
                fi
            fi
        bin=$(bin_for "$cli")
        if ! command -v "$bin" >/dev/null 2>&1; then
            echo "SKIP  [$cli] $rel — '$bin' not on PATH"
            continue
        fi
        # Populates HEADLESS_ARGV (argv array). $cmd is a HUMAN-READABLE render for
        # logs/reports/dry-run ONLY — it is never executed (execution uses the array).
        headless_cmd "$cli" "$rel" || { echo "SKIP  [$cli] $rel — unknown CLI"; continue; }
        cmd="${HEADLESS_ARGV[*]}"
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
            # Worktree-per-CLI (ADR-0004 amendment): establish (idempotently
            # reuse or create) this CLI's dedicated worktree BEFORE launching.
            # Contract: wt_path is EITHER a real, usable worktree path, OR this
            # branch fails the dispatch outright. There is no third outcome —
            # ensure_cli_worktree() never returns the primary checkout as a
            # substitute, and neither does this call site.
            wt_path="$(ensure_cli_worktree "$cli")"
            wt_rc=$?
            if [ "$wt_rc" -ne 0 ] || [ -z "$wt_path" ]; then
                echo "FAIL  [$cli] $rel — could not establish worktree; refusing to fall back to primary checkout"
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (worktree setup)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Stage: worktree-per-CLI setup (ADR-0004 amendment) — never reached CLI invocation"
                    echo ""
                    echo "Triage: run 'bash $WT_BOOTSTRAP $root $cli' manually to see the failure."
                    echo "The handoff stays OPEN — the dispatcher will retry it on the next --exec run."
                    echo "This dispatch was deliberately NOT run in the primary checkout — falling back"
                    echo "to shared-HEAD execution is the exact bug ADR-0004's amendment forbids."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                rm -f "$claim"
                continue
            fi

            # Declared-base branch cut (second, independent defect from the
            # shared-HEAD one): never leave the worktree on ambient HEAD.
            if ! base="$(base_for "$f")"; then
                echo "FAIL  [$cli] $rel — $base"
                EXEC_FAILED=$((EXEC_FAILED+1))
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (declared-base branch)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Worktree: ${wt_path#$root/}"
                    echo "- Declared base: <unresolvable>"
                    echo "- Stage: declared-base resolution (no origin/HEAD, origin/main, local main, or HEAD resolves)"
                    echo ""
                    echo "Triage: inspect $wt_path by hand (git status/log) before retrying."
                    echo "The handoff stays OPEN — the dispatcher will retry it on the next --exec run."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                rm -f "$claim"
                continue
            fi
            # Observed-in evidence-base check (protocol v4, ADR-0015): normalize the
            # sender's SHA and accept an ancestor of (or equal to) the resolved base.
            # Equality handles the common case; ancestor check keeps the field useful
            # when the base has advanced past the observation. Descendants are rejected
            # because evidence observed ahead of the cut base is not present in the
            # worktree the recipient will run in.
            observed_sha="$(observed_in_sha "$f")"
            if [ -n "$observed_sha" ]; then
                observed_full="$(git -C "$root" rev-parse --verify --quiet "$observed_sha^{commit}" 2>/dev/null || true)"
                if [ -z "$observed_full" ]; then
                    echo "FAIL  [$cli] $rel — Observed-in resolves to unknown commit ($observed_sha)"
                    EXEC_FAILED=$((EXEC_FAILED+1))
                    ts=$(date -u +%Y%m%d%H%M%S)
                    report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                    {
                        echo "# Dispatch failure — $cli (evidence-base unknown commit)"
                        echo ""
                        echo "- Handoff: $rel"
                        echo "- UTC: $ts"
                        echo "- Framework: $(framework_version)"
                        echo "- Worktree: ${wt_path#$root/}"
                        echo "- Resolved base: $base"
                        echo "- Observed-in SHA: $observed_sha"
                        echo "- Stage: evidence-base unknown commit (protocol v4)"
                        echo ""
                        echo "The handoff asserts evidence was observed in commit $observed_sha,"
                        echo "but that commit cannot be resolved. The sender should correct"
                        echo "Observed-in: or re-verify the evidence. The handoff stays OPEN until"
                        echo "corrected or retired manually."
                    } > "$report"
                    echo "ALERT: dispatch failed — report written to ${report#$root/}"
                    fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                    rm -f "$claim"
                    continue
                fi
                base_full="$(git -C "$root" rev-parse --verify --quiet "$base^{commit}" 2>/dev/null || true)"
                if [ -z "$base_full" ]; then
                    echo "FAIL  [$cli] $rel — declared base '$base' does not resolve for Observed-in check"
                    EXEC_FAILED=$((EXEC_FAILED+1))
                    ts=$(date -u +%Y%m%d%H%M%S)
                    report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                    {
                        echo "# Dispatch failure — $cli (evidence-base unresolvable base)"
                        echo ""
                        echo "- Handoff: $rel"
                        echo "- UTC: $ts"
                        echo "- Framework: $(framework_version)"
                        echo "- Worktree: ${wt_path#$root/}"
                        echo "- Resolved base: $base"
                        echo "- Observed-in SHA: $observed_sha"
                        echo "- Stage: evidence-base base resolution (protocol v4)"
                        echo ""
                        echo "The declared dispatch base could not be resolved for the Observed-in"
                        echo "check. The handoff stays OPEN until corrected or retired manually."
                    } > "$report"
                    echo "ALERT: dispatch failed — report written to ${report#$root/}"
                    fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                    rm -f "$claim"
                    continue
                fi
                if [ "$observed_full" != "$base_full" ] && \
                   ! git -C "$root" merge-base --is-ancestor "$observed_full" "$base_full" 2>/dev/null; then
                    echo "FAIL  [$cli] $rel — evidence-base mismatch (Observed-in: $observed_sha [$observed_full], base $base: $base_full; not an ancestor of the cut base)"
                    EXEC_FAILED=$((EXEC_FAILED+1))
                    ts=$(date -u +%Y%m%d%H%M%S)
                    report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                    {
                        echo "# Dispatch failure — $cli (evidence-base mismatch)"
                        echo ""
                        echo "- Handoff: $rel"
                        echo "- UTC: $ts"
                        echo "- Framework: $(framework_version)"
                        echo "- Worktree: ${wt_path#$root/}"
                        echo "- Resolved base: $base"
                        echo "- Resolved base SHA: $base_full"
                        echo "- Observed-in SHA: $observed_sha ($observed_full)"
                        echo "- Stage: evidence-base mismatch (protocol v4)"
                        echo ""
                        echo "The handoff asserts evidence was observed in commit $observed_sha,"
                        echo "but that commit is not an ancestor of the resolved dispatch base."
                        echo "The sender should re-verify the evidence in the current tree or"
                        echo "update Observed-in:. The handoff stays OPEN until corrected or"
                        echo "retired manually."
                    } > "$report"
                    echo "ALERT: dispatch failed — report written to ${report#$root/}"
                    fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                    rm -f "$claim"
                    continue
                fi
            fi
            if ! ensure_declared_base_branch "$wt_path" "$cli" "$slug" "$base"; then
                echo "FAIL  [$cli] $rel — could not establish declared-base branch (base=$base)"
                EXEC_FAILED=$((EXEC_FAILED+1))
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (declared-base branch)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Worktree: ${wt_path#$root/}"
                    echo "- Declared base: $base"
                    echo "- Stage: declared-base branch cut (ADR-0004 amendment) — never reached CLI invocation"
                    echo ""
                    echo "Triage: inspect $wt_path by hand (git status/log) before retrying."
                    echo "The handoff stays OPEN — the dispatcher will retry it on the next --exec run."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                rm -f "$claim"
                continue
            fi
            # Snapshot-copy the canonical .ai/ into the worktree. This MUST happen
            # AFTER ensure_declared_base_branch(): that function restores the
            # worktree from the declared base, and on Windows/MSYS the `':!.ai'`
            # pathspec used to exclude .ai/ from the restore can be mangled. If we
            # snapshot first and the restore later touches .ai/, the worktree .ai/
            # is wiped before the CLI runs (observed as every .ai/ file marked
            # deleted and cross-queue handoffs vanishing). By cutting the branch
            # first and then snapshotting, the canonical .ai/ state always wins.
            if ! snapshot_ai "$wt_path"; then
                echo "FAIL  [$cli] $rel — could not snapshot canonical .ai/ into worktree"
                EXEC_FAILED=$((EXEC_FAILED+1))
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (.ai/ snapshot)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Worktree: ${wt_path#$root/}"
                    echo "- Stage: .ai/ snapshot-copy (ADR-0016) — never reached CLI invocation"
                    echo ""
                    echo "Triage: run 'bash $root/.ai/tools/sync-ai-state.sh snapshot $root/.ai $wt_path/.ai' manually."
                    echo "The handoff stays OPEN — the dispatcher will retry it on the next --exec run."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                rm -f "$claim"
                continue
            fi

            # Verify the dispatched handoff actually arrived in the worktree.
            # If snapshot-copy silently dropped it (e.g. tar race or junction
            # churn), launching the CLI would eventually cause sync-back to
            # delete the canonical open handoff (ADR-0016 deletion-policy bug).
            if [ ! -f "$wt_path/$rel" ]; then
                echo "FAIL  [$cli] $rel — handoff file missing from worktree after .ai/ snapshot" >&2
                EXEC_FAILED=$((EXEC_FAILED+1))
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (.ai/ snapshot incomplete)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Worktree: ${wt_path#$root/}"
                    echo "- Stage: .ai/ snapshot-copy verification (ADR-0016) — never reached CLI invocation"
                    echo ""
                    echo "Triage: the dispatcher snapshot-copied canonical .ai/ into the worktree,"
                    echo "but the dispatched handoff file is not present. Inspect the snapshot manifest:"
                    echo "  $wt_path/.ai/.snapshot-manifest"
                    echo "This is usually caused by a concurrent modification, a tar race during"
                    echo "snapshot, or a stale .ai/ directory in the worktree. The handoff stays OPEN."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$(owner_for "$cli")" || true
                rm -f "$claim"
                continue
            fi

            # Remove any stale pane-runner global claim that snapshot copied into
            # the worktree. The claim belongs to a previous pane-runner process
            # (pid may be dead) and must not be visible to the new headless CLI,
            # which determines identity from AI_HANDOFF_AUTO, not from sidecars.
            rm -f "$wt_path/.ai/.claim-$cli.json" "$wt_path/.ai/.heartbeat-$cli.json" 2>/dev/null || true

            echo "DISPATCH [$cli] $rel — worktree: ${wt_path#$root/} branch: exec/$cli/$slug (base: $base)"
            owner=$(owner_for "$cli")
            # PICKED notify — right as we commit to dispatching, before launch.
            # Fail-open: a notify error must never abort a dispatch.
            fleet_notify picked "$project_name" "$slug" "$cli" "$owner" || true
            out_tmp=$(mktemp)
            # AI_HANDOFF_DISPATCH=1 marks the spawned CLI's environment so its own
            # SessionStart/Stop dispatch hook no-ops (recursion guard — see header).
            # Native argv invocation ("${HEADLESS_ARGV[@]}"), NOT eval on a string —
            # the handoff path is an inert argv element, never re-parsed by the shell.
            #
            # cd "$wt_path" (NOT "$root"): this is the worktree-per-CLI fix itself —
            # every dispatched CLI runs in its OWN working tree, never the primary
            # checkout, so a concurrent dispatch's `git checkout` can never revert
            # this session's on-disk files (ADR-0004 amendment).
            # S3-1 root cause: force UTF-8 locale so any bash subprocess the CLI
            # spawns writes em-dashes and other non-ASCII chars as UTF-8, not cp1252.
            ( cd "$wt_path" && export AI_HANDOFF_DISPATCH=1 && export AI_HANDOFF_AUTO=1 && export LC_ALL='C.UTF-8' && export LANG='C.UTF-8' && "${HEADLESS_ARGV[@]}" ) 2>&1 | tee "$out_tmp"
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
                    echo "- Framework: $(framework_version)"
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
                # ALERT notify (Tier B — act, then notify). Fail-open.
                fleet_notify alert "$project_name" "$slug" "$cli" "$owner" || true
            else
                # DONE notify — handoff dispatched to completion (exit 0). The
                # recipient self-retires (moves to done/); we just announce it.
                # Fail-open.
                fleet_notify done "$project_name" "$slug" "$cli" "$owner" || true
            fi
            rm -f "$out_tmp"

            # Sync the worktree's .ai/ changes back to canonical and remove the
            # worktree copy. Mostly fail-open (content-level sync-back errors are
            # logged but do not abort dispatch; the recipient's changes are
            # already in the canonical working tree or recoverable from the
            # worktree) EXCEPT a missing sync-ai-state.sh script, which
            # sync_back_ai() now refuses to no-op on (see its definition) —
            # write a dispatch-failure report so this is never silent again.
            if ! sync_back_ai "$wt_path"; then
                echo "FAIL  [$cli] $rel — sync-back could not run (see error above)" >&2
                EXEC_FAILED=$((EXEC_FAILED+1))
                ts=$(date -u +%Y%m%d%H%M%S)
                report="$root/.ai/reports/dispatch-failure-$ts-$cli-$slug.md"
                {
                    echo "# Dispatch failure — $cli (sync-back script missing)"
                    echo ""
                    echo "- Handoff: $rel"
                    echo "- UTC: $ts"
                    echo "- Framework: $(framework_version)"
                    echo "- Worktree: ${wt_path#$root/}"
                    echo "- Stage: sync-back (after CLI invocation) — the CLI already ran; only the .ai/ sync-back failed"
                    echo ""
                    echo "Triage: \$root/.ai/tools/sync-ai-state.sh did not exist when sync-back ran. This"
                    echo "usually means \$root was not the expected checkout (e.g. dispatch-handoffs.sh was"
                    echo "invoked from inside an executor worktree instead of the primary checkout). Inspect"
                    echo "$wt_path by hand; its .ai/ may still hold the recipient's changes uncommitted."
                } > "$report"
                echo "ALERT: dispatch failed — report written to ${report#$root/}"
                fleet_notify alert "$project_name" "$slug" "$cli" "$owner" || true
            fi

            # Release the claim: the recipient self-retires the handoff (moves it
            # to done/) or leaves it OPEN/BLOCKED. Either way our lease is over —
            # drop the sidecar so a re-run (or a pane) can reclaim if still OPEN.
            rm -f "$claim"

            # --one mode: dispatch a single handoff and exit. This lets a
            # supervisor apply a per-handoff timeout instead of timing out a
            # long invocation that processes an entire queue.
            if [ "$ONE" = "1" ]; then
                break 3
            fi
        else
            echo "WOULD DISPATCH [$cli] $rel"
            echo "    $cmd"
            # In dry-run --one mode, report the single selected handoff and stop.
            if [ "$ONE" = "1" ]; then
                break 3
            fi
        fi
        done
    done
done

if [ "$found" -eq 0 ]; then
    echo "No open/review handoffs marked 'Auto: yes'."
fi
[ "$MODE" = "dry-run" ] && [ "$found" -gt 0 ] && echo "(dry-run — pass --exec to launch)"
if [ "$MODE" = "exec" ] && [ "$EXEC_FAILED" -gt 0 ]; then
    echo "ERROR: $EXEC_FAILED declared-base branch-cut failure(s) — see reports above" >&2
    exit 1
fi
exit 0
