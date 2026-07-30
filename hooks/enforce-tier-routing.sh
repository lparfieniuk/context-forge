#!/usr/bin/env bash
set -euo pipefail

# Hook 3: enforce-tier-routing.sh (PreToolUse — Agent)
# Block Task() calls when a cheaper Tier 0/1 alternative exists.

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
# Agent tool stores prompt in 'prompt' field
print(ti.get('prompt', ti.get('description', '')))
" 2>/dev/null || echo "")

# Extract first 20 words from Task() prompt
PROMPT_WORDS=$(echo "$TOOL_INPUT" | tr ' ' '\n' | head -20 | tr '\n' ' ')

# Check if route-to-tier.sh exists and is executable
# CLAUDE_PLUGIN_ROOT is injected by the Claude Code hook runner; guard it so
# `set -u` doesn't abort the hook if it's ever unset (fall back to script dir).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROUTE_SCRIPT="${PLUGIN_ROOT}/core/scripts/tools/route-to-tier.sh"
if [ ! -x "$ROUTE_SCRIPT" ]; then
  # Script not available, allow the call
  exit 0
fi

# Run route-to-tier.sh with first 20 words (requires --task flag)
TIER_OUTPUT=$("$ROUTE_SCRIPT" --task "$PROMPT_WORDS" 2>/dev/null || echo "TIER:2")

# Parse tier from output
TIER=$(echo "$TIER_OUTPUT" | rg "^TIER:" | head -1 | cut -d':' -f2)

# If TIER:0 or TIER:1, block and suggest alternative
if [[ "$TIER" == "0" ]] || [[ "$TIER" == "1" ]]; then
  # Extract action/alternative command if available
  ACTION=$(echo "$TIER_OUTPUT" | rg "^ACTION:" | head -1 | cut -d':' -f2- || echo "")

  cat >&2 << EOF
[BLOCKED] Task() call for cheaper Tier $TIER alternative.
REASON: Tier $TIER script available (rule 011-subagent-orchestration).

PROMPT KEYWORDS: $PROMPT_WORDS

ROUTE ANALYSIS: $TIER_OUTPUT

USE INSTEAD: $ACTION

TIP: Use Tier 0 (rg, diff, wc, git) and Tier 1 scripts before spawning sub-agents.
EOF
  exit 2
fi

# TIER:2 or TIER:3 — allow
exit 0
