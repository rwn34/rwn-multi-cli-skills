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
# Two further holes closed (handoff 202607120022, 2026-07-12):
#  - The bump must be a strict semver INCREASE. An unchanged version fails (the
#    original rule), but a DOWNGRADE fails too — a lower version doesn't just
#    stay silent, it inverts the drift warning for every adopter at once.
#  - A bump requires a matching '## [<new-version>]' heading in CHANGELOG.md
#    (0.0.20 shipped with no entry; the gap is still visible in the changelog).
#  - Unparseable/missing version on either side fails CLOSED: a gate that
#    cannot parse its input refuses, never waves through.
#
# Usage (from repo root):
#   scripts/check-version-bump.sh <base-ref>
#   BASE_REF=origin/master scripts/check-version-bump.sh
#
# Exit codes: 0 = PASS (no versioned change, or version properly bumped),
#             1 = FAIL (versioned change without a valid bump),
#             2 = usage / environment error.
#
# Dependency-light on purpose: bash + git + sed/grep only, no npm/node.
# Source with CHECK_VERSION_BUMP_LIB=1 to load the functions without running
# the gate (used by scripts/test-check-version-bump.sh).

set -u

PKG="tools/multi-cli-install/package.json"
CHANGELOG="CHANGELOG.md"

# Extract the first "version": "x.y.z" value from package.json content on stdin.
extract_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# is_semver <v> — strict x.y.z, all three components numeric.
is_semver() {
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# version_gt <new> <old> — 0 iff new > old by semantic-version ordering.
# Equal, lower, or unparseable input all return non-0 (callers fail closed).
# Field-wise numeric comparison, NOT string sort: 0.0.10 > 0.0.9 even though
# "0.0.10" < "0.0.9" lexicographically.
version_gt() {
  is_semver "$1" || return 1
  is_semver "$2" || return 1
  local n1 n2 n3 o1 o2 o3
  IFS=. read -r n1 n2 n3 <<<"$1"
  IFS=. read -r o1 o2 o3 <<<"$2"
  # 10# forces base-10 so a leading zero can't be read as octal.
  n1=$((10#$n1)); n2=$((10#$n2)); n3=$((10#$n3))
  o1=$((10#$o1)); o2=$((10#$o2)); o3=$((10#$o3))
  [ "$n1" -gt "$o1" ] && return 0
  [ "$n1" -lt "$o1" ] && return 1
  [ "$n2" -gt "$o2" ] && return 0
  [ "$n2" -lt "$o2" ] && return 1
  [ "$n3" -gt "$o3" ]
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

main() {
  BASE_REF="${1:-${BASE_REF:-}}"
  [ -n "$BASE_REF" ] || { echo "check-version-bump: no base ref (pass as arg1 or BASE_REF env)"; exit 2; }

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

  if ! is_semver "$new_version"; then
    echo ""
    echo "FAIL: cannot parse a strict x.y.z version from HEAD $PKG (got '$new_version')"
    echo "      — a gate that cannot parse its input refuses. Fix the version."
    exit 1
  fi

  if ! is_semver "$old_version"; then
    echo ""
    echo "FAIL: cannot parse a strict x.y.z version from $BASE_REF:$PKG (got '$old_version')"
    echo "      — FAIL CLOSED: refusing to wave through an unverifiable base."
    exit 1
  fi

  if ! version_gt "$new_version" "$old_version"; then
    echo ""
    if [ "$old_version" = "$new_version" ]; then
      echo "FAIL: Framework content changed but $PKG version was not bumped"
      echo "      (still '$new_version') — onboarded projects won't see the drift."
      echo "      Bump the version."
    else
      echo "FAIL: $PKG version $old_version -> $new_version is a DOWNGRADE."
      echo "      Adopters holding '$old_version' would see the drift warning INVERTED."
      echo "      The version must strictly increase."
    fi
    exit 1
  fi

  # A valid bump must ship with its CHANGELOG entry — the missing [0.0.20]
  # heading is the hole this closes. Strictness note: this proves the heading
  # EXISTS, not that the entry is accurate (a human reads it at release).
  if ! grep -q "^## \[$new_version\]" "$CHANGELOG" 2>/dev/null; then
    echo ""
    echo "FAIL: version bumped to '$new_version' but $CHANGELOG has no '## [$new_version]' heading."
    echo "      Add the release entry — a version without a changelog line ships undocumented."
    exit 1
  fi

  echo "check-version-bump: version bumped $old_version -> $new_version with CHANGELOG entry — PASS"
  exit 0
}

if [ "${CHECK_VERSION_BUMP_LIB:-0}" != "1" ]; then
  main "$@"
fi
