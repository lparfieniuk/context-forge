#!/usr/bin/env bash
set -euo pipefail

# Hook 8: session-end-reminder.sh (SessionEnd)
# Remind to capture session learnings before closing.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Generate session ID based on date and a short repo-root hash (see repo_root_hash)
REPO_HASH=$(repo_root_hash)
SESSION_ID=$(date +%Y-%m-%d)-${REPO_HASH}
LOG_FILE=~/worklogs/runs/${SESSION_ID}.yaml

# Check if log file exists and count entries
COMMAND_COUNT=0
AGENT_COUNT=0
FAILURE_COUNT=0

if [ -f "$LOG_FILE" ]; then
  COMMAND_COUNT=$(rg -c "^- ts:" "$LOG_FILE" 2>/dev/null || echo 0)
  AGENT_COUNT=$(rg -c "type: subagent" "$LOG_FILE" 2>/dev/null || echo 0)
  FAILURE_COUNT=$(rg -c "status: failure" "$LOG_FILE" 2>/dev/null || echo 0)
fi

# Check if session-learnings was invoked (look for a marker file)
LEARNINGS_MARKER="/tmp/.session-learnings-done-${REPO_HASH}"
LEARNINGS_STATUS="✗ NOT YET"
if [ -f "$LEARNINGS_MARKER" ]; then
  LEARNINGS_STATUS="✓ YES"
fi

# Emit session end block
cat << EOF
[SESSION END]
- Commands executed: $COMMAND_COUNT
- Agents spawned: $AGENT_COUNT
- Failures recorded: $FAILURE_COUNT
- Session learnings captured: $LEARNINGS_STATUS
EOF

if [ "$LEARNINGS_STATUS" == "✗ NOT YET" ]; then
  cat << 'EOF'
  → Run /session-learnings to capture observations before closing.
EOF
  if [ "$FAILURE_COUNT" -gt 0 ]; then
    cat << 'EOF'
  ⚠ Failures recorded this session — /session-learnings is strongly recommended.
EOF
  fi
fi

echo "[END SESSION]"

exit 0
