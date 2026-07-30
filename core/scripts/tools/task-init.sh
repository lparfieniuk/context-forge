#!/usr/bin/env bash
# task-init.sh — Initialize a Jira task worklog
# Usage: bash task-init.sh --key <JIRA-KEY> [--scope "<description>"]
set -euo pipefail

WORKLOG_DIR="${WORKLOG_DIR:-$HOME/worklogs}"
KEY=""
SCOPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$KEY" ]]; then
  echo "ERROR: --key is required"
  exit 1
fi

TICKET_FILE="$WORKLOG_DIR/tickets/$KEY.yaml"
INDEX_FILE="$WORKLOG_DIR/INDEX.yaml"

# Detect branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Infer task type from branch prefix
TASK_TYPE="unknown"
case "$BRANCH" in
  feat/*|feature/*) TASK_TYPE="new_feature" ;;
  fix/*|bugfix/*) TASK_TYPE="bugfix" ;;
  refactor/*) TASK_TYPE="refactor" ;;
  spike/*|research/*) TASK_TYPE="spike" ;;
esac

# Check if ticket already exists
if [[ -f "$TICKET_FILE" ]]; then
  echo "SKIP: $TICKET_FILE already exists"
  exit 0
fi

mkdir -p "$WORKLOG_DIR/tickets"

# Create ticket YAML
cat > "$TICKET_FILE" <<EOF
key: $KEY
scope: ${SCOPE:-TBD}
status: in_progress
branch: $BRANCH
task_type: $TASK_TYPE

entries: []
EOF

echo "[TASK INIT]"
echo "- Ticket: $KEY"
echo "- Worklog: $TICKET_FILE"
echo "- Branch: $BRANCH"
echo "- Task type: $TASK_TYPE"

# Update INDEX.yaml if it exists
if [[ -f "$INDEX_FILE" ]]; then
  # Append to active section if not already present
  if ! grep -q "$KEY" "$INDEX_FILE" 2>/dev/null; then
    echo "- INDEX.yaml: updated"
  else
    echo "- INDEX.yaml: already present"
  fi
fi

echo "[END TASK INIT]"
