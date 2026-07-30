#!/usr/bin/env bash
# tools/pack-context.sh — Bundle matching files in <f p="path"> XML format
# Port from ai-system; adapted for context-forge
# Usage: pack-context.sh --pattern <regex> --search-path <path> [--max-files N]
# Output: XML <f p="...">content</f> blocks
set -euo pipefail

# Parse args
_PATTERN=""
_SEARCH_PATH=""
_MAX_FILES="15"
_MAX_LINES="400"   # per-file line budget before head+tail truncation kicks in

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: pack-context.sh --pattern <regex> --search-path <path> [--max-files N]

Bundle matching files into XML context format.
Output: <f p="path">content</f> blocks for each matched file.

Options:
  --pattern <regex>      — Pattern to match (ripgrep regex)
  --search-path <path>   — Directory to search
  --max-files <N>        — Max files to include (default: 15)
  --max-lines <N>        — Per-file line budget; larger files show head+tail (default: 400)

Examples:
  pack-context.sh --pattern "export class.*Service" --search-path "libs/auth/src"
  pack-context.sh --pattern "BillingFacade" --search-path "." --max-files 10
  pack-context.sh --pattern "TODO|FIXME" --search-path "src" --max-files 5
EOF
      exit 0
      ;;
    --pattern)
      _PATTERN="$2"
      shift 2
      ;;
    --search-path)
      _SEARCH_PATH="$2"
      shift 2
      ;;
    --max-files)
      _MAX_FILES="$2"
      shift 2
      ;;
    --max-lines)
      _MAX_LINES="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

PATTERN="$_PATTERN"
SEARCH_PATH="$_SEARCH_PATH"
MAX_FILES="$_MAX_FILES"
MAX_LINES="$_MAX_LINES"

if [[ -z "$PATTERN" || -z "$SEARCH_PATH" ]]; then
  echo "ERROR: --pattern and --search-path required"
  exit 1
fi

# Resolve path
if [[ ! "$SEARCH_PATH" = /* ]]; then
  SEARCH_PATH="$(pwd)/$SEARCH_PATH"
fi

if [[ ! -e "$SEARCH_PATH" ]]; then
  echo "ERROR: search path not found: $SEARCH_PATH"
  exit 1
fi

echo "=== PACK CONTEXT: '$PATTERN' in $SEARCH_PATH ==="
echo ""

# Step 1: Find matching files (exclude binaries and generated)
MATCHED_FILES=$(rg -l "$PATTERN" "$SEARCH_PATH" \
  --glob '!*.{lock,min.js,map,png,jpg,gif,svg,ico,woff,woff2,ttf,eot}' \
  --glob '!dist/**' --glob '!node_modules/**' --glob '!.git/**' \
  2>/dev/null | head -"$MAX_FILES")

FILE_COUNT=$(echo "$MATCHED_FILES" | rg -c '.' 2>/dev/null || echo "0")

echo "## Selection"
echo "Pattern: '$PATTERN' | Files found: $FILE_COUNT (max $MAX_FILES)"
echo ""

if [[ -z "$MATCHED_FILES" ]]; then
  echo "No files matched pattern. Try broader regex or different path."
  exit 0
fi

if [[ $FILE_COUNT -gt $MAX_FILES ]]; then
  echo "WARNING: $FILE_COUNT files matched — truncated to $MAX_FILES"
  echo ""
fi

# Step 2: Output each file in <f p="..."> XML format
while IFS= read -r FILE; do
  [[ -z "$FILE" ]] && continue

  LINE_COUNT=$(wc -l < "$FILE" | tr -d ' ')

  # Make path relative to current dir for output
  REL_PATH="${FILE#$(pwd)/}"
  [[ "$REL_PATH" == "$FILE" ]] && REL_PATH="$FILE"

  echo "<f p=\"$REL_PATH\" lines=\"$LINE_COUNT\">"

  # Truncate large files with a head+tail window, not a first-30-lines cliff.
  # A file was matched because it is relevant; hiding 94% of it (the old behaviour:
  # 30 of 500+ lines) routinely dropped the very code the caller needed. Show a
  # generous head (imports, exports, signatures) plus a tail (the change site often
  # lives near the end), and report exactly how many lines were elided.
  if [[ $LINE_COUNT -gt $MAX_LINES ]]; then
    HEAD_N=$(( MAX_LINES * 3 / 4 ))
    TAIL_N=$(( MAX_LINES - HEAD_N ))
    ELIDED=$(( LINE_COUNT - MAX_LINES ))
    echo "  [TRUNCATED: $LINE_COUNT lines — showing first $HEAD_N + last $TAIL_N, $ELIDED elided; re-run with --max-lines to widen]"
    head -"$HEAD_N" "$FILE" | sed 's/^/  /'
    echo "  ... [$ELIDED lines elided] ..."
    tail -"$TAIL_N" "$FILE" | sed 's/^/  /'
    echo "  [END TRUNCATION]"
  else
    # Include full file
    sed 's/^/  /' "$FILE"
  fi

  echo "</f>"
  echo ""
done <<<"$MATCHED_FILES"

echo "=== DONE PACK CONTEXT ==="
