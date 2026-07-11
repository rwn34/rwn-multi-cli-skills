#!/bin/bash
# check-version-bump.sh — CI gate (gap D1): fail a PR that changes versioned
# framework content without bumping tools/multi-cli-install/package.json .version.
#
# Why this exists: onboarded projects compare their .ai/.framework-version
# against the template's package.json .version to decide whether to warn the
# operator about drift. If framework *content* changes but the version does NOT,
# every onboarded project's version still equals the template's → the drift
# warning stays silent → drift ships undetected. This check closes that hole by
# requiring a version bump whenever versioned framework content changes in a PR.
#
# Usage (from repo root):
#   scripts/check-version-bump.sh <base-ref>
#   BASE_REF=origin/master scripts/check-version-bump.sh
#
# Exit codes: 0 = PASS (no versioned change, or version was bumped),
#             1 = FAIL (versioned change without a bump),
#             2 = usage / environment error.
#
# Dependency-light on purpose: bash + git + sed/grep only, no npm/node.

set -u

BASE_REF="${1:-${BASE_REF:-}}"
[ -n "$BASE_REF" ] || { echo "check-version-bump: no base ref (pass as arg1 or BASE_REF env)"; exit 2; }

PKG="tools/multi-cli-install/package.json"

# Extract the first "version": "x.y.z" value from package.json content on stdin.
extract_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Is a changed path versioned framework content? Denylist (runtime / generated)
# is checked FIRST so it wins over the broader allowlist prefixes (e.g.
# .claude/settings.local.json is excluded even though .claude/* is versioned).
is_versioned() {
  case "$1" in
    # --- denylist: runtime / non-versioned state (never requires a bump) ---
    .ai/activity/*|.ai/reports/*|.ai/research/*|.ai/.scratch/*) return 1 ;;
    .ai/.claim*) return 1 ;;
    .ai/handoffs/.claims/*|.ai/handoffs/.claim*) return 1 ;;
    .ai/handoffs/to-*) return 1 ;;
    docs/*) return 1 ;;
    .claude/settings.local.json) return 1 ;;
    # --- allowlist: versioned framework content (requires a bump) ---
    .ai/instructions/*|.ai/tools/*|.ai/config-snippets/*) return 0 ;;
    .ai/sync.md|.ai/known-limitations.md|.ai/cli-map.md) return 0 ;;
    .ai/handoffs/README.md|.ai/handoffs/template.md) return 0 ;;
    .claude/*|.kimi/*|.kiro/*|.opencode/*) return 0 ;;
    scripts/git-hooks/*|scripts/install-template.sh) return 0 ;;
    # Shipped-to-adopters scripts the installer copies (install-template.sh:396-397).
    # NOT tools/4ai-panes/** — that is deliberately not shipped that way.
    scripts/fleet-init.sh|scripts/sync-4ai-panes-install.ps1) return 0 ;;
    CLAUDE.md|AGENTS.md|opencode.json|.codegraph/config.json) return 0 ;;
    .github/workflows/framework-check.yml|.github/workflows/gates.yml) return 0 ;;
    # --- everything else: project source, not versioned framework content ---
    *) return 1 ;;
  esac
}

changed=$(git diff --name-only "$BASE_REF"...HEAD)
if [ -z "$changed" ]; then
  echo "check-version-bump: no changed files vs $BASE_REF — PASS"
  exit 0
fi

versioned_hits=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if is_versioned "$f"; then
    versioned_hits="${versioned_hits}${f}"$'\n'
  fi
done <<EOF
$changed
EOF

if [ -z "$versioned_hits" ]; then
  echo "check-version-bump: no versioned framework content changed — PASS"
  exit 0
fi

old_version=$(git show "$BASE_REF:$PKG" 2>/dev/null | extract_version)
new_version=$(extract_version < "$PKG" 2>/dev/null)

echo "Versioned framework content changed:"
printf '%s' "$versioned_hits" | sed 's/^/  - /'
echo "package.json .version: base='$old_version' head='$new_version'"

if [ -z "$new_version" ]; then
  echo "check-version-bump: cannot read HEAD version from $PKG — FAIL"
  exit 1
fi

if [ "$old_version" = "$new_version" ]; then
  echo ""
  echo "FAIL: Framework content changed but $PKG version was not bumped"
  echo "      (still '$new_version') — onboarded projects won't see the drift."
  echo "      Bump the version."
  exit 1
fi

echo "check-version-bump: version bumped $old_version -> $new_version — PASS"
exit 0
