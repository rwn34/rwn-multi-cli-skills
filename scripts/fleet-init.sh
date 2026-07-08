#!/usr/bin/env bash
# fleet-init.sh — idempotently scaffold the cross-orchestrator coordination tier
# (`.fleet/`) from .ai/research/worktree-multi-project-topology.md section 5.
#
# `.fleet/` is a third coordination plane spanning projects, mirroring a single
# project's `.ai/` one level up: a project whitelist (registry.json), per-project
# inter-orchestrator handoff queues, and a fleet-level activity log. Per the
# user's accepted decision (design section 8), `.fleet/` is its OWN small git
# repo for auditability — this script `git init`s it.
#
# Usage: bash scripts/fleet-init.sh [--root <dir>] [<project>[:<talks_to,...>] ...]
#        (default --root: the PARENT of the current git repo's toplevel)
#
# Sourcing this file does nothing — `.fleet/` is created only when invoked.
#
# Companion to scripts/wt-bootstrap.sh (code plane). This is the fleet plane.
#
# Requirements: bash, git. Git Bash (Windows) + Linux/macOS compatible.

set -euo pipefail

# ---------- logging ----------
log()  { echo "[fleet-init] $*"; }
warn() { echo "[fleet-init] WARN: $*" >&2; }
err()  { echo "[fleet-init] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- help ----------
usage() {
  cat <<'EOF'
fleet-init.sh — scaffold the cross-orchestrator coordination tier (.fleet/), idempotent.

Usage:
  bash scripts/fleet-init.sh [--root <dir>] [<project>[:<talks_to,comma,sep>] ...]

Arguments:
  --root <dir>   Where to create .fleet/. Default: the PARENT of the current
                 git repo's toplevel (e.g. cwd ~/Code/myrepo => root ~/Code,
                 so .fleet/ lands at ~/Code/.fleet/).
  <project>...   Project specs. "a:b,c" sets project a's talks_to = [b, c].
                 A bare "a" gives project a an empty talks_to.

What it does:
  1. Create <root>/.fleet/ if absent, and `git init` it (its own repo) unless
     it is already a git repository.
  2. Create handoffs/to-<project>/{open,done}/ for each named project, plus
     activity/. Empty dirs get a .gitkeep so git tracks them.
  3. Create activity/log.md (fleet-level, newest-at-top) only if missing.
  4. Create registry.json only if missing:
       - from the given project specs, or
       - a template with example entries when no specs are given.
     An existing registry.json is NEVER overwritten.
  5. Create README.md (the tier's doc) only if missing.

Safety:
  - Never clobbers an existing registry.json, activity/log.md, or README.md.
  - Sourcing this file has no side effects.

Notes:
  - registry.json `path` values are best-effort (<root>/<project>); the script
    cannot know real on-disk paths. Review and edit them after running.

Options:
  --help, -h     Show this help and exit.
EOF
}

# ---------- arg parsing ----------
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
  esac
done

ROOT_ARG=""
SPECS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --root)    shift; [ "$#" -gt 0 ] || die "--root needs a directory argument"; ROOT_ARG="$1" ;;
    --root=*)  ROOT_ARG="${1#--root=}" ;;
    --*)       die "Unknown flag: $1 (see --help)" ;;
    *)         SPECS="${SPECS:+$SPECS }$1" ;;
  esac
  shift
done

# ---------- resolve root ----------
if [ -z "$ROOT_ARG" ]; then
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "Not in a git repo and no --root given; pass --root <dir>."
  ROOT_ARG="$(dirname "$toplevel")"
fi
[ -d "$ROOT_ARG" ] || die "Root dir not found: $ROOT_ARG"
ROOT_DIR="$(cd "$ROOT_ARG" && pwd)"
FLEET_DIR="$ROOT_DIR/.fleet"

log "Root:   $ROOT_DIR"
log "Fleet:  $FLEET_DIR"

