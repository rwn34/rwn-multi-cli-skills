#!/bin/bash
# path-policy.sh — SHARED path-normalization + territorial-policy library.
# Installs to .claude/hooks/lib/path-policy.sh.
#
# Sourced by BOTH pretool-write-edit.sh (Write|Edit guard) and pretool-bash.sh
# (Bash guard). It is the SINGLE SOURCE OF TRUTH for:
#   * path canonicalization (Windows/MSYS/mixed-separator -> POSIX, lexical),
#   * the territorial / sensitive-file / root-file policy (classify_path).
# Neither hook re-implements either. The recurring bug this closes is two
# enforcement surfaces drifting on normalization OR policy — extracting both
# here makes drift impossible: there is only one implementation to be wrong.
#
# Contract:
#   * Pure functions. NO side effects, NO `exit`. The library never terminates
#     the caller — it CLASSIFIES and returns; the hook decides how to react.
#     (The old inlined code called `exit 2` directly; that cannot live in a
#     sourced lib without killing whichever hook sourced it.)
#   * fail-CLOSED: a path shape that cannot be canonicalized returns non-zero
#     (canonicalize_and_relativize) — the caller MUST block on that, never allow.
#   * Deliberately LEXICAL — NO realpath / cygpath. Two load-bearing reasons:
#       1. realpath/cygpath RESOLVE symlinks + Windows junctions; per ADR-0004
#          the .ai/ dir inside an executor worktree IS a junction — resolving it
#          would relocate every .ai/ write outside the worktree and make Rule 2.6
#          block legitimate handoff writes.
#       2. An external converter re-opens the fail-OPEN door: `cygpath -u C:`
#          returns "/c" and `cygpath -u 'C:foo'` returns a path rather than an
#          error, so the two shapes we deliberately REFUSE (bare drive,
#          drive-relative) would sail through. A refusal here must be FINAL.

