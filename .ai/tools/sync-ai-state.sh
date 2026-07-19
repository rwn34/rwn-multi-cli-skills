#!/usr/bin/env bash
# sync-ai-state.sh — copy/sync the shared .ai/ coordination plane between the
# primary checkout and executor worktrees (snapshot-copy model).
#
# Replaces the old junction/symlink model (ADR-0004) with explicit dispatcher-owned
# copy/sync, removing the reverse-write hazard that let `git clean/reset/worktree
# remove` inside a worktree destroy canonical .ai/ state.
#
# Usage:
#   bash .ai/tools/sync-ai-state.sh snapshot <canonical-.ai> <worktree-.ai>
#       Copy canonical .ai/ into worktree as ordinary files and record a manifest.
#   bash .ai/tools/sync-ai-state.sh sync-back <worktree-dir> <canonical-project-dir>
#       Replay worktree .ai/ changes into canonical .ai/, commit, remove worktree .ai/.
#
# Exit: 0 on success, non-zero on failure.
set -euo pipefail

MANIFEST_NAME=".snapshot-manifest"

log()  { echo "[sync-ai-state] $*"; }
err()  { echo "[sync-ai-state] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# Compute a stable manifest: one line per file, "<sha256>  <rel-path>".
# Output is sorted by path.
manifest_for() {
    local dir="$1"
    ( cd "$dir" && while IFS= read -r -d '' f; do
        printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "${f#./}"
    done < <(find . -type f ! -path "./$MANIFEST_NAME" -print0 2>/dev/null) | LC_ALL=C sort -k2 )
}

# snapshot <canonical-ai> <worktree-ai>
cmd_snapshot() {
    local src="$1" dst="$2"
    if command -v cygpath >/dev/null 2>&1; then
        src="$(cygpath -u "$src")"
        dst="$(cygpath -u "$dst")"
    fi
    [ -d "$src" ] || die "canonical .ai/ missing: $src"

    # Remove any existing worktree .ai/ (junction, dir, stale copy) and recreate.
    rm -rf "$dst"
    mkdir -p "$dst"

    # Copy all files in one stream. The per-file cp loop used earlier was
    # pathologically slow on Windows Git-Bash (likely real-time protection
    # scanning each tiny cp -a invocation) and could hang the dispatcher.
    # .gitkeep files are omitted: they exist only to keep empty queue dirs in
    # git, and the worktree snapshot does not need them (directories are still
    # created; only the empty sentinel files are skipped).
    tar -C "$src" -cf - --exclude='.gitkeep' . | tar -C "$dst" -xf -

    # Record manifest inside the snapshot so it travels with the worktree .ai/.
    manifest_for "$dst" > "$dst/$MANIFEST_NAME"
    log "snapshot copied to $dst"
}

# sync-back <worktree-dir> <canonical-project-dir>
cmd_sync_back() {
    local wt="$1" project="$2"
    if command -v cygpath >/dev/null 2>&1; then
        wt="$(cygpath -u "$wt")"
        project="$(cygpath -u "$project")"
    fi
    local wt_ai="$wt/.ai" canon_ai="$project/.ai"
    local manifest="$wt_ai/$MANIFEST_NAME"

    [ -d "$wt_ai" ] || { log "worktree .ai/ already removed; nothing to sync"; return 0; }
    [ -f "$manifest" ] || die "manifest missing at $manifest; cannot sync safely"
    [ -d "$canon_ai" ] || die "canonical .ai/ missing: $canon_ai"

    # Build a temp working manifest comparison.
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir:-}"' EXIT

    local manifest_old="$tmpdir/manifest-old" manifest_new="$tmpdir/manifest-new"
    cp "$manifest" "$manifest_old"
    manifest_for "$wt_ai" > "$manifest_new"

    # Files in new manifest: copy to canonical if new or changed.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local rel new_hash old_hash
        new_hash="${line%%  *}"
        rel="${line#*  }"
        old_hash="$(awk -v r="$rel" '$2==r {print $1}' "$manifest_old" || true)"
        if [ "$old_hash" != "$new_hash" ]; then
            mkdir -p "$(dirname "$canon_ai/$rel")"
            cp -a "$wt_ai/$rel" "$canon_ai/$rel"
            log "sync-back: $rel"
        fi
    done < "$manifest_new"

    # Files in old manifest but not new -> deletion. Only replay deletions of
    # actual handoff files moving out of open/ or review/ (handoff retirement
    # moves). Never delete .gitkeep files, done/ history, reports, logs, etc.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local rel old_hash canon_hash
        old_hash="${line%%  *}"
        rel="${line#*  }"
        # If the file still exists in the worktree, it was not retired here.
        if awk -v r="$rel" '$2==r {found=1} END {exit !found}' "$manifest_new"; then
            continue
        fi
        case "$rel" in
            handoffs/to-*/open/*.md|handoffs/to-*/review/*.md)
                if [ -e "$canon_ai/$rel" ]; then
                    canon_hash="$(sha256sum "$canon_ai/$rel" | awk '{print $1}')"
                    if [ "$canon_hash" != "$old_hash" ]; then
                        log "sync-back skip delete: $rel (canonical changed since snapshot; not our retirement)"
                        continue
                    fi
                    rm -f "$canon_ai/$rel"
                    log "sync-back removed: $rel (handoff retirement)"
                fi
                ;;
            *)
                # All other deletions (including .gitkeep files, done/ history,
                # reports, logs) are NOT propagated from the worktree snapshot.
                ;;
        esac
    done < "$manifest_old"

    # Commit canonical .ai/ changes. Fail open: if commit fails, warn but do not
    # abort (the changes are already in the working tree; a human can recover).
    if [ -n "$(git -C "$project" status --porcelain -- "$canon_ai" 2>/dev/null || true)" ]; then
        local ts
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git -C "$project" add -- "$canon_ai" >/dev/null 2>&1 || true
        git -C "$project" commit -m "chore(ai): sync shared .ai/ state from executor worktree ($ts)" >/dev/null 2>&1 || \
            log "WARN: could not commit canonical .ai/ changes; they remain in the working tree"
    fi

    # Remove worktree .ai/ completely.
    rm -rf "$wt_ai"
    log "removed $wt_ai after sync-back"
}

# ---------- main ----------
case "${1:-}" in
    snapshot)
        [ "$#" -eq 3 ] || die "Usage: sync-ai-state.sh snapshot <canonical-.ai> <worktree-.ai>"
        cmd_snapshot "$2" "$3"
        ;;
    sync-back)
        [ "$#" -eq 3 ] || die "Usage: sync-ai-state.sh sync-back <worktree-dir> <canonical-project-dir>"
        cmd_sync_back "$2" "$3"
        ;;
    *)
        die "Unknown command: ${1:-}. Use: snapshot | sync-back"
        ;;
esac