# ---------- parse project specs ----------
# PROJECTS: space-separated names. talks_to lookup via per-name variable not
# available in POSIX sh portably, so keep aligned arrays-as-strings.
PROJECTS=""
SPEC_TALKS=""   # newline-separated "name<TAB>t1,t2" pairs
for spec in $SPECS; do
  name="${spec%%:*}"
  talks=""
  case "$spec" in
    *:*) talks="${spec#*:}" ;;
  esac
  [ -n "$name" ] || die "Empty project name in spec: '$spec'"
  PROJECTS="${PROJECTS:+$PROJECTS }$name"
  SPEC_TALKS="$SPEC_TALKS$name	$talks
"
done

# Echo the talks_to for a project name (comma-separated, possibly empty).
talks_for() {
  printf '%s' "$SPEC_TALKS" | while IFS="$(printf '\t')" read -r n t; do
    [ "$n" = "$1" ] || continue
    printf '%s' "$t"
    break
  done
}

# ---------- create .fleet/ + git init ----------
CREATED=""
SKIPPED=""
mark_created() { CREATED="${CREATED:+$CREATED
}  + $1"; }
mark_skipped() { SKIPPED="${SKIPPED:+$SKIPPED
}  - $1"; }

if [ -d "$FLEET_DIR" ]; then
  log "skip   .fleet/ — already exists"
  mark_skipped ".fleet/ (existing)"
else
  mkdir -p "$FLEET_DIR"
  log "create .fleet/"
  mark_created ".fleet/"
fi

if git -C "$FLEET_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  log "skip   git init — .fleet/ is already a git repo"
  mark_skipped "git repo (existing)"
else
  git -C "$FLEET_DIR" init -q
  log "create git repo (own repo, per design section 8)"
  mark_created "git repo"
fi

# ---------- directory structure ----------
gitkeep() {
  dir="$1"
  mkdir -p "$dir"
  [ -e "$dir/.gitkeep" ] || : > "$dir/.gitkeep"
}

for name in $PROJECTS; do
  gitkeep "$FLEET_DIR/handoffs/to-$name/open"
  gitkeep "$FLEET_DIR/handoffs/to-$name/done"
done
mkdir -p "$FLEET_DIR/activity"

if [ -n "$PROJECTS" ]; then
  log "create handoff queues for: $PROJECTS"
  mark_created "handoffs/to-{$(echo "$PROJECTS" | tr ' ' ',')}/{open,done}/"
else
  warn "no project specs given — no handoff queues created (add some later)"
fi

# ---------- activity/log.md ----------
ACTIVITY_LOG="$FLEET_DIR/activity/log.md"
if [ -e "$ACTIVITY_LOG" ]; then
  log "skip   activity/log.md — already exists (never clobbered)"
  mark_skipped "activity/log.md (existing)"
else
  cat > "$ACTIVITY_LOG" <<'EOF'
# Fleet Activity Log

Fleet-level coordination across project orchestrators. Newest entries at the top.
Each orchestrator prepends an entry after substantive cross-project work (sending
or accepting a `.fleet/` handoff, registry changes, cross-orchestrator decisions).

This log is fleet-scoped: it records inter-orchestrator activity only. Intra-project
work belongs in that project's own `.ai/activity/log.md`, not here.

**Timestamp rule:** the `HH:MM` in each entry heading is local wall-clock time at the
moment of prepending (when the work finished, not when it started). Orchestrators on
different local clocks may produce timestamps that don't sort monotonically;
**prepend order is the authoritative sequencing**, timestamps are annotations.

Entry format:

    ## YYYY-MM-DD HH:MM — <orchestrator-name>
    - Action: <one-line summary>
    - Files: <paths, or "—">
    - Decisions: <non-obvious choices, or "—">

---
EOF
  log "create activity/log.md"
  mark_created "activity/log.md"
fi

# ---------- registry.json ----------
REGISTRY="$FLEET_DIR/registry.json"
if [ -e "$REGISTRY" ]; then
  log "skip   registry.json — already exists; NOT overwriting (edit it yourself)"
  mark_skipped "registry.json (existing — left untouched)"
