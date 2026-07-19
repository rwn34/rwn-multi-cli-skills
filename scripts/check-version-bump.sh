#!/bin/bash
# check-version-bump.sh — CI DETECTIVE gate (ADR-0012): after a merge lands on
# main, fail the main-push run if versioned framework content changed without
# a strict semver bump of tools/multi-cli-install/package.json .version (+ its
# matching CHANGELOG heading). It runs on `push: main`, comparing the PREVIOUS
# main tip to the NEW one — NOT on feature-branch PRs.
#
# Why the trigger moved (ADR-0012, 2026-07-12): requiring the bump on every
# feature branch forced N concurrent PRs to collide on the same two lines
# (package.json .version + the CHANGELOG heading), hand-serializing an otherwise
# parallel merge train and risking a merge-order version downgrade. The
# release-engineer now assigns ONE version at the single serialized merge point;
# this gate verifies — detectively, on the resulting main push — that the
# assignment actually happened. Feature-branch PRs deliberately do NOT bump.
#
# Why it still exists at all: onboarded projects compare their .ai/.framework-version
# against the template's package.json .version to decide whether to warn the
# operator about drift (tools/4ai-panes/Selector.ps1 `Test-FrameworkDrift` and the
# Node installer's tools/multi-cli-install/src/upgrade/version.ts). If framework
# *content* changes on main but the version does NOT, every onboarded project's
# version still equals the template's → the drift warning stays silent → drift
# ships undetected. One increment per merge keeps adopter drift-detection honest.
#
# Checks:
#  - The bump must be a strict semver INCREASE. An unchanged version fails (the
#    original rule), but a DOWNGRADE fails too — a lower version doesn't just
#    stay silent, it inverts the drift warning for every adopter at once.
#  - A bump requires a matching '## [<new-version>]' heading in CHANGELOG.md
#    (0.0.20 shipped with no entry; the gap is still visible in the changelog).
#  - The '## [<new-version>]' section must be SUBSTANTIVE — not empty or
#    placeholder-only (closes the gap ADR-0012 itself opened).
#  - The '## [<new-version>]' bullets must have been promoted from the
#    '## [Unreleased]' bullets that disappeared between BASE and HEAD
#    (closes the wrong-content hole; see limitations below).
#  - The versioned-path allowlist (is_versioned) must agree with what the
#    installers actually ship to adopters (closes the hand-maintained-restatement
#    hole). This self-check runs when the installer sources are present.
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
# The promoted-bullets check (closes the wrong-content hole):
# the gate has both master tips (BASE and HEAD), so it diffs '## [Unreleased]'
# across BASE...HEAD and asserts that every bullet under the new '## [x.y.z]'
# heading appears in the set of Unreleased bullets that disappeared in the same
# push. This is a MECHANICAL check, not a semantic one.
#
# What this does NOT close — be honest about the residual holes:
#   - It does NOT prove the bullets DESCRIBE THE RIGHT PR. It only proves they
#     were promoted from the Unreleased section that just emptied. A PR that
#     never added Unreleased bullets in the first place, then invents bullets
#     directly under the version heading, still fails — but only because the
#     bullets cannot be found in the disappeared Unreleased set.
#   - It does NOT tolerate hand-edits during promotion. If the release-engineer
#     promotes the right bullets but rewords, rewraps, or adds a date, the
#     normalized bullet text no longer matches and the check fails. This is
#     intentional: the check is mechanical, not a semantic similarity judgment.
#   - It does NOT close a truly empty Unreleased section that gets promoted
#     with invented bullets; that case is already caught as "not from Unreleased".
# A human still reads the entry at release.
#
# The manifest-sync check (closes the hand-restatement hole):
# is_versioned() must agree with the union of the three installer ship manifests
# (scripts/install-template.sh, tools/multi-cli-install/scripts/sync-assets.ts,
# tools/multi-cli-install/src/installer/copy-framework.ts). If a path reaches
# adopters but is_versioned() does not consider it versioned, a change can ship
# silently. If is_versioned() considers a path versioned but no installer ships
# it, the gate demands bumps for changes adopters never receive. Both divergences
# fail closed. The runtime/state denylist (.ai/activity/*, .claude/settings.local.json,
# etc.) is legitimately hand-curated and is respected by this check.
#
# '## [Unreleased]' is exempt BY CONSTRUCTION, not by a special case: the gate
# only ever inspects the section named by the NEW SEMVER VERSION, and
# "Unreleased" is not a semver string, so it is never the target. An Unreleased
# section that is empty right after a promotion — the normal steady state — is
# therefore never examined and can never fail this gate.
#
# Usage (from repo root):
#   scripts/check-version-bump.sh <base-ref>
#     - CI (push: main): base-ref = the previous main tip (github.event.before)
#     - Local:             base-ref = origin/main (checks your committed diff)
#   BASE_REF=origin/main scripts/check-version-bump.sh
#
# Exit codes: 0 = PASS (no versioned change, or version properly bumped),
#             1 = FAIL (versioned change without a valid bump),
#             2 = usage / environment / configuration error (incl. an
#                 unresolvable base ref or an allowlist↔manifest divergence).
#
# Dependency-light on purpose: bash + git + sed/grep only, no npm/node.
# Source with CHECK_VERSION_BUMP_LIB=1 to load the functions without running
# the gate (used by scripts/test-check-version-bump.sh).

