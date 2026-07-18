#!/bin/bash
# PreToolUse hook — matcher: Bash
# Blocks (a) destructive commands and (b) write-commands whose TARGET path
# violates the territorial / sensitive-file / root-file policy — the same policy
# pretool-write-edit.sh enforces, via the SAME shared classifier. This closes the
# Bash side-door: before this, cp/mv/install/ln/dd/tee/sed -i/redirects could
# write into .kimi/, .claude/hooks/, .env, or root and defeat the Write/Edit guard.
# Reads tool call JSON from stdin; exit 2 + stderr to block.
#
# SCOPE (honest): this stops ACCIDENTAL and STRAIGHTFORWARD-DELIBERATE writes and
# shuts the trivial cp/redirect door. It is NOT a boundary against an adversary
# actively evading its own guard — command substitution ($(...)), eval/sh -c,
# base64-decoded or variable-built paths, and dynamic command NAMES remain
# possible. Those are BLOCKED where detected (fail-closed) rather than parsed, but
# a determined self-evader can still construct writes we cannot statically resolve.

# Extract command + agent_type from stdin JSON.
#
# CRITICAL (fail-CLOSED): extraction MUST NOT depend on python (WindowsApps stub
# prints nothing + exits 0). python is an OPTIONAL fast first attempt; the real
# extractor is a pure-sed fallback that runs whenever the python result is EMPTY.
input=$(cat)

# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$input" | tr -d '[:space:]')" ]; then
    exit 0
fi

cmd=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$cmd" ] && cmd=$(printf '%s' "$input" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
# sed fallback (python-less runtime). Best-effort, not a JSON parser: grabs the
# "command" value greedily to the LAST double-quote. Over-capture is safe for a
# BLOCK hook — it can only match MORE, never less.
[ -z "$cmd" ] && cmd=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

agent_type=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_type','') or '')" 2>/dev/null)
[ -z "$agent_type" ] && agent_type=$(printf '%s' "$input" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_type','') or '')" 2>/dev/null)
[ -z "$agent_type" ] && agent_type=$(printf '%s' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

block() {
    echo "BLOCKED by hook: $1" >&2
    exit 2
}
block_unparseable() {
    block "unparseable command construct ($1) — blocked for safety. This guard refuses to guess at a write target it cannot statically resolve. Simplify the command or ask the user to run it manually."
}

# stdin was non-empty but no command parsed. A Bash tool call always carries
# command, so an empty result means the parse failed — refuse to fail open.
if [ -z "$cmd" ]; then
    block "could not parse tool input (no command found) — refusing to fail open."
fi

# ===========================================================================
# PART A — destructive-command guard (UNCHANGED; orthogonal to path targets).
# ===========================================================================
norm=$(echo "$cmd" | tr -s ' \t' '  ')

# Dangerous rm patterns — broad targets (/ ~ * .). Boundary-aware.
rm_flags='(-[rRfF]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $norm " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    block "'rm -rf' with a broad target (/, ~, *, .) is destructive. Use a specific path, or ask the user to run it manually."
fi

# Force push
case " $norm " in
    *"git push --force"*|*"git push -f "*|*"git push -f"|*"--force-with-lease"*)
        block "Force-push variants (--force, -f, --force-with-lease) overwrite remote history. Route through release-engineer with explicit user approval." ;;
esac

# Hard reset
case " $norm " in
    *"git reset --hard"*|*"git reset -q --hard"*|*"git reset --hard "*)
        block "'git reset --hard' discards uncommitted changes. Ask the user before resetting." ;;
esac

# DROP / TRUNCATE
upper=$(echo "$norm" | tr '[:lower:]' '[:upper:]')
case " $upper " in
    *" DROP DATABASE "*|*" DROP TABLE "*|*" DROP SCHEMA "*|*" TRUNCATE TABLE "*|*"DROP DATABASE "*|*"DROP TABLE "*|*"DROP SCHEMA "*|*"TRUNCATE TABLE "*)
        block "DROP / TRUNCATE destroys data. Route through data-migrator with explicit user confirmation." ;;
esac

# ===========================================================================
# PART B — path-target territorial enforcement (NEW; shared classifier).
# ===========================================================================
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/path-policy.sh"
# shellcheck source=lib/path-policy.sh
. "$LIB" || block "could not source path-policy library ('$LIB') — refusing to fail open."

project_root=$(canon_root "$(pwd 2>/dev/null)") || block "cannot canonicalize the project root (pwd) — refusing to evaluate write rules against an unknown root."

# Commands that write a filesystem target, and shell wrappers we refuse to parse.
WRITE_CMDS=" cp mv install ln dd tee sed "
WRAPPERS=" sh bash dash ash ksh zsh "

