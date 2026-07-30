#!/usr/bin/env bash
# tools/git-status-summary.sh — Branch + task type detection
# Adapted from ai-system's git-context.sh
# Usage: git-status-summary.sh [--verbose]
# Output: JSON/YAML with branch, task_type, uncommitted files count
set -euo pipefail

_VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: git-status-summary.sh [--verbose]

Detect current branch, infer task type, and count uncommitted files.

Output:
  branch: <git branch>
  task_type: bugfix | feature | refactor | spike | unknown
  uncommitted_files: <count>
  status: clean | dirty

Examples:
  git-status-summary.sh
  git-status-summary.sh --verbose
EOF
      exit 0
      ;;
    --verbose)
      _VERBOSE=true
      shift
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Infer task type from branch name
TASK_TYPE="unknown"
case "$BRANCH" in
  fix/*|bugfix/*)
    TASK_TYPE="bugfix"
    ;;
  feature/*)
    TASK_TYPE="feature"
    ;;
  refactor/*)
    TASK_TYPE="refactor"
    ;;
  spike/*)
    TASK_TYPE="spike"
    ;;
  *)
    TASK_TYPE="unknown"
    ;;
esac

# Count uncommitted files
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# Check if clean
STATUS="clean"
if [[ $UNCOMMITTED -gt 0 ]]; then
  STATUS="dirty"
fi

# Output as YAML (default)
cat <<YAML
branch: $BRANCH
task_type: $TASK_TYPE
uncommitted_files: $UNCOMMITTED
status: $STATUS
YAML

if [[ "$_VERBOSE" == "true" ]]; then
  echo "" >&2
  echo "DEBUG: Uncommitted files:" >&2
  git status --porcelain 2>/dev/null | head -10 >&2 || true
fi
