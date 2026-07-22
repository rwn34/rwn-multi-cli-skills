#!/usr/bin/env bash
# install-template.sh — copy the multi-CLI AI coordination framework into an
# existing project and adapt it.
#
# Usage: bash scripts/install-template.sh <target-dir> [--dry-run]
# See scripts/README.md for details. Referenced from .ai/sync.md.
#
# Requirements: bash, git, sed, awk, find, diff. python3 is optional — only used
# to merge an existing .mcp.json (absent → plain-text write, no deps needed).
# Git Bash (Windows) + Linux/macOS compatible. POSIX-ish bash, no mapfile/readarray.

set -euo pipefail

# ---------- constants ----------
MARKER="# ADDED BY install-template.sh"
BRANCH="ai-template-install"
ROLLBACK_FILE=".ai-install-rollback-point.txt"
# Phase A: framework version stamped into .ai/.framework-version on install.
# Resolved at runtime from tools/multi-cli-install/package.json (SSOT) once the
# template dir is known; this literal is only the fallback if that file is unreadable.
FRAMEWORK_VERSION="0.0.53"

# ---------- globals set later ----------
TEMPLATE_DIR=""
TEMPLATE_SHA=""
TARGET=""
DRY_RUN=0
MANIFEST=""   # path to a temp file tracking changed paths (relative to TARGET)
ORIGINAL_BRANCH=""   # target's branch at install time (main/master/etc.)
INTERACTIVE=0 # 1 = prompt for agent commands and merge confirmation
AUTO_MERGE=1  # 1 = auto-merge ai-template-install into ORIGINAL_BRANCH after commit
AUTO_MERGE_EXPLICIT=0 # set by --merge/--no-merge so --interactive doesn't override an explicit choice
AUTO_COMMIT_DIRTY=1 # 1 = auto-commit uncommitted changes before installing
# A4: 1 when re-running on an already-onboarded project (.ai/.framework-version
# present). In update mode we preserve accumulated cross-CLI state (activity log,
# in-flight handoffs, reports) instead of wiping it back to the empty template.
UPDATE_MODE=0
AI_STASH_DIR=""      # mktemp dir holding stashed .ai state across the .ai copy
LOCAL_STASH_DIR=""   # mktemp dir holding gitignored per-CLI local state across the .claude copy

# ---------- logging ----------
log()  { echo "[install] $*"; }
warn() { echo "[install] WARN: $*" >&2; }
err()  { echo "[install] ERROR: $*" >&2; }

die() {
  err "$*"
  if [ -n "${TARGET:-}" ] && [ -d "${TARGET:-}/.git" ]; then
    err "Install branch left intact for inspection. To roll back:"
    err "  cd \"$TARGET\" && git checkout - && git branch -D $BRANCH"
  fi
  exit 1
}

run() {
  # Execute or echo based on DRY_RUN.
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: $*"
  else
    log "RUN: $*"
    eval "$@"
  fi
}

# ---------- help ----------
usage() {
  cat <<'EOF'
install-template.sh — install the multi-CLI AI framework into an existing project.

Usage:
  bash scripts/install-template.sh <target-dir> [--dry-run] [--interactive] [--no-merge] [--no-auto-commit]

Arguments:
  <target-dir>   Absolute or relative path to the target project.

Options:
  --dry-run      Print planned actions without touching the target.
  --interactive, -i  Prompt for agent-command customization and ask before
                     merging the install branch. Default is fully automatic.
  --no-merge     Leave the install branch unmerged; print manual merge
                 instructions instead.
  --no-auto-commit   Abort on a dirty working tree instead of auto-committing
                     existing changes as a WIP.
  --help, -h     Show this help and exit.

What it does (6 phases):
  0. Pre-flight: verify target repo, auto-commit any dirty changes as WIP,
     record rollback SHA, create branch 'ai-template-install'.
  1. Copy framework files (.ai/, .claude/, .kimi/, .kiro/, .archive/,
     CLAUDE.md, AGENTS.md, ADR, CI workflow, .codegraph/config.json).
  2. Sanitize template state (reset activity log, clear handoffs/reports).
  3. Reconcile conflicts (merge .gitignore, create/merge .mcp.json codegraph
     server, detect language, amend ADR + uncomment matching patterns in
     root-guard hooks).
  4. Tailor agent configs (uses suggested defaults automatically; --interactive
     to customize).
  5. Verify (hook tests + SSOT drift) and commit on the install branch.
  6. Merge the install branch back to the original branch and clean up.

By default the script is fully automatic: it commits dirty changes as WIP,
merges automatically, and accepts suggested test/build/lint commands. If a
merge fails (e.g. conflicts), the install branch is left intact.
EOF
}

# ---------- arg parsing ----------
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
  esac
done

if [ "$#" -lt 1 ]; then
  usage
  die "Missing <target-dir> argument."
fi

TARGET="$1"
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --interactive|-i) INTERACTIVE=1 ;;
    --merge|-m) AUTO_MERGE=1; AUTO_MERGE_EXPLICIT=1 ;;
    --no-merge|--no-auto-merge) AUTO_MERGE=0; AUTO_MERGE_EXPLICIT=1 ;;
    --no-auto-commit) AUTO_COMMIT_DIRTY=0 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown arg: $1 (see --help)" ;;
  esac
  shift
done

