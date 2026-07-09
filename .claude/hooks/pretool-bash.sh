#!/bin/bash
# PreToolUse hook — matcher: Bash
# Blocks destructive commands that should require explicit user action.
# Reads tool call JSON from stdin; exit 2 + stderr to block.

# Extract the Bash `command` field from the tool-call JSON on stdin.
#
# CRITICAL (fail-CLOSED): extraction MUST NOT depend on python. In the live Claude
# hook runtime python3 can resolve to a Windows Store alias stub that prints nothing
# and exits 0 — a `|| python` chain keyed on exit status never fires, cmd comes back
# empty, and the old `[ -z "$cmd" ] && exit 0` made every destructive-command rule a
# no-op (fail-OPEN — the higher-severity twin of the write-edit hole fixed in 588ed9c).
# So: python is only an OPTIONAL first attempt (fast, handles JSON escapes); the real
# extractor is a pure-sed fallback that runs whenever the python result is EMPTY (not
# merely when it exits non-zero). jq is not reliably installed on Windows/Git Bash.
input=$(cat)

# Empty (or whitespace-only) stdin → nothing to evaluate → allow.
if [ -z "$(printf '%s' "$input" | tr -d '[:space:]')" ]; then
    exit 0
fi

cmd=$(printf '%s' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$cmd" ] && cmd=$(printf '%s' "$input" | python -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
# sed fallback (python-less runtime). CAVEAT: Bash commands routinely contain quotes,
# &&, pipes, and other JSON-escaped characters, so this is best-effort — not a JSON
# parser. It grabs the "command" value greedily to the LAST double-quote on the line,
# which is correct when command is the last/only large string field (the normal Bash
# tool payload). An embedded escaped \" inside the command would be captured verbatim
# (over-capture), which for a BLOCK hook is safe: it can only match MORE, never less.
[ -z "$cmd" ] && cmd=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# stdin was non-empty but no command parsed. A Bash tool call always carries
# command, so an empty result means the parse failed — refuse to fail open.
if [ -z "$cmd" ]; then
    echo "BLOCKED by hook: could not parse tool input (no command found) — refusing to fail open." >&2
    exit 2
fi

# Normalize whitespace to single spaces for matching
norm=$(echo "$cmd" | tr -s ' \t' '  ')

block() {
    echo "BLOCKED by hook: $1" >&2
    exit 2
}

# Dangerous rm patterns — broad targets (/ ~ * .)
# Boundary-aware: the target must be followed by whitespace, a shell separator
# (; & |), or end-of-string. Otherwise `rm -rf /tmp/foo` would false-positive
# on a naive substring match against `rm -rf /`.
rm_flags='(-[rRfF]+|-r[[:space:]]+-f|-f[[:space:]]+-r|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)'
rm_target='(/|~|\*|\.)'
rm_tail='([[:space:]]|[;|&]|$)'
if [[ " $norm " =~ [[:space:]]rm[[:space:]]+${rm_flags}[[:space:]]+${rm_target}${rm_tail} ]]; then
    block "'rm -rf' with a broad target (/, ~, *, .) is destructive. Use a specific path, or ask the user to run it manually."
fi

# Force push — any variant (including --force-with-lease, which is still risky)
case " $norm " in
    *"git push --force"*|*"git push -f "*|*"git push -f"|*"--force-with-lease"*)
        block "Force-push variants (--force, -f, --force-with-lease) overwrite remote history. Route through release-engineer with explicit user approval." ;;
esac

# Hard reset
case " $norm " in
    *"git reset --hard"*|*"git reset -q --hard"*|*"git reset --hard "*)
        block "'git reset --hard' discards uncommitted changes. Ask the user before resetting." ;;
esac

# DROP / TRUNCATE in SQL contexts (uppercase match)
upper=$(echo "$norm" | tr '[:lower:]' '[:upper:]')
case " $upper " in
    *" DROP DATABASE "*|*" DROP TABLE "*|*" DROP SCHEMA "*|*" TRUNCATE TABLE "*|*"DROP DATABASE "*|*"DROP TABLE "*|*"DROP SCHEMA "*|*"TRUNCATE TABLE "*)
        block "DROP / TRUNCATE destroys data. Route through data-migrator with explicit user confirmation." ;;
esac

exit 0
