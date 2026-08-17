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

# Detect repo. Defaulting to "context-forge" made every lookup in a foreign
# checkout miss — the manifest refresh-manifest.sh writes is named after the repo
# you are standing in.
REPO="${_REPO:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")}"

# Manifest path
MANIFEST_PATH="$IDE_DIR/shadow/$REPO/_manifest.lightweight.yaml"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "ERROR: manifest not found at $MANIFEST_PATH"
  echo "HINT: Run 'bash core/scripts/tools/refresh-manifest.sh' to generate"
  exit 1
fi

# Search the manifest and emit the documented TSV: symbol<TAB>kind<TAB>file<TAB>repo.
# The previous `rg "kind:|file:|repo:" -o` printed the bare field labels — the
# pattern captured no values — so every successful lookup returned three useless
# lines. One awk pass over the entry blocks instead.
RESULT=$(awk -v want="$SYMBOL" -v kindf="$_KIND" '
  /^  - symbol:/ { sym=$3; kind=""; file=""; repo=""; next }
  /^    kind:/   { kind=$2; next }
  /^    file:/   { file=$2; next }
  /^    repo:/ {
    repo=$2
    if (sym == want && (kindf == "" || kind == kindf))
      printf "%s\t%s\t%s\t%s\n", sym, kind, file, repo
    sym=""
  }
' "$MANIFEST_PATH")

if [[ -z "$RESULT" ]]; then
  if [[ -n "$_KIND" ]]; then
    echo "ERROR: symbol '$SYMBOL' (kind: $_KIND) not found in $MANIFEST_PATH"
  else
    echo "ERROR: symbol '$SYMBOL' not found in $MANIFEST_PATH"
  fi
  exit 1
fi

printf '%s\n' "$RESULT"
