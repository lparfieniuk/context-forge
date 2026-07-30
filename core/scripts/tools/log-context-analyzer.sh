#!/usr/bin/env bash
# tools/log-context-analyzer.sh — Extract RCA from error logs
# Port from ai-system's analyze-log.sh; adapted for context-forge
# Usage: log-context-analyzer.sh --file <log_path> [--anchor <keyword>] [--type <error_type>] [--max-errors <n>]
# Output: [RCA] envelope (root cause, failing file, line, fix)
set -euo pipefail

# Parse args
_FILE=""
_ANCHOR=""
_TYPE=""
_MAX_ERRORS="3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: log-context-analyzer.sh --file <log_path> [--anchor <keyword>] [--type <error_type>] [--max-errors <n>]

Extract root cause analysis from error logs.
Detects TypeScript, Jest, ESLint, build, and safe-exec observation logs automatically.

Options:
  --file <path>       — Log file to analyze
  --log <path>        — Alias for --file
  --log-file <path>   — Alias for --file
  --anchor <keyword>  — Focus on lines containing keyword
  --type <type>       — Force error type: typescript|jest|eslint|build|generic
  --format <type>     — Alias for --type
  --max-errors <n>    — Limit generic output lines (default: 3)

Output:
  [RCA] envelope with:
    - Root cause (1 sentence)
    - Failing file (if identifiable)
    - Error line number
    - Suggested fix (1 line)

Examples:
  log-context-analyzer.sh --file build.log
  log-context-analyzer.sh --file test.log --type jest --anchor "expect"
  log-context-analyzer.sh --file errors.txt --anchor "FAILED"
EOF
      exit 0
      ;;
    --file)
      _FILE="$2"
      shift 2
      ;;
    --log|--log-file)
      _FILE="$2"
      shift 2
      ;;
    --anchor)
      _ANCHOR="$2"
      shift 2
      ;;
    --type|--format)
      _TYPE="$2"
      shift 2
      ;;
    --max-errors)
      _MAX_ERRORS="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

FILE="$_FILE"
MAX_ERRORS="$_MAX_ERRORS"

if [[ -z "$FILE" ]]; then
  echo "ERROR: --file required"
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE"
  exit 1
fi

case "$MAX_ERRORS" in
  ''|*[!0-9]*)
    MAX_ERRORS="3"
    ;;
esac

if [[ "$MAX_ERRORS" -lt 1 ]]; then
  MAX_ERRORS="1"
fi

echo "[RCA]"
echo ""

# Detect error type if not specified
ERROR_TYPE="${_TYPE:-}"
if [[ -z "$ERROR_TYPE" ]]; then
  # Auto-detect
  if rg -q "TS\d+:" "$FILE" 2>/dev/null; then
    ERROR_TYPE="typescript"
  elif rg -q "Jest|FAIL|PASS" "$FILE" 2>/dev/null; then
    ERROR_TYPE="jest"
  elif rg -q "<status>|<signal>|<instruction>|Failed Tests|ERROR:" "$FILE" 2>/dev/null; then
    ERROR_TYPE="safe-exec"
  elif rg -q "error:|warning:" "$FILE" 2>/dev/null; then
    ERROR_TYPE="eslint"
  else
    ERROR_TYPE="generic"
  fi
fi

# Focus on anchor if provided
SEARCH_CONTEXT="$FILE"
TEMP_CONTEXT=""
if [[ -n "$_ANCHOR" ]]; then
  TEMP_CONTEXT="$(mktemp "${TMPDIR:-/tmp}/log-context-analyzer.XXXXXX")"
  rg -B 5 -A 10 "$_ANCHOR" "$FILE" 2>/dev/null | head -100 > "$TEMP_CONTEXT" || true
  SEARCH_CONTEXT="$TEMP_CONTEXT"
fi

