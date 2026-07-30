#!/usr/bin/env bash
set -euo pipefail

# Hook 5: run-log-writer.sh (PostToolUse — Bash)
# Automatically log every significant tool execution for the self-evolving loop.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
TOOL_OUTPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_result',''))" 2>/dev/null || echo "")

# List of trivial commands to skip
TRIVIAL_CMDS=("ls" "pwd" "echo" "cd" "which" "type" "true" "false")

# Extract command from TOOL_INPUT (first token)
CMD=$(echo "$TOOL_INPUT" | awk '{print $1}')

# Check if command is trivial
for trivial in "${TRIVIAL_CMDS[@]}"; do
  if [ "$CMD" == "$trivial" ]; then
    # Skip trivial command
    exit 0
  fi
done

# Ensure ~/worklogs/runs directory exists
mkdir -p ~/worklogs/runs

# Generate session ID based on date and a short hash of PWD
SESSION_ID=$(date +%Y-%m-%d)-$(repo_root_hash)
LOG_FILE=~/worklogs/runs/${SESSION_ID}.yaml

# Calculate output size in KB
OUTPUT_KB=$(echo -n "$TOOL_OUTPUT" | wc -c | awk '{print int($1/1024)}')

# Get current timestamp (macOS compatible)
TIMESTAMP=$(date -u "+%Y-%m-%d %H:%M:%S")

# Detect exit code: use explicit field if available, otherwise omit from log
EXIT_CODE=$(echo "$HOOK_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Claude Code PostToolUse may expose exit_code directly
    if 'exit_code' in d:
        print(int(d['exit_code']))
except Exception:
    pass
" 2>/dev/null || echo "")

# Estimate duration (not available, set to 0)
DURATION_MS=0

# Create YAML entry (only include exit_code if explicit value exists)
cat >> "$LOG_FILE" << EOF
- ts: "$TIMESTAMP"
  cmd: "$CMD"
EOF

if [ -n "$EXIT_CODE" ]; then
  cat >> "$LOG_FILE" << EOF
  exit: $EXIT_CODE
EOF
fi

cat >> "$LOG_FILE" << EOF
  output_kb: $OUTPUT_KB
  duration_ms: $DURATION_MS
EOF

exit 0
