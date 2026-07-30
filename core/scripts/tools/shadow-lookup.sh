#!/usr/bin/env bash
# tools/shadow-lookup.sh — Symbol → file path TSV lookup from manifest
# Port from ai-system; adapted for context-forge
# Usage: shadow-lookup.sh --symbol <symbol> [--repo <repo>] [--kind <kind>]
# Output: TSV (symbol | kind | file | repo)
set -euo pipefail

# Parse args
_SYMBOL=""
_REPO=""
_KIND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: shadow-lookup.sh --symbol <symbol> [--repo <repo>] [--kind <kind>]

Look up a symbol in the lightweight shadow manifest.
Auto-detects IDE (.claude or .cursor) for manifest location.

Output: TSV (symbol | kind | file | repo)

Examples:
  shadow-lookup.sh --symbol AuthService
  shadow-lookup.sh --symbol BillingFacade --kind class
  shadow-lookup.sh --symbol createUser --kind function --repo auth
EOF
      exit 0
      ;;
    --symbol)
      _SYMBOL="$2"
      shift 2
      ;;
    --repo)
      _REPO="$2"
      shift 2
      ;;
    --kind)
      _KIND="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

SYMBOL="$_SYMBOL"

if [[ -z "$SYMBOL" ]]; then
  echo "ERROR: --symbol required"
  exit 1
fi

# Auto-detect IDE
IDE_DIR=".claude"
if [[ ! -d ".claude" ]] && [[ -d ".cursor" ]]; then
  IDE_DIR=".cursor"
fi

# Detect repo (context-forge by default)
REPO="${_REPO:-context-forge}"

# Manifest path
MANIFEST_PATH="$IDE_DIR/shadow/$REPO/_manifest.lightweight.yaml"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "ERROR: manifest not found at $MANIFEST_PATH"
  echo "HINT: Run 'bash core/scripts/tools/refresh-manifest.sh' to generate"
  exit 1
fi

# Search manifest by symbol and optional kind/repo filter
if [[ -n "$_KIND" ]]; then
  # Filter by both symbol and kind
  rg -A 2 "symbol:\s*${SYMBOL}$" "$MANIFEST_PATH" 2>/dev/null | \
    rg -B 2 -A 2 "kind:\s*${_KIND}" | \
    rg "file:|repo:" -o || echo "ERROR: symbol '$SYMBOL' (kind: $_KIND) not found"
else
  # Filter by symbol only
  rg -A 3 "symbol:\s*${SYMBOL}$" "$MANIFEST_PATH" 2>/dev/null | \
    rg "kind:|file:|repo:" -o || echo "ERROR: symbol '$SYMBOL' not found"
fi

# Output as TSV for downstream processing
# Format: symbol<TAB>kind<TAB>file<TAB>repo
