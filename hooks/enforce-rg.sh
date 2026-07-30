#!/usr/bin/env bash
set -euo pipefail

# Hook 2: enforce-rg.sh (PreToolUse — Bash)
# Block `grep` usage in Bash commands, enforce `rg` (ripgrep).

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Parse command for standalone `grep` usage
# Allow: pipes containing grep, grep -v grep, .sh scripts
# Block: grep "pattern" file, grep -r pattern dir/

# Extract first token (the command being executed)
FIRST_TOKEN=$(echo "$TOOL_INPUT" | awk '{print $1}')

# Check if it's a .sh script being executed (first token only)
if [[ "$FIRST_TOKEN" =~ \.sh$ ]]; then
  exit 0
fi

# Check if first token is grep and there are pipes in the command
# If there are pipes, check each segment before the pipe
if [[ "$FIRST_TOKEN" == "grep" ]]; then
  # First segment starts with grep, check if there's a pipe that makes it allowed
  if [[ "$TOOL_INPUT" =~ \| ]]; then
    # Grep is in a pipe, which is allowed
    exit 0
  fi
fi

# Check for grep -v grep in any segment (filtering out grep from ps output, etc.)
if [[ "$TOOL_INPUT" =~ grep[[:space:]]+-v[[:space:]]+grep ]]; then
  exit 0
fi

# Check for standalone grep as the first token OR grep preceded only by whitespace
# This catches both "grep ..." at start and "  grep ..." after being split
if [[ "$FIRST_TOKEN" == "grep" ]]; then
  # Check if there are pipes in the ENTIRE command; if not, it's a standalone grep (forbidden)
  if [[ ! "$TOOL_INPUT" =~ \| ]]; then
    # This is a standalone grep call
    cat >&2 << 'EOF'
[BLOCKED] grep usage detected
REASON: grep is BANNED. Use rg (ripgrep) instead (rule 003-code-search).

EXAMPLES:
  OLD: grep "pattern" file.txt
  NEW: rg "pattern" file.txt

  OLD: grep -r "pattern" directory/
  NEW: rg "pattern" directory/

  OLD: grep -n "error" *.log
  NEW: rg -n "error" *.log
EOF
    exit 2
  fi
fi

# For piped commands, check each segment before the pipe
# Split by pipe and check if first token of any segment (after pipe) is grep without preceding command
IFS='|' read -ra SEGMENTS <<< "$TOOL_INPUT"
for i in "${!SEGMENTS[@]}"; do
  segment="${SEGMENTS[$i]}"
  segment_first=$(echo "$segment" | awk '{print $1}')
  # First segment already checked above
  # For subsequent segments (after pipe), grep is allowed
  if [ "$i" -gt 0 ] && [[ "$segment_first" == "grep" ]]; then
    # Grep after pipe is allowed
    continue
  fi
done

# Command allowed
exit 0
