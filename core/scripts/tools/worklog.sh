#!/usr/bin/env bash
# tools/worklog.sh — Read/write worklog entries
# Port from ai-system; adapted for context-forge
# Usage: worklog.sh --key <KEY> [--scope <scope>] [--ctx <context>] [--append|--read|--compress]
# Files: ~/worklogs/tickets/<KEY>.yaml
set -euo pipefail

# Parse args
_KEY=""
_SCOPE=""
_CTX=""
_ACTION="read"  # default
_COMPRESS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: worklog.sh --key <KEY> [--scope <scope>] [--ctx <context>] [--append|--read|--compress]

Manage worklog entries in ~/worklogs/tickets/<KEY>.yaml

Actions:
  --read       — Read worklog entries (default)
  --append     — Append a new entry
  --compress   — Compress to history_summary if >15 entries

Options:
  --key <KEY>      — Jira key (e.g., PROJ-1234)
  --scope <text>   — What changed (required for --append)
  --ctx <text>     — Context/why (required for --append)

Examples:
  worklog.sh --key PROJ-1234 --read
  worklog.sh --key PROJ-1234 --append --scope "Refactored auth" --ctx "Removed duplication"
  worklog.sh --key PROJ-1234 --compress
EOF
      exit 0
      ;;
    --key)
      _KEY="$2"
      shift 2
      ;;
    --scope)
      _SCOPE="$2"
      shift 2
      ;;
    --ctx)
      _CTX="$2"
      shift 2
      ;;
    --read)
      _ACTION="read"
      shift
      ;;
    --append)
      _ACTION="append"
      shift
      ;;
    --compress)
      _ACTION="compress"
      shift
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

KEY="$_KEY"

if [[ -z "$KEY" ]]; then
  echo "ERROR: --key required"
  exit 1
fi

WORKLOG_DIR="${HOME}/worklogs/tickets"
WORKLOG_FILE="$WORKLOG_DIR/${KEY}.yaml"

mkdir -p "$WORKLOG_DIR"

case "$_ACTION" in
  read)
    if [[ ! -f "$WORKLOG_FILE" ]]; then
      echo "ERROR: worklog not found: $WORKLOG_FILE"
      exit 1
    fi
    cat "$WORKLOG_FILE"
    ;;

  append)
    if [[ -z "$_SCOPE" || -z "$_CTX" ]]; then
      echo "ERROR: --scope and --ctx required for --append"
      exit 1
    fi

    # Skip trivial entries validation
    if [[ "${#_SCOPE}" -lt 5 ]] && [[ "${#_CTX}" -lt 5 ]]; then
      echo "WARNING: entry seems trivial (too short), but appending anyway"
    fi

    # Create file if doesn't exist
    if [[ ! -f "$WORKLOG_FILE" ]]; then
      cat > "$WORKLOG_FILE" <<YAML
key: $KEY
scope: unknown
status: in_progress
entries: []
YAML
    fi

    # Generate timestamp (BSD-compatible)
    TS=$(date "+%Y-%m-%d %H:%M")

    # Append entry
    cat >> "$WORKLOG_FILE" <<YAML
- ts: "$TS"
  scope: $_SCOPE
  ctx: $_CTX
  decisions: []
YAML

    echo "Entry appended to $WORKLOG_FILE"
    ;;

  compress)
    if [[ ! -f "$WORKLOG_FILE" ]]; then
      echo "ERROR: worklog not found: $WORKLOG_FILE"
      exit 1
    fi

    # Count entries
    ENTRY_COUNT=$(rg -c "^\s*-\s+ts:" "$WORKLOG_FILE" 2>/dev/null || echo 0)

    if [[ $ENTRY_COUNT -le 15 ]]; then
      echo "Worklog has $ENTRY_COUNT entries (≤15), no compression needed"
      exit 0
    fi

    echo "Compressing worklog ($ENTRY_COUNT entries)..."

    # Extract last 5 entries and create summary
    # This is a simplified version; full implementation would parse YAML properly
    echo "TODO: Implement full YAML compression (extract last 5, create history_summary)"
    echo "Entries to compress: $ENTRY_COUNT"
    ;;

  *)
    echo "ERROR: unknown action: $_ACTION"
    exit 1
    ;;
esac
