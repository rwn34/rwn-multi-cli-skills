#!/bin/bash
# SessionStart hook — injects git status + open handoffs list into context.
# Both are "only if non-empty" so a fresh clean session stays silent.

output=""

# --- Git status ---
git_status=$(git status --short 2>/dev/null | head -20)
if [ -n "$git_status" ]; then
    output="${output}--- Git status at session start ---
$git_status
--- end ---

"
fi

# --- Open handoffs addressed to claude ---
handoffs=""
for f in .ai/handoffs/to-claude/open/*.md; do
    [ -e "$f" ] || continue
    # Skip README if it ever lives there
    case "$(basename "$f")" in
        README.md|template.md) continue ;;
    esac
    # Extract title (first heading) for display
    title=$(head -1 "$f" | sed 's/^# //')
    handoffs="${handoffs}  $f  —  ${title}
"
done

if [ -n "$handoffs" ]; then
    output="${output}--- Open handoffs addressed to claude ---
$handoffs--- end ---
"
fi

if [ -n "$output" ]; then
    printf "%s" "$output"
fi

exit 0
