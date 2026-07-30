#!/usr/bin/env bash
# tools/compress-observation.sh — Generic output compressor
# Input: text (stdin or --file)
# If >5KB: extract first line, last line, error lines; return summary ≤500 chars
# If ≤5KB: pass through unchanged
set -euo pipefail

# Parse args
_FILE=""
_THRESHOLD="5120"  # 5 KB in bytes

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: compress-observation.sh [--file <path>] [--threshold <bytes>]

Compress large text output to preserve context.
Keeps first and last lines, extracts error lines.

If output > threshold:
  - Return: first 5 lines + error lines + last 3 lines
  - Total: max 500 characters

If output ≤ threshold:
  - Pass through unchanged

Options:
  --file <path>         — Read from file (default: stdin)
  --threshold <bytes>   — Compression threshold (default: 5120 = 5KB)

Examples:
  compress-observation.sh --file build.log
  echo "long output..." | compress-observation.sh
  compress-observation.sh --file test.log --threshold 2048
EOF
      exit 0
      ;;
    --file)
      _FILE="$2"
      shift 2
      ;;
    --threshold)
      _THRESHOLD="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

if [[ -n "$_FILE" ]]; then
  if [[ ! -f "$_FILE" ]]; then
    echo "ERROR: file not found: $_FILE"
    exit 1
  fi
  INPUT_FILE="$_FILE"
else
  # Read from stdin into temp file
  INPUT_FILE=$(mktemp)
  cat > "$INPUT_FILE"
  trap "rm -f $INPUT_FILE" EXIT
fi

# Check file size
FILE_SIZE=$(wc -c < "$INPUT_FILE" | tr -d ' ')

if [[ $FILE_SIZE -le $_THRESHOLD ]]; then
  # Under threshold: pass through
  cat "$INPUT_FILE"
  exit 0
fi

# Over threshold: compress
echo "[COMPRESSED OUTPUT — original $(( FILE_SIZE / 1024 ))KB]"
echo ""

# First 5 lines
echo "=== FIRST 5 LINES ==="
head -5 "$INPUT_FILE"
echo ""

# Error lines
echo "=== ERRORS ==="
rg -i "error|ERROR|FAIL|exception" "$INPUT_FILE" 2>/dev/null | head -10 || echo "  (none found)"
echo ""

# Last 3 lines
echo "=== LAST 3 LINES ==="
tail -3 "$INPUT_FILE"
echo ""

echo "[END COMPRESSED OUTPUT]"