# to_posix <path> — lexical Windows/MSYS -> POSIX form. Returns 1 (no output) on
# a shape we refuse to guess at, so the caller can fail closed.
to_posix() {
    local p="$1" d
    [ -n "$p" ] || return 1
    p="${p//\\//}"                              # backslashes -> forward slashes
    case "$p" in
        [A-Za-z]:/*)                            # C:/x -> /c/x   (drive letter folded)
            d=$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')
            p="/$d/${p#?:/}" ;;
        [A-Za-z]:)      return 1 ;;             # bare "C:" — a drive, not a file
        [A-Za-z]:*)     return 1 ;;             # "C:foo" — drive-RELATIVE, ambiguous
        /[A-Za-z]/*|/[A-Za-z])                  # /C/x -> /c/x   (MSYS form, upper drive)
            d=$(printf '%s' "${p:1:1}" | tr 'A-Z' 'a-z')
            p="/$d${p:2}" ;;
    esac
    [ -n "$p" ] || return 1
    printf '%s' "$p"
}

# collapse <posix-path> — lexically remove empty / "." / ".." segments.
# ".." pops the accumulated path; at an absolute root it is clamped.
collapse() {
    local p="$1" seg out="" abs=0
    case "$p" in /*) abs=1 ;; esac
    local IFS='/'
    set -f                                      # path segments must never glob
    for seg in $p; do
        case "$seg" in
            ''|.) : ;;
            ..)
                case "$out" in
                    ''|..|*/..) [ "$abs" -eq 1 ] || out="${out:+$out/}.." ;;
                    */*)        out="${out%/*}" ;;
                    *)          out="" ;;
                esac ;;
            *) out="${out:+$out/}$seg" ;;
        esac
    done
    set +f
    if [ "$abs" -eq 1 ]; then printf '/%s' "$out"; else printf '%s' "$out"; fi
}

# canon_root <raw-pwd> — canonicalize a project root (pwd). Echoes the canonical
# root, or returns 1 (empty output) if it cannot be canonicalized.
canon_root() {
    local r
    r=$(to_posix "$1") || return 1
    r=$(collapse "$r")
    r="${r%/}"
    [ -n "$r" ] || return 1
    printf '%s' "$r"
}

# canonicalize_and_relativize <path> <canonical-project-root>
# Echoes the repo-RELATIVE path if the target is genuinely under the root, or the
# canonical ABSOLUTE path if it is outside (Rules 2.6/2.7 match on the absolute
# form). On any shape it refuses to understand it returns 1 and echoes a
# human reason on stdout instead — the caller MUST block with that reason.
canonicalize_and_relativize() {
    local path="$1" project_root="$2" norm root_lc norm_lc rel
    norm=$(to_posix "$path") || { printf '%s' "could not canonicalize path '$path' (unrecognized or ambiguous shape — e.g. a bare drive 'C:' or a drive-RELATIVE 'C:foo'). Refusing to fail open: an enforcement hook that cannot understand its input must deny."; return 1; }
    [ -n "$norm" ] || { printf '%s' "path '$path' canonicalized to empty — refusing to fail open."; return 1; }
    case "$norm" in
        /*) : ;;                                # already absolute
        *)  norm="$project_root/$norm" ;;       # relative -> resolve against the root
    esac
    norm=$(collapse "$norm")
    [ -n "$norm" ] || { printf '%s' "path '$path' canonicalized to empty — refusing to fail open."; return 1; }
    # Relativize ONLY if genuinely under the root (case-folded compare, real casing
    # preserved in the slice). Trailing "/" is the boundary guard: /c/repo-evil must
    # NOT read as living under /c/repo.
    root_lc=$(printf '%s' "$project_root" | tr 'A-Z' 'a-z')
    norm_lc=$(printf '%s' "$norm" | tr 'A-Z' 'a-z')
    if [ "$norm_lc" = "$root_lc" ]; then
        printf '%s' "path '$path' resolves to the project root directory itself, not a file — refusing to fail open."; return 1
    elif [ "${norm_lc#"$root_lc"/}" != "$norm_lc" ]; then
        rel="${norm:$((${#project_root} + 1))}" # genuinely under the root -> repo-relative
    else
        rel="$norm"                             # OUTSIDE the root -> stays ABSOLUTE
    fi
    [ -n "$rel" ] || { printf '%s' "path '$path' normalized to an empty relative path — refusing to fail open."; return 1; }
    printf '%s' "$rel"
}

# classify_path <rel> <canonical-project-root> <agent_type>
# The SINGLE decision point for "is this write path allowed". Echoes exactly one:
#   ALLOW
#   BLOCK:<rule-id>:<human-reason>
# and returns 0. Both hooks call this — write-edit once per file_path, bash once
# per extracted write TARGET — so the two surfaces can never disagree on policy.
# agent_type empty == MAIN THREAD (orchestrator; most restrictive, Rule 2.5).
classify_path() {
    local rel="$1" project_root="$2" agent_type="$3" rel_lc
    rel_lc=$(printf '%s' "$rel" | tr 'A-Z' 'a-z')

    # Rule 1 — framework dirs for OTHER CLIs. Hard block, no exceptions.
    # "*/" arms catch the ABSOLUTE form (a path outside this root that still lands
    # inside some .kimi/.kiro dir). Claude has no business writing one anywhere.
    case "$rel_lc" in
        .kimi|.kimi/*|*/.kimi|*/.kimi/*)
            echo "BLOCK:1:.kimi/ is Kimi CLI's territory. Claude never writes there. Use .ai/handoffs/to-kimi/open/YYYYMMDDHHMM-slug.md to request the change."; return 0 ;;
        .kiro|.kiro/*|*/.kiro|*/.kiro/*)
            echo "BLOCK:1:.kiro/ is Kiro CLI's territory. Claude never writes there. Use .ai/handoffs/to-kiro/open/YYYYMMDDHHMM-slug.md to request the change."; return 0 ;;
        .kimigraph|.kimigraph/*|*/.kimigraph|*/.kimigraph/*)
            echo "BLOCK:1:.kimigraph/ was KimiGraph's dir — tool REMOVED 2026-07-09 (ADR-0003 amendment). Nothing writes here anymore."; return 0 ;;
        .kirograph|.kirograph/*|*/.kirograph|*/.kirograph/*)
            echo "BLOCK:1:.kirograph/ was KiroGraph's dir — tool REMOVED 2026-07-09 (ADR-0003 amendment). Nothing writes here anymore."; return 0 ;;
    esac

    # Rule 1.5 — enforcement-layer self-protection. The guard scripts are
    # owner-apply-ONLY: no agent (not even Claude) edits its own guards via any
    # tool (Write/Edit OR a bash write-command). The Claude harness already
    # refuses Write/Edit here; stating it in the shared classifier closes the SAME
    # door for the Bash surface (the side-door this fix exists to shut) and for any
    # subagent Write/Edit the harness may not cover — one rule, both surfaces.
    case "$rel_lc" in
        .claude/hooks|.claude/hooks/*|*/.claude/hooks|*/.claude/hooks/*)
            echo "BLOCK:1.5:.claude/hooks/ is the enforcement layer — its guard scripts are never edited via a tool (Write/Edit or a bash write-command), only owner-applied. This is the self-modification door and it stays shut."; return 0 ;;
    esac

    # Rule 2 — sensitive-file patterns. Block even for the orchestrator.
    case "$rel_lc" in
        .env|.env.*|*/\.env|*/\.env.*)
            echo "BLOCK:2:Sensitive file pattern (.env*). Do not write secrets from an agent. Ask the user to edit this manually."; return 0 ;;
        *.key|*.pem|*.p12|*.pfx|*/\.key|*/\.pem|*/*.p12|*/*.pfx)
            echo "BLOCK:2:Sensitive file pattern (*.key, *.pem, *.p12, *.pfx). Do not write cryptographic material from an agent. Ask the user to edit manually."; return 0 ;;
        id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|*/id_rsa*|*/id_ed25519*)
            echo "BLOCK:2:SSH private key pattern. Do not write SSH keys from an agent. Ask the user to edit manually."; return 0 ;;
        .aws|.aws/*|*/\.aws|*/\.aws/*)
            echo "BLOCK:2:AWS credentials directory (.aws/). Do not write AWS credentials from an agent. Ask the user to edit manually."; return 0 ;;
        .ssh|.ssh/*|*/\.ssh|*/\.ssh/*)
            echo "BLOCK:2:SSH config directory (.ssh/). Do not write SSH configs from an agent. Ask the user to edit manually."; return 0 ;;
        secrets.*|*.secrets|*-secrets.*|secrets/*|*/secrets.*|*/*.secrets|*/*-secrets.*|credentials|credentials.*|*-credentials.*|*/credentials|*/credentials.*|*/*-credentials.*)
            echo "BLOCK:2:Secrets/credentials file pattern. Do not write secret material from an agent. Ask the user to edit manually."; return 0 ;;
    esac

    # Rule 2.6 — worktree confinement (ADR-0004). Inside an executor worktree
    # (<parent>/.wt/<project>/<executor>/) the only legal targets are inside it
    # (+ the junctioned .ai/). Absolute paths that did not relativize are escapes;
    # so are ../ climbs.
    case "$project_root" in
        */.wt/*/*)
            case "$rel" in
                /*|[A-Za-z]:/*)
                    echo "BLOCK:2.6:Worktree confinement (ADR-0004/ADR-0016): this session runs in executor worktree '$project_root' and may write only inside it (+ the snapshot-copied .ai/). Escaping to '$rel' is blocked — cross-tree changes go through .ai/handoffs/."; return 0 ;;
                ..|../*|*/..|*/../*)
                    echo "BLOCK:2.6:Worktree confinement (ADR-0004): relative path escapes the worktree ('$rel'). Write only inside this worktree; cross-tree changes go through .ai/handoffs/."; return 0 ;;
            esac ;;
    esac

    # Rule 2.7 — fleet whitelist (ADR-0004). Cross-orchestrator handoffs at
    # <root>/.fleet/handoffs/to-<project>/ are legal only if THIS project's
    # talks_to list (in <root>/.fleet/registry.json) includes the target.
    # fail-CLOSED: missing registry blocks.
    local fleet_norm="$rel" fleet_target fleet_root registry project_name
    case "$fleet_norm" in
        .fleet/*) fleet_norm="./$fleet_norm" ;;
    esac
    case "$fleet_norm" in
        */.fleet/handoffs/to-*)
            fleet_target=$(printf '%s' "$fleet_norm" | sed -n 's|.*/\.fleet/handoffs/to-\([^/]*\).*|\1|p')
            fleet_root=$(printf '%s' "$fleet_norm" | sed -n 's|\(.*/\.fleet\)/.*|\1|p')
            registry="$fleet_root/registry.json"
            project_name=$(basename "$project_root")
            if [ ! -f "$registry" ]; then
                echo "BLOCK:2.7:Fleet whitelist (ADR-0004): no registry at '$registry' — cannot verify talks_to for '$fleet_target'. Scaffold the fleet tier first (scripts/fleet-init.sh)."; return 0
            fi
            _fleet_check() { "$1" -c "
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
talks = d.get('projects', {}).get(sys.argv[2], {}).get('talks_to', [])
sys.exit(0 if sys.argv[3] in talks else 1)
" "$registry" "$project_name" "$fleet_target"; }
            if _fleet_check python3 2>/dev/null || _fleet_check python 2>/dev/null; then
                echo "ALLOW"; return 0
            else
                echo "BLOCK:2.7:Fleet whitelist (ADR-0004): '$project_name' is not whitelisted to talk to '$fleet_target' (registry: $registry). Add it to talks_to (owner decision) or route via an allowed project."; return 0
            fi ;;
        */.fleet/*)
            echo "ALLOW"; return 0 ;;           # fleet activity log / README / registry
    esac

    # Rule 2.5 — main-thread delegation (orchestrator pattern / ADR-0002). Empty
    # agent_type == main thread: it writes ONLY framework paths; project-source
    # mutations must come from a subagent.
    if [ -z "$agent_type" ]; then
        case "$rel" in
            .ai|.ai/*) : ;;
            .claude|.claude/*) : ;;
            CLAUDE.md|AGENTS.md) : ;;
            opencode.json|.opencode|.opencode/*) : ;;
            .codegraph|.codegraph/*) : ;;
            .mcp.json|.mcp.json.example) : ;;
            *)
                echo "BLOCK:2.5:Main-thread (orchestrator) write to project path '$rel'. Delegate this to a subagent (coder, doc-writer, tester, ...) — the orchestrator writes only framework paths. See .ai/instructions/orchestrator-pattern/principles.md."; return 0 ;;
        esac
    fi

    # Rule 3 — root-file policy. Path is at root iff it has no "/".
    case "$rel" in
        */*) echo "ALLOW"; return 0 ;;
        "")  echo "ALLOW"; return 0 ;;
        AGENTS.md|README.md|CLAUDE.md) echo "ALLOW"; return 0 ;;
        LICENSE|LICENSE.*) echo "ALLOW"; return 0 ;;
        CHANGELOG|CHANGELOG.*) echo "ALLOW"; return 0 ;;
        CONTRIBUTING.md|SECURITY.md|CODE_OF_CONDUCT.md) echo "ALLOW"; return 0 ;;
        .gitignore|.gitattributes) echo "ALLOW"; return 0 ;;
        .editorconfig) echo "ALLOW"; return 0 ;;
        .dockerignore|.gitlab-ci.yml) echo "ALLOW"; return 0 ;;
        .mcp.json|.mcp.json.example|opencode.json) echo "ALLOW"; return 0 ;;
        *)
            echo "BLOCK:3:Writing '$rel' at repo root violates the root-file policy. See docs/architecture/0001-root-file-exceptions.md for the allowlist. If this is a tooling-required exception not yet in the ADR, surface it to the user for approval + ADR amendment before creating."; return 0 ;;
    esac
}