is_write_cmd() { case "$WRITE_CMDS" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# classify_target <raw-token> — echoes ALLOW / BLOCK:.. / UNPARSEABLE for one
# extracted write target. Dynamic content ($ / $( / backtick) is UNPARSEABLE:
# we cannot resolve it without running the shell.
classify_target() {
    local t="$1" rel v
    case "$t" in
        *'$'*|*'`'*) echo "UNPARSEABLE"; return 0 ;;
    esac
    [ -n "$t" ] || { echo "UNPARSEABLE"; return 0; }
    rel=$(canonicalize_and_relativize "$t" "$project_root") || { echo "UNPARSEABLE"; return 0; }
    classify_path "$rel" "$project_root" "$agent_type"
}

# handle_target <raw-token> — classify one WRITE target and act on the verdict.
handle_target() {
    local v
    v=$(classify_target "$1")
    case "$v" in
        ALLOW) : ;;
        UNPARSEABLE) block_unparseable "dynamic or un-canonicalizable target '$1'" ;;
        BLOCK:*) block "${v#BLOCK:*:}" ;;
        *) block "policy classifier returned an unrecognized verdict ('$v') — refusing to fail open." ;;
    esac
}

# handle_target_rm <raw-token> — for rm, enforce ONLY territorial (Rule 1/1.5) and
# sensitive (Rule 2) blocks. Deleting an ordinary project/scratch file (src/old.rs,
# /tmp/foo) is legitimate dev work — the main-thread-delegation (2.5) and root-file
# (3) rules are about CREATING project content and do not apply to a delete. Broad
# destructive targets (rm -rf /) stay Part A's job. This is the design's
# "territorial/sensitive, not a second broad-target check" reconciliation.
handle_target_rm() {
    local v rule
    v=$(classify_target "$1")
    case "$v" in
        UNPARSEABLE) block_unparseable "dynamic or un-canonicalizable rm target '$1'" ;;
        BLOCK:*)
            rule="${v#BLOCK:}"; rule="${rule%%:*}"
            case "$rule" in
                1|1.5|2) block "${v#BLOCK:*:}" ;;
            esac ;;
    esac
}

# split_commands <string> — split into simple commands on ; newline && || | &,
# quote-aware and operator-aware (>|, >>, >&, &>, 2>&1 are NOT separators).
# Prints one simple command per line; returns 1 on globally-unbalanced quotes.
split_commands() {
    local s="$1" n i=0 c nx q="" cur="" pv; n=${#s}
    while [ "$i" -lt "$n" ]; do
        c="${s:$i:1}"
        if [ -n "$q" ]; then
            cur+="$c"; [ "$c" = "$q" ] && q=""; i=$((i+1)); continue
        fi
        case "$c" in
            "'"|'"') q="$c"; cur+="$c"; i=$((i+1)); continue ;;
            '\')
                cur+="$c"; i=$((i+1))
                [ "$i" -lt "$n" ] && { cur+="${s:$i:1}"; i=$((i+1)); }
                continue ;;
        esac
        nx="${s:$((i+1)):1}"; pv="${cur: -1}"
        case "$c" in
            ';'|$'\n') printf '%s\n' "$cur"; cur=""; i=$((i+1)) ;;
            '|')
                if [ "$pv" = ">" ]; then cur+="$c"; i=$((i+1))          # >| redirect
                elif [ "$nx" = "|" ]; then printf '%s\n' "$cur"; cur=""; i=$((i+2))   # ||
                else printf '%s\n' "$cur"; cur=""; i=$((i+1)); fi       # pipe
                ;;
            '&')
                if [ "$pv" = ">" ]; then cur+="$c"; i=$((i+1))          # >&
                elif [ "$nx" = ">" ]; then cur+="$c"; i=$((i+1))        # &>
                elif [ "$nx" = "&" ]; then printf '%s\n' "$cur"; cur=""; i=$((i+2))   # &&
                else printf '%s\n' "$cur"; cur=""; i=$((i+1)); fi       # background
                ;;
            *) cur+="$c"; i=$((i+1)) ;;
        esac
    done
    [ -n "$q" ] && return 1
    [ -n "$cur" ] && printf '%s\n' "$cur"
    return 0
}