# ---------- resolve template dir (script's own repo root) ----------
SCRIPT_PATH="${BASH_SOURCE[0]}"
# Resolve to absolute
case "$SCRIPT_PATH" in
  /*|?:*|?:\\*) ABS_SCRIPT="$SCRIPT_PATH" ;;
  *) ABS_SCRIPT="$(pwd)/$SCRIPT_PATH" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$ABS_SCRIPT")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$TEMPLATE_DIR" ] && die "Could not locate template git root from $SCRIPT_DIR"
TEMPLATE_SHA="$(cd "$TEMPLATE_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# ---------- resolve framework version (SSOT: tools/multi-cli-install/package.json) ----------
PKG_JSON="$TEMPLATE_DIR/tools/multi-cli-install/package.json"
PKG_VERSION=""
if [ -f "$PKG_JSON" ]; then
  PKG_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PKG_JSON" | head -n 1 || true)"
fi
if [ -n "$PKG_VERSION" ]; then
  FRAMEWORK_VERSION="$PKG_VERSION"
else
  warn "Could not read version from $PKG_JSON — falling back to $FRAMEWORK_VERSION"
fi

log "Template dir: $TEMPLATE_DIR (sha: $TEMPLATE_SHA)"
log "Framework version: $FRAMEWORK_VERSION"
log "Target dir:   $TARGET"
[ "$DRY_RUN" -eq 1 ] && log "Mode: DRY-RUN (no writes)"

# ---------- validate target ----------
[ -d "$TARGET" ] || die "Target is not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ -d "$TARGET/.git" ] || die "Target is not a git repo (no .git): $TARGET"

# refuse installing into the template itself
if [ "$TARGET" = "$TEMPLATE_DIR" ]; then
  die "Refusing to install template into itself ($TARGET)."
fi

# ---------- manifest for precise git add ----------
MANIFEST="$(mktemp -t install-template-manifest.XXXXXX 2>/dev/null || mktemp)"
trap 'rm -f "$MANIFEST" 2>/dev/null || true' EXIT

track() {
  # Record a relative path (relative to TARGET) as touched.
  echo "$1" >> "$MANIFEST"
}

# Exclude framework-managed ephemeral sidecars from the dirty-tree check. These
# files are created at runtime by the pane-runner / supervisor (heartbeats,
# claim locks, quarantine markers) and are already gitignored by the current
# template, but projects installed from older templates may lack the rules. If
# we did not exclude them here, the installer's own runtime artifacts would
# block every update. We use .git/info/exclude so the working tree is not
# dirtied by this pre-flight step itself; merge_gitignore() later persists the
# rules in the committed .gitignore.
exclude_runtime_sidecars() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  local exclude="$TARGET/.git/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  [ -f "$exclude" ] || touch "$exclude"

  local added=0
  local line
  for line in \
    ".ai/.heartbeat-*.json" \
    ".ai/.claim-*.json" \
    ".ai/handoffs/.claims/*" \
    ".ai/handoffs/.quarantine/*"; do
    if ! grep -Fxq "$line" "$exclude" 2>/dev/null; then
      # trailing newline safety
      [ -n "$(tail -c 1 "$exclude" 2>/dev/null)" ] && echo "" >> "$exclude"
      echo "$line" >> "$exclude"
      added=$((added + 1))
    fi
  done
  if [ "$added" -gt 0 ]; then
    log "Excluded $added ephemeral framework sidecar pattern(s) from dirty-check via .git/info/exclude."
  fi
}

# When the installer is launched from inside a now-removed executor worktree,
# the parent shell may have GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR set to the
# missing worktree gitdir. Those variables override the target repo's .git and
# make every target git command fail with "not a git repository". Sanitize them
# as the first thing after entering the target directory.
sanitize_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_PREFIX
}

# normalize_default_branch_to_main — ensure the target repo uses `main` as its
# default branch. If the repo still uses `master`, rename it locally to `main`
# (or create `main` from `master` if the current branch is not master) and try
# to update origin/HEAD so future dispatcher base resolution never relies on
# `origin/master`. This is idempotent: a repo already on `main` is untouched.
normalize_default_branch_to_main() {
  local current
  current="$(git -C "$TARGET" symbolic-ref --short HEAD 2>/dev/null || true)"

  # Case 1: we are currently on `master` -> rename it to `main` in-place.
  if [ "$current" = "master" ]; then
    if git -C "$TARGET" rev-parse --verify --quiet main >/dev/null 2>&1; then
      # Both exist and we're on master. This is a weird state; switch to main
      # and leave master for manual cleanup rather than overwriting.
      warn "Both 'master' and 'main' exist and current branch is 'master'. Switching to 'main' but NOT deleting 'master'."
      git -C "$TARGET" checkout -q main || warn "Could not switch to 'main'."
    else
      git -C "$TARGET" branch -m master main
      log "Renamed current branch 'master' -> 'main'."
    fi
    current="$(git -C "$TARGET" symbolic-ref --short HEAD 2>/dev/null || true)"
  fi

  # Case 2: `master` still exists but `main` does not -> create `main` from the
  # tip of `master`, then delete `master`. Safe even if we're on a feature
  # branch because we only create/delete refs, not the working tree.
  if git -C "$TARGET" rev-parse --verify --quiet master >/dev/null 2>&1 && \
     ! git -C "$TARGET" rev-parse --verify --quiet main >/dev/null 2>&1; then
    local master_sha
    master_sha="$(git -C "$TARGET" rev-parse master)"
    git -C "$TARGET" branch main "$master_sha"
    log "Created 'main' from existing 'master' ($master_sha)."
    git -C "$TARGET" branch -D master
    log "Deleted local 'master' branch."
  fi

  # Update the installer's merge target if it still references the now-removed
  # `master` branch.
  if [ "${ORIGINAL_BRANCH:-}" = "master" ]; then
    ORIGINAL_BRANCH="main"
  fi

  # Case 3: origin/HEAD still points to origin/master -> try to point it at
  # origin/main. This is best-effort: if the remote truly has no main ref yet,
  # we do not fail the install.
  local origin_head
  origin_head="$(git -C "$TARGET" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||' || true)"
  if [ "$origin_head" = "origin/master" ]; then
    git -C "$TARGET" remote set-head origin -a >/dev/null 2>&1 || true
    origin_head="$(git -C "$TARGET" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||' || true)"
    if [ "$origin_head" = "origin/master" ] && \
       git -C "$TARGET" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
      git -C "$TARGET" remote set-head origin main >/dev/null 2>&1 || true
      log "Updated origin/HEAD -> origin/main."
    fi
  fi

  # Case 4: if the GitHub remote still has `master` as its default branch,
  # rename it to `main` via the GitHub API. This closes the remaining hole
  # where fresh clones of the repo keep fetching `origin/master`.
  normalize_remote_default_branch_to_main
}

# github_owner_repo <remote-name> -> echoes "owner/repo" for a GitHub remote URL,
# or empty string if the remote is missing or not a github.com URL. Supports both
# HTTPS and SSH styles, with or without a trailing ".git".
github_owner_repo() {
  local remote_name="${1:-origin}"
  local url
  url="$(git -C "$TARGET" remote get-url "$remote_name" 2>/dev/null || true)"
  [ -n "$url" ] || return 0
  case "$url" in
    https://github.com/*|http://github.com/*|git@github.com:*)
      # Strip protocol, auth, and trailing .git.
      echo "$url" | sed -E 's#^(https?://[^/]+/|git@github.com:)##; s/\.git$//'
      ;;
  esac
}

# normalize_remote_default_branch_to_main — best-effort GitHub API rename of the
# remote default branch from `master` to `main`. Requires `gh` CLI and auth.
# Never fails the install: if `gh` is missing, unauthenticated, or the remote is
# not GitHub, the function logs a warning and returns.
normalize_remote_default_branch_to_main() {
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found; skipping remote default-branch check. Install gh and rerun if you want GitHub's default branch flipped to 'main'."
    return 0
  fi

  local owner_repo
  owner_repo="$(github_owner_repo origin)"
  [ -n "$owner_repo" ] || return 0

  local default_branch
  default_branch="$(gh api "repos/$owner_repo" --jq '.default_branch' 2>/dev/null || true)"
  [ -n "$default_branch" ] || {
    warn "Could not read default branch for GitHub repo $owner_repo (gh not authenticated or no network). Skipping remote rename."
    return 0
  }

  if [ "$default_branch" = "main" ]; then
    log "GitHub remote $owner_repo already has default branch 'main'."
    return 0
  fi

  if [ "$default_branch" != "master" ]; then
    warn "GitHub remote $owner_repo has unexpected default branch '$default_branch'; leaving it alone."
    return 0
  fi

  log "Renaming GitHub default branch 'master' -> 'main' for $owner_repo..."
  if gh api -X PATCH "repos/$owner_repo" -f default_branch=main >/dev/null 2>&1; then
    log "GitHub default branch renamed to 'main'."
  else
    warn "Could not rename GitHub default branch for $owner_repo. You may need to do it manually in the repo settings."
  fi
}

# recover_original_branch — when the target is currently on the install branch
# (e.g. a previous install/update left it there), figure out which branch we
# should merge back into and delete the install branch from. Order:
#   1. .ai-install-rollback-point.txt SHA -> branch containing it (not install branch)
#   2. git reflog -> branch we were on before the most recent checkout to install branch
#   3. main / master fallback
recover_original_branch() {
  local candidate=""

  # 1. Rollback file contains the HEAD SHA of the original branch at install time.
  if [ -f "$TARGET/$ROLLBACK_FILE" ]; then
    local rollback_sha
    rollback_sha="$(head -n 1 "$TARGET/$ROLLBACK_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -n "$rollback_sha" ]; then
      # Prefer main if it contains the SHA, then master, then any other branch.
      for probe in main master; do
        if git -C "$TARGET" rev-parse --verify "$probe" >/dev/null 2>&1 && \
           git -C "$TARGET" merge-base --is-ancestor "$rollback_sha" "$probe" 2>/dev/null; then
          candidate="$probe"
          break
        fi
      done
      if [ -z "$candidate" ]; then
        candidate="$(git -C "$TARGET" branch --contains "$rollback_sha" --format='%(refname:short)' 2>/dev/null | grep -v "^$BRANCH$" | head -n 1 || true)"
      fi
    fi
  fi

  # 2. Reflog: "checkout: moving from <old> to <new>" records. Find the most
  # recent move onto the install branch and return the source branch.
  if [ -z "$candidate" ] && [ -f "$TARGET/.git/logs/HEAD" ]; then
    candidate="$(git -C "$TARGET" reflog --pretty=format:'%gs' 2>/dev/null \
      | grep -E "^checkout: moving from .+ to $BRANCH\b" \
      | head -n 1 \
      | sed -E "s/^checkout: moving from (.+) to $BRANCH\b.*$/\1/" \
      || true)"
    # If the recovered branch is itself the install branch, ignore it.
    [ "$candidate" = "$BRANCH" ] && candidate=""
  fi

  # 3. Fallback to main or master.
  if [ -z "$candidate" ]; then
    if git -C "$TARGET" rev-parse --verify main >/dev/null 2>&1; then
      candidate="main"
    elif git -C "$TARGET" rev-parse --verify master >/dev/null 2>&1; then
      candidate="master"
    fi
  fi

  echo "$candidate"
}

# Remove any nested .git file or directory that cp -R copied from a source
# directory. Source framework dirs (.ai, .claude, .kimi, .kiro, .opencode)
# should never contain git repos, but when the installer runs from a worktree
# whose per-CLI dirs are junctions/symlinks, a nested git worktree can be
# present (e.g. .claude/worktrees/<name>/.git). If left in place, `git add -A`
# stages it as a submodule gitlink and corrupts the target repo.
strip_nested_git() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  local found=0
  local g
  # -prune avoids recursing into matched .git dirs; -mindepth 1 keeps us from
  # removing the target repo root .git if someone accidentally passed it.
  while IFS= read -r -d '' g; do
    rm -rf "$g"
    log "Removed nested git entry from copied tree: ${g#$TARGET/}"
    found=1
  done < <(find "$dir" -mindepth 1 -name ".git" -print0 2>/dev/null)
  [ "$found" -eq 1 ] || true
}

# ==========================================================================
# PHASE 0 — Pre-flight
# ==========================================================================
phase0() {
  log "=== Phase 0: pre-flight ==="
  cd "$TARGET"
  sanitize_git_env

  # A4: detect update vs fresh install BEFORE any copy touches .ai. An existing
  # .ai/.framework-version means this project was already onboarded — preserve its
  # accumulated cross-CLI state (activity log, in-flight handoffs, reports) rather
  # than clobbering it with the template's empty .ai.
  if [ -f "$TARGET/.ai/.framework-version" ]; then
    UPDATE_MODE=1
    log "=== Update mode: preserving .ai state (existing .ai/.framework-version found) ==="
  else
    UPDATE_MODE=0
    log "=== Fresh install: no .ai/.framework-version marker found ==="
  fi

  # Allow the install to proceed even when the only "dirty" files are framework
  # runtime sidecars that the project is missing .gitignore rules for.
  exclude_runtime_sidecars

  # Use --untracked-files=all so heartbeat files inside a brand-new .ai/ dir are
  # listed individually and can be filtered out.
  local status
  status="$(git status --porcelain --untracked-files=all | grep -vE '^.. \.ai/\.heartbeat-.*\.json$|^.. \.ai/\.claim-.*\.json$|^.. \.ai/handoffs/\.claims/|^.. \.ai/handoffs/\.quarantine/' || true)"
  if [ -n "$status" ]; then
    if [ "$AUTO_COMMIT_DIRTY" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
      log "Working tree has uncommitted changes; auto-committing as WIP before install."
      if ! git add -A || ! git commit --no-verify -m "chore: auto-commit pre-framework-install state [template $TEMPLATE_SHA]"; then
        err "Could not auto-commit existing changes. Commit or stash them manually and retry."
        echo "$status" >&2
        die "Aborting."
      fi
      log "Auto-committed existing changes."
    else
      err "Target working tree is dirty. Commit or stash first."
      echo "$status" >&2
      die "Aborting to protect in-flight changes."
    fi
  fi

  # Normalize the repo's default branch to `main` so the framework never relies
  # on `origin/master` for dispatcher base resolution or install merge targets.
  # This is idempotent for repos already on main.
  if [ "$DRY_RUN" -eq 0 ]; then
    normalize_default_branch_to_main
  else
    log "DRY-RUN: would normalize default branch to 'main' if needed."
  fi

  local head_sha
  head_sha="$(git rev-parse HEAD)"
  log "Target HEAD: $head_sha"

  local original_branch
  original_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")"

  # If the target was left on the install branch by a previous aborted run,
  # recover the real original branch so phase6 can merge and delete cleanly.
  if [ "$original_branch" = "$BRANCH" ]; then
    local recovered
    recovered="$(recover_original_branch)"
    if [ -n "$recovered" ]; then
      log "Target is on install branch; recovered original branch: $recovered"
      original_branch="$recovered"
    else
      warn "Target is on install branch and original branch could not be recovered; defaulting to main."
      original_branch="main"
    fi
  fi

  ORIGINAL_BRANCH="$original_branch"
  log "Target original branch: $ORIGINAL_BRANCH"

  if [ "$DRY_RUN" -eq 0 ]; then
    echo "$head_sha" > "$TARGET/$ROLLBACK_FILE"
    log "Wrote rollback SHA → $ROLLBACK_FILE"
  else
    log "DRY: would write $head_sha → $ROLLBACK_FILE"
  fi

  # Idempotent branch creation: reuse if it already exists.
  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    log "Branch '$BRANCH' exists — switching to it (idempotent rerun)."
    run "git checkout \"$BRANCH\""
  else
    run "git checkout -b \"$BRANCH\""
  fi
}

# ==========================================================================
# PHASE 1 — Copy framework files
# ==========================================================================
copy_dir() {
  # copy_dir <rel-path>  — copies $TEMPLATE_DIR/<rel-path> → $TARGET/<rel-path>
  local rel="$1"
  local src="$TEMPLATE_DIR/$rel"
  local dst="$TARGET/$rel"
  if [ ! -e "$src" ]; then
    warn "Source missing, skipping: $rel"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: cp -R \"$src\" → \"$dst\""
    return 0
  fi
  # rm first so re-runs don't accumulate stale sub-paths
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  # Nested git repos/worktrees must never become gitlinks in the target.
  strip_nested_git "$dst"
  track "$rel"
  log "Copied dir: $rel"
}

copy_file() {
  local rel="$1"
  local src="$TEMPLATE_DIR/$rel"
  local dst="$TARGET/$rel"
  if [ ! -f "$src" ]; then
    warn "Source missing, skipping: $rel"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: cp \"$src\" → \"$dst\""
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  track "$rel"
  log "Copied file: $rel"
}

# A4: stash the stateful parts of the target's .ai before copy_dir ".ai" rm -rf's
# it, so the refreshed .ai keeps its accumulated cross-CLI state. No-op on fresh
# install (UPDATE_MODE=0); in DRY_RUN just logs. Stateful paths (only if present):
#   .ai/activity/  (log + archive)   .ai/reports/  (whole dir)
#   .ai/research/  (accumulated notes) .ai/handoffs/to-*/{open,done}  (queues)
preserve_ai_state() {
  [ "$UPDATE_MODE" -eq 1 ] || return 0
  local src_ai="$TARGET/.ai"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: update mode — would preserve .ai/activity, .ai/reports, .ai/research, and .ai/handoffs/to-*/{open,done} across the .ai copy"
    return 0
  fi

  AI_STASH_DIR="$(mktemp -d -t install-ai-stash.XXXXXX 2>/dev/null || mktemp -d)"
  local p
  for p in activity reports research; do
    if [ -d "$src_ai/$p" ]; then
      cp -R "$src_ai/$p" "$AI_STASH_DIR/$p"
      log "Preserved .ai/$p"
    fi
  done
  # Handoff queues: glob the to-* recipient dirs (guarded — the glob may not match).
  local d q rel
  for d in "$src_ai/handoffs"/to-*; do
    [ -d "$d" ] || continue
    for q in open done; do
      if [ -d "$d/$q" ]; then
        rel="handoffs/$(basename "$d")/$q"
        mkdir -p "$AI_STASH_DIR/$(dirname "$rel")"
        cp -R "$d/$q" "$AI_STASH_DIR/$rel"
        log "Preserved .ai/$rel"
      fi
    done
  done
}

