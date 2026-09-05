#!/usr/bin/env bash
set -euo pipefail

# Hook 7: compact-anchor.sh (PostCompact)
# Re-inject critical rules at the top of the FRESH context after compaction.
# Bound to PreCompact until 2026-09-05: the anchor was emitted into the context
# that compaction then summarised away, so it protected nothing. PostCompact runs
# after the new context exists, which is where an anchor has to land.

# Fallback: CLAUDE_PLUGIN_ROOT is injected by Claude Code hook runner
# If running standalone, resolve from script directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Identify top 3 always-on rules and extract SYSTEM CONSTRAINTS
RULES_DIR="${PLUGIN_ROOT}/core/rules"

# Extract SYSTEM CONSTRAINTS from rule files
extract_constraints() {
  local rule_file="$1"

  if [ ! -f "$rule_file" ]; then
    return
  fi

  rg -A 20 "^## SYSTEM CONSTRAINTS" "$rule_file" | head -25
}

# Emit anchor block
cat << 'EOF'
[CONTEXTFORGE ANCHOR — Re-injected after compaction]
CRITICAL CONSTRAINTS (from cf-001, cf-003, cf-010, cf-013, cf-014):
EOF

# Extract from cf-token-efficiency (001)
if [ -f "${RULES_DIR}/001-cf-token-efficiency.md" ]; then
  echo ""
  echo "TOKEN EFFICIENCY (001):"
  extract_constraints "${RULES_DIR}/001-cf-token-efficiency.md" | sed 's/^/  /'
fi

# Extract from cf-tier-routing (003)
if [ -f "${RULES_DIR}/003-cf-tier-routing.md" ]; then
  echo ""
  echo "TIER ROUTING (003):"
  extract_constraints "${RULES_DIR}/003-cf-tier-routing.md" | sed 's/^/  /'
fi

# Extract from cf-context-budget (010)
if [ -f "${RULES_DIR}/010-cf-context-budget.md" ]; then
  echo ""
  echo "CONTEXT BUDGET (010):"
  extract_constraints "${RULES_DIR}/010-cf-context-budget.md" | sed 's/^/  /'
fi

# Extract from cf-interleaved-thinking (013)
if [ -f "${RULES_DIR}/013-cf-interleaved-thinking.md" ]; then
  echo ""
  echo "INTERLEAVED THINKING (013):"
  extract_constraints "${RULES_DIR}/013-cf-interleaved-thinking.md" | sed 's/^/  /'
fi

# Extract from cf-tool-result-clearing (014)
if [ -f "${RULES_DIR}/014-cf-tool-result-clearing.md" ]; then
  echo ""
  echo "TOOL RESULT CLEARING (014):"
  extract_constraints "${RULES_DIR}/014-cf-tool-result-clearing.md" | sed 's/^/  /'
fi

echo ""
echo "[END ANCHOR]"

exit 0