# split_words <simple-command> — quote-aware word split (strips quotes,
# unescapes \x). Prints one word per line; returns 1 on unbalanced quotes.
split_words() {
    local s="$1" n i=0 c q="" w="" started=0; n=${#s}
    while [ "$i" -lt "$n" ]; do
        c="${s:$i:1}"
        if [ -n "$q" ]; then
            if [ "$c" = "$q" ]; then q=""; else w+="$c"; fi
            started=1; i=$((i+1)); continue
        fi
        case "$c" in
            "'"|'"') q="$c"; started=1; i=$((i+1)) ;;
            '\') i=$((i+1)); [ "$i" -lt "$n" ] && { w+="${s:$i:1}"; started=1; i=$((i+1)); } ;;
            ' '|$'\t') [ "$started" -eq 1 ] && { printf '%s\n' "$w"; w=""; started=0; }; i=$((i+1)) ;;
            *) w+="$c"; started=1; i=$((i+1)) ;;
        esac
    done
    [ -n "$q" ] && return 1
    [ "$started" -eq 1 ] && printf '%s\n' "$w"
    return 0
}

# extract_redirects <simple-command> — quote-aware scan for write redirections
# (> >> >|, optionally fd-prefixed). Prints each target path (quotes stripped).
# fd-dup targets (>&N) are skipped. A "$" or backtick in a redirect target is
# left intact so the caller's classify_target marks it UNPARSEABLE.
extract_redirects() {
    local s="$1" n i=0 c q="" tgt; n=${#s}
    while [ "$i" -lt "$n" ]; do
        c="${s:$i:1}"
        if [ -n "$q" ]; then [ "$c" = "$q" ] && q=""; i=$((i+1)); continue; fi
        case "$c" in
            "'"|'"') q="$c"; i=$((i+1)); continue ;;
            '\') i=$((i+2)); continue ;;
            '<') i=$((i+1)); continue ;;
            '>')
                i=$((i+1))
                [ "${s:$i:1}" = ">" ] && i=$((i+1))     # >>
                [ "${s:$i:1}" = "|" ] && i=$((i+1))     # >|
                while [ "${s:$i:1}" = " " ] || [ "${s:$i:1}" = $'\t' ]; do i=$((i+1)); done
                [ "${s:$i:1}" = "&" ] && continue       # fd dup, not a file
                tgt=""
                while [ "$i" -lt "$n" ]; do
                    c="${s:$i:1}"
                    case "$c" in
                        ' '|$'\t'|';'|'|'|'&'|'<'|'>') break ;;
                        "'"|'"') i=$((i+1)) ;;          # strip quotes inside target
                        *) tgt+="$c"; i=$((i+1)) ;;
                    esac
                done
                [ -n "$tgt" ] && printf '%s\n' "$tgt" ;;
            *) i=$((i+1)) ;;
        esac
    done
    return 0
}

# --- Split the whole command; unbalanced quotes anywhere -> fail closed. ---
simple_out=$(split_commands "$cmd") || block_unparseable "unbalanced quotes"