cleanup() {
  if [[ -n "$TEMP_CONTEXT" && -f "$TEMP_CONTEXT" ]]; then
    rm -f "$TEMP_CONTEXT"
  fi
}
trap cleanup EXIT

echo "### Root Cause"
echo ""

case "$ERROR_TYPE" in
  typescript)
    # Extract first TS error
    FIRST_ERROR=$(rg "^(.+\.ts\(\d+,\d+\):.*TS\d+:.+)" "$SEARCH_CONTEXT" 2>/dev/null | head -1 || true)
    if [[ -n "$FIRST_ERROR" ]]; then
      echo "$FIRST_ERROR"

      # Extract file and line
      FILE_PATH=$(echo "$FIRST_ERROR" | rg "^(.+\.ts)\(" -r '$1' 2>/dev/null || true)
      LINE_NUM=$(echo "$FIRST_ERROR" | rg "^.+\((\d+)," -r '$1' 2>/dev/null || true)

      echo ""
      echo "**File:** $FILE_PATH"
      echo "**Line:** $LINE_NUM"
      echo ""
      echo "**Suggested fix:** Check type annotations, imports, and interface compatibility on line $LINE_NUM"
    fi
    ;;
  jest)
    # Extract first failing test
    FIRST_FAIL=$(rg "^●\s+(.+)$" -r '$1' "$SEARCH_CONTEXT" 2>/dev/null | head -1 || true)
    if [[ -n "$FIRST_FAIL" ]]; then
      echo "$FIRST_FAIL"

      # Extract expect failure
      EXPECT_LINE=$(rg "expect\((.+)\)\." -A 2 "$SEARCH_CONTEXT" 2>/dev/null | head -1 || true)
      if [[ -n "$EXPECT_LINE" ]]; then
        echo ""
        echo "**Assertion:** $EXPECT_LINE"
        echo "**Suggested fix:** Verify test data and expected values match actual behavior"
      fi
    fi
    ;;
  eslint)
    # Extract first lint error
    FIRST_LINT=$(rg "^(.+)\s+error:" "$SEARCH_CONTEXT" 2>/dev/null | head -1 || true)
    if [[ -n "$FIRST_LINT" ]]; then
      echo "$FIRST_LINT"

      FILE_PATH=$(echo "$FIRST_LINT" | rg "^(.+)\s+error:" -r '$1' 2>/dev/null || true)
      echo ""
      echo "**File:** $FILE_PATH"
      echo "**Suggested fix:** Run 'npm run lint -- --fix' to auto-correct style issues"
    fi
    ;;
  safe-exec)
    FIRST_ERROR=$(rg -i "^.*ERROR:.*$" "$SEARCH_CONTEXT" 2>/dev/null | head -1 || true)
    if [[ -z "$FIRST_ERROR" ]]; then
      FIRST_ERROR=$(rg -i "^.*(Failed Tests|<signal>|<status>|<instruction>).*$" "$SEARCH_CONTEXT" 2>/dev/null | head -"$MAX_ERRORS" || true)
    fi

    if [[ -n "$FIRST_ERROR" ]]; then
      echo "$FIRST_ERROR"
      echo ""
      echo "**Suggested fix:** Inspect the failing command output captured in $FILE and fix the first reported failure"
    else
      echo "No clear error found. Review log file at $FILE"
    fi
    ;;
  *)
    # Generic: find first ERROR or FAIL line
    FIRST_ERROR=$(rg -i "^.*(ERROR:|ERROR|Failed Tests|FAILED|EXCEPTION|PANIC).*$" "$SEARCH_CONTEXT" 2>/dev/null | head -"$MAX_ERRORS" || true)
    if [[ -n "$FIRST_ERROR" ]]; then
      echo "$FIRST_ERROR"
      echo ""
      echo "**Suggested fix:** Check log file at $FILE for full context"
    else
      echo "No clear error found. Review log file at $FILE"
    fi
    ;;
esac

echo ""
echo "[END RCA]"
