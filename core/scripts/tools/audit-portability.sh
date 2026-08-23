#!/usr/bin/env bash
# audit-portability.sh — harness-coupling gate for ContextForge sources.
#
# Verifies the agnosticism contract:
#   1. core/skills/ and core/agents/ reference the plugin root ONLY via the
#      neutral <CF_PLUGIN_ROOT> placeholder — never a harness env var.
#   2. dist/AGENTS.md (when present) has no unresolved placeholders and no
#      Claude Code env var leaked into emitted output.
#
# Rules are exempt from (1): doctrine may NAME harness specifics when it is
# documenting them (e.g. rule 009's install-layout table). Skills and agents
# are executable instructions — they must stay neutral at the source.
#
# Usage:
#   bash core/scripts/tools/audit-portability.sh [--plugin-root <path>]
#
# Exit codes: 0 = clean, 1 = violation found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin-root) PLUGIN_ROOT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: audit-portability.sh [--plugin-root <path>]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

violations=0

echo "=== AUDIT PORTABILITY ==="
echo "  plugin-root: $PLUGIN_ROOT"
echo ""

# 1. Sources must be placeholder-neutral.
if rg -l 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/core/skills/" "$PLUGIN_ROOT/core/agents/" >/dev/null 2>&1; then
  echo "FAIL: harness env var in neutral sources (use <CF_PLUGIN_ROOT>):"
  rg -l 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/core/skills/" "$PLUGIN_ROOT/core/agents/"
  violations=$((violations + 1))
else
  echo "PASS: core/skills + core/agents carry no harness env var"
fi

# 2. Emitted AGENTS.md must be fully resolved.
AGENTS_MD="$PLUGIN_ROOT/dist/AGENTS.md"
if [[ -f "$AGENTS_MD" ]]; then
  if rg -q '<CF_PLUGIN_ROOT>' "$AGENTS_MD"; then
    echo "FAIL: dist/AGENTS.md contains unresolved <CF_PLUGIN_ROOT> placeholders"
    violations=$((violations + 1))
  elif rg -q 'CLAUDE_PLUGIN_ROOT' "$AGENTS_MD"; then
    echo "FAIL: dist/AGENTS.md leaks the Claude Code env var into emitted output"
    violations=$((violations + 1))
  else
    echo "PASS: dist/AGENTS.md fully resolved"
  fi
else
  echo "SKIP: dist/AGENTS.md not emitted yet (run npm run emit:agents)"
fi

echo ""
echo "STATUS: $([[ $violations -eq 0 ]] && echo OK || echo "VIOLATIONS=$violations")"
exit $([[ $violations -eq 0 ]] && echo 0 || echo 1)
