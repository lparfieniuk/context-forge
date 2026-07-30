#!/usr/bin/env bash
# tools/record-failure.sh — Create sharded YAML failure ledger
# Port from ai-system; adapted for context-forge
# Usage: record-failure.sh --slug <slug> --goal <goal> --error <snippet> --reflection <text>
# Creates: <IDE_DIR>/lessons/YYYY/MM/DD/<PREFIX>/<UUID>-<slug>.yaml
set -euo pipefail

# Parse args
_SLUG=""
_GOAL=""
_ERROR=""
_REFLECTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: record-failure.sh --slug <slug> --goal <goal> --error <snippet> --reflection <text>

Create a sharded failure ledger YAML file.
Path: <IDE_DIR>/lessons/YYYY/MM/DD/<UUID-PREFIX>/<UUID>-<slug>.yaml

Options:
  --slug <text>       — 2-3 kebab-case words (e.g., "billing-export-fail")
  --goal <text>       — What was being attempted
  --error <text>      — Error message (max 500 chars)
  --reflection <text> — Root cause analysis (why it failed)

Examples:
  record-failure.sh --slug "auth-token-fail" \
    --goal "Add refresh token logic" \
    --error "TypeError: token is undefined" \
    --reflection "Token extraction logic assumed JWT always present, but skipped validation"

  record-failure.sh --slug "ci-timeout" \
    --goal "Add new integration test" \
    --error "Test suite timed out after 30s" \
    --reflection "Test spawned 100 concurrent requests without rate limiting"
EOF
      exit 0
      ;;
    --slug)
      _SLUG="$2"
      shift 2
      ;;
    --goal)
      _GOAL="$2"
      shift 2
      ;;
    --error)
      _ERROR="$2"
      shift 2
      ;;
    --reflection)
      _REFLECTION="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

SLUG="${_SLUG:-unknown-failure}"
GOAL="${_GOAL:-unknown goal}"
ERROR="${_ERROR:-no error text provided}"
REFLECTION="${_REFLECTION:-no reflection provided}"

echo "=== RECORD FAILURE: $SLUG ==="
echo ""

# Auto-detect IDE
IDE_DIR=".claude"
if [[ ! -d ".claude" ]] && [[ -d ".cursor" ]]; then
  IDE_DIR=".cursor"
fi

# Generate UUID (portable: use openssl or /dev/urandom)
if command -v openssl >/dev/null 2>&1; then
  UUID=$(openssl rand -hex 16)
else
  # Fallback: use /dev/urandom via od
  UUID=$(od -x /dev/urandom 2>/dev/null | head -1 | awk '{OFS=""; print $2,$3,$4,$5,$6,$7,$8,$9}' | head -c 32)
fi

UUID=$(echo "$UUID" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase (bash 3.2 compatible)
PREFIX="${UUID:0:2}"

# Date sharding (BSD-compatible date)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)

LEDGER_DIR="$IDE_DIR/lessons/$YEAR/$MONTH/$DAY/$PREFIX"
LEDGER_FILE="$LEDGER_DIR/${UUID}-${SLUG}.yaml"

mkdir -p "$LEDGER_DIR"

# Truncate error to 500 chars
ERROR_TRUNCATED="${ERROR:0:500}"
if [[ ${#ERROR} -gt 500 ]]; then
  ERROR_TRUNCATED="${ERROR_TRUNCATED}
  [TRUNCATED]"
fi

# Write YAML ledger
cat > "$LEDGER_FILE" <<YAML
execution_context:
  goal: "${GOAL}"
  tool: "record-failure.sh"
error_trajectory: |
  ${ERROR_TRUNCATED}
agent_reflection: "${REFLECTION}"
YAML

echo "Ledger created:"
echo "  Path: $IDE_DIR/lessons/$YEAR/$MONTH/$DAY/$PREFIX/${UUID}-${SLUG}.yaml"
echo "  UUID: $UUID"
echo ""
echo "METRICS:"
echo "  uuid=$UUID"
echo "  path=$IDE_DIR/lessons/$YEAR/$MONTH/$DAY/$PREFIX/${UUID}-${SLUG}.yaml"
echo "=== DONE RECORD FAILURE ==="
