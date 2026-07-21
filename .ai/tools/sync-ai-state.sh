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
warn() { echo "[sync-ai-state] WARN: $*" >&2; }
err()  { echo "[sync-ai-state] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# Remove a path, tolerating the Windows "Device or resource busy" condition
# that occurs when a dispatched CLI child still holds a handle on the
# snapshot-copy .ai/ directory after exiting. On failure we rename the path
# to a stale name and continue; stale names are cleaned up opportunistically.
safe_rm_rf() {
    local path="$1"
    [ -e "$path" ] || return 0
    local rmerr
    rmerr="$(mktemp)"
    if rm -rf "$path" 2>"$rmerr"; then
        rm -f "$rmerr"
        return 0
    fi
    # Windows lock: rename out of the way so the dispatch can continue.
    if grep -qi "device or resource busy" "$rmerr" 2>/dev/null; then
        local stale
        stale="${path}.stale-$$-$(date -u +%Y%m%d%H%M%S)"
        warn "$path is busy; renaming to $stale for later cleanup"
        mv "$path" "$stale" || { cat "$rmerr" >&2; rm -f "$rmerr"; return 1; }
        rm -f "$rmerr"
        return 0
    fi
    cat "$rmerr" >&2
    rm -f "$rmerr"
    return 1
}

# Opportunistically clean stale directories left by safe_rm_rf. Never fatal.
cleanup_stale_dirs() {
    local parent
    parent="$(dirname "$1")"
    while IFS= read -r d; do
        rm -rf "$d" 2>/dev/null || true
    done < <(find "$parent" -maxdepth 1 -type d -name '.ai.stale-*' 2>/dev/null)
}

# Compute a stable manifest: one line per file, "<sha256>  <rel-path>".
# Output is sorted by path. Files that disappear or become unreadable between
# find and hash (Windows lock/race during concurrent snapshots, antivirus, or
# a CLI child still writing) are retried a few times; any that remain unreadable
# after the retries are skipped with a warning rather than aborting the whole
# snapshot/sync-back.
manifest_for() {
    local dir="$1"
    local tmp_manifest tmp_warnings
    tmp_manifest="$(mktemp)"
    tmp_warnings="$(mktemp)"

    local attempt=0 rc=0
    while [ "$attempt" -lt 5 ]; do
        attempt=$((attempt+1))
        : > "$tmp_manifest"
        : > "$tmp_warnings"
        ( cd "$dir" && while IFS= read -r -d '' f; do
            if [ ! -f "$f" ] || [ ! -r "$f" ]; then
                echo "manifest skipped unreadable file: ${f#./}" >> "$tmp_warnings"
                continue
            fi
            local hash
            hash="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')" || {
                echo "manifest skipped unhashable file: ${f#./}" >> "$tmp_warnings"
                continue
            }
            if [ -z "$hash" ]; then
                echo "manifest skipped empty hash: ${f#./}" >> "$tmp_warnings"
                continue
            fi
            printf '%s  %s\n' "$hash" "${f#./}"
        done < <(find . -type f \
            ! -path "./$MANIFEST_NAME" \
            ! -path "./handoffs/.quarantine/*" \
            ! -path "./activity/archive/*" \
            ! -path "./activity/log.md" \
            -print0 2>/dev/null) | LC_ALL=C sort -k2 > "$tmp_manifest" )
        if [ ! -s "$tmp_warnings" ]; then
            cat "$tmp_manifest"
            rm -f "$tmp_manifest" "$tmp_warnings"
            return 0
        fi
        if [ "$attempt" -lt 5 ]; then
            warn "manifest attempt $attempt skipped some files; retrying after 1s for locks to clear..."
            sleep 1
        fi
    done
    cat "$tmp_warnings" >&2
    cat "$tmp_manifest"
    rm -f "$tmp_manifest" "$tmp_warnings"
}

# snapshot <canonical-ai> <worktree-ai>
cmd_snapshot() {
    local src="$1" dst="$2"
    if command -v cygpath >/dev/null 2>&1; then
        src="$(cygpath -u "$src")"
        dst="$(cygpath -u "$dst")"
    fi
    [ -d "$src" ] || die "canonical .ai/ missing: $src"

    # Self-collision guard (root cause of the 2026-07-21 canonical .ai/
    # deletion incident, handoff 202607211105-diagnose-canonical-ai-deletion.md):
    # this function's very next step is safe_rm_rf "$dst", unconditional. If a
    # caller ever computes a worktree path that collapses onto (or contains)
    # the canonical .ai/ itself -- a bad dirname/basename substitution, a
    # mis-anchored $root from running the dispatcher inside a nested worktree,
    # etc. -- that rm deletes canonical BEFORE tar ever reads from $src. By the
    # time tar fails (because $src is now also gone, or missing), the only copy
    # of the data is already destroyed. Compare resolved realpaths, not string
    # prefixes, so a symlink/junction/relative-path variant can't slip through.
    local real_src real_dst
    real_src="$(cd "$src" 2>/dev/null && pwd -P)" || die "cannot resolve realpath of src: $src"
    if [ -d "$dst" ]; then
        real_dst="$(cd "$dst" 2>/dev/null && pwd -P)" || real_dst=""
        if [ -n "$real_dst" ]; then
            if [ "$real_src" = "$real_dst" ]; then
                die "refusing snapshot: src and dst resolve to the same directory ($real_src) -- this would delete the only copy of the data"
            fi
            case "$real_src/" in
                "$real_dst"/*) die "refusing snapshot: dst ($real_dst) is an ancestor of src ($real_src) -- deleting dst would delete src" ;;
            esac
        fi
    fi

    # Clean up any stale dirs left by a previous Windows lock.
    cleanup_stale_dirs "$dst"

    # Remove any existing worktree .ai/ (junction, dir, stale copy). If a
    # Windows process still holds the dir open, safe_rm_rf renames it out of
    # the way rather than aborting the dispatch.
    safe_rm_rf "$dst"
    mkdir -p "$(dirname "$dst")"

    # Stage into a temp dir next to the target and retry if concurrent writers
    # cause tar to complain. This shortens the critical window and tolerates
    # the brief races that happen when another executor syncs back at the same
    # minute. The final mv atomically swaps the temp dir into place.
    local tmpdst attempt tarerr
    tmpdst="${dst}.tmp-$$"
    safe_rm_rf "$tmpdst"
    mkdir -p "$tmpdst"
    tarerr="$(mktemp)"
    attempt=0
    while [ "$attempt" -lt 3 ]; do
        attempt=$((attempt+1))
        rm -f "$tarerr"
        if tar -C "$src" -cf - . 2>"$tarerr" | tar -C "$tmpdst" -xf - 2>/dev/null; then
            break
        fi
        if grep -q "file changed as we read it" "$tarerr" 2>/dev/null; then
            warn "snapshot tar race on attempt $attempt; retrying..."
            safe_rm_rf "$tmpdst"
            mkdir -p "$tmpdst"
            sleep 1
            continue
        fi
        cat "$tarerr" >&2
        rm -f "$tarerr"
        safe_rm_rf "$tmpdst"
        return 1
    done
    rm -f "$tarerr"
    if ! mv "$tmpdst" "$dst"; then
        safe_rm_rf "$tmpdst"
        return 1
    fi

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

    # B4: tracks whether an entries/ filename collision was hit this run, so
    # the function can signal it via a distinct exit code (2) in addition to
    # the marker file + warn() written at the point of detection. The sync
    # itself still completes (canonical is never left inconsistent), but the
    # caller must be able to tell "completed clean" from "completed with a
    # conflict needing a human" without scraping dark-gray pane text.
    local had_conflict=0

    # Files in new manifest: copy to canonical if new or changed.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local rel new_hash old_hash
        new_hash="${line%%  *}"
        rel="${line#*  }"
        old_hash="$(awk -v r="$rel" '$2==r {print $1}' "$manifest_old" || true)"
        if [ "$old_hash" != "$new_hash" ]; then
            mkdir -p "$(dirname "$canon_ai/$rel")"
            case "$rel" in
                activity/entries/*)
                    # ADR-0010 invariant: no writer ever rewrites another
                    # writer's entry file. Unlike the generic path below
                    # (which trusts the worktree-vs-worktree-snapshot diff
                    # alone and never looks at canonical's current content),
                    # an entries/ path is compared against canonical's
                    # current file, byte-for-byte, before any write.
                    if [ ! -e "$canon_ai/$rel" ] && [ ! -L "$canon_ai/$rel" ]; then
                        cp -a "$wt_ai/$rel" "$canon_ai/$rel"
                        log "sync-back: $rel"
                    elif cmp -s "$wt_ai/$rel" "$canon_ai/$rel"; then
                        : # identical — idempotent re-sync (e.g. retried dispatch), nothing to do
                    else
                        # B3 (2026-07-21, review handoff 202607201755): the
                        # worktree's .ai/ is removed unconditionally at the end
                        # of this function (safe_rm_rf "$wt_ai" below), so
                        # merely warning-and-skipping here permanently loses
                        # the worktree's entry body the instant the worktree is
                        # torn down. Preserve BOTH sides: canonical keeps its
                        # current file untouched (unchanged from before), and
                        # the worktree body is copied aside into canonical as
                        # a distinctly-named conflict file so a human can
                        # reconcile it later instead of it vanishing.
                        local conflict_hash conflict_rel
                        conflict_hash="$(sha256sum "$wt_ai/$rel" | awk '{print $1}' | cut -c1-8)"
                        conflict_rel="${rel%.md}.conflict-${conflict_hash}.md"
                        mkdir -p "$(dirname "$canon_ai/$conflict_rel")"
                        cp -a "$wt_ai/$rel" "$canon_ai/$conflict_rel"
                        # B4: a silent warn() is dark-gray stderr text buried
                        # among dozens of routine "sync-back: <path>" lines in
                        # a pane nobody reads during headless dispatch — not a
                        # guard. Record this refusal in a durable, greppable
                        # marker file in addition to the loud warn below, so
                        # fleet-health / a human auditing canonical .ai/ after
                        # the fact can discover it without having captured the
                        # pane's live output.
                        local marker="$canon_ai/.sync-conflict-${conflict_hash}.marker"
                        {
                            echo "entries/ filename collision at sync-back"
                            echo "canonical: $canon_ai/$rel (kept, unchanged)"
                            echo "worktree copy preserved as: $canon_ai/$conflict_rel"
                            echo "detected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
                        } > "$marker"
                        warn "ENTRY FILENAME COLLISION: $rel differs between canonical and worktree. Canonical kept as-is; worktree body preserved at $conflict_rel. Marker: $(basename "$marker"). This must never happen under normal filename generation -- investigate the collision."
                        had_conflict=1
                    fi
                    ;;
                *)
                    cp -a "$wt_ai/$rel" "$canon_ai/$rel"
                    log "sync-back: $rel"
                    ;;
            esac
        fi
    done < "$manifest_new"

    # Deletion-policy guard (ADR-0016): a handoff may only disappear from
    # open/ or review/ if it is explicitly retired to done/. If a handoff
    # file was in the old snapshot but is missing from the worktree with no
    # matching done/<basename> entry, refuse the sync-back instead of silently
    # deleting canonical history.
    local refused=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        local rel_del old_hash_del
        old_hash_del="${line%%  *}"
        rel_del="${line#*  }"
        case "$rel_del" in
            handoffs/to-*/open/*.md|handoffs/to-*/review/*.md)
                # If it still exists in the worktree, not a deletion.
                if awk -v r="$rel_del" '$2==r {found=1} END {exit !found}' "$manifest_new"; then
                    continue
                fi
                local recipient_del basename_del done_rel
                recipient_del="${rel_del#handoffs/to-}"
                recipient_del="${recipient_del%%/*}"
                basename_del="$(basename "$rel_del")"
                done_rel="handoffs/to-$recipient_del/done/$basename_del"
                # Accept the deletion only if the done/ counterpart exists (in the
                # worktree or already in canonical). Checking the filesystem directly
                # defends against a transient manifest race where the done file is
                # temporarily unreadable while a CLI child is releasing its handle.
                if ! [ -e "$canon_ai/$done_rel" ] && \
                   ! [ -e "$wt_ai/$done_rel" ] && \
                   ! awk -v r="$done_rel" '$2==r {found=1} END {exit !found}' "$manifest_new"; then
                    refused="${refused}  - $rel_del (no matching $done_rel)\n"
                fi
                ;;
        esac
    done < "$manifest_old"
    if [ -n "$refused" ]; then
        echo "REFUSE: sync-back would delete open/review handoff(s) without a done/ counterpart:" >&2
        printf '%b' "$refused" >&2
        echo "Aborting sync-back to prevent data loss." >&2
        return 1
    fi

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

    # Remove worktree .ai/ completely. Tolerate Windows locks by renaming to a
    # stale dir; the next snapshot will clean it up.
    cleanup_stale_dirs "$wt_ai"
    if ! safe_rm_rf "$wt_ai"; then
        warn "could not remove $wt_ai immediately; left for later cleanup"
    fi
    log "removed $wt_ai after sync-back"

    # B4: distinct non-zero exit when an entries/ collision was preserved
    # this run. The sync itself completed successfully (canonical is
    # consistent, nothing was silently lost) -- this is a "needs a human"
    # signal, not a failure, so it is deliberately a different code (2) than
    # the hard-abort deletion-guard's exit 1 above.
    if [ "$had_conflict" -eq 1 ]; then
        err "sync-back completed with an entries/ filename collision preserved as a .conflict-*.md file; see the .sync-conflict-*.marker written in canonical .ai/"
        return 2
    fi
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
