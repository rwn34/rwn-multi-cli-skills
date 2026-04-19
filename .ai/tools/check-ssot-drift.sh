#!/bin/bash
# check-ssot-drift.sh — verify CLI-native replicas match .ai/instructions/ sources.
# Exit 0 if all synced, 1 if any drift. Run from repo root.
#
# SSOT map lives in .ai/sync.md. 12 replicas across Claude/Kimi/Kiro.
#
# Preamble shapes (stripped before compare):
#   Claude SKILL.md  — `---\n<frontmatter>\n---\n\n<!-- SSOT: ... -->\n\n<body>`
#   Kiro  SKILL.md   — same shape, but with extra `<!-- Kiro ... -->` /
#                      `<!-- Default-agent ... -->` comment lines BEFORE the
#                      SSOT marker. Stripping through the SSOT line + one
#                      blank line handles both uniformly.
# For both, body that remains must equal source byte-for-byte.
# Kimi steering + Claude EXAMPLES.md + Kimi resource = no preamble (direct copy).

drift=0
checked=0

# Strip everything up to and including first `<!-- SSOT:` line + one blank line.
strip_preamble() {
  awk '
    !started && /^<!-- SSOT:/ { skip_blank=1; next }
    !started && skip_blank && /^$/ { started=1; next }
    !started && skip_blank { started=1; print; next }
    started { print }
  ' "$1"
}

check_pair() {
  local src="$1" dst="$2" strip="$3"
  checked=$((checked + 1))

  if [ ! -f "$src" ]; then
    echo "MISSING: $src"
    drift=$((drift + 1))
    return
  fi
  if [ ! -f "$dst" ]; then
    echo "MISSING: $dst"
    drift=$((drift + 1))
    return
  fi

  local tmp
  tmp=$(mktemp)
  if [ "$strip" = "yes" ]; then
    strip_preamble "$dst" > "$tmp"
  else
    cat "$dst" > "$tmp"
  fi

  local n
  n=$(diff "$src" "$tmp" | grep -c '^[<>]' || true)
  if [ "$n" -ne 0 ]; then
    echo "DRIFT: $src -> $dst ($n lines differ)"
    drift=$((drift + 1))
  fi
  rm -f "$tmp"
}

# karpathy-guidelines / principles
check_pair ".ai/instructions/karpathy-guidelines/principles.md" ".claude/skills/karpathy-guidelines/SKILL.md"   yes
check_pair ".ai/instructions/karpathy-guidelines/principles.md" ".kimi/steering/karpathy-guidelines.md"          no
check_pair ".ai/instructions/karpathy-guidelines/principles.md" ".kiro/steering/karpathy-guidelines.md"          no
# karpathy-guidelines / examples
check_pair ".ai/instructions/karpathy-guidelines/examples.md"   ".claude/skills/karpathy-guidelines/EXAMPLES.md" no
check_pair ".ai/instructions/karpathy-guidelines/examples.md"   ".kimi/resource/karpathy-guidelines-examples.md" no
check_pair ".ai/instructions/karpathy-guidelines/examples.md"   ".kiro/skills/karpathy-guidelines/SKILL.md"      yes
# orchestrator-pattern / principles
check_pair ".ai/instructions/orchestrator-pattern/principles.md" ".claude/skills/orchestrator-pattern/SKILL.md"  yes
check_pair ".ai/instructions/orchestrator-pattern/principles.md" ".kimi/steering/orchestrator-pattern.md"        no
check_pair ".ai/instructions/orchestrator-pattern/principles.md" ".kiro/steering/orchestrator-pattern.md"        no
# agent-catalog / principles
check_pair ".ai/instructions/agent-catalog/principles.md"       ".claude/skills/agent-catalog/SKILL.md"          yes
check_pair ".ai/instructions/agent-catalog/principles.md"       ".kimi/steering/agent-catalog.md"                no
check_pair ".ai/instructions/agent-catalog/principles.md"       ".kiro/steering/agent-catalog.md"                no

echo "Checked: $checked replicas, Drift: $drift"
[ "$drift" -eq 0 ] && exit 0 || exit 1