# A4: restore the stashed stateful paths over the freshly-copied (empty) .ai, so
# the target ends with its ORIGINAL activity/reports/handoff-queues plus the
# refreshed instruction/config files. rm -rf the fresh empty version first.
restore_ai_state() {
  [ "$UPDATE_MODE" -eq 1 ] || return 0
  local dst_ai="$TARGET/.ai"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: update mode — would restore preserved .ai state over the refreshed .ai"
    return 0
  fi

  [ -n "$AI_STASH_DIR" ] && [ -d "$AI_STASH_DIR" ] || { warn "No .ai stash to restore"; return 0; }

  local p
  for p in activity reports research; do
    if [ -d "$AI_STASH_DIR/$p" ]; then
      rm -rf "$dst_ai/$p"
      cp -R "$AI_STASH_DIR/$p" "$dst_ai/$p"
      track ".ai/$p"
      log "Restored .ai/$p"
    fi
  done
  local d q rel
  for d in "$AI_STASH_DIR/handoffs"/to-*; do
    [ -d "$d" ] || continue
    for q in open done; do
      if [ -d "$d/$q" ]; then
        rel="handoffs/$(basename "$d")/$q"
        rm -rf "$dst_ai/$rel"
        mkdir -p "$(dirname "$dst_ai/$rel")"
        cp -R "$d/$q" "$dst_ai/$rel"
        track ".ai/$rel"
        log "Restored .ai/$rel"
      fi
    done
  done
  rm -rf "$AI_STASH_DIR"
  AI_STASH_DIR=""
}

# A4: stash gitignored per-CLI local state before copy_dir ".claude" rm -rf's it.
# .claude/settings.local.json is a gitignored local permission allowlist — git
# can't recover it, so an update on an onboarded project would silently drop it.
# No-op on fresh install (UPDATE_MODE=0); in DRY_RUN just logs.
preserve_local_state() {
  [ "$UPDATE_MODE" -eq 1 ] || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: update mode — would preserve .claude/settings.local.json across the .claude copy"
    return 0
  fi

  LOCAL_STASH_DIR="$(mktemp -d -t install-local-stash.XXXXXX 2>/dev/null || mktemp -d)"
  if [ -f "$TARGET/.claude/settings.local.json" ]; then
    cp "$TARGET/.claude/settings.local.json" "$LOCAL_STASH_DIR/settings.local.json"
    log "Preserved .claude/settings.local.json"
  fi
}

# A4: restore the stashed gitignored local state over the freshly-copied .claude.
restore_local_state() {
  [ "$UPDATE_MODE" -eq 1 ] || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: update mode — would restore preserved .claude/settings.local.json over the refreshed .claude"
    return 0
  fi

  [ -n "$LOCAL_STASH_DIR" ] && [ -d "$LOCAL_STASH_DIR" ] || return 0

  if [ -f "$LOCAL_STASH_DIR/settings.local.json" ]; then
    mkdir -p "$TARGET/.claude"
    cp "$LOCAL_STASH_DIR/settings.local.json" "$TARGET/.claude/settings.local.json"
    track ".claude/settings.local.json"
    log "Restored .claude/settings.local.json"
  fi
  rm -rf "$LOCAL_STASH_DIR"
  LOCAL_STASH_DIR=""
}

