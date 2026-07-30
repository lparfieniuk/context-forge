#!/usr/bin/env bash
# tools/safe-exec.sh — Run command with observation masking for context safety
# Port from ai-system; adapted for context-forge
# Usage: safe-exec.sh -- <command> [args...]
# Output: XML observation block; full log stored at ~/worklogs/logs/ (never in-repo)
set -euo pipefail

# Parse args
_CMD=()
_INTENT=""
_PASSTHROUGH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: safe-exec.sh [--intent <text>] [--passthrough] -- <command> [args...]

Execute a command with automatic output compression.
Prevents context poisoning by writing large logs to disk.

Options:
  --intent <text>      — Intent for compression heuristic
  --passthrough        — Skip compression, return raw output

Output:
  XML <observation> block with:
    - Exit status
    - Line count
    - Log file pointer
    - Compressed excerpt (if >5KB)

Examples:
  safe-exec.sh -- npm run build
  safe-exec.sh --intent "find build errors" -- npm run lint
  safe-exec.sh --passthrough -- cat huge-file.log
EOF
      exit 0
      ;;
    --intent)
      _INTENT="$2"
      shift 2
      ;;
    --passthrough)
      _PASSTHROUGH=true
      shift
      ;;
    --)
      shift
      _CMD=("$@")
      break
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

CMD=("${_CMD[@]+${_CMD[@]}}")

if [[ ${#CMD[@]} -eq 0 ]]; then
  echo "ERROR: command required"
  echo "Usage: safe-exec.sh [--intent <text>] [--passthrough] -- <command> [args...]"
  exit 1
fi

# Log storage: ~/worklogs/logs/, NOT inside the project tree. `${CLAUDE_PLUGIN_DATA}`
# is not a real Claude Code env var (only Codex/Copilot expose an equivalent) — an
# in-repo fallback here previously wrote to .claude/cache/, which audit-runtime-artifacts.sh
# then flags even though it's gitignored (see 008-cf-worklog.md: worklogs never live in-repo).
CACHE_DIR="$HOME/worklogs/logs"
mkdir -p "$CACHE_DIR"
TS=$(date +%Y%m%d_%H%M%S)
RAND=$(openssl rand -hex 4 2>/dev/null || echo "0000")
LOG_FILE="$CACHE_DIR/run_${TS}_${RAND}.log"

# Execute command, capture output
EXIT_CODE=0
"${CMD[@]}" > "$LOG_FILE" 2>&1 || EXIT_CODE=$?

# Count output size
LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
BYTES=$(wc -c < "$LOG_FILE" | tr -d ' ')

# Passthrough mode: skip all compression and XML
if [[ "$_PASSTHROUGH" == "true" ]]; then
  cat "$LOG_FILE"
  exit $EXIT_CODE
fi

# 5 KB threshold or verbose multi-line output
THRESHOLD_EXCEEDED=false
COMPRESSED=false
COMPRESSED_OUTPUT=""

if [[ $BYTES -gt 5120 || $LINES -gt 200 ]]; then
  THRESHOLD_EXCEEDED=true
fi

# Intent-driven compression: truncate if threshold exceeded and intent provided
if [[ $THRESHOLD_EXCEEDED == true ]] && [[ -n "$_INTENT" ]]; then
  # Simple compression: first 10 lines + last 5 lines + error lines
  set +o pipefail
  COMPRESSED_OUTPUT=$(
    {
      echo "=== FIRST 10 LINES ==="
      head -10 "$LOG_FILE"
      echo ""
      echo "=== LAST 5 LINES ==="
      tail -5 "$LOG_FILE"
      echo ""
      echo "=== ERROR LINES ==="
      rg -i "error|ERROR|Error|FAILED|exception" "$LOG_FILE" 2>/dev/null | head -10 || true
    } | head -c 500
  )
  set -o pipefail
  COMPRESSED=true
fi

# Extract first error signal on failure
SIGNAL=""
if [[ $EXIT_CODE -ne 0 ]]; then
  SIGNAL=$(rg -m1 -i "error|ERROR|Error|FAILED|Fatal|panic|exception" "$LOG_FILE" 2>/dev/null || echo "")
fi

# Build instruction
if [[ $EXIT_CODE -eq 0 ]]; then
  INSTRUCTION="Command succeeded. Read pointer only if downstream logic requires specific values."
else
  INSTRUCTION="Command FAILED (exit $EXIT_CODE). Use log-context-analyzer for RCA. Do NOT read raw log directly."
fi

# Output XML observation
{
  echo "<observation>"
  echo "  <cmd>${CMD[*]}</cmd>"
  echo "  <status>$EXIT_CODE</status>"
  echo "  <lines>$LINES</lines>"
  echo "  <bytes>$BYTES</bytes>"
  echo "  <compressed>${COMPRESSED}</compressed>"
  echo "  <pointer>$LOG_FILE</pointer>"
  echo "  <signal>${SIGNAL}</signal>"
  if [[ $THRESHOLD_EXCEEDED == true ]] && [[ $COMPRESSED == false ]]; then
    echo "  <threshold_warning>output exceeds threshold (${BYTES} bytes, ${LINES} lines); provide --intent for compression</threshold_warning>"
  fi
  if [[ $COMPRESSED == true ]]; then
    echo "  <excerpt><![CDATA[${COMPRESSED_OUTPUT}]]></excerpt>"
  fi
  echo "  <instruction>${INSTRUCTION}</instruction>"
  echo "</observation>"
}

exit $EXIT_CODE
