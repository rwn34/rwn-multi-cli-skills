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
# Checks:
#  1. STRICT SEMVER INCREASE. An unchanged version fails (the original rule),
#     and a DOWNGRADE fails too — a lower version doesn't just stay silent, it
#     inverts the drift warning for every adopter at once.
#  2. CHANGELOG HEADING. A bump requires a matching '## [<new-version>]'
#     heading in CHANGELOG.md (0.0.20 shipped with no entry; the gap is still
#     visible in the changelog).
#  3. SUBSTANTIVE SECTION (PR #59). The '## [<new-version>]' section must hold
#     at least one real content line — not empty, and not only Keep-a-Changelog
#     placeholder scaffolding ('- [TODO: ...]', TBD, WIP, '...', an empty '- '
#     bullet, or comments only). Both produce a released version documented by
#     nothing.
#  4. SHIP-LIST AGREEMENT (2026-07-13, handoff 202607122000 "Hole 1").
#     is_versioned's allow/deny lists were a hand-maintained RESTATEMENT of what
#     the installers ship, with nothing keeping them in lockstep — and a live
#     divergence had already crept in (scripts/wt-bootstrap.sh was shipped but
#     unclassified). The first real failure of that class: someone adds a file
#     the installer copies, forgets is_versioned, and it ships to adopters with
#     no version bump — the exact bug this gate exists to prevent, arriving
#     through the gate's own blind spot. So every run now DERIVES the ship list
#     from the installers themselves (the copy_dir/copy_file calls in
#     scripts/install-template.sh, plus the manifests in
#     tools/multi-cli-install/scripts/sync-assets.ts and
#     tools/multi-cli-install/src/installer/copy-framework.ts) and asserts that
#     every shipped path — every TRACKED file under a shipped dir, plus each
#     shipped file — has an EXPLICIT is_versioned verdict (allow or deny), never
#     the catch-all "no opinion" (return 2). The denylist stays legitimately
#     hand-curated (runtime/generated paths); the check only forces every
#     shipped path to carry a DELIBERATE verdict. It runs against the repo THIS
#     SCRIPT lives in (override: CVB_REPO_ROOT), so it bites in CI, in local
#     runs, and in the test suite's throwaway repos.
#     What it does NOT close: it classifies PATHS, not content — a shipped path
#     deliberately denylisted (docs/*, .archive/*) still ships changes bump-free
#     by curators' choice. And the two installers do not ship identical sets
#     (the bash installer ships more than the npm-path installer); this check
#     unions them, it does not reconcile them.
#  5. UNRELEASED PROVENANCE (2026-07-13, handoff 202607122000 "Hole 2").
#     Check 3 proves the new section is non-empty, not that its bullets describe
#     THIS release: under a parallel merge train the first symptom of a botched
#     promotion is a heading whose bullets belong to a different PR. The
#     push-mode gate has both master tips, so it now asserts a mechanical
#     provenance claim: every substantive line of the new '## [<new-version>]'
#     section must appear VERBATIM in BASE's '## [Unreleased]' and be GONE from
#     HEAD's — the promoted bullets must have come from the Unreleased section
#     this push emptied. Bullets invented at promotion time, bullets merely
#     COPIED (left behind in HEAD's Unreleased), and reworded bullets all FAIL.
#     A missing/placeholder-only Unreleased at BASE, or a missing CHANGELOG at
#     BASE, fails closed.
#     What it does NOT close: (a) provenance is to the UNRELEASED SECTION, not
#     to the PR — stale leftover Unreleased bullets from an older PR satisfy the
#     check while describing the wrong change; (b) matching is verbatim per line
#     after whitespace normalization, so a correctly-promoted but hand-EDITED
#     bullet fails too — by design: edit the Unreleased bullet first, then
#     promote it; (c) only the section named by HEAD's version is checked, so
#     intermediate version sections in a multi-merge push are not; (d) it cannot
#     judge whether a bullet's TEXT truthfully describes the change — a human
#     still reads the entry at release.
#
# Unparseable/missing input on any check fails CLOSED: a gate that cannot parse
# its input refuses, never waves through.
#
# '## [Unreleased]' is exempt FROM CHECK 3 by construction, not by a special
# case: check 3 only ever inspects the section named by the NEW SEMVER VERSION,
# and "Unreleased" is not a semver string, so it is never the target. An
# Unreleased section that is empty right after a promotion — the normal steady
# state — is therefore never examined by check 3 (check 5 compares it across
# the push, which is exactly when it SHOULD be empty).
#
# Usage (from repo root):
#   scripts/check-version-bump.sh <base-ref>
#     - CI (push: master): base-ref = the previous master tip (github.event.before)
#     - Local:             base-ref = origin/master (checks your committed diff)
#   BASE_REF=origin/master scripts/check-version-bump.sh
#   CVB_REPO_ROOT=/path    override which repo the check-4 ship-list agreement
#                          inspects (default: the repo THIS SCRIPT lives in, so
#                          the check is meaningful even in the throwaway repos
#                          the test suite builds).
#
# Exit codes: 0 = PASS (no versioned change, or version properly bumped),
#             1 = FAIL (versioned change without a valid bump; ship-list
#                  divergence; unverifiable promotion provenance),
#             2 = usage / environment error (incl. an unresolvable base ref or
#                 an unparsable installer manifest).
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
#
# Return codes: 0 = versioned (allow), 1 = explicitly NOT versioned (deny),
# 2 = NO OPINION (catch-all). Callers treat any non-zero as "not versioned";
# 2 exists so check 4 (ship-list agreement) can distinguish "deliberately
# denied" from "never classified" — a SHIPPED path must never land on 2.
is_versioned() {
  case "$1" in
    # --- denylist: runtime / non-versioned state (never requires a bump) ---
    .ai/activity/*|.ai/reports/*|.ai/research/*|.ai/.scratch/*) return 1 ;;
    .ai/.claim*) return 1 ;;
    .ai/handoffs/.claims/*|.ai/handoffs/.claim*) return 1 ;;
    # quarantine sidecars are runtime plumbing, sibling class of .claims.
    .ai/handoffs/.quarantine/*|.ai/handoffs/.quarantine) return 1 ;;
    .ai/handoffs/to-*) return 1 ;;
    # .archive ships to fresh installs but is PRESERVED on update (per-project
    # history — install-template.sh phase1 skips it in update mode), the same
    # class as .ai/activity: template content on first install, adopter-owned
    # thereafter.
    .archive/*) return 1 ;;
    docs/*) return 1 ;;
    .claude/settings.local.json) return 1 ;;
    # --- allowlist: versioned framework content (requires a bump) ---
    .ai/instructions/*|.ai/tools/*|.ai/tests/*|.ai/config-snippets/*) return 0 ;;
    .ai/sync.md|.ai/known-limitations.md|.ai/cli-map.md|.ai/README.md) return 0 ;;
    .ai/handoffs/README.md|.ai/handoffs/template.md) return 0 ;;
    .claude/*|.kimi/*|.kiro/*|.opencode/*) return 0 ;;
    scripts/git-hooks/*|scripts/install-template.sh) return 0 ;;
    # Shipped-to-adopters scripts the installer copies (install-template.sh
    # phase1 copy_file calls). NOT tools/4ai-panes/** — that is deliberately
    # not shipped that way (the STUB in install-template.sh says so).
    scripts/fleet-init.sh|scripts/sync-4ai-panes-install.ps1|scripts/wt-bootstrap.sh) return 0 ;;
    # .gitignore is bundled by sync-assets.ts and MERGED into adopter .gitignore
    # by adapt-policy — adopters receive it, so changes must bump.
    CLAUDE.md|AGENTS.md|opencode.json|.codegraph/config.json|.gitignore) return 0 ;;
    .github/workflows/framework-check.yml|.github/workflows/gates.yml) return 0 ;;
    # --- everything else: NO OPINION (2), not an explicit deny (1) ---
    # Project source and CI-side files (including this script itself — it is
    # not shipped to adopters) land here. Check 4 FAILS any shipped path that
    # does; non-shipped paths here simply never require a bump.
    *) return 2 ;;
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

# substantive_lines <section> <file> — print the section's substantive content
# lines, one per line, NORMALIZED (bullet marker stripped, whitespace squeezed
# to single spaces). Returns 1 if the section heading is absent (fail closed).
# "Substantive" excludes exactly what section_is_substantive ignores: blank
# lines, '### ' sub-headings, HTML comments (including blocks), and placeholder
# lines — so check 5 compares precisely the lines check 3 accepted.
substantive_lines() {
  local section="$1" file="$2" body line text in_comment=0
  body="$(changelog_section "$section" "$file")" || return 1

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
    # Squeeze internal whitespace so a re-indented bullet still matches
    # verbatim across the promotion (single line here — no newlines involved).
    text=$(printf '%s' "$text" | tr -s '[:space:]' ' ')
    printf '%s\n' "$text"
  done <<EOF
$body
EOF

  return 0
}

# section_is_substantive <version> <file> — 0 iff the '## [<version>]' section
# exists AND holds at least one real content line. A missing/unreadable section
# returns 1 (fail closed). Thin wrapper over substantive_lines, which carries
# the actual filter (shared with check 5).
section_is_substantive() {
  local lines
  lines="$(substantive_lines "$1" "$2")" || return 1
  [ -n "$lines" ]
}

# extract_ts_list <file> <anchor-regex> — print the single-quoted entries of a
# TS manifest list, from the line matching <anchor-regex> through the first
# line containing ']'. Same extraction shape as .ai/tools/check-asset-drift.sh.
extract_ts_list() {
  awk "/$2/{f=1} f{print} f&&/\]/{exit}" "$1" | grep -o "'[^']*'" | tr -d "'"
}

# check_ship_list_agreement — check 4 (see header). Derives the installer ship
# list from the installers themselves and asserts every shipped path has an
# EXPLICIT is_versioned verdict (0 or 1, never the catch-all 2).
# Returns: 0 = agreement, 1 = divergence (prints the offending paths),
#          2 = a manifest is missing/unparsable or the root is not a git repo.
# Inspects ${CVB_REPO_ROOT:-the repo this script lives in}.
check_ship_list_agreement() {
  local root="${CVB_REPO_ROOT:-}"
  if [ -z "$root" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  local inst="$root/scripts/install-template.sh"
  local pkg="$root/tools/multi-cli-install"
  local cf="$pkg/src/installer/copy-framework.ts"
  local sa="$pkg/scripts/sync-assets.ts"

  [ -f "$inst" ] || { echo "check-version-bump: ship-list agreement: missing $inst"; return 2; }
  [ -f "$cf" ]   || { echo "check-version-bump: ship-list agreement: missing $cf"; return 2; }
  [ -f "$sa" ]   || { echo "check-version-bump: ship-list agreement: missing $sa"; return 2; }
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "check-version-bump: ship-list agreement: $root is not a git repo"; return 2; }
  grep -q "FRAMEWORK_DIRS" "$cf" || {
    echo "check-version-bump: ship-list agreement: cannot parse FRAMEWORK_DIRS in $cf"; return 2; }
  grep -q "FRAMEWORK_FILES" "$cf" || {
    echo "check-version-bump: ship-list agreement: cannot parse FRAMEWORK_FILES in $cf"; return 2; }
  grep -qE "for \(const d of" "$sa" || {
    echo "check-version-bump: ship-list agreement: cannot parse the dir manifest in $sa"; return 2; }
  grep -qE "for \(const f of" "$sa" || {
    echo "check-version-bump: ship-list agreement: cannot parse the file manifest in $sa"; return 2; }

  local entries
  entries=$(
    {
      # bash installer: literal copy_dir/copy_file arguments on non-comment
      # lines (comment lines are excluded so the STUB's
      # `copy_dir "tools/4ai-panes"` guidance is not mistaken for a ship entry).
      # Entries are TAGGED d:/f: with the manifest's own dir-vs-file claim, so
      # a file entry absent from this checkout is still classified as a file
      # path instead of being mistaken for a dir.
      grep -vE '^[[:space:]]*#' "$inst" | grep -oE 'copy_dir[[:space:]]+"[^"]+"'  | cut -d'"' -f2 | sed 's/^/d:/'
      grep -vE '^[[:space:]]*#' "$inst" | grep -oE 'copy_file[[:space:]]+"[^"]+"' | cut -d'"' -f2 | sed 's/^/f:/'
      extract_ts_list "$cf" 'FRAMEWORK_DIRS[[:space:]]*='  | sed 's/^/d:/'
      extract_ts_list "$cf" 'FRAMEWORK_FILES[[:space:]]*=' | sed 's/^/f:/'
      extract_ts_list "$sa" 'for \(const d of' | sed 's/^/d:/'
      extract_ts_list "$sa" 'for \(const f of' | sed 's/^/f:/'
    } | sort -u
  )
  [ -n "$entries" ] || {
    echo "check-version-bump: ship-list agreement: no ship entries parsed from any manifest"
    return 2; }

  local divergent="" e kind path f rc files probe
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    kind="${e%%:*}"; path="${e#*:}"
    if [ "$kind" = "f" ]; then
      # shipped file: the path itself must be classified
      is_versioned "$path"; rc=$?
      [ "$rc" -eq 2 ] && divergent="${divergent}${path}"$'\n'
    else
      # shipped dir: every TRACKED file under it must be classified. If
      # nothing is tracked yet, probe a representative path so a future file
      # cannot slip through the catch-all either. Tracked files are the
      # deterministic contract — the installers run from clean checkouts /
      # regenerated asset trees.
      files=$(git -C "$root" ls-files -- "$path")
      if [ -n "$files" ]; then
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          is_versioned "$f"; rc=$?
          [ "$rc" -eq 2 ] && divergent="${divergent}${f}"$'\n'
        done <<EOF
$files
EOF
      else
        probe="$path/.__cvb_probe__"
        is_versioned "$probe"; rc=$?
        [ "$rc" -eq 2 ] && divergent="${divergent}${probe}   (dir '$path' has no tracked files yet)"$'\n'
      fi
    fi
  done <<EOF
$entries
EOF

  if [ -n "$divergent" ]; then
    echo "check-version-bump: ship-list agreement FAILED — these paths ship to adopters but"
    echo "is_versioned has NO explicit verdict for them (they fall through to the catch-all):"
    printf '%s' "$divergent" | sort -u | sed 's/^/  - /'
    echo "Add each to the is_versioned allowlist (versioned) or denylist (explicitly"
    echo "non-versioned) in scripts/check-version-bump.sh — a shipped path must never"
    echo "stay unclassified, or it ships to adopters with no version bump."
    return 1
  fi
  return 0
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

  # Check 4 — ship-list agreement. The gate's own is_versioned must hold an
  # EXPLICIT verdict for every path the installers ship; otherwise a file can
  # reach adopters with no version bump through the gate's own blind spot. It
  # runs BEFORE the diff: a gate whose classifier disagrees with the installers
  # cannot be trusted to classify the diff at all.
  agreement_out=$(check_ship_list_agreement 2>&1); agreement_rc=$?
  if [ "$agreement_rc" -ne 0 ]; then
    printf '%s\n' "$agreement_out"
    if [ "$agreement_rc" -eq 2 ]; then
      exit 2
    fi
    echo ""
    echo "FAIL: is_versioned disagrees with the installer ship list (check 4)."
    echo "      Give every shipped path an explicit verdict in is_versioned."
    exit 1
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

  # ...and the heading must have something UNDER it (check 3). An empty or
  # placeholder-only section is a version documented by nothing: the promotion
  # of the '## [Unreleased]' bullets (ADR-0012) silently did not happen.
  # Check 5 below then verifies WHERE the bullets came from.
  if ! section_is_substantive "$new_version" "$CHANGELOG"; then
    echo ""
    echo "FAIL: $CHANGELOG '## [$new_version]' section has no substantive content."
    echo "      It is empty, or holds only placeholders (TODO/TBD/WIP/'...'/empty bullet/comments)."
    echo "      Under ADR-0012 the release-engineer promotes the accumulated '## [Unreleased]'"
    echo "      bullets into '## [$new_version]' at merge — that promotion did not happen."
    echo "      Move the real notes under the heading (and strip the TODO scaffolding)."
    exit 1
  fi

  # Check 5 — Unreleased provenance. Every substantive line of the new section
  # must appear verbatim in BASE's '## [Unreleased]' and be gone from HEAD's.
  base_changelog_tmp=$(mktemp) || { echo "check-version-bump: mktemp failed (env error)"; exit 2; }
  trap 'rm -f "$base_changelog_tmp"' EXIT
  if ! git show "$BASE_REF:$CHANGELOG" > "$base_changelog_tmp" 2>/dev/null; then
    echo ""
    echo "FAIL: cannot read $CHANGELOG at $BASE_REF — cannot verify that the"
    echo "      '## [$new_version]' bullets came from this push's '## [Unreleased]'."
    echo "      FAIL CLOSED: an unverifiable promotion never waves through."
    exit 1
  fi
  if ! unreleased_base=$(substantive_lines "Unreleased" "$base_changelog_tmp"); then
    echo ""
    echo "FAIL: $CHANGELOG at $BASE_REF has no '## [Unreleased]' section — cannot verify"
    echo "      promotion provenance. FAIL CLOSED."
    exit 1
  fi
  unreleased_head=$(substantive_lines "Unreleased" "$CHANGELOG" || true)
  # gone = substantive Unreleased lines at BASE that are no longer present at HEAD
  if [ -n "$unreleased_head" ]; then
    gone=$(printf '%s\n' "$unreleased_base" | grep -Fvx -f <(printf '%s\n' "$unreleased_head") || true)
  else
    gone="$unreleased_base"
  fi
  promoted=$(substantive_lines "$new_version" "$CHANGELOG")
  wrong=""
  while IFS= read -r cline; do
    [ -n "$cline" ] || continue
    if ! printf '%s\n' "$gone" | grep -Fxq -- "$cline"; then
      wrong="${wrong}${cline}"$'\n'
    fi
  done <<EOF
$promoted
EOF
  if [ -n "$wrong" ]; then
    echo ""
    echo "FAIL: '## [$new_version]' holds bullets that did NOT come from this push's '## [Unreleased]':"
    printf '%s' "$wrong" | sed 's/^/    /'
    if [ -z "$unreleased_base" ]; then
      echo "      (BASE's '## [Unreleased]' held NO substantive bullets at all.)"
    fi
    echo "      Under ADR-0012 the release-engineer PROMOTES the accumulated Unreleased bullets:"
    echo "      each must appear verbatim in BASE's Unreleased and be cleared from HEAD's."
    echo "      Fix: add the real note under '## [Unreleased]' first, then promote it."
    exit 1
  fi

  echo "check-version-bump: version bumped $old_version -> $new_version with a substantive CHANGELOG entry promoted from this push's [Unreleased] — PASS"
  exit 0
}

if [ "${CHECK_VERSION_BUMP_LIB:-0}" != "1" ]; then
  main "$@"
fi