phase1() {
  log "=== Phase 1: copy framework files ==="
  # A4: on update, stash stateful .ai content around the destructive .ai copy.
  preserve_ai_state
  copy_dir ".ai"
  restore_ai_state

  # A4: on update, stash gitignored .claude local state around the destructive copy.
  preserve_local_state
  copy_dir ".claude"
  restore_local_state
  copy_dir ".kimi"
  copy_dir ".kiro"
  # A4: keep the target's archived history on update — don't clobber with the
  # template's empty .archive. Fresh install copies it as before.
  if [ "$UPDATE_MODE" -eq 0 ]; then
    copy_dir ".archive"
  elif [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: update mode — would skip .archive copy (preserving target's archived history)"
  else
    log "Update mode: skipping .archive copy (preserving target's archived history)"
  fi

  copy_file "CLAUDE.md"
  copy_file "AGENTS.md"
  # A5: copy the WHOLE ADR set, not just 0001. Copied guards/hooks cite
  # ADR-0002..0009 in their block messages; shipping only 0001 leaves every
  # such citation dangling in an adopted project. Phase-3's amend_adr still
  # targets 0001 specifically, which survives the dir copy.
  copy_dir "docs/architecture"
  copy_file ".github/workflows/framework-check.yml"
  copy_file ".codegraph/config.json"

  # OpenCode config + second CI workflow (framework additions; no-op if absent).
  copy_dir  ".opencode"
  # .opencode/node_modules is git-ignored and regenerated by OpenCode on first
  # run; copy_dir's `cp -R` would otherwise drag the heavy tree onto the target.
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: would strip .opencode/node_modules"
  elif [ -d "$TARGET/.opencode/node_modules" ]; then
    rm -rf "$TARGET/.opencode/node_modules"
  fi
  copy_file "opencode.json"
  copy_file ".github/workflows/gates.yml"

  # Universal git pre-commit backstop (ADR-0005). We copy ONLY scripts/git-hooks
  # (not all of scripts/, which would drag this installer into the target), then
  # wire core.hooksPath so it is active on the target clone.
  wire_git_hooks

  # A5: copy the concrete files that copied artifacts REFERENCE, so no link in a
  # copied guard/hook dangles in the adopted project:
  #   - scripts/fleet-init.sh              cited by 3 guards ("Scaffold the fleet
  #                                        tier first (scripts/fleet-init.sh)"):
  #                                        .claude/hooks/pretool-write-edit.sh,
  #                                        .kimi/hooks/worktree-fleet-guard.sh,
  #                                        .kiro/hooks/fleet-whitelist-guard.sh
  #   - scripts/sync-4ai-panes-install.ps1 the copied git hooks (post-checkout/
  #                                        post-commit/post-merge) set SYNC_SCRIPT
  #                                        to it
  #   - docs/specs/4ai-panes-install-sync.md   those same git hooks cite it
  #   - scripts/wt-bootstrap.sh            .ai/tools/dispatch-handoffs.sh (COPIED
  #                                        below, and the pane-runner's candidate
  #                                        #1) resolves it as
  #                                        <project>/scripts/wt-bootstrap.sh.
  #                                        Without this copy that reference dangles
  #                                        in every adopted project and worktree
  #                                        setup fails — the exact class of break
  #                                        that took the whole pane fleet down on
  #                                        2026-07-12 (flat-install topology).
  copy_file "scripts/fleet-init.sh"
  copy_file "scripts/sync-4ai-panes-install.ps1"
  copy_file "scripts/wt-bootstrap.sh"
  copy_file "docs/specs/4ai-panes-install-sync.md"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: chmod +x scripts/fleet-init.sh scripts/wt-bootstrap.sh"
  else
    chmod +x "$TARGET/scripts/fleet-init.sh" 2>/dev/null || true
    chmod +x "$TARGET/scripts/wt-bootstrap.sh" 2>/dev/null || true
  fi

  # STUB / FLAG (A5, owner decision pending): the tools/4ai-panes/ pane fleet is
  # deliberately NOT shipped to adopters by default. Whether every adopter gets
  # the full pane runner + Selector + supervised launchers is a PRODUCT decision,
  # not a correctness one — fleet-init.sh (copied above) scaffolds the fleet tier
  # on demand, and the copied git hooks no-op safely when tools/4ai-panes/ is
  # absent (their `grep -q '^tools/4ai-panes/'` gate never matches). Left explicit
  # here rather than silently missing. Owner: framework maintainer. To ship it,
  # add `copy_dir "tools/4ai-panes"` (mind node_modules / heavy trees) here.
  log "NOTE: tools/4ai-panes fleet not shipped to adopters by default — owner decision pending (see STUB in phase1)."

  # Note: we did NOT copy the rest of scripts/ (would copy this installer into
  # target), nor README.md/LICENSE/CHANGELOG (target keeps its own).
}

wire_git_hooks() {
  copy_dir "scripts/git-hooks"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: chmod +x scripts/git-hooks/* ; git -C \"$TARGET\" config core.hooksPath scripts/git-hooks"
    return 0
  fi
  chmod +x "$TARGET/scripts/git-hooks/pre-commit" 2>/dev/null || true
  chmod +x "$TARGET/scripts/git-hooks/test-pre-commit.sh" 2>/dev/null || true
  # core.hooksPath is per-clone and never inherited — must be set explicitly.
  if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$TARGET" config core.hooksPath scripts/git-hooks \
      && log "Wired core.hooksPath -> scripts/git-hooks (ADR-0005 commit backstop)"
  else
    warn "Target is not a git repo yet; skipped core.hooksPath. Run: git config core.hooksPath scripts/git-hooks"
  fi
}

# ==========================================================================
# PHASE 2 — Sanitize template state
# ==========================================================================
prune_legacy() {
  log "=== Prune deprecated artifacts (ADR-0002, ADR-0003) ==="
  local path
  for path in \
    "CRUSH.md" \
    ".crush" \
    ".crush.json" \
    ".kimigraph" \
    ".kirograph" \
  ; do
    local abs="$TARGET/$path"
    [ -e "$abs" ] || continue          # idempotent: absent → no-op
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY: prune $path (rm -rf + git add -A -- $path)"
      continue
    fi
    rm -rf "$abs"
    # phase5's manifest loop only stages paths that STILL EXIST (line ~851:
    # `if [ -e "$TARGET/$rel" ]`), so a deletion would never be committed.
    # Stage it here, explicitly. `git add -A -- <path>` stages the deletion of
    # a tracked path and is a safe no-op for an untracked one.
    git -C "$TARGET" add -A -- "$path" 2>/dev/null || true
    log "Pruned deprecated artifact: $path"
  done
}

write_clean_activity_log() {
  # ADR-0010 (2026-07-13): the activity log is an entry-per-file spool, not a
  # single log.md. A clean install gets an EMPTY spool directory; log.md becomes
  # a generated, gitignored view (bash .ai/tools/render-activity-log.sh). Any
  # log.md that rode along with the template copy is removed so adopters do not
  # inherit the template's own history.
  local log_file="$TARGET/.ai/activity/log.md"
  local keep="$TARGET/.ai/activity/entries/.gitkeep"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: rm -f $log_file ; create $keep (empty entry spool, ADR-0010)"
    return 0
  fi
  rm -f "$log_file"
  # Clear any entries copied from the template tree (adopters must not inherit
  # the template's own spool), then leave an empty spool behind.
  rm -rf "$TARGET/.ai/activity/entries"
  mkdir -p "$(dirname "$keep")"
  : > "$keep"
  track ".ai/activity/entries/.gitkeep"
  log "Reset activity log: removed log.md, created empty entry spool (ADR-0010)."
}

clear_dir_contents() {
  # clear_dir_contents <abs-dir> [keep-glob ...]
  # Remove all files/subdirs except those matching any keep-glob basename.
  local dir="$1"
  shift
  [ -d "$dir" ] || return 0
  local entry base keep
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    base="$(basename "$entry")"
    keep=0
    for pat in "$@"; do
      case "$base" in
        $pat) keep=1; break ;;
      esac
    done
    if [ "$keep" -eq 0 ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY: rm -rf $entry"
      else
        rm -rf "$entry"
      fi
    fi
  done
}

phase2() {
  log "=== Phase 2: sanitize template state ==="
  # A4: the activity-log reset + handoff/report/archive clears are fresh-install
  # only. On update they'd erase exactly the state preserve/restore_ai_state kept,
  # so skip them. The known-limitations attribution below is marker-idempotent and
  # runs in both modes.
  if [ "$UPDATE_MODE" -eq 1 ]; then
    log "Update mode: preserving activity/handoffs/reports (skipping sanitize)"
  else
    write_clean_activity_log

    # Handoffs: wipe open/ and done/ for each to-*/ subdir. Keep README.md + template.md at handoffs/ root.
    local d
    for d in to-claude to-kimi to-kiro; do
      clear_dir_contents "$TARGET/.ai/handoffs/$d/open"
      clear_dir_contents "$TARGET/.ai/handoffs/$d/done"
    done
    # Reports: keep README.md, wipe everything else
    clear_dir_contents "$TARGET/.ai/reports" "README.md"

    # Archive folders
    clear_dir_contents "$TARGET/.archive/ai/handoffs"
    clear_dir_contents "$TARGET/.archive/ai/reports"
    clear_dir_contents "$TARGET/.archive/ai/activity"
  fi

  # Append attribution header to known-limitations.md (idempotent via marker).
  local kl="$TARGET/.ai/known-limitations.md"
  if [ -f "$kl" ]; then
    if grep -qF "$MARKER" "$kl" 2>/dev/null; then
      log "known-limitations.md already annotated — skipping."
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY: append attribution header to known-limitations.md"
      else
        {
          echo ""
          echo "---"
          echo ""
          echo "$MARKER (copied from template @ $TEMPLATE_SHA)"
        } >> "$kl"
        track ".ai/known-limitations.md"
        log "Appended attribution header to known-limitations.md"
      fi
    fi
  fi

  # Remove deprecated Crush-era + per-CLI-graph artifacts before phase5 staging.
  prune_legacy
}

# ==========================================================================
# PHASE 3 — Reconcile conflicts (merge .gitignore, detect language, amend ADR, patch hooks)
# ==========================================================================
merge_gitignore() {
  local src="$TEMPLATE_DIR/.gitignore"
  local dst="$TARGET/.gitignore"
  [ -f "$src" ] || { warn ".gitignore not found in template"; return 0; }

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: merge .gitignore (append missing template entries)"
    return 0
  fi

  [ -f "$dst" ] || touch "$dst"

  local already_merged=0
  if grep -qF "$MARKER gitignore-merge" "$dst" 2>/dev/null; then
    already_merged=1
  fi

  local added=0
  # tmp output: original + (marker if absent) + missing lines
  local tmp
  tmp="$(mktemp)"
  cat "$dst" > "$tmp"
  # trailing newline safety
  [ -n "$(tail -c 1 "$tmp" 2>/dev/null)" ] && echo "" >> "$tmp"

  if [ "$already_merged" -eq 0 ]; then
    {
      echo ""
      echo "$MARKER gitignore-merge (template @ $TEMPLATE_SHA)"
    } >> "$tmp"
  fi

  local line
  # Read template .gitignore line by line (no mapfile — Git Bash compat).
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip blanks and comments for comparison
    case "$line" in
      ""|\#*) continue ;;
    esac
    if grep -Fxq "$line" "$dst" 2>/dev/null; then
      continue
    fi
    echo "$line" >> "$tmp"
    added=$((added + 1))
  done < "$src"

  if [ "$added" -gt 0 ] || [ "$already_merged" -eq 0 ]; then
    mv "$tmp" "$dst"
    track ".gitignore"
    if [ "$added" -gt 0 ]; then
      log "Merged $added new entries into .gitignore"
    else
      log ".gitignore already contains all template entries — marker added."
    fi
  else
    rm -f "$tmp"
    log ".gitignore already contains all template entries — no merge needed."
  fi
}

# Echo a WORKING python interpreter command (python3 or python), or "" if none.
# On Windows, `command -v python3` finds the Microsoft Store alias stub that
# prints a help message and exits non-zero — so we actually run `-c` to confirm
# the interpreter works before trusting it.
find_python() {
  local py
  for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1 && "$py" -c "import json,sys" >/dev/null 2>&1; then
      echo "$py"
      return 0
    fi
  done
  echo ""
}

# Create or merge .mcp.json with the codegraph server entry.
# - Absent: write the one-server JSON (plain text — no tooling needed).
# - Present: merge codegraph in only if absent, using a working python parser
#   when available, else warn-and-skip to avoid corrupting the adopter's JSON.
#   Mirrors src/installer/wire-mcp.ts. The bash baseline ships no jq/python
#   dependency, so the merge path is best-effort (degraded — see README).
wire_mcp() {
  local dst="$TARGET/.mcp.json"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: create-or-merge .mcp.json with codegraph server"
    return 0
  fi

  if [ ! -f "$dst" ]; then
    cat > "$dst" <<'EOF'
{
  "mcpServers": {
    "codegraph": {
      "command": "npx",
      "args": ["-y", "@colbymchenry/codegraph", "serve", "--mcp"]
    }
  }
}
EOF
    track ".mcp.json"
    log "Created .mcp.json with codegraph server."
    return 0
  fi

  # Already present — only add codegraph if absent, preserving other servers.
  if grep -q '"codegraph"' "$dst" 2>/dev/null; then
    log ".mcp.json already has a codegraph entry — skipping."
    return 0
  fi

  local py
  py="$(find_python)"
  if [ -n "$py" ]; then
    if "$py" - "$dst" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
servers = data.setdefault("mcpServers", {})
if "codegraph" not in servers:
    servers["codegraph"] = {"command": "npx", "args": ["-y", "@colbymchenry/codegraph", "serve", "--mcp"]}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
    then
      track ".mcp.json"
      log "Merged codegraph server into existing .mcp.json."
    else
      warn "Failed to merge .mcp.json (python error). Add the codegraph server manually:"
      warn '  "codegraph": { "command": "npx", "args": ["-y", "@colbymchenry/codegraph", "serve", "--mcp"] }'
    fi
  else
    warn "No working python interpreter — cannot safely merge existing .mcp.json."
    warn "Add the codegraph server manually under mcpServers:"
    warn '  "codegraph": { "command": "npx", "args": ["-y", "@colbymchenry/codegraph", "serve", "--mcp"] }'
  fi
}

# reconcile_block <target-file> <begin-marker> <end-marker> <snippet-file>
# Idempotent RECONCILE of a marker-fenced managed block inside a user-global text
# file (gap D3, docs/specs/global-config-tracking.md). The snippet file carries
# its OWN begin/end sentinel lines (they ARE its first + last lines), so the whole
# snippet is the managed block. This SUPERSEDES the old append-once wire step:
#   - existing block (begin AND end present): replace it (inclusive) with snippet
#   - absent: append the fenced snippet on a fresh line (CREATE)
# Content OUTSIDE the sentinels is never read or rewritten. Atomic write via a
# same-dir temp file + rename (a crash never leaves a truncated global config).
# POSIX-bash / Git-Bash safe.
reconcile_block() {
  local target="$1" begin="$2" end="$3" snippet="$4"

  if [ ! -f "$snippet" ]; then
    warn "Managed-block snippet missing, skipping reconcile: $snippet"
    return 0
  fi

  local have_block=0
  if [ -f "$target" ] \
     && grep -qF "$begin" "$target" 2>/dev/null \
     && grep -qF "$end" "$target" 2>/dev/null; then
    have_block=1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$have_block" -eq 1 ]; then
      log "DRY: reconcile (SUPERSEDE) managed block '$begin' in $target"
    else
      log "DRY: reconcile (CREATE) managed block '$begin' in $target"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -f "$target" ] || touch "$target"

  local dir tmp
  dir="$(dirname "$target")"
  tmp="$(mktemp "$dir/.reconcile-XXXXXX" 2>/dev/null || echo "$dir/.reconcile.$$")"

  if [ "$have_block" -eq 1 ]; then
    # SUPERSEDE: at the begin line, emit the whole snippet; skip the old block up
    # to and including the old end line; pass every other line through untouched.
    awk -v b="$begin" -v e="$end" -v sf="$snippet" '
      $0 == b {
        while ((getline line < sf) > 0) print line
        close(sf)
        skipping = 1
        next
      }
      $0 == e { skipping = 0; next }
      skipping { next }
      { print }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
    log "Reconciled (superseded) managed block '$begin' in $target"
  else
    # CREATE: preserve existing content, ensure it ends with a newline, then
    # append a blank separator + the fenced snippet.
    cat "$target" > "$tmp"
    [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp" 2>/dev/null)" ] && printf '\n' >> "$tmp"
    [ -s "$tmp" ] && printf '\n' >> "$tmp"
    cat "$snippet" >> "$tmp"
    mv "$tmp" "$target"
    log "Reconciled (created) managed block '$begin' in $target"
  fi
}

# reconcile_mcp <target-json> <deprecated-key> [deprecated-key ...]
# Key-managed reconcile of a per-user MCP JSON (gap D3). The framework owns a set
# of server keys; here it PRUNES the known-deprecated ones (kimigraph, kirograph,
# and a legacy bare codegraph — the ADR-0003-removed servers that produced the
# every-terminal startup error). User-added servers are NEVER touched. No-op if
# the target file is absent. Uses python for a safe JSON edit (find_python), with
# a warn-only fallback if no python — never a hand-rolled JSON edit that could
# corrupt the file. Parse errors are fail-closed (warn + skip, never corrupt).
reconcile_mcp() {
  local target="$1"; shift
  local deprecated="$*"

  if [ ! -f "$target" ]; then
    log "MCP reconcile: $target absent — nothing to prune."
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: prune deprecated MCP servers [$deprecated] from $target (preserve user servers)"
    return 0
  fi

  local py
  py="$(find_python)"
  if [ -n "$py" ]; then
    if "$py" - "$target" $deprecated <<'PYEOF'
import json, os, sys, tempfile
path = sys.argv[1]
deprecated = sys.argv[2:]
try:
    with open(path) as f:
        data = json.load(f)
except (ValueError, OSError) as e:
    sys.stderr.write("reconcile_mcp: cannot parse %s (%s) — skipping\n" % (path, e))
    sys.exit(3)
servers = data.get("mcpServers")
if not isinstance(servers, dict):
    sys.exit(0)  # no managed section — nothing to prune
removed = [k for k in deprecated if k in servers]
for k in removed:
    servers.pop(k, None)
if removed:
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)  # atomic same-dir rename
    sys.stderr.write("reconcile_mcp: pruned %s\n" % ", ".join(removed))
PYEOF
    then
      log "MCP reconcile: $target checked (deprecated servers pruned if present)."
    else
      warn "MCP reconcile: python parse/prune failed for $target — left unchanged (fail-closed)."
    fi
  else
    # No python: never hand-edit JSON. Warn if deprecated keys look present.
    if grep -Eq '"(kimigraph|kirograph|codegraph)"' "$target" 2>/dev/null; then
      warn "MCP reconcile: no python interpreter; $target may still contain deprecated"
      warn "  servers (kimigraph/kirograph/codegraph). Remove them by hand, or install"
      warn "  python and re-run the installer."
    else
      log "MCP reconcile: no python; no obvious deprecated servers in $target."
    fi
  fi
}

