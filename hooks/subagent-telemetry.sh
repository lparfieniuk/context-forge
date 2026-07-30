#!/usr/bin/env bash
set -euo pipefail

# Hook 6: subagent-telemetry.sh (SubagentStop)
# Track sub-agent spawns for cost awareness and the self-evolving loop.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input',{}); print(str(ti))" 2>/dev/null || echo "")
TOOL_OUTPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('tool_result','')))" 2>/dev/null || echo "")

# Ensure ~/worklogs/runs directory exists
mkdir -p ~/worklogs/runs

# Generate session ID based on date and a short hash of PWD
SESSION_ID=$(date +%Y-%m-%d)-$(repo_root_hash)
LOG_FILE=~/worklogs/runs/${SESSION_ID}.yaml

# Parse agent info from TOOL_INPUT
# Default values
AGENT_TYPE="unknown"
MODEL="haiku"
DURATION_MS=0
STATUS="unknown"
TIER=2

# Try to extract agent type (e.g., cf-scribe, code-reviewer) from JSON structure
EXTRACTED_TYPE=$(echo "$HOOK_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    # Check for subagent_type field in tool_input
    if isinstance(ti, dict):
        subagent_type = ti.get('subagent_type', '')
        if subagent_type:
            print(subagent_type)
except Exception:
    pass
" 2>/dev/null || echo "")

if [ -n "$EXTRACTED_TYPE" ]; then
  AGENT_TYPE="$EXTRACTED_TYPE"
elif echo "$TOOL_INPUT" | rg -q '"subagent_type"\s*:\s*"[^"]*scribe'; then
  AGENT_TYPE="cf-scribe"
elif echo "$TOOL_INPUT" | rg -q '"subagent_type"\s*:\s*"[^"]*router'; then
  AGENT_TYPE="cf-router"
elif echo "$TOOL_INPUT" | rg -q '"subagent_type"\s*:\s*"[^"]*code-review'; then
  AGENT_TYPE="code-reviewer"
  TIER=3
elif echo "$TOOL_INPUT" | rg -q '"subagent_type"\s*:\s*"[^"]*architect'; then
  AGENT_TYPE="architect"
  TIER=3
  MODEL="default"
fi

# Try to extract status (success/failure)
if echo "$TOOL_OUTPUT" | rg -q "ERROR|error|failed|FAILED"; then
  STATUS="failure"
else
  STATUS="success"
fi

# Try to detect if Tier 3
if echo "$TOOL_INPUT" | rg -q "Tier[[:space:]]*3|tier[[:space:]]*3"; then
  TIER=3
  MODEL="default"
fi

# Get current timestamp (macOS compatible)
TIMESTAMP=$(date -u "+%Y-%m-%d %H:%M:%S")

# Create YAML entry
cat >> "$LOG_FILE" << EOF
- ts: "$TIMESTAMP"
  type: subagent
  agent: $AGENT_TYPE
  model: $MODEL
  duration_ms: $DURATION_MS
  status: $STATUS
  tier: $TIER
EOF

exit 0
