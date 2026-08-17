#!/usr/bin/env bash
set -euo pipefail

# Hook 2: enforce-rg.sh (PreToolUse — Bash)
# Block `grep` usage in Bash commands, enforce `rg` (ripgrep).

# Read JSON input from stdin (Claude Code hook protocol)
HOOK_JSON=$(cat)
TOOL_INPUT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Parse the command for `grep` in any pipeline position.
# Allow: `grep -v grep` (the ps idiom), .sh scripts.
# Block: grep as the command of any segment — `grep p f`, `grep -r p dir/`,
#        `grep p f | head`, `cat f | grep p`.
#
# This used to exempt every command containing a pipe, on the theory that grep
# after a pipe is a filter rather than a search. In practice almost every grep
# is piped into something, so the exemption let the common shape straight
# through and the hook enforced close to nothing. Rule 005 bans grep outright
# and `rg` reads from a pipe just as well, so the exemption bought nothing.

# No command to inspect (non-Bash tool, or a malformed payload). Nothing to
# block. Returning early also keeps bash 3.2 from expanding an empty SEGMENTS
# array below, which `set -u` reports as an unbound variable.
[ -z "$TOOL_INPUT" ] && exit 0

# Extract first token (the command being executed)
FIRST_TOKEN=$(echo "$TOOL_INPUT" | awk '{print $1}')

# Check if it's a .sh script being executed (first token only)
if [[ "$FIRST_TOKEN" =~ \.sh$ ]]; then
  exit 0
fi

# `grep -v grep` filters grep out of process listings — no search intent, keep it.
if [[ "$TOOL_INPUT" =~ grep[[:space:]]+-v[[:space:]]+grep ]]; then
  exit 0
fi

# Is grep the command of any pipeline segment?
GREP_FOUND=0
# `|| true`: read returns non-zero at EOF, and an empty command (malformed hook
# payload) would otherwise abort the hook under `set -e` with exit 1.
IFS='|' read -ra SEGMENTS <<< "$TOOL_INPUT" || true
for segment in "${SEGMENTS[@]}"; do
  segment_first=$(echo "$segment" | awk '{print $1}')
  if [[ "$segment_first" == "grep" ]]; then
    GREP_FOUND=1
    break
  fi
done

if [ "$GREP_FOUND" -eq 1 ]; then
    cat >&2 << 'EOF'
[BLOCKED] grep usage detected
REASON: grep is BANNED. Use rg (ripgrep) instead (rule 005-cf-code-search).

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

# Command allowed
exit 0