set -u

PKG="tools/multi-cli-install/package.json"
CHANGELOG="CHANGELOG.md"
INSTALL_TEMPLATE="scripts/install-template.sh"
SYNC_ASSETS="tools/multi-cli-install/scripts/sync-assets.ts"
COPY_FRAMEWORK="tools/multi-cli-install/src/installer/copy-framework.ts"

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

# Denylist for paths inside shipped directories that are runtime/state/local.
# These are never versioned framework content, even though the directory that
# contains them is shipped to adopters.
is_denylisted() {
  case "$1" in
    .ai/activity/*|.ai/reports/*|.ai/research/*|.ai/.scratch/*) return 0 ;;
    .ai/.claim*) return 0 ;;
    .ai/.framework-version) return 0 ;;
    .ai/handoffs/.claims/*|.ai/handoffs/.claim*|.ai/handoffs/.quarantine/*) return 0 ;;
    .ai/handoffs/to-*) return 0 ;;
    .claude/settings.local.json) return 0 ;;
    *) return 1 ;;
  esac
}

# Is a changed path versioned framework content? Denylist (runtime / generated)
# is checked FIRST so it wins over the broader allowlist prefixes (e.g.
# .claude/settings.local.json is excluded even though .claude/* is versioned).
#
# The allowlist is kept in lockstep with the installer ship manifests by
# assert_versioned_manifest_sync(); if you add a shipped path, update both.
is_versioned() {
  is_denylisted "$1" && return 1
  case "$1" in
    # --- shipped docs (must precede the broader docs denylist) ---
    docs/architecture/*|docs/specs/4ai-panes-install-sync.md) return 0 ;;
    # --- denylist: project docs not shipped to adopters ---
    docs/*) return 1 ;;
    # --- allowlist: versioned framework content (requires a bump) ---
    .archive/*) return 0 ;;
    .ai/instructions/*|.ai/tools/*|.ai/config-snippets/*|.ai/tests/*) return 0 ;;
    .ai/README.md|.ai/sync.md|.ai/known-limitations.md|.ai/cli-map.md) return 0 ;;
    .ai/handoffs/README.md|.ai/handoffs/template.md) return 0 ;;
    .claude/*|.kimi/*|.kiro/*|.opencode/*) return 0 ;;
    scripts/git-hooks/*) return 0 ;;
    scripts/fleet-init.sh|scripts/sync-4ai-panes-install.ps1|scripts/wt-bootstrap.sh) return 0 ;;
    CLAUDE.md|AGENTS.md|opencode.json|.codegraph/config.json|.gitignore) return 0 ;;
    .github/workflows/framework-check.yml|.github/workflows/gates.yml) return 0 ;;
    # --- everything else: project source / CI-side scripts, not shipped ---
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

# ---------------------------------------------------------------------------
# Installer manifest parsing and allowlist sync check (Hole 1)
# ---------------------------------------------------------------------------

# Parse the bash installer's copy_file/copy_dir calls and emit one line per
# shipped item: F:<file> or D:<dir>.
parse_install_template_manifest() {
  local file="$1"
  [ -f "$file" ] || { echo "parse_install_template_manifest: missing $file" >&2; return 1; }
  sed -n 's/^[[:space:]]*copy_file "\([^"]*\)".*/F:\1/p;
          s/^[[:space:]]*copy_dir "\([^"]*\)".*/D:\1/p' "$file" \
    | sort -u
}

# Extract single-quoted entries from a manifest list in a TypeScript file.
# $1 = file, $2 = regex anchoring the list's opening line.
# Tolerates both inline and multi-line array literals.
extract_ts_list() {
  local file="$1" anchor="$2"
  [ -f "$file" ] || return 0
  awk "/$anchor/{f=1} f{print} f&&/\\]/{exit}" "$file" | grep -o "'[^']*'" | tr -d "'" | sort -u
}

