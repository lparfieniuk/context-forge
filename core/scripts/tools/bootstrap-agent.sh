#!/usr/bin/env bash
# tools/bootstrap-agent.sh — Bootstrap cache management with 1-hour TTL
# Usage: bootstrap-agent.sh [--refresh] [--verbose]
# Reads/writes: .bootstrap.yaml with cache TTL
set -euo pipefail

_REFRESH=false
_VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: bootstrap-agent.sh [--refresh] [--verbose]

Manage bootstrap cache for agent initialization.
Caches: task_type, manifest status, active ticket.

Options:
  --refresh   — Force refresh cache (ignore TTL)
  --verbose   — Show debug output

Output:
  YAML block with:
    - task_type: bugfix | feature | refactor | spike | unknown
    - manifest_status: available | missing | generating
    - active_ticket: <JIRA_KEY> (if found)
    - cache_age: <seconds>
    - cache_valid: true | false

Examples:
  bootstrap-agent.sh
  bootstrap-agent.sh --refresh
  bootstrap-agent.sh --verbose
EOF
      exit 0
      ;;
    --refresh)
      _REFRESH=true
      shift
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

BOOTSTRAP_FILE=".bootstrap.yaml"
CACHE_TTL=3600  # 1 hour

# Check if cache exists and is fresh
CACHE_VALID=false
CACHE_AGE=0

if [[ -f "$BOOTSTRAP_FILE" ]] && [[ "$_REFRESH" != "true" ]]; then
  # Check cache age
  MTIME=$(stat -f%m "$BOOTSTRAP_FILE" 2>/dev/null || stat -c%Y "$BOOTSTRAP_FILE" 2>/dev/null || echo "0")
  NOW=$(date +%s)
  CACHE_AGE=$((NOW - MTIME))

  if [[ $CACHE_AGE -lt $CACHE_TTL ]]; then
    CACHE_VALID=true
    if [[ "$_VERBOSE" == "true" ]]; then
      echo "Cache valid (age: ${CACHE_AGE}s)" >&2
    fi
    cat "$BOOTSTRAP_FILE"
    exit 0
  fi
fi

# Cache missing or expired: regenerate
if [[ "$_VERBOSE" == "true" ]]; then
  echo "Regenerating bootstrap cache..." >&2
fi

# Detect task type from branch
TASK_TYPE="unknown"
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
case "$BRANCH" in
  fix/*|bugfix/*) TASK_TYPE="bugfix" ;;
  feature/*) TASK_TYPE="feature" ;;
  refactor/*) TASK_TYPE="refactor" ;;
  spike/*) TASK_TYPE="spike" ;;
esac

# Check manifest status
MANIFEST_STATUS="missing"
IDE_DIR=".claude"
if [[ ! -d ".claude" ]] && [[ -d ".cursor" ]]; then
  IDE_DIR=".cursor"
fi

if [[ -f "$IDE_DIR/shadow/context-forge/_manifest.lightweight.yaml" ]]; then
  MANIFEST_STATUS="available"
fi

# Try to find active ticket from branch or worklogs
ACTIVE_TICKET=""
if [[ "$BRANCH" =~ (CRISP|IC|IMM)-[0-9]+ ]]; then
  ACTIVE_TICKET="${BASH_REMATCH[0]}"
elif [[ -f ~/worklogs/INDEX.yaml ]]; then
  ACTIVE_TICKET=$(rg "active:\s*-.*key:\s*(\S+)" ~/worklogs/INDEX.yaml -r '$1' 2>/dev/null | head -1 || echo "")
fi

# Write bootstrap cache
cat > "$BOOTSTRAP_FILE" <<YAML
# Bootstrap cache — auto-generated
# TTL: 1 hour
generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
task_type: $TASK_TYPE
manifest_status: $MANIFEST_STATUS
active_ticket: ${ACTIVE_TICKET:-none}
branch: $BRANCH
ide_dir: $IDE_DIR
YAML

# Output the cache
cat "$BOOTSTRAP_FILE"

if [[ "$_VERBOSE" == "true" ]]; then
  echo "" >&2
  echo "Bootstrap cache written to $BOOTSTRAP_FILE" >&2
fi
