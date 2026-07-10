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
FRAMEWORK_VERSION="0.0.5"

# ---------- globals set later ----------
TEMPLATE_DIR=""
TEMPLATE_SHA=""
TARGET=""
DRY_RUN=0
MANIFEST=""   # path to a temp file tracking changed paths (relative to TARGET)
ORIGINAL_BRANCH=""   # target's branch at install time (main/master/etc.)

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
  bash scripts/install-template.sh <target-dir> [--dry-run]

Arguments:
  <target-dir>   Absolute or relative path to the target project. Must be a
                 clean git working tree.

Options:
  --dry-run      Print planned actions without touching the target.
  --help, -h     Show this help and exit.

What it does (6 phases):
  0. Pre-flight: verify target is a clean git repo, record rollback SHA,
     create branch 'ai-template-install'.
  1. Copy framework files (.ai/, .claude/, .kimi/, .kiro/, .archive/,
     CLAUDE.md, AGENTS.md, ADR, CI workflow, .codegraph/config.json).
  2. Sanitize template state (reset activity log, clear handoffs/reports).
  3. Reconcile conflicts (merge .gitignore, create/merge .mcp.json codegraph
     server, detect language, amend ADR + uncomment matching patterns in
     root-guard hooks).
  4. Interactive agent-config tailoring (skippable).
  5. Verify (hook tests + SSOT drift) and commit on the install branch.

The script leaves you on the 'ai-template-install' branch with one commit.
Phase 6 (merge to original branch) is printed as follow-up instructions; it is
not executed.
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

# ==========================================================================
# PHASE 0 — Pre-flight
# ==========================================================================
phase0() {
  log "=== Phase 0: pre-flight ==="
  cd "$TARGET"
  local status
  status="$(git status --porcelain)"
  if [ -n "$status" ]; then
    err "Target working tree is dirty. Commit or stash first."
    echo "$status" >&2
    die "Aborting to protect in-flight changes."
  fi

  local head_sha
  head_sha="$(git rev-parse HEAD)"
  log "Target HEAD: $head_sha"

  local original_branch
  original_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")"
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

phase1() {
  log "=== Phase 1: copy framework files ==="
  copy_dir ".ai"
  copy_dir ".claude"
  copy_dir ".kimi"
  copy_dir ".kiro"
  copy_dir ".archive"

  copy_file "CLAUDE.md"
  copy_file "AGENTS.md"
  copy_file "docs/architecture/0001-root-file-exceptions.md"
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
  local dst="$TARGET/.ai/activity/log.md"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: reset $dst to clean header"
    return 0
  fi
  cat > "$dst" <<'EOF'
# Activity Log

Newest entries at the top. Each CLI prepends an entry after completing substantive work.

**Timestamp rule:** the `HH:MM` in each entry heading is local wall-clock time at the
moment of prepending (i.e. when the work finished, not when it started). CLIs on
different local clocks may produce timestamps that don't sort monotonically;
**prepend order is the authoritative sequencing**, timestamps are annotations.

**Archive:** older entries live in `.ai/activity/archive/YYYY-MM.md` (one file per
calendar month). See `.ai/activity/archive/README.md` for the rollover protocol.

---

EOF
  track ".ai/activity/log.md"
  log "Reset activity log."
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

  if grep -qF "$MARKER gitignore-merge" "$dst" 2>/dev/null; then
    log ".gitignore already merged by installer — skipping."
    return 0
  fi

  local added=0
  # tmp output: original + marker + missing lines
  local tmp
  tmp="$(mktemp)"
  cat "$dst" > "$tmp"
  # trailing newline safety
  [ -n "$(tail -c 1 "$tmp" 2>/dev/null)" ] && echo "" >> "$tmp"
  {
    echo ""
    echo "$MARKER gitignore-merge (template @ $TEMPLATE_SHA)"
  } >> "$tmp"

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

  if [ "$added" -gt 0 ]; then
    mv "$tmp" "$dst"
    track ".gitignore"
    log "Merged $added new entries into .gitignore"
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
      "command": "codegraph",
      "args": ["serve", "--mcp"]
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
    servers["codegraph"] = {"command": "codegraph", "args": ["serve", "--mcp"]}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
    then
      track ".mcp.json"
      log "Merged codegraph server into existing .mcp.json."
    else
      warn "Failed to merge .mcp.json (python error). Add the codegraph server manually:"
      warn '  "codegraph": { "command": "codegraph", "args": ["serve", "--mcp"] }'
    fi
  else
    warn "No working python interpreter — cannot safely merge existing .mcp.json."
    warn "Add the codegraph server manually under mcpServers:"
    warn '  "codegraph": { "command": "codegraph", "args": ["serve", "--mcp"] }'
  fi
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
  log "=== Phase 4: tailor agent configs (interactive) ==="
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: skipping interactive prompts."
    return 0
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    warn "Non-interactive shell (no TTY). Skipping agent tailoring."
    log "To customize later: edit .claude/agents/{tester,coder}.md,"
    log ".kimi/agents/{tester.yaml,system/coder-executor.md}, .kiro/agents/{tester,coder}.json"
    return 0
  fi

  local ans
  printf "[install] Customize agent commands for your stack? (y/N) "
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) ;;
    *) log "Skipping agent tailoring."; return 0 ;;
  esac

  local test_cmd build_cmd lint_cmd
  test_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" test)"
  build_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" build)"
  lint_cmd="$(suggest_cmd_for "${DETECTED_LANG:-none}" lint)"

  printf "[install] test command [%s]: " "$test_cmd"
  read -r ans || ans=""
  [ -n "$ans" ] && test_cmd="$ans"
  printf "[install] build command [%s]: " "$build_cmd"
  read -r ans || ans=""
  [ -n "$ans" ] && build_cmd="$ans"
  printf "[install] lint command [%s]: " "$lint_cmd"
  read -r ans || ans=""
  [ -n "$ans" ] && lint_cmd="$ans"

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
  log "Wrote .ai/reports/install-template-commands.md (manual edit instructions)."
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

  git commit -m "feat(infra): adopt multi-CLI AI coordination framework [from template $TEMPLATE_SHA]"
  log "Committed on branch $BRANCH."
}