# Parse the Node asset-bundler manifest.
parse_sync_assets_manifest() {
  local file="$1"
  extract_ts_list "$file" 'for \(const d of' | sed 's/^/D:/'
  extract_ts_list "$file" 'for \(const f of' | sed 's/^/F:/'
}

# Parse the Node installer's runtime copy manifest.
parse_copy_framework_manifest() {
  local file="$1"
  extract_ts_list "$file" 'FRAMEWORK_DIRS =' | sed 's/^/D:/'
  extract_ts_list "$file" 'FRAMEWORK_FILES =' | sed 's/^/F:/'
}

# Return the union of shipped paths from all three installers, one per line,
# prefixed F:<file> or D:<dir>.
installer_shipped_paths() {
  local install_template="$1" sync_assets="$2" copy_framework="$3"
  {
    parse_install_template_manifest "$install_template"
    parse_sync_assets_manifest "$sync_assets"
    parse_copy_framework_manifest "$copy_framework"
  } | sort -u
}

# Verify that is_versioned() agrees with the union of the three installer
# ship manifests. Fail closed on any divergence:
#   - a shipped file, or a file under a shipped directory, that is neither
#     accepted by is_versioned() nor on the runtime denylist, or
#   - an existing tracked file that is_versioned() accepts but that is not
#     covered by any shipped file or directory prefix.
assert_versioned_manifest_sync() {
  local install_template="$1" sync_assets="$2" copy_framework="$3"
  local manifest entry path ptype
  local shipped_files shipped_dirs
  local fail=0 f covered d

  manifest="$(installer_shipped_paths "$install_template" "$sync_assets" "$copy_framework")" || return 1

  # Forward check: every shipped file, and every tracked file under a shipped
  # directory, must be either allowlisted or denylisted.
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    ptype="${entry%%:*}"
    path="${entry#*:}"
    case "$ptype" in
      F)
        if ! is_versioned "$path" && ! is_denylisted "$path"; then
          echo "  manifest->allowlist miss: shipped file '$path' is neither versioned nor denylisted" >&2
          fail=1
        fi
        ;;
      D)
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          if ! is_versioned "$f" && ! is_denylisted "$f"; then
            echo "  manifest->allowlist miss: shipped dir '$path' contains tracked file '$f' that is neither versioned nor denylisted" >&2
            fail=1
          fi
        done < <(git ls-files "$path/" 2>/dev/null)
        ;;
      *)
        echo "  unparseable manifest entry: $entry" >&2
        fail=1
        ;;
    esac
  done <<EOF
$manifest
EOF

  # Reverse check: every tracked file that is_versioned() accepts must be
  # covered by a shipped file or a shipped directory prefix.
  shipped_files="$(printf '%s\n' "$manifest" | grep '^F:' | sed 's/^F://' | sort -u)"
  shipped_dirs="$(printf '%s\n' "$manifest" | grep '^D:' | sed 's/^D://' | sort -u)"

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_versioned "$f" || continue
    if printf '%s\n' "$shipped_files" | grep -qxF "$f"; then
      continue
    fi
    covered=0
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$f" in "$d"/*) covered=1; break ;; esac
    done <<EOF
$shipped_dirs
EOF
    if [ "$covered" -eq 0 ]; then
      echo "  allowlist->manifest miss: versioned tracked file '$f' is not covered by any shipped path" >&2
      fail=1
    fi
  done < <(git ls-files 2>/dev/null)

  [ "$fail" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Promoted-bullets provenance check (Hole 2)
# ---------------------------------------------------------------------------

# Extract normalized bullet first-lines from a changelog section body.
# A bullet is a line starting with - / * / + followed by whitespace.
# We strip the bullet marker and trim. Multi-line bullets are NOT reassembled;
# only the first line of each bullet is considered, matching the mechanical
# nature of this check.
extract_bullets() {
  local body="$1" line text
  while IFS= read -r line; do
    line="${line%$'\r'}"
    text="${line#"${line%%[![:space:]]*}"}"  # ltrim
    case "$text" in
      -[[:space:]]*|'-') text="${text#-}" ;;
      \*[[:space:]]*|'*') text="${text#\*}" ;;
      +[[:space:]]*|'+') text="${text#+}" ;;
      *) continue ;;
    esac
    text="${text#"${text%%[![:space:]]*}"}"  # ltrim
    text="${text%"${text##*[![:space:]]}"}"  # rtrim
    [ -n "$text" ] || continue
    printf '%s\n' "$text"
  done <<EOF
$body
EOF
}