# Reconcile the project's Kimi hook snippet into the user-global Kimi config so
# the guards actually fire. Kimi Code reads ~/.kimi-code/config.toml (NOT ~/.kimi/;
# the latter is the pre-migration path — see ~/.kimi/.migrated-to-kimi-code and
# the snippet's own SSOT header). Creates the dir/file if absent. POSIX-bash /
# Git-Bash safe.
#
# A4 (resolved): this is no longer APPEND-ONCE. reconcile_block SUPERSEDES the
# fenced kimi-hooks block on every run (BEGIN/END sentinels carried by the snippet
# itself), so a changed snippet — a new guard, a fixed path, a removed hook — now
# propagates to an already-wired machine. User content OUTSIDE the sentinels is
# preserved byte-for-byte. Resolves the former TODO(A4-followup).
# strip_legacy_kimi_block <target-file>
# Migration for pre-sentinel machines. An OLDER append-once wire_kimi_hooks
# appended a block headed `# ADDED BY install-template.sh kimi-hooks (template @
# SHA)` with NO begin/end sentinels — just the four guard [[hooks]] entries
# (root-guard, framework-guard, sensitive-guard, destructive-guard). reconcile_block
# keys on the NEW sentinels, so it is blind to that legacy block and would append a
# SECOND managed block beside it. This strips the clearly-marked legacy block first
# so reconcile converges to exactly ONE sentinel-fenced block regardless of prior
# state. Conservative: only a stanza whose command references one of those four
# legacy guard scripts is dropped; the first non-legacy [[hooks]] (safety-check.ps1,
# activity-log-remind.sh, worktree-fleet-guard, any user hook) ends the legacy region
# and everything from there on is preserved byte-for-byte. Atomic same-dir rename.
strip_legacy_kimi_block() {
  local target="$1"
  local marker="$MARKER kimi-hooks"   # "# ADDED BY install-template.sh kimi-hooks"

  [ -f "$target" ] || return 0
  grep -qF "$marker" "$target" 2>/dev/null || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: strip legacy '$marker' block from $target (pre-sentinel migration)"
    return 0
  fi

  local dir tmp
  dir="$(dirname "$target")"
  tmp="$(mktemp "$dir/.kimi-strip-XXXXXX" 2>/dev/null || echo "$dir/.kimi-strip.$$")"

  # A "stanza" is buffered from a [[hooks]] line (plus any comments accumulated
  # before the next boundary). In the legacy region the default disposition is
  # DROP; a command referencing a non-legacy script flips the stanza (and all
  # that follow) to KEEP and ends the region. Legacy leading/trailing comments
  # carry no command and are dropped by the default.
  awk -v marker="$marker" '
    function flush_stanza() {
      if (sn == 0) return
      if (drop) { sn = 0; return }
      for (i = 1; i <= sn; i++) print sbuf[i]
      sn = 0
    }
    BEGIN { in_legacy = 0; sn = 0; drop = 0; nb = 0 }
    {
      line = $0

      if (!in_legacy) {
        if (index(line, marker) > 0) {
          nb = 0                 # drop buffered pre-marker blanks + marker line
          in_legacy = 1; sn = 0; drop = 1
          next
        }
        if (line ~ /^[ \t]*$/) { nb++; next }
        while (nb > 0) { print ""; nb-- }
        print line
        next
      }

      # ---- legacy region ----
      # A managed-block sentinel ends the region; reconcile owns that block.
      if (index(line, ">>> rwn-framework:") > 0) {
        flush_stanza(); in_legacy = 0; print line; next
      }
      # A second legacy marker starts a fresh legacy stanza.
      if (index(line, marker) > 0) {
        flush_stanza(); sn = 0; drop = 1; next
      }
      # New stanza boundary.
      if (line ~ /^[ \t]*\[\[hooks\]\]/) {
        flush_stanza(); sn = 0; drop = 1; sbuf[++sn] = line; next
      }
      # The command line decides this stanza.
      if (line ~ /^[ \t]*command[ \t]*=/) {
        sbuf[++sn] = line
        if (line ~ /(root-guard|framework-guard|sensitive-guard|destructive-guard)\.sh/) {
          drop = 1               # legacy guard -> drop this stanza
        } else {
          drop = 0               # non-legacy hook -> keep + end legacy region
          flush_stanza(); in_legacy = 0
        }
        next
      }
      # Comments / event / matcher / timeout / blanks: buffer with the stanza.
      sbuf[++sn] = line
      next
    }
    END {
      if (in_legacy) { sn = 0 }  # trailing legacy stanza at EOF -> drop
      else { flush_stanza() }
      while (nb > 0) { print ""; nb-- }
    }
  ' "$target" > "$tmp"

  mv "$tmp" "$target"
  log "Stripped legacy kimi-hooks block from $target (migrated to sentinel scheme)"
}