# ==========================================================================
# Final summary
# ==========================================================================
print_summary() {
  cat <<EOF

==============================================================================
[install] Install complete (on branch: $BRANCH)
==============================================================================

Template SHA:      $TEMPLATE_SHA
Framework version: $FRAMEWORK_VERSION (stamped in .ai/.framework-version)
Target:            $TARGET
Language detected: ${DETECTED_LANG:-none}

Files tracked (added/modified):
EOF
  if [ -f "$MANIFEST" ]; then
    sort -u "$MANIFEST" | sed 's/^/  - /'
  fi

  cat <<EOF

Phase 6 — follow-up (NOT executed by this script):

  cd "$TARGET"
  # 1. Review the commit
  git log -1 --stat
  # 2. Merge to $ORIGINAL_BRANCH
  git checkout $ORIGINAL_BRANCH
  git merge --no-ff $BRANCH
  # 3. Or roll back cleanly
  git checkout $ORIGINAL_BRANCH
  git branch -D $BRANCH
  rm $ROLLBACK_FILE

Kimi hooks wiring reminder:
  The Kimi CLI reads ~/.kimi/config.toml (user-global) for hook definitions.
  Append .ai/config-snippets/kimi-hooks.toml to ~/.kimi/config.toml to wire
  hooks for this project. (Project-level .kimi/config.toml is not auto-loaded
  by Kimi CLI at time of writing — see .ai/known-limitations.md.)

  cat "$TARGET/.ai/config-snippets/kimi-hooks.toml" >> ~/.kimi/config.toml

EOF
}

# ==========================================================================
# Main
# ==========================================================================
phase0
phase1
phase2
phase3
phase4
phase5
print_summary
