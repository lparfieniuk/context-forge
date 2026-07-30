#!/usr/bin/env bash
# tools/extract-signatures.sh — Extract TypeScript/PHP method stubs from source file
# Port from ai-system; adapted for context-forge
# Usage: extract-signatures.sh --file <file_path>
# Output: Indented signature blocks and method list
set -euo pipefail

# Parse args
_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: extract-signatures.sh --file <file_path>

Extract exported TypeScript/JS symbols and method signatures from a source file.
Output: Indented signature blocks with line numbers and symbol types.

Examples:
  extract-signatures.sh --file src/auth/auth.service.ts
  extract-signatures.sh --file libs/billing/src/index.ts
EOF
      exit 0
      ;;
    --file)
      _FILE="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

FILE="$_FILE"

if [[ -z "$FILE" ]]; then
  echo "ERROR: --file required"
  echo "Usage: extract-signatures.sh --file <file_path>"
  exit 1
fi

# Resolve absolute path
if [[ ! "$FILE" = /* ]]; then
  FILE="$(pwd)/$FILE"
fi

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE"
  exit 1
fi

ISSUES=0
echo "=== EXTRACT SIGNATURES: $(basename "$FILE") ==="
echo ""

# Count lines to decide strategy
LINE_COUNT=$(wc -l < "$FILE" | tr -d ' ')

if [[ $LINE_COUNT -le 50 ]]; then
  echo "## File ($LINE_COUNT lines) — reading directly"
  cat "$FILE"
else
  echo "## Exported top-level symbols"
  echo ""
  rg -n "^export (default )?(abstract )?(class|interface|enum|type|function|const|let|var|async function)" "$FILE" 2>/dev/null || echo "  (none found)"
  echo ""

  echo "## All top-level declarations"
  echo ""
  rg -n "^(export |async )?(class|interface|function|const|type|enum) " "$FILE" 2>/dev/null || echo "  (none found)"
  echo ""

  echo "## Public class members"
  echo ""
  rg -n "(public |readonly |static |abstract )?[a-zA-Z_\$][a-zA-Z0-9_\$]*\s*[:\(]" "$FILE" 2>/dev/null | \
    rg -v "(private |protected )" | \
    head -40 || echo "  (none found)"
  echo ""

  echo "## Decorators (Angular, NestJS, etc.)"
  echo ""
  rg -n "^@(Component|Injectable|NgModule|Directive|Pipe|Input|Output|ViewChild|HostListener|Controller|Get|Post|Put|Delete)" "$FILE" 2>/dev/null | head -20 || true
fi

echo ""
echo "METRICS:"
echo "  issues=$ISSUES"
echo "  lines=$LINE_COUNT"
echo "=== DONE EXTRACT SIGNATURES ==="