wire_kimi_hooks() {
  # Source the snippet from the template (SSOT, always present) rather than the
  # target: phase1's copy only lands in non-dry runs, and template == target copy.
  local snippet="$TEMPLATE_DIR/.ai/config-snippets/kimi-hooks.toml"
  local cfg="$HOME/.kimi-code/config.toml"

  # Pre-sentinel migration: remove any legacy `# ADDED BY … kimi-hooks` block so
  # reconcile does not append a duplicate beside it. No-op once migrated.
  strip_legacy_kimi_block "$cfg"

  reconcile_block "$cfg" \
    "# >>> rwn-framework:kimi-hooks >>>" \
    "# <<< rwn-framework:kimi-hooks <<<" \
    "$snippet"
}

# Prune the ADR-0003-removed MCP servers from Kimi's per-user MCP JSON. The D3
# incident was ~/.kimi/mcp.json still registering kimigraph/kirograph/codegraph
# after ADR-0003 removed them, producing a startup error on every terminal. Also
# checks ~/.kimi-code/mcp.json (post-migration path). Both no-op if absent.
reconcile_kimi_mcp() {
  local f
  for f in "$HOME/.kimi/mcp.json" "$HOME/.kimi-code/mcp.json"; do
    reconcile_mcp "$f" kimigraph kirograph codegraph
  done
}

detect_language() {
  # Echo one of: node-npm, node-yarn, node-pnpm, rust, python, go, ruby, none, multi
  local found=""
  local count=0
  [ -f "$TARGET/package.json" ] && { count=$((count + 1)); local flavor="node-npm"
    [ -f "$TARGET/yarn.lock" ] && flavor="node-yarn"
    [ -f "$TARGET/pnpm-lock.yaml" ] && flavor="node-pnpm"
    found="$flavor"; }
  [ -f "$TARGET/Cargo.toml" ]     && { count=$((count + 1)); found="rust"; }
  [ -f "$TARGET/pyproject.toml" ] && { count=$((count + 1)); found="python"; }
  [ -f "$TARGET/go.mod" ]         && { count=$((count + 1)); found="go"; }
  [ -f "$TARGET/Gemfile" ]        && { count=$((count + 1)); found="ruby"; }

  if [ "$count" -eq 0 ]; then
    echo "none"
  elif [ "$count" -gt 1 ]; then
    echo "multi"
  else
    echo "$found"
  fi
}