elif [ -n "$PROJECTS" ]; then
  {
    printf '{\n  "projects": {\n'
    first=1
    for name in $PROJECTS; do
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      talks="$(talks_for "$name")"
      # build JSON array from comma-separated talks
      arr=""
      if [ -n "$talks" ]; then
        IFS=','
        for t in $talks; do
          [ -n "$t" ] || continue
          arr="${arr:+$arr, }\"$t\""
        done
        unset IFS
      fi
      printf '    "%s": { "path": "%s", "talks_to": [%s] }' \
        "$name" "$ROOT_DIR/$name" "$arr"
    done
    printf '\n  }\n}\n'
  } > "$REGISTRY"
  log "create registry.json from specs"
  mark_created "registry.json (from specs — VERIFY paths)"
else
  cat > "$REGISTRY" <<'EOF'
{
  "_comment": "Fleet registry: the project whitelist IS the security boundary. Each project lists who it may talk to via talks_to. An orchestrator accepts a .fleet/ handoff only if the sender is in its talks_to. JSON has no comments, so this _comment field documents the schema; the example entries below are placeholders — replace them with your real projects and verify each absolute path.",
  "projects": {
    "project-a": { "path": "~/Code/project-a", "talks_to": ["project-b"] },
    "project-b": { "path": "~/Code/project-b", "talks_to": ["project-a"] }
  }
}
EOF
  log "create registry.json (template — fill it in)"
  mark_created "registry.json (template)"
fi

# ---------- README.md ----------
README="$FLEET_DIR/README.md"
if [ -e "$README" ]; then
  log "skip   README.md — already exists"
  mark_skipped "README.md (existing)"
else
  cat > "$README" <<'EOF'
# `.fleet/` — cross-orchestrator coordination tier

This is the **fleet plane**: a coordination layer spanning multiple projects,
mirroring a single project's `.ai/` one level up. It exists so each project's
Claude orchestrator can coordinate with other projects' orchestrators **without
reaching directly into another project's tree**. Spec:
`.ai/research/worktree-multi-project-topology.md` section 5.

`.fleet/` is its **own small git repo** (decision recorded in design section 8) so
cross-orchestrator coordination is auditable independently of any one project.

## `registry.json` — the whitelist is the security boundary

```json
{
  "projects": {
    "project-a": { "path": "~/Code/project-a", "talks_to": ["project-b"] },
    "project-b": { "path": "~/Code/project-b", "talks_to": ["project-a"] }
  }
}
```

Each entry maps a project name to its on-disk `path` and a `talks_to` list. The
`talks_to` whitelist **is the access-control boundary**: an orchestrator accepts a
handoff in `handoffs/to-<self>/open/` **only if the sender is in its own
`talks_to` list**. No whitelist entry, no accepted handoff. Edit `registry.json`
by hand when projects or trust relationships change — `fleet-init.sh` will never
overwrite an existing registry.

## Two queues, two scopes

| Scope | Where | Between |
|---|---|---|
| **Intra-project** | `project-x/.ai/handoffs/` | a project's Claude ↔ its executors (Kiro/Kimi/Crush) |
| **Inter-orchestrator** | `.fleet/handoffs/` | Claude-A ↔ Claude-B across projects |

Cross-project work is **always** a handoff written into the recipient's
`.fleet/handoffs/to-<recipient>/open/` — never a direct write into another
project's files. This is the per-CLI folder-ownership rule lifted one level up.

## Layout

```
.fleet/
  registry.json              project whitelist + who-may-talk-to-whom
  handoffs/
    to-<project>/open/       inbound cross-orchestrator handoffs (act on these)
    to-<project>/done/       processed handoffs (moved here when complete)
  activity/log.md            fleet-level activity log (newest at top)
```

Scaffold or re-scaffold idempotently with `bash scripts/fleet-init.sh`.
EOF
  log "create README.md"
  mark_created "README.md"
fi

# ---------- summary ----------
echo
log "Summary for $FLEET_DIR"
log "Created:"
printf '%s\n' "${CREATED:-  (nothing — all present)}"
log "Skipped (already present):"
printf '%s\n' "${SKIPPED:-  (none)}"
echo
log "Resolved .fleet/ path: $FLEET_DIR"
log "REMINDER: review registry.json — its \"path\" values are best-effort guesses"
log "          (<root>/<project>); fix any that don't match real on-disk paths."
log "Done."
