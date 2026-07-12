#!/bin/bash
# check-version-bump.sh — CI DETECTIVE gate (ADR-0012): after a merge lands on
# master, fail the master-push run if versioned framework content changed without
# a strict semver bump of tools/multi-cli-install/package.json .version (+ its
# matching CHANGELOG heading). It runs on `push: master`, comparing the PREVIOUS
# master tip to the NEW one — NOT on feature-branch PRs.
#
# Why the trigger moved (ADR-0012, 2026-07-12): requiring the bump on every
# feature branch forced N concurrent PRs to collide on the same two lines
# (package.json .version + the CHANGELOG heading), hand-serializing an otherwise
# parallel merge train and risking a merge-order version downgrade. The
# release-engineer now assigns ONE version at the single serialized merge point;
# this gate verifies — detectively, on the resulting master push — that the
# assignment actually happened. Feature-branch PRs deliberately do NOT bump.
#
# Why it still exists at all: onboarded projects compare their .ai/.framework-version
# against the template's package.json .version to decide whether to warn the
# operator about drift (tools/4ai-panes/Selector.ps1 `Test-FrameworkDrift` and the
# Node installer's tools/multi-cli-install/src/upgrade/version.ts). If framework
# *content* changes on master but the version does NOT, every onboarded project's
# version still equals the template's → the drift warning stays silent → drift
# ships undetected. One increment per merge keeps adopter drift-detection honest.
#
# Checks (unchanged from the PR#44 hardening, handoff 202607120022):
#  - The bump must be a strict semver INCREASE. An unchanged version fails (the
#    original rule), but a DOWNGRADE fails too — a lower version doesn't just
#    stay silent, it inverts the drift warning for every adopter at once.
#  - A bump requires a matching '## [<new-version>]' heading in CHANGELOG.md
#    (0.0.20 shipped with no entry; the gap is still visible in the changelog).
#  - The '## [<new-version>]' section must be SUBSTANTIVE — see below.
#  - Unparseable/missing version on either side fails CLOSED: a gate that
#    cannot parse its input refuses, never waves through.
#
# The substantive-section check (closes the gap ADR-0012 itself opened):
# moving version assignment to merge time means the release-engineer now
# MANUALLY promotes the accumulated '## [Unreleased]' bullets into a versioned
# heading. Asserting only that the heading EXISTS lets two silent-wrong-record
# failures through: an EMPTY section, and a section holding nothing but the
# Keep-a-Changelog placeholder scaffolding ('- [TODO: new features]', TBD, WIP,
# '...', an empty '- ' bullet, or comments only). Both produce a released
# version documented by nothing. So the section must now hold at least one real
# content line between its heading and the next '## ' heading (or EOF).
#
# What this does NOT close — be honest about the residual hole: it does NOT
# prove the bullets DESCRIBE THE PR THAT BUMPED THE VERSION. Under a parallel
# merge train the first symptom of a botched promotion is a version heading
# whose bullets belong to a *different* PR, and that is WRONG CONTENT, not
# empty content. Verifying it needs a reliable "which PR merged here" signal
# this gate does not have. This closes the EMPTY/PLACEHOLDER hole only; a human
# still reads the entry at release.
#
# '## [Unreleased]' is exempt BY CONSTRUCTION, not by a special case: the gate
# only ever inspects the section named by the NEW SEMVER VERSION, and
# "Unreleased" is not a semver string, so it is never the target. An Unreleased
# section that is empty right after a promotion — the normal steady state — is
# therefore never examined and can never fail this gate.
#
# Usage (from repo root):
#   scripts/check-version-bump.sh <base-ref>
#     - CI (push: master): base-ref = the previous master tip (github.event.before)
#     - Local:             base-ref = origin/master (checks your committed diff)
#   BASE_REF=origin/master scripts/check-version-bump.sh
#
# Exit codes: 0 = PASS (no versioned change, or version properly bumped),
#             1 = FAIL (versioned change without a valid bump),
#             2 = usage / environment error (incl. an unresolvable base ref).
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

# changelog_section <version> <file> — print the BODY of the '## [<version>]'
# section: every line strictly between that heading and the next '## ' heading
# (or EOF). Returns 1 if the heading is absent, so callers fail closed on a
# section they cannot parse. Pure bash — no sed/awk escaping games with the
# literal brackets in the heading.
changelog_section() {
  local version="$1" file="$2" line in_section=0 found=0
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"   # tolerate CRLF checkouts
    case "$line" in
      "## [$version]"*)
        in_section=1; found=1; continue ;;
      "## "*)
        # any other top-level heading ends the section we were collecting
        [ "$in_section" -eq 1 ] && break
        continue ;;
    esac
    [ "$in_section" -eq 1 ] && printf '%s\n' "$line"
  done < "$file"
  [ "$found" -eq 1 ]
}