# Describe manifest + lockfile for the ADR amendment
lang_files() {
  # Echo "manifest lockfile" for the given language flavor, or "" if none.
  case "$1" in
    node-npm)   echo "package.json package-lock.json" ;;
    node-yarn)  echo "package.json yarn.lock" ;;
    node-pnpm)  echo "package.json pnpm-lock.yaml" ;;
    rust)       echo "Cargo.toml Cargo.lock" ;;
    python)     echo "pyproject.toml uv.lock" ;;
    go)         echo "go.mod go.sum" ;;
    ruby)       echo "Gemfile Gemfile.lock" ;;
    *)          echo "" ;;
  esac
}

amend_adr() {
  local lang="$1"
  local adr="$TARGET/docs/architecture/0001-root-file-exceptions.md"
  [ -f "$adr" ] || { warn "ADR not present, skipping amendment"; return 0; }

  local files
  files="$(lang_files "$lang")"
  [ -z "$files" ] && { log "No lang files for '$lang' — skipping ADR amend."; return 0; }

  if grep -qF "$MARKER adr-category-f-$lang" "$adr" 2>/dev/null; then
    log "ADR already amended for '$lang' — skipping."
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: amend ADR Category F for lang='$lang' with files: $files"
    return 0
  fi

  # Append a new allowlist note at the end of the ADR (append-only is simplest & robust).
  {
    echo ""
    echo "$MARKER adr-category-f-$lang (template @ $TEMPLATE_SHA)"
    echo ""
    echo "### F-install. Language manifests activated on install ($lang)"
    echo ""
    local f
    for f in $files; do
      echo "- \`$f\` — allowed at repo root (language detected: $lang)"
    done
  } >> "$adr"
  track "docs/architecture/0001-root-file-exceptions.md"
  log "Amended ADR Category F for $lang."
}

# Uncomment manifest patterns in the three root-guard hooks by adding a case-arm.
# We append a new case-arm block (guarded by MARKER) so the files stay close to
# template — rather than editing the specific "Examples to uncomment later" line.
patch_hook_allow() {
  local lang="$1"
  local files
  files="$(lang_files "$lang")"
  [ -z "$files" ] && return 0

  local hook
  for hook in \
    "$TARGET/.claude/hooks/pretool-write-edit.sh" \
    "$TARGET/.kimi/hooks/root-guard.sh" \
    "$TARGET/.kiro/hooks/root-file-guard.sh" \
  ; do
    [ -f "$hook" ] || { warn "Hook missing, skipping: $hook"; continue; }

    if grep -qF "$MARKER hook-allow-$lang" "$hook" 2>/dev/null; then
      log "Hook already patched for '$lang': $hook"
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY: patch $hook to allow $files"
      continue
    fi

    # Build case pattern: "package.json|package-lock.json"
    local pattern=""
    local f
    for f in $files; do
      if [ -z "$pattern" ]; then pattern="$f"; else pattern="$pattern|$f"; fi
    done

    # Inject the allow-arm INSIDE the root-file-policy case statement, before
    # the default `*)` arm (which calls block/exit 2 and would otherwise run
    # first). We look for the first line matching `    *)` (4+ spaces then `*)`)
    # after the root-file policy comment and insert above it.
    #
    # Heuristic: find first line that begins with whitespace then `*)` AFTER
    # the string "root-file policy" appears. Works for all three hook files
    # (they all share the same structural pattern).
    local tmp
    tmp="$(mktemp)"
    # Heuristic: the three root-guard hooks all share the pattern of one
    # `case` statement whose `*)` default arm blocks unknown root files.
    # We inject the new allow-arm immediately before the first such `*)`
    # line (whitespace-indented). If no match → fallback warning at EOF.
    awk -v marker="$MARKER hook-allow-$lang" -v patt="$pattern" '
      BEGIN { injected=0 }
      {
        if (!injected && $0 ~ /^[[:space:]]+\*\)/) {
          print "    # " marker
          print "    " patt ") exit 0 ;;"
          injected=1
        }
        print
      }
      END {
        if (!injected) {
          # Fallback: append at end so the marker is visible even if heuristic failed.
          print ""
          print "# " marker " (fallback: could not find case default — manual review needed)"
          print "# " patt " should exit 0 before any root-file block() call."
        }
      }
    ' "$hook" > "$tmp"
    mv "$tmp" "$hook"
    chmod +x "$hook" 2>/dev/null || true

    local rel_hook="${hook#$TARGET/}"
    track "$rel_hook"
    log "Patched $rel_hook to allow: $pattern"
  done
}

phase3() {
  log "=== Phase 3: reconcile + adapt ==="
  merge_gitignore
  wire_mcp
  wire_kimi_hooks
  reconcile_kimi_mcp

  local lang
  lang="$(detect_language)"
  case "$lang" in
    none)
      warn "No language manifest detected at $TARGET (no package.json/Cargo.toml/pyproject.toml/go.mod/Gemfile)."
      warn "Skipping ADR amendment + hook patching. Amend ADR + hooks manually when you pick a language."
      ;;
    multi)
      warn "Multiple language manifests detected. Skipping auto-amend to avoid wrong choice."
      warn "Amend docs/architecture/0001-root-file-exceptions.md Category F manually."
      ;;
    *)
      log "Detected language: $lang"
      amend_adr "$lang"
      patch_hook_allow "$lang"
      ;;
  esac
  DETECTED_LANG="$lang"
}

# ==========================================================================
# PHASE 4 — Tailor agent configs (interactive, skippable)
# ==========================================================================
suggest_cmd_for() {
  # suggest_cmd_for <lang> <kind: test|build|lint>
  local lang="$1" kind="$2"
  case "$lang" in
    node-npm)  case "$kind" in test) echo "npm test";;     build) echo "npm run build";;   lint) echo "npm run lint";; esac ;;
    node-yarn) case "$kind" in test) echo "yarn test";;    build) echo "yarn build";;      lint) echo "yarn lint";; esac ;;
    node-pnpm) case "$kind" in test) echo "pnpm test";;    build) echo "pnpm build";;      lint) echo "pnpm lint";; esac ;;
    rust)      case "$kind" in test) echo "cargo test";;   build) echo "cargo build";;     lint) echo "cargo clippy -- -D warnings";; esac ;;
    python)    case "$kind" in test) echo "pytest";;       build) echo "python -m build";; lint) echo "ruff check .";; esac ;;
    go)        case "$kind" in test) echo "go test ./...";; build) echo "go build ./...";;  lint) echo "golangci-lint run";; esac ;;
    ruby)      case "$kind" in test) echo "bundle exec rspec";; build) echo "bundle install";; lint) echo "bundle exec rubocop";; esac ;;
    *)         echo "" ;;
  esac
}

phase4() {
  log "=== Phase 4: tailor agent configs ==="
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: skipping agent tailoring."
    return 0
  fi

  local test_cmd build_cmd lint_cmd
  test_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" test)"
  build_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" build)"
  lint_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" lint)"

  if [ "$INTERACTIVE" -eq 1 ] && [ -t 0 ] && [ -t 1 ]; then
    local ans
    printf "[install] Customize agent commands for your stack? (y/N) "
    read -r ans </dev/tty || ans=""
    case "$ans" in
      y|Y|yes|YES)
        printf "[install] test command [%s]: " "$test_cmd"
        read -r ans </dev/tty || ans=""
        [ -n "$ans" ] && test_cmd="$ans"
        printf "[install] build command [%s]: " "$build_cmd"
        read -r ans </dev/tty || ans=""
        [ -n "$ans" ] && build_cmd="$ans"
        printf "[install] lint command [%s]: " "$lint_cmd"
        read -r ans </dev/tty || ans=""
        [ -n "$ans" ] && lint_cmd="$ans"
        ;;
      *) log "Using suggested defaults." ;;
    esac
  else
    log "Non-interactive mode: using suggested defaults."
  fi

  # Agent configs currently have NO standardized <PROJECT_*_CMD> placeholders.
  # Rather than brittle sed across 6 files, emit a clear manual-edit note +
  # write a record to .ai/reports/ so the user can copy-paste.
  local note="$TARGET/.ai/reports/install-template-commands.md"
  {
    echo "# Project commands (captured during install-template.sh)"
    echo ""
    echo "Template @ $TEMPLATE_SHA. Language detected: ${DETECTED_LANG:-none}."
    echo ""
    echo "- test:  \`$test_cmd\`"
    echo "- build: \`$build_cmd\`"
    echo "- lint:  \`$lint_cmd\`"
    echo ""
    echo "## Manual edit needed"
    echo ""
    echo "The tester/coder agents across 3 CLIs don't use templated placeholders."
    echo "Paste the commands above into the \`Shell scope\` / behavior sections of:"
    echo ""
    echo "- .claude/agents/tester.md (Shell scope bullet)"
    echo "- .claude/agents/coder.md"
    echo "- .kimi/agents/tester.yaml"
    echo "- .kimi/agents/system/coder-executor.md"
    echo "- .kiro/agents/tester.json (prompt field)"
    echo "- .kiro/agents/coder.json (prompt field)"
  } > "$note"
  track ".ai/reports/install-template-commands.md"
  log "Wrote .ai/reports/install-template-commands.md."
  warn "Agent configs lack standardized placeholders; edits remain manual."
}

