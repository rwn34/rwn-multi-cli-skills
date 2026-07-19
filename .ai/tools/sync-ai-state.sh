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

# Merge a worktree activity/log.md into the canonical log. If the worktree
# dropped canonical history (executor overwrite, encoding round-trip, etc.),
# recover by prepending only the genuinely new entries. This keeps the shared
# activity ledger append-only.
merge_activity_log() {
    local canon="$1" wt="$2"
    if [ ! -r "$canon" ]; then
        cat "$wt"
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        python - "$canon" "$wt" <<'PY'
import sys
canon_path, wt_path = sys.argv[1], sys.argv[2]

def parse(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except Exception:
        return []
    entries = []
    current = []
    for line in text.splitlines():
        if line.startswith('## '):
            if current:
                entries.append('\n'.join(current))
            current = [line]
        else:
            current.append(line)
    if current:
        entries.append('\n'.join(current))
    return entries

canon_entries = parse(canon_path)
wt_entries = parse(wt_path)
canon_headers = {e.split('\n')[0] for e in canon_entries}
wt_headers = {e.split('\n')[0] for e in wt_entries}
missing = canon_headers - wt_headers
if missing:
    print(
        f"LOG-MERGE WARN: worktree activity/log.md is missing {len(missing)} canonical entry header(s); merging to preserve history",
        file=sys.stderr,
    )
new_entries = [e for e in wt_entries if e.split('\n')[0] not in canon_headers]
out = '\n\n'.join(new_entries + canon_entries)
if out and not out.endswith('\n'):
    out += '\n'
sys.stdout.write(out)
PY
    else
        # Pure-awk fallback for hosts without python. Same semantics: prepend
        # worktree entries whose headers are not already in canonical, then emit
        # the full canonical log.
        awk -v canon="$canon" -v wt="$wt" '
            function read_file(path,    line, h, in_e, body, n) {
                n = 0
                while ((getline line < path) > 0) {
                    if (line ~ /^## /) {
                        if (in_e) { entries[h] = body; order[++n] = h }
                        h = line; in_e = 1; body = ""
                    } else if (in_e) {
                        body = body line "\n"
                    }
                }
                if (in_e) { entries[h] = body; order[++n] = h }
                close(path)
                return n
            }
            BEGIN {
                n_canon = read_file(canon)
                for (i = 1; i <= n_canon; i++) {
                    canon_headers[order[i]] = 1
                    delete order[i]
                }
                n_wt = read_file(wt)
                for (i = 1; i <= n_wt; i++) {
                    h = order[i]
                    if (!canon_headers[h]) {
                        print h
                        printf "%s", entries[h]
                    }
                    delete order[i]
                }
                n_canon = read_file(canon)
                for (i = 1; i <= n_canon; i++) {
                    h = order[i]
                    print h
                    printf "%s", entries[h]
                }
            }
        '
        # TODO: warn on truncation in awk fallback if needed.
    fi
}

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
            if [ "$rel" = "activity/log.md" ]; then
                merge_activity_log "$canon_ai/$rel" "$wt_ai/$rel" > "$canon_ai/$rel.merge-tmp"
                mv "$canon_ai/$rel.merge-tmp" "$canon_ai/$rel"
            else
                cp -a "$wt_ai/$rel" "$canon_ai/$rel"
            fi
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
