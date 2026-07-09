#!/bin/bash
# Hook 3: Sensitive file guard
# Block writes to .env*, *.key, *.pem, id_rsa*, .aws/, .ssh/

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

extract_path() {
    local out
    out=$(printf '%s' "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | python  -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(ti.get('file_path') or ti.get('path',''))" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
    out=$(printf '%s' "$1" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$out" ] && { printf '%s' "$out"; return; }
}

FILE_PATH=$(extract_path "$INPUT")

if [ -z "$FILE_PATH" ]; then
    echo "BLOCKED: Could not parse tool input path; failing closed against sensitive-file writes." >&2
    exit 2
fi

BASENAME=$(basename "$FILE_PATH")

# Check sensitive patterns
case "$BASENAME" in
    .env*|*.env)
        echo "BLOCKED: Direct modification of .env files is not allowed. Use .env.example for templates." >&2
        exit 2
        ;;
    secrets.*|*.secrets|*-secrets.*)
        echo "BLOCKED: Writing to secrets files is not allowed: $FILE_PATH" >&2
        exit 2
        ;;
    credentials|credentials.*|*-credentials.*)
        echo "BLOCKED: Writing to credentials files is not allowed: $FILE_PATH" >&2
        exit 2
        ;;
esac

case "$FILE_PATH" in
    *.key|*.pem|id_rsa*|id_ed25519*|*.p12|*.pfx)
        echo "BLOCKED: Writing to key/certificate files is not allowed: $FILE_PATH" >&2
        exit 2
        ;;
    .aws/*|.ssh/*)
        echo "BLOCKED: Writing to credential directories is not allowed: $FILE_PATH" >&2
        exit 2
        ;;
esac

exit 0