# is_placeholder_line <text> — 0 iff a content line is an obvious placeholder
# rather than a real note. <text> is the line AFTER its bullet marker is
# stripped. Both patterns are ANCHORED AT THE START, so a genuine note that
# merely mentions a keyword ("dropped the TODO scaffolding") is NOT rejected —
# only a line that *opens* as a placeholder is.
is_placeholder_line() {
  local t="$1"
  # Empty is a placeholder (an empty '- ' bullet lands here). Checked BEFORE the
  # greps: `printf '%s' ""` pipes ZERO lines to grep, so an empty string matches
  # no pattern at all and would otherwise be misread as real content.
  [ -z "$t" ] && return 0
  # Nothing but whitespace/punctuation: '   ', '-', '...', '—'.
  printf '%s\n' "$t" | grep -qE '^[[:space:][:punct:]]*$' && return 0
  # Optional leading markers ( [ ( * _ ` ) then a placeholder keyword.
  # '(TODO|...)([^A-Za-z]|$)' instead of '\b' — portable across grep -E flavors.
  printf '%s\n' "$t" \
    | grep -qiE '^[][(*_`[:space:]]*(TODO|TBD|WIP|XXX|PLACEHOLDER)([^A-Za-z]|$)' \
    && return 0
  return 1
}

# section_is_substantive <version> <file> — 0 iff the '## [<version>]' section
# exists AND holds at least one real content line. Ignored as non-content:
# blank lines, '### ' sub-headings (Keep-a-Changelog structure, not notes),
# HTML comments, and placeholder lines. A missing/unreadable section returns 1
# (fail closed).
section_is_substantive() {
  local version="$1" file="$2" body line text in_comment=0
  body="$(changelog_section "$version" "$file")" || return 1

  while IFS= read -r line; do
    line="${line%$'\r'}"

    # HTML comments carry no release information — skip them, including blocks.
    case "$line" in *'<!--'*) in_comment=1 ;; esac
    if [ "$in_comment" -eq 1 ]; then
      case "$line" in *'-->'*) in_comment=0 ;; esac
      continue
    fi

    text="${line#"${line%%[![:space:]]*}"}"    # ltrim
    text="${text%"${text##*[![:space:]]}"}"    # rtrim
    [ -n "$text" ] || continue                 # blank line
    case "$text" in '#'*) continue ;; esac     # '### Fixed' etc: structure

    # Strip one leading bullet marker, then re-trim: '- x' / '* x' / '+ x'.
    case "$text" in
      -[[:space:]]*|'-')    text="${text#-}" ;;
      \*[[:space:]]*|'*')   text="${text#\*}" ;;
      +[[:space:]]*|'+')    text="${text#+}" ;;
    esac
    text="${text#"${text%%[![:space:]]*}"}"

    is_placeholder_line "$text" && continue
    return 0                                   # a real content line — done
  done <<EOF
$body
EOF

  return 1
}

main() {
  BASE_REF="${1:-${BASE_REF:-}}"
  [ -n "$BASE_REF" ] || { echo "check-version-bump: no base ref (pass as arg1 or BASE_REF env)"; exit 2; }

  # Fail CLOSED on an unresolvable base ref. On `push: master` the base is
  # github.event.before, which is the all-zero SHA on a branch-create/force-push
  # edge — a gate that cannot resolve its comparison point refuses (env error),
  # it never waves through.
  git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || {
    echo "check-version-bump: base ref '$BASE_REF' does not resolve to a commit — cannot diff (env error)"
    exit 2
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
  # heading is the hole this closes.
  if ! grep -q "^## \[$new_version\]" "$CHANGELOG" 2>/dev/null; then
    echo ""
    echo "FAIL: version bumped to '$new_version' but $CHANGELOG has no '## [$new_version]' heading."
    echo "      Add the release entry — a version without a changelog line ships undocumented."
    exit 1
  fi

  # ...and the heading must have something UNDER it. An empty or
  # placeholder-only section is a version documented by nothing: the promotion
  # of the '## [Unreleased]' bullets (ADR-0012) silently did not happen.
  # Scope note: this proves the section is SUBSTANTIVE, not that it is ACCURATE
  # — bullets describing the wrong PR still pass. A human reads it at release.
  if ! section_is_substantive "$new_version" "$CHANGELOG"; then
    echo ""
    echo "FAIL: $CHANGELOG '## [$new_version]' section has no substantive content."
    echo "      It is empty, or holds only placeholders (TODO/TBD/WIP/'...'/empty bullet/comments)."
    echo "      Under ADR-0012 the release-engineer promotes the accumulated '## [Unreleased]'"
    echo "      bullets into '## [$new_version]' at merge — that promotion did not happen."
    echo "      Move the real notes under the heading (and strip the TODO scaffolding)."
    exit 1
  fi

  echo "check-version-bump: version bumped $old_version -> $new_version with a substantive CHANGELOG entry — PASS"
  exit 0
}

if [ "${CHECK_VERSION_BUMP_LIB:-0}" != "1" ]; then
  main "$@"
fi
