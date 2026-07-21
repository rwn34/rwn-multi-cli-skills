#!/bin/bash
# check-changelog-unreleased.sh — PR gate (ADR-0012 follow-up): if a PR touches
# versioned framework content, it must add at least one real bullet under
# CHANGELOG.md '## [Unreleased]'. This closes the "bump-only push silently
# disables the version-bump detective" hole by enforcing provenance at PR time.
#
# The gate is intentionally narrower than the main-push detective: it only
# requires an Unreleased bullet, not a full semver bump. Feature branches still
# do not assign versions.
#
# Usage:
#   bash .ai/tools/check-changelog-unreleased.sh [<base-ref> [<head-ref>]]
#   BASE_REF=origin/main HEAD=HEAD bash .ai/tools/check-changelog-unreleased.sh
#
# Exit codes: 0 = pass (no versioned change, or Unreleased bullet present)
#             1 = fail (versioned change without Unreleased bullet)
#             2 = environment / configuration error (unresolvable ref, etc.)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG="CHANGELOG.md"

BASE_REF="${1:-${BASE_REF:-origin/main}}"
HEAD="${2:-${HEAD:-HEAD}}"

# Reuse the versioned-path predicate from the main-push detective.
CHECK_VERSION_BUMP_LIB=1 . "$REPO_ROOT/scripts/check-version-bump.sh"

# Fail closed on unresolvable refs.
git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || {
  echo "check-changelog-unreleased: base ref '$BASE_REF' does not resolve to a commit" >&2
  exit 2
}
git rev-parse --verify --quiet "$HEAD^{commit}" >/dev/null || {
  echo "check-changelog-unreleased: head ref '$HEAD' does not resolve to a commit" >&2
  exit 2
}

changed=$(git diff --name-only "$BASE_REF"..."$HEAD" 2>/dev/null || true)
if [ -z "$changed" ]; then
  echo "check-changelog-unreleased: no changed files vs $BASE_REF — PASS"
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
  echo "check-changelog-unreleased: no versioned framework content changed — PASS"
  exit 0
fi

echo "Versioned framework content changed:"
printf '%s' "$versioned_hits" | sed 's/^/  - /'

# Extract the body of the '## [Unreleased]' section from a changelog file.
extract_unreleased() {
  local file="$1" line in_section=0 found=0
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "## [Unreleased]"*)
        in_section=1; found=1; continue ;;
      "## "*)
        [ "$in_section" -eq 1 ] && break
        continue ;;
    esac
    [ "$in_section" -eq 1 ] && printf '%s\n' "$line"
  done < "$file"
  [ "$found" -eq 1 ]
}

# Normalize a changelog line to its bullet text (if it is a bullet) or empty.
bullet_text() {
  local line="$1" text
  line="${line%$'\r'}"
  text="${line#"${line%%[![:space:]]*}"}"   # ltrim
  case "$text" in
    -[[:space:]]*|'-') text="${text#-}" ;;
    \*[[:space:]]*|'*') text="${text#\*}" ;;
    +[[:space:]]*|'+') text="${text#+}" ;;
    *) return 0 ;;
  esac
  text="${text#"${text%%[![:space:]]*}"}"   # ltrim
  text="${text%"${text##*[![:space:]]}"}"   # rtrim
  printf '%s' "$text"
}

tmp_base=$(mktemp)
tmp_head=$(mktemp)
cleanup() { rm -f "$tmp_base" "$tmp_head"; }
trap cleanup EXIT

git show "$BASE_REF:$CHANGELOG" 2>/dev/null > "$tmp_base" || true
git show "$HEAD:$CHANGELOG" 2>/dev/null > "$tmp_head" || true

head_found=0
head_unreleased=$(extract_unreleased "$tmp_head" 2>/dev/null) && head_found=1
base_unreleased=$(extract_unreleased "$tmp_base" 2>/dev/null || true)

if [ "$head_found" -eq 0 ]; then
  echo ""
  echo "FAIL: versioned framework content changed but CHANGELOG.md has no '## [Unreleased]' section."
  exit 1
fi

# Build normalized set of base Unreleased bullet texts.
base_bullets_file=$(mktemp)
cleanup() { rm -f "$tmp_base" "$tmp_head" "$base_bullets_file"; }
trap cleanup EXIT

while IFS= read -r line; do
  text=$(bullet_text "$line")
  [ -n "$text" ] && printf '%s\n' "$text"
done <<EOF > "$base_bullets_file"
$base_unreleased
EOF

added_bullets=0
while IFS= read -r line; do
  text=$(bullet_text "$line")
  [ -n "$text" ] || continue
  if ! grep -qxF "$text" "$base_bullets_file"; then
    added_bullets=$((added_bullets + 1))
  fi
done <<EOF
$head_unreleased
EOF

if [ "$added_bullets" -eq 0 ]; then
  echo ""
  echo "FAIL: versioned framework content changed but CHANGELOG.md '## [Unreleased]' has no new bullet."
  echo "      Add a bullet describing the change under '## [Unreleased]'."
  exit 1
fi

echo "check-changelog-unreleased: $added_bullets new Unreleased bullet(s) — PASS"
exit 0