# Check that every bullet under '## [version]' in HEAD's CHANGELOG came from
# the '## [Unreleased]' bullets that disappeared between base_ref and HEAD.
# Returns 0 if all promoted bullets are accounted for, 1 otherwise.
bullets_came_from_unreleased() {
  local version="$1" changelog="$2" base_ref="$3"
  local base_unreleased head_unreleased version_section
  local base_bullets head_bullets disappeared version_bullets
  local b v missing=0

  local base_changelog tmp
  tmp="$(mktemp)"
  git show "$base_ref:$changelog" 2>/dev/null > "$tmp" || { rm -f "$tmp"; return 1; }
  base_unreleased="$(changelog_section "Unreleased" "$tmp")" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"

  head_unreleased="$(changelog_section "Unreleased" "$changelog")" || return 1
  version_section="$(changelog_section "$version" "$changelog")" || return 1

  base_bullets="$(extract_bullets "$base_unreleased" | sort -u)"
  head_bullets="$(extract_bullets "$head_unreleased" | sort -u)"
  version_bullets="$(extract_bullets "$version_section" | sort -u)"

  # disappeared = Unreleased bullets present at BASE but no longer present at HEAD
  disappeared=""
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if ! printf '%s\n' "$head_bullets" | grep -qxF "$b"; then
      disappeared="${disappeared}${b}"$'\n'
    fi
  done <<EOF
$base_bullets
EOF

  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if ! printf '%s\n' "$disappeared" | grep -qxF "$v"; then
      echo "  promoted bullet not found in disappeared Unreleased bullets: $v" >&2
      missing=1
    fi
  done <<EOF
$version_bullets
EOF

  [ "$missing" -eq 0 ]
}

main() {
  BASE_REF="${1:-${BASE_REF:-}}"
  [ -n "$BASE_REF" ] || { echo "check-version-bump: no base ref (pass as arg1 or BASE_REF env)"; exit 2; }

  # Fail CLOSED on an unresolvable base ref. On `push: main` the base is
  # github.event.before, which is the all-zero SHA on a branch-create/force-push
  # edge — a gate that cannot resolve its comparison point refuses (env error),
  # it never waves through.
  git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null || {
    echo "check-version-bump: base ref '$BASE_REF' does not resolve to a commit — cannot diff (env error)"
    exit 2
  }

  # Self-check: the versioned-path allowlist must stay in lockstep with the
  # installer ship manifests. Skip in throwaway test repos where the installer
  # sources are absent; fail closed if the sources are present but disagree.
  if [ -f "$INSTALL_TEMPLATE" ] && [ -f "$SYNC_ASSETS" ] && [ -f "$COPY_FRAMEWORK" ]; then
    if ! assert_versioned_manifest_sync "$INSTALL_TEMPLATE" "$SYNC_ASSETS" "$COPY_FRAMEWORK"; then
      echo ""
      echo "FAIL: versioned-path allowlist is out of sync with the installer ship manifests."
      echo "      The allowlist in is_versioned() must agree with what"
      echo "      $INSTALL_TEMPLATE, $SYNC_ASSETS, and $COPY_FRAMEWORK ship to adopters."
      echo "      Fix the allowlist or the installer manifests so they describe the same set."
      exit 2
    fi
  fi

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
  if ! section_is_substantive "$new_version" "$CHANGELOG"; then
    echo ""
    echo "FAIL: $CHANGELOG '## [$new_version]' section has no substantive content."
    echo "      It is empty, or holds only placeholders (TODO/TBD/WIP/'...'/empty bullet/comments)."
    echo "      Under ADR-0012 the release-engineer promotes the accumulated '## [Unreleased]'"
    echo "      bullets into '## [$new_version]' at merge — that promotion did not happen."
    echo "      Move the real notes under the heading (and strip the TODO scaffolding)."
    exit 1
  fi

  # ...and the bullets under it must have been promoted from the Unreleased
  # section that disappeared in this same push (closes the wrong-content hole).
  if ! bullets_came_from_unreleased "$new_version" "$CHANGELOG" "$BASE_REF"; then
    echo ""
    echo "FAIL: $CHANGELOG '## [$new_version]' section contains bullets that were NOT"
    echo "      promoted from '## [Unreleased]' between $BASE_REF and HEAD."
    echo "      Under ADR-0012 the release-engineer promotes the accumulated Unreleased"
    echo "      bullets into '## [$new_version]' at merge. Add the bullets to"
    echo "      [Unreleased] first, then promote them unchanged."
    echo "      (This check is mechanical: hand-edits during promotion also fail.)"
    exit 1
  fi

  echo "check-version-bump: version bumped $old_version -> $new_version with a substantive, Unreleased-promoted CHANGELOG entry — PASS"
  exit 0
}

if [ "${CHECK_VERSION_BUMP_LIB:-0}" != "1" ]; then
  main "$@"
fi