# ==========================================================================
# PHASE 5 — Verify + commit
# ==========================================================================
run_tests() {
  local failed=0
  local test
  for test in \
    ".claude/hooks/test_hooks.sh" \
    ".kimi/hooks/test_hooks.sh" \
    ".kiro/hooks/test_hooks.sh" \
    ".ai/tools/check-ssot-drift.sh" \
  ; do
    local abs="$TARGET/$test"
    if [ ! -f "$abs" ]; then
      warn "Missing test script: $test (skipping)"
      continue
    fi
    log "Running: $test"
    if ( cd "$TARGET" && bash "$test" ); then
      log "PASS: $test"
    else
      err "FAIL: $test"
      failed=$((failed + 1))
    fi
  done
  return $failed
}

# Phase A (multi-cli-skills v0.0.3+): write framework version marker + manifest
# so future --upgrade (Node installer) works for bash-installed projects too.
# Manifest is intentionally empty for bash installs — the bash installer doesn't
# enumerate framework-owned files reliably. Node --upgrade rebuilds it on first run.
write_framework_marker() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$TARGET/.ai"
  cat > "$TARGET/.ai/.framework-version" <<EOF
{
  "framework_version": "$FRAMEWORK_VERSION",
  "installer_name": "scripts/install-template.sh",
  "installer_version": "$FRAMEWORK_VERSION",
  "installed_at": "$now",
  "upgrade_history": []
}
EOF
  cat > "$TARGET/.ai/.framework-manifest.json" <<EOF
{
  "version": "$FRAMEWORK_VERSION",
  "files": {}
}
EOF
  track ".ai/.framework-version"
  track ".ai/.framework-manifest.json"
  log "Wrote .ai/.framework-version + .ai/.framework-manifest.json (v$FRAMEWORK_VERSION)"
}

phase5() {
  log "=== Phase 5: verify + commit ==="
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: would run hook tests + ssot drift check + git commit."
    log "DRY-RUN: would write .ai/.framework-version + .ai/.framework-manifest.json (v$FRAMEWORK_VERSION)"
    return 0
  fi

  if ! run_tests; then
    die "One or more verification tests failed. Branch '$BRANCH' left intact for inspection."
  fi

  write_framework_marker

  cd "$TARGET"

  # Stage only tracked paths from the manifest (+ rollback file).
  # De-dupe manifest entries.
  local uniq_manifest
  uniq_manifest="$(mktemp)"
  sort -u "$MANIFEST" > "$uniq_manifest"

  local any=0
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    if [ -e "$TARGET/$rel" ]; then
      git add -- "$rel" 2>/dev/null && any=1 || warn "git add failed for: $rel"
    fi
  done < "$uniq_manifest"
  rm -f "$uniq_manifest"

  # Intentionally do NOT commit the rollback-point file — it's a local aid.
  # Add it to .gitignore to keep target clean.
  if ! grep -qxF "$ROLLBACK_FILE" "$TARGET/.gitignore" 2>/dev/null; then
    echo "$ROLLBACK_FILE" >> "$TARGET/.gitignore"
    git add .gitignore
  fi

  if git diff --cached --quiet; then
    warn "Nothing staged. Skipping commit (idempotent rerun)."
    return 0
  fi

  # --no-verify: phase1 just wired core.hooksPath -> scripts/git-hooks (the
  # ADR-0005 pre-commit backstop). Its cross-CLI territory rule blocks ANY single
  # committer from committing the full .claude/ + .kimi/ + .kiro/ + .opencode/
  # payload this installer stages — so an ordinary commit here is guaranteed to be
  # rejected and set -e would abort, leaving the target half-applied. The installer
  # is the trusted template author performing the one-time bootstrap adopt-commit,
  # so it (and only it) bypasses the backstop it just wired. Nothing else does.
  git commit --no-verify -m "feat(infra): adopt multi-CLI AI coordination framework [from template $TEMPLATE_SHA]"
  log "Committed on branch $BRANCH."
}

# ==========================================================================
# PHASE 6 — Merge install branch back to original branch and clean up
# ==========================================================================
phase6() {
  log "=== Phase 6: merge install branch ==="
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: would merge $BRANCH into $ORIGINAL_BRANCH if --no-merge was not given."
    return 0
  fi

  if [ -z "$ORIGINAL_BRANCH" ]; then
    warn "Original branch not recorded; skipping auto-merge."
    return 0
  fi

  cd "$TARGET"

  # Decide whether to merge.
  local do_merge=0
  if [ "$AUTO_MERGE" -eq 1 ]; then
    do_merge=1
  elif [ "$INTERACTIVE" -eq 1 ] && [ "$AUTO_MERGE_EXPLICIT" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    local ans
    printf "[install] Merge $BRANCH into $ORIGINAL_BRANCH now? (Y/n) "
    read -r ans </dev/tty || ans=""
    case "$ans" in
      n|N|no|NO) log "Skipping merge." ;;
      *) do_merge=1 ;;
    esac
  fi

  if [ "$do_merge" -eq 0 ]; then
    log "Install branch left intact: $BRANCH"
    return 0
  fi

  # Guard: if we still think the original branch is the install branch, we cannot
  # merge/delete it. Try one more recovery before giving up.
  if [ "$ORIGINAL_BRANCH" = "$BRANCH" ]; then
    local recovered
    recovered="$(recover_original_branch)"
    if [ -n "$recovered" ] && [ "$recovered" != "$BRANCH" ]; then
      ORIGINAL_BRANCH="$recovered"
      log "Recovered original branch in phase6: $ORIGINAL_BRANCH"
    else
      warn "Original branch is the install branch ($BRANCH); cannot auto-merge/delete."
      log "Switch away from $BRANCH manually, then delete it."
      return 0
    fi
  fi

  # Safety: abort if there are unexpected uncommitted changes before switching.
  if [ -n "$(git status --porcelain)" ]; then
    warn "Working tree is not clean; cannot auto-merge."
    log "Finish committing or stashing changes, then run:"
    log "  cd \"$TARGET\" && git checkout $ORIGINAL_BRANCH && git merge --no-ff $BRANCH"
    return 0
  fi

  log "Merging $BRANCH into $ORIGINAL_BRANCH..."
  if ! git checkout "$ORIGINAL_BRANCH"; then
    warn "Could not switch to $ORIGINAL_BRANCH; leaving install branch intact."
    return 0
  fi

  if ! git merge --no-ff --no-edit "$BRANCH"; then
    warn "Merge failed. Resolve conflicts manually, then complete the merge."
    log "To abort: cd \"$TARGET\" && git merge --abort && git checkout $BRANCH"
    return 0
  fi

  git branch -d "$BRANCH"
  rm -f "$TARGET/$ROLLBACK_FILE"
  log "Merged and cleaned up. Working tree is on $ORIGINAL_BRANCH."
}

# ==========================================================================
# Final summary
# ==========================================================================
print_summary() {
  cat <<EOF

==============================================================================
[install] Install complete
==============================================================================

Template SHA:      $TEMPLATE_SHA
Framework version: $FRAMEWORK_VERSION (stamped in .ai/.framework-version)
Target:            $TARGET
Language detected: ${DETECTED_LANG:-none}
Current branch:    $(cd "$TARGET" && git symbolic-ref --short HEAD 2>/dev/null || echo "unknown")

Files tracked (added/modified):
EOF
  if [ -f "$MANIFEST" ]; then
    sort -u "$MANIFEST" | sed 's/^/  - /'
  fi

  cat <<EOF

Kimi hooks wiring:
  The Kimi CLI reads ~/.kimi-code/config.toml (user-global) for hook definitions.
  This installer RECONCILED the .ai/config-snippets/kimi-hooks.toml managed block
  into that file (BEGIN/END fenced, idempotent) in phase 3 — see the wire_kimi_hooks
  log line above. Reconcile SUPERSEDES on every run: a changed snippet now
  propagates to an already-wired machine (no longer append-once), while your own
  hooks OUTSIDE the >>> / <<< sentinels are preserved. It also pruned the
  ADR-0003-removed MCP servers (kimigraph/kirograph/codegraph) from ~/.kimi/mcp.json
  if present. If you need to re-apply the block manually (Project-level
  .kimi/config.toml is not auto-loaded by Kimi CLI at time of writing — see
  .ai/known-limitations.md):

  cat "$TARGET/.ai/config-snippets/kimi-hooks.toml" >> ~/.kimi-code/config.toml

EOF
}

# ==========================================================================
# Main
# ==========================================================================
if [ "${INSTALL_TEMPLATE_LIB:-0}" != "1" ]; then
  phase0
  phase1
  phase2
  phase3
  phase4
  phase5
  phase6
  print_summary
fi