while IFS= read -r sc; do
    [ -n "$sc" ] || continue

    # Strip leading whitespace, then sudo / env / VAR=val assignment prefixes.
    while : ; do
        sc="${sc#"${sc%%[![:space:]]*}"}"                 # ltrim
        tok="${sc%%[[:space:]]*}"
        case "$tok" in
            sudo|env) sc="${sc#"$tok"}" ;;
            [A-Za-z_]*=*) sc="${sc#"$tok"}" ;;            # VAR=val
            *) break ;;
        esac
    done
    sc="${sc#"${sc%%[![:space:]]*}"}"                     # ltrim again
    [ -n "$sc" ] || continue
    head="${sc%%[[:space:]]*}"

    # A leading option with no command (e.g. `env -i cp ...` after env-strip) hides
    # the real command — fail closed.
    case "$head" in -*) block_unparseable "leading option before a command ('$head')" ;; esac

    # --- Shell wrappers we refuse to parse (they hide a second command). ---
    case "$head" in
        eval) block_unparseable "eval" ;;
    esac
    case "$WRAPPERS" in
        *" $head "*)
            # sh/bash/... -c "<payload>" builds a command we do not recurse into.
            case " $sc " in *" -c "*|*" -c\""*|*" -c'"*) block_unparseable "$head -c inline script" ;; esac ;;
    esac
    if [ "$head" = "xargs" ]; then
        # xargs [flags] <write-cmd> runs a write-capable command against stdin
        # paths — a target we cannot resolve. If any token after `xargs` is a
        # write-capable command, refuse.
        xw=0 xfirst=1
        while IFS= read -r xt; do
            [ "$xfirst" -eq 1 ] && { xfirst=0; continue; }   # skip the `xargs` token itself
            is_write_cmd "$xt" && { xw=1; break; }
        done < <(split_words "$sc")
        [ "$xw" -eq 1 ] && block_unparseable "xargs invoking a write-capable command"
    fi

    # --- Does this simple command WRITE (write-capable head or a redirection)? ---
    redir_out=$(extract_redirects "$sc")
    has_write=0
    is_write_cmd "$head" && has_write=1
    [ "$head" = "rm" ] && has_write=1           # rm gets territorial (not broad-target) screening
    [ -n "$redir_out" ] && has_write=1
    case "$sc" in *'>'*) has_write=1 ;; esac    # a bare '>' with no target still = write intent

    [ "$has_write" -eq 1 ] || continue

    # fail-CLOSED: for a write-COMMAND (cp/mv/install/ln/dd/tee/sed) a command
    # substitution or variable ANYWHERE means positional target extraction cannot be
    # trusted — refuse rather than guess. Redirect-only commands are exempt here
    # because their target is extracted and checked individually below (so a benign
    # `echo "$VAR" > src/out.txt` is allowed, while `echo x > $DEST` is still caught
    # by classify_target on the dynamic target).
    if is_write_cmd "$head"; then
        case "$sc" in
            *'$'*|*'`'*) block_unparseable "command substitution or variable in a write command" ;;
        esac
    fi

    # Quote-aware word split; unbalanced -> fail closed.
    words_out=$(split_words "$sc") || block_unparseable "unbalanced quotes"
    mapfile -t words <<< "$words_out"

    # --- Redirection targets (apply to ANY command head). ---
    while IFS= read -r rt; do
        [ -n "$rt" ] && handle_target "$rt"
    done <<< "$redir_out"

    # --- Command-specific write TARGET extraction. ---
    case "$head" in
        cp|mv|install)
            # target = LAST positional arg. -t/--target-directory reverses the
            # positional order -> fail closed (cannot locate the target).
            case " ${words[*]} " in *" -t "*|*" --target-directory"*) block_unparseable "$head -t/--target-directory" ;; esac
            last=""
            for w in "${words[@]:1}"; do case "$w" in -*) : ;; *) last="$w" ;; esac; done
            [ -n "$last" ] && handle_target "$last" ;;
        ln)
            # target = LINK NAME = last positional. -t reverses; a single positional
            # is ambiguous (link named after basename in cwd) -> fail closed.
            case " ${words[*]} " in *" -t "*|*" --target-directory"*) block_unparseable "ln -t/--target-directory" ;; esac
            pos=(); for w in "${words[@]:1}"; do case "$w" in -*) : ;; *) pos+=("$w") ;; esac; done
            if [ "${#pos[@]}" -ge 2 ]; then handle_target "${pos[-1]}"
            elif [ "${#pos[@]}" -eq 1 ]; then block_unparseable "ln with a single operand (link target ambiguous)"; fi ;;
        dd)
            # target = value of of=PATH. No of= -> writes stdout, no file target.
            for w in "${words[@]:1}"; do case "$w" in of=*) handle_target "${w#of=}" ;; esac; done ;;
        tee)
            # target = EVERY positional (tee writes them all). Zero targets = stdout
            # passthrough, but ambiguous -> fail closed.
            teecount=0
            for w in "${words[@]:1}"; do case "$w" in -*) : ;; *) handle_target "$w"; teecount=$((teecount+1)) ;; esac; done
            [ "$teecount" -eq 0 ] && block_unparseable "tee with no file operand" ;;
        sed)
            # Only -i (in-place) writes a file. GNU -i takes an OPTIONAL attached
            # suffix (-i.bak); BSD -i takes a MANDATORY next-arg suffix (-i '').
            # A BARE -i is therefore ambiguous (next arg = suffix or first FILE?)
            # -> fail closed. -e/-f make the script/file boundary unparseable too.
            has_i=0; bare_i=0
            for w in "${words[@]:1}"; do
                case "$w" in
                    -i) has_i=1; bare_i=1 ;;
                    -i*) has_i=1 ;;
                    -e|-f|--expression|--file|--expression=*|--file=*) block_unparseable "sed -e/-f (script/file boundary unresolvable)" ;;
                esac
            done
            [ "$has_i" -eq 0 ] && continue            # no in-place write -> nothing to guard
            [ "$bare_i" -eq 1 ] && block_unparseable "sed -i with a detached/ambiguous suffix (GNU vs BSD)"
            # GNU attached-suffix form: positionals after options = [script, files...].
            pos=(); for w in "${words[@]:1}"; do case "$w" in -*) : ;; *) pos+=("$w") ;; esac; done
            for f in "${pos[@]:1}"; do handle_target "$f"; done ;;   # skip pos[0] = the sed script
        rm)
            # Territorial (NOT broad-target — that is Part A's job). Route each
            # non-flag operand through the shared classifier: a narrow
            # `rm .kimi/x` is a territory violation Part A does not catch.
            for w in "${words[@]:1}"; do
                case "$w" in
                    -*) : ;;
                    /|'~'|'*'|.) : ;;                 # broad targets belong to Part A
                    *) handle_target_rm "$w" ;;
                esac
            done ;;
    esac
done <<< "$simple_out"

exit 0
